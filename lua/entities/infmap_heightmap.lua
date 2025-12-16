AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_heightmap"

if !INFMAP then return end

local function get_chunk(ply)
	local ply_chunk = ply:GetChunk()
	if ply_chunk then 
		return ply_chunk 
	end

	local vbsp = ply:GetNWEntity("INFMAP_VBSP")
	if IsValid(vbsp) then
		return vbsp:GetChunk()
	else
		return nil -- where the fuck are we..??
	end
end

-- client hack (sometimes `self` isnt initialized when client sees it)
local function get_quadtree(self)
	local quadtree = self.INFMAP_HEIGHTMAP_QUADTREE
	if !quadtree then
		quadtree = INFMAP.Quadtree(Vector(), 393701)
		self.INFMAP_HEIGHTMAP_QUADTREE = quadtree
	end

	return quadtree
end

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "Height")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:KeyValue(key, value)
	if key == "path" then
		--value = "materials/" .. value
		self.INFMAP_HEIGHTMAP_SAMPLER = ImageReader(file.Read("materials/Wolf_Run_Height_Map_8192x8192_0_0.png", "GAME"))--ImageReader(file.Read(value, "GAME")) -- defined in imagereader.dll
	elseif key == "origin" then
		self:SetChunk(INFMAP.Vector(0, 0, 0))
	end
end

local heightmaps = ents.FindByClass("infmap_heightmap")
function ENT:Initialize()
	self:SetNoDraw(true)

	if CLIENT or self.INFMAP_HEIGHTMAP_SAMPLER then
		table.insert(heightmaps, self)
	end
end

------------------
-- SERVER LOGIC --
------------------
if SERVER then
	require("imagereader")
	util.AddNetworkString("INFMAP_HEIGHTMAP")

	-- requesting
	local RESOLUTION = 16
	local function validate_tree(heightmap, tree)
		if tree.validated then return end
		tree.validated = {}

		local metadata = {}
		local sampler = heightmap.INFMAP_HEIGHTMAP_SAMPLER
		local inv_res = tree.size / RESOLUTION
		local inv_size = 1 / heightmap.INFMAP_HEIGHTMAP_QUADTREE.size
		local min, max = 2^16-1, 0
		for y = 0, RESOLUTION do
			for x = 0, RESOLUTION do
				local sample = math.Round(sampler:Get(
					(tree.pos[1] + x * inv_res) * inv_size, 
					(tree.pos[2] + y * inv_res) * inv_size,
					false
				))

				min, max = math.min(min, sample), math.max(max, sample)
				table.insert(metadata, sample)
			end
		end
		metadata.min = min
		metadata.max = max
		tree.metadata = metadata
	end

	timer.Create("INFMAP_HEIGHTMAP", 0.25, 0, function()
		local s = SysTime()

		for _, ply in player.Iterator() do
			local ply_chunk = get_chunk(ply)
			if !ply_chunk then continue end

			-- TODO:
				-- WHY is the SERVER validating CLIENT VISUALS???
				-- let the fucking CLIENT build visuals.. ONLY THING THE SERVER SHOULD WORRY ABOUT IS COLLISION
				-- this is some shitass fucking code!! come on man!!!!
			ply.INFMAP_QUEUE = ply.INFMAP_QUEUE or INFMAP.Queue()
			local pos = ply:INFMAP_GetPos()
			for _, heightmap in ipairs(heightmaps) do
				local offset = INFMAP.unlocalize(pos, ply_chunk - heightmap:GetChunk())
				get_quadtree(heightmap):traverse(function(tree)
					validate_tree(heightmap, tree)

					-- collision
					if !tree.colliders and #tree.path == 9 then
						local _, chunk_min = INFMAP.localize(Vector(0, 0, tree.metadata.min))
						local _, chunk_max = INFMAP.localize(Vector(0, 0, tree.metadata.max))
						local pos, chunk_offset = INFMAP.localize(tree.pos)
						chunk_offset = chunk_offset + heightmap:GetChunk()

						tree.colliders = {}
						for z = chunk_min[3], chunk_max[3] do
							local collider = ents.Create("infmap_heightmap_collider")
							collider:SetHeightmap(heightmap)
							collider:SetPath(tree.path)
							collider:SetChunk(chunk_offset + INFMAP.Vector(0, 0, z))
							collider:INFMAP_SetPos(pos)
							collider:Spawn()
							table.insert(tree.colliders, collider)
						end
					end

					-- networking
					if !tree.validated[ply] then
						tree.validated[ply] = true
						ply.INFMAP_QUEUE:insert({heightmap, tree, false})
						return true -- stop recursion
					end

					if tree:should_split_pos(offset) then
						tree.curtime = CurTime()
						tree:split()
						return -- continue recursion
					end

					-- tree hasn't been visited in a while, invalidate it (for everyone)
					if tree.curtime and tree.curtime + 1 < CurTime() then
						for p, _ in pairs(tree.validated) do
							p.INFMAP_QUEUE:insert({heightmap, tree, true})
						end

						tree:traverse(function(self)
							if self != tree then
								self.invalid = true
							end

							if self.colliders then
								for k, v in ipairs(self.colliders) do 
									SafeRemoveEntity(v) 
								end
							end
						end)

						tree.children = nil
						tree.curtime = nil
					end

					return true
				end)
			end
		end

		print("heightmaps parsed in " .. (SysTime() - s) * 1000 .. "ms")
	end)

	hook.Add("Think", "infmap_heightmap", function()
		for _, ply in player.Iterator() do
			local queue = ply.INFMAP_QUEUE
			if !queue then continue end

			for i = 1, 5 do
				local data = queue:remove()
				if !data then break end

				-- REPLACE WITH XALPHOX NETWORKING
				local heightmap, tree, free = data[1], data[2], data[3]
				net.Start("INFMAP_HEIGHTMAP")
					net.WriteEntity(heightmap)
					net.WriteString(tree.path)
					if !free then
						-- delta encoding
						local min = tree.metadata.min
						local bits = math.ceil(math.log(math.max(tree.metadata.max - min, 2), 2)) -- 1:16
						net.WriteUInt(bits - 1, 4) --0:15
						net.WriteUInt(min, 16)
						for _, sample in ipairs(tree.metadata) do
							net.WriteUInt(sample - min, bits)
						end
					end
				net.Send(ply)
			end
		end
	end)

	return
end

------------------
-- CLIENT LOGIC --
------------------
local function generate_tree(heightmap, tree)
	local metadata = tree.metadata
	local res = math.sqrt(#metadata) 
	assert(res == math.floor(res)) 
	assert(res <= 91)

	local res_1 = res - 1
	local scale = tree.size / res_1
	local inv_uv_size = 1 / heightmap.INFMAP_HEIGHTMAP_QUADTREE.size
	local offset_x, offset_y, offset_z = tree.pos[1], tree.pos[2], tree.pos[3]
	local function vertex(x, y, z, u, v)
		mesh.Position(x, y, z)
		--mesh.Normal(normal)
		mesh.TexCoord(0, u, v)
		mesh.AdvanceVertex()
	end

	tree.imesh = Mesh()
	mesh.Begin(tree.imesh, MATERIAL_QUADS, res_1 * res_1)
	for y = 0, res_1 - 1 do
		for x = 0, res_1 - 1 do
			-- positions
			local px0 = offset_x + (x    ) * scale
			local px1 = offset_x + (x + 1) * scale
			local py0 = offset_y + (y    ) * scale
			local py1 = offset_y + (y + 1) * scale
			
			-- heightmap indices
			local hx0 = (x    ) % res
			local hx1 = (x + 1) % res
			local hy0 = (y    ) * res
			local hy1 = (y + 1) * res

			-- heightmap positions
			local p00 = offset_z + metadata[hx0 + hy0 + 1]
			local p10 = offset_z + metadata[hx1 + hy0 + 1]
			local p01 = offset_z + metadata[hx0 + hy1 + 1]
			local p11 = offset_z + metadata[hx1 + hy1 + 1]
			
			-- uv coords (world space)
			local u0 =  px0 * inv_uv_size
			local u1 =  px1 * inv_uv_size
			local v0 = -py0 * inv_uv_size
			local v1 = -py1 * inv_uv_size

			if x % 2 == y % 2 then
				vertex(px0, py0, p00, u0, v0)
				vertex(px0, py1, p01, u0, v1)
				vertex(px1, py1, p11, u1, v1)
				vertex(px1, py0, p10, u1, v0)
			else
				vertex(px1, py0, p10, u1, v0)
				vertex(px0, py0, p00, u0, v0)
				vertex(px0, py1, p01, u0, v1)
				vertex(px1, py1, p11, u1, v1)
			end
		end
	end
	mesh.End()
end

-- received
net.Receive("INFMAP_HEIGHTMAP", function(len, ply)
	local heightmap = net.ReadEntity()
	len = len - 13

	local path = net.ReadString()
	len = len - (#path + 1) * 8

	local tree = get_quadtree(heightmap):traverse_path(path, true)
	if len <= 0 then
		print("received invalid tree " .. path .. ".. discarding..")
		tree.children = nil
		return
	end

	local bits = net.ReadUInt(4) + 1
	len = len - 4

	local metadata = {}
	local min, max = net.ReadUInt(16), 0
	len = len - 16
	while len > 0 do
		local sample = net.ReadUInt(bits) + min
		len = len - bits
		max = math.max(max, sample)
		table.insert(metadata, sample)
	end
	metadata.min = min
	metadata.max = max
	tree.metadata = metadata

	local s = SysTime()
	generate_tree(heightmap, tree)
	print("mesh generation with " .. #metadata .. " points took " .. (SysTime() - s) * 1000 .. "ms")
end)

local function traverse_render(tree, pos)
	local children = tree.children
	if !children then
		tree.imesh:Draw()
		return
	end

	if !tree:should_split_pos(pos) then
		tree.imesh:Draw()
		return
	end

	for i = 1, 4 do
		if !children[i].imesh then
			tree.imesh:Draw()
			return
		end
	end

	for i = 1, 4 do
		traverse_render(children[i], pos)
	end
end

-- rendering
local imesh_offset = Matrix()
hook.Add("PostDrawOpaqueRenderables", "infmap_heightmap", function(_, _, sky3d)
	local local_player = LocalPlayer()
	local local_player_chunk = get_chunk(local_player)
	if !local_player_chunk then return end

	local eye_pos = local_player:EyePos()
	for _, heightmap in ipairs(heightmaps) do
		local quadtree = get_quadtree(heightmap)
		if !quadtree or !quadtree.imesh then continue end

		local offset = INFMAP.unlocalize(quadtree.pos, local_player_chunk - heightmap:GetChunk())
		--render.SetMaterial(Material("models/wireframe"))
		--render.SetMaterial(Material("models/props_combine/combine_interface_disp"))
		render.SetMaterial(Material("sstrp25/heightmaps/wolf_run"))
		imesh_offset:SetTranslation(-offset)
		offset:Add(eye_pos)

		cam.PushModelMatrix(imesh_offset)
			render.OverrideDepthEnable(true, true)
			traverse_render(quadtree, offset)
			render.OverrideDepthEnable(false, false)
		cam.PopModelMatrix()
	end
end)