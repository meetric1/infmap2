AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_heightmap"

if !INFMAP then return end

local function get_chunk(local_player)
	local local_player_chunk = local_player:GetChunk()
	if local_player_chunk then 
		return local_player_chunk 
	end

	local vbsp = local_player:GetNWEntity("INFMAP_VBSP")
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
	self:NetworkVar("String", 0, "HeightmapPath")
	self:SetNoDraw(true)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:KeyValue(key, value)
	if key == "path" then
		value = "materials/" .. value
		print(value)
		self.INFMAP_HEIGHTMAP_SAMPLER = ImageReader(file.Read("materials/Wolf_Run_Height_Map_8192x8192_0_0.png", "GAME"))--ImageReader(file.Read(value, "GAME")) -- defined in imagereader .dll
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

------------
-- SERVER --
------------
if SERVER then
	require("imagereader")
	util.AddNetworkString("INFMAP_HEIGHTMAP")

	-- requesting
	local queue = setmetatable({["f"] = 0, ["l"] = -1}, {["__index"] = {
		["insert"] = function(self, v)
			local l = self.l + 1
			self.l = l
			self[l] = v
		end,
		["remove"] = function(self)
			local f = self.f
			local v = self[f]
			self[f] = nil
			f = f + 1
			if f >= 1000 then
				local l = self.l
				for shift = f, l do
					self[shift - f] = self[shift]
					self[shift] = nil
				end
				self.l = l - f
				f = 0
			end
			self.f = f
			return v
		end,
		["is_empty"] = function(self)
			return self.f > self.l
		end
	}})

	timer.Create("INFMAP_HEIGHTMAP", 0.5, 0, function()
		local s = SysTime()

		for _, ply in player.Iterator() do
			local ply_chunk = get_chunk(ply)
			if !ply_chunk then continue end

			local eye_pos = ply:INFMAP_EyePos()
			for _, heightmap in ipairs(heightmaps) do
				local offset = INFMAP.unlocalize(eye_pos, ply_chunk - heightmap:GetChunk())
				get_quadtree(heightmap):traverse(function(tree)
					tree.validated = tree.validated or {}
					if !tree.validated[ply] then
						tree.validated[ply] = true
						queue:insert({ply, heightmap, tree, false})
						return true -- stop recursion
					end

					if tree:should_split_pos(offset, 2) then
						tree.curtime = CurTime() -- used for garbage collection
						tree:split() -- continue recursion
					else
						-- tree hasn't been visited in a while, invalidate it
						if tree.curtime and tree.curtime + 1 < CurTime() and tree.children then
							for p, _ in pairs(tree.validated) do
								queue:insert({ply, heightmap, tree, true})
							end
							
							tree.children = nil
						end
						return true
					end
				end)
			end
		end
		
		print("parse took " .. (SysTime() - s) * 1000 .. " ms")
	end)

	local RESOLUTION = 16
	hook.Add("Think", "infmap_heightmap", function()
		local i = 0
		while !queue:is_empty() do
			if i > 25 then break end -- too much
			i = i + 1

			-- REPLACE WITH XALPHOX NETWORKING
			local data = queue:remove()
			local ply, heightmap, tree, free = data[1], data[2], data[3], data[4]
			net.Start("INFMAP_HEIGHTMAP")
				net.WriteEntity(heightmap)
				net.WriteString(tree.path)

				if !free then
					local mult = tree.size / RESOLUTION
					local inv_res = 1 / heightmap.INFMAP_HEIGHTMAP_QUADTREE.size
					for y = 0, RESOLUTION do
						for x = 0, RESOLUTION do
							net.WriteUInt(heightmap.INFMAP_HEIGHTMAP_SAMPLER:Get(
								(tree.pos[1] + x * mult) * inv_res, 
								(tree.pos[2] + y * mult) * inv_res
							), 16)
						end
					end
				end
			net.Send(ply)
		end
	end)

	return
end

------------
-- CLIENT --
------------
local function generate_tree(tree, metadata)
	local res = math.sqrt(#metadata)
	assert(res == math.floor(res))
	assert(res <= 91)

	local res_1 = res - 1
	local scale = tree.size / res_1
	local offset_x, offset_y, offset_z = tree.pos[1], tree.pos[2], tree.pos[3]

	local imesh = Mesh()
	mesh.Begin(imesh, MATERIAL_QUADS, res_1 * res_1)
	for y = 0, res_1 - 1 do
		for x = 0, res_1 - 1 do
			-- positions
			local px0 = offset_x + (x    ) * scale
			local px1 = offset_x + (x + 1) * scale
			local py0 = offset_y + (y    ) * scale
			local py1 = offset_y + (y + 1) * scale
			
			-- heightmap values
			local x0 = (x    ) % res
			local x1 = (x + 1) % res
			local y0 = (y    ) * res
			local y1 = (y + 1) * res

			-- heightmap lookup
			local i00 = offset_z + metadata[x0 + y0 + 1]
			local i10 = offset_z + metadata[x1 + y0 + 1]
			local i01 = offset_z + metadata[x0 + y1 + 1]
			local i11 = offset_z + metadata[x1 + y1 + 1]
			
			-- uv coords (world space)
			local u0 = -px0 / 1000
			local u1 = -px1 / 1000
			local v0 =  py0 / 1000
			local v1 =  py1 / 1000
			
			mesh.Position(px0, py0, i00)
			--mesh.Normal(normal)
			mesh.TexCoord(0, u0, v0)
			mesh.AdvanceVertex()

			mesh.Position(px0, py1, i01)
			--mesh.Normal(normal)
			mesh.TexCoord(0, u0, v1)
			mesh.AdvanceVertex()

			mesh.Position(px1, py1, i11)
			--mesh.Normal(normal)
			mesh.TexCoord(0, u1, v1)
			mesh.AdvanceVertex()

			mesh.Position(px1, py0, i10)
			--mesh.Normal(normal)
			mesh.TexCoord(0, u1, v0)
			mesh.AdvanceVertex()
		end
	end
	mesh.End()

	return imesh
end

-- received
net.Receive("INFMAP_HEIGHTMAP", function(len, ply)
	local heightmap = net.ReadEntity()
	local path = net.ReadString()
	len = len - (#path + 1) * 8 - 13

	local tree = get_quadtree(heightmap):traverse_path(path)
	if len <= 0 then
		print("received invalid tree " .. path .. ".. discarding..")
		tree.children = nil
		return
	end

	local metadata = {}
	while len > 0 do
		table.insert(metadata, net.ReadUInt(16))
		len = len - 16
	end

	local systime = SysTime()
	tree.imesh = generate_tree(tree, metadata)
	print("mesh generation with " .. #metadata .. " points took " .. (SysTime() - systime) * 1000 .. "ms")
end)

local function traverse_render(tree, pos)
	local children = tree.children
	if !children then
		tree.imesh:Draw()
		return
	end

	if !tree:should_split_pos(pos, 2) then
		--tree.children = nil
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

	--[[
	local children = tree.children
	if !children then
		if tree.imesh then
			tree.imesh:Draw()
		end
	else
		for i = 1, 4 do
			traverse_render(children[i], pos)
		end
	end]]
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
		render.SetMaterial(Material("models/wireframe"))
		imesh_offset:SetTranslation(-offset)
		offset:Add(eye_pos)
		cam.PushModelMatrix(imesh_offset)
			traverse_render(quadtree, offset)
		cam.PopModelMatrix()
	end
end)