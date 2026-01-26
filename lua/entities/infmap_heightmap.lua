AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_heightmap"

if !INFMAP then return end

local RESOLUTION = 8
local function validate_tree(heightmap, tree)
	if tree.metadata then return end

	local metadata = {}
	local sampler = heightmap.INFMAP_HEIGHTMAP_SAMPLER
	local inv_res = tree.size / RESOLUTION
	local inv_size = 1 / heightmap.INFMAP_HEIGHTMAP_QUADTREE.size
	local min, max
	for y = 0, RESOLUTION do
		for x = 0, RESOLUTION do
			local sample = sampler:sample(
				(tree.pos[1] + x * inv_res) * inv_size, 
				(tree.pos[2] + y * inv_res) * inv_size,
				false
			)

			min, max = math.min(min or sample, sample), math.max(max or sample, sample)
			table.insert(metadata, sample)
		end
	end
	metadata.min = min
	metadata.max = max
	tree.metadata = metadata
end

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Path")
	self:NetworkVar("String", 1, "MaterialInternal")
	self:NetworkVar("Float", 0, "Height")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:KeyValue(key, value)
	if key == "path" then
		self:SetPath(value)
		self:SetChunk(INFMAP.Vector(0, 0, 0))
	elseif key == "mat" then
		self:SetMaterialInternal(value)
	end
end

local heightmaps = ents.FindByClass("infmap_heightmap")--{}
function ENT:Initialize()
	--self:SetNoDraw(true)
	self:SetNotSolid(true)

	self.INFMAP_HEIGHTMAP_SAMPLER = INFMAP.Sampler("materials/" .. self:GetPath())
	self.INFMAP_HEIGHTMAP_QUADTREE = INFMAP.Quadtree(Vector(), 393701) -- 10KM
	table.insert(heightmaps, self)

	if CLIENT then
		local mat_path = self:GetMaterialInternal()
		self.INFMAP_HEIGHTMAP_MATERIAL = Material(mat_path)
		self.INFMAP_HEIGHTMAP_MATERIAL_FLASHLIGHT = CreateMaterial(mat_path .. "_vl", "VertexLitGeneric", {
			["$basetexture"] = self.INFMAP_HEIGHTMAP_MATERIAL:GetString("$basetexture")
		})
		self:SetRenderBounds(Vector(), Vector(393701, 393701, 65536))
	end
end

------------------
-- SERVER LOGIC --
------------------
if SERVER then
	local function traverse_collision(heightmap, tree, local_pos)
		if !tree.colliders and tree.bottom and tree:should_split_pos(local_pos, 1, true) then
			tree.colliders = {}
			validate_tree(heightmap, tree)

			-- TODO: only spawn relevant chunks (for VERY steep slopes)
			local world_pos = heightmap:INFMAP_GetPos()
			for i = 1, 3 do world_pos[i] = world_pos[i] + tree.pos[i] end

			local world_pos, world_chunk = INFMAP.localize(world_pos)
			world_chunk = world_chunk + heightmap:GetChunk()

			local _, chunk_min = INFMAP.localize(Vector(0, 0, world_pos[3] + tree.metadata.min))
			local _, chunk_max = INFMAP.localize(Vector(0, 0, world_pos[3] + tree.metadata.max))
			local bottom = world_chunk[3] + chunk_min[3]
			local top = world_chunk[3] + chunk_max[3]
			for z = bottom, top do
				local collider = ents.Create("infmap_heightmap_collider")
				collider:SetHeightmap(heightmap)
				collider:SetPath(tree.path)
				collider:SetChunk(world_chunk + INFMAP.Vector(0, 0, z))
				collider:INFMAP_SetPos(world_pos)
				collider:Spawn()
				table.insert(tree.colliders, collider)
			end
		end

		if tree:should_split_pos(local_pos, 0.5) then
			tree.curtime = CurTime()
			tree:split()

			for i = 1, 4 do
				traverse_collision(heightmap, tree.children[i], local_pos)
			end
		else
			-- tree hasn't been visited in a while, invalidate it
			if tree.curtime and tree.curtime + 1 < CurTime() then
				tree:traverse(function(self)
					if !self.colliders then return end

					for k, v in ipairs(self.colliders) do 
						SafeRemoveEntity(v) 
					end
				end)

				tree.children = nil
				tree.curtime = nil
			end
		end
	end

	timer.Create("INFMAP_HEIGHTMAP", 0.1, 0, function()
		for _, ply in player.Iterator() do
			local pos, chunk
			if ply:IsChunkValid() then
				pos = ply:INFMAP_GetPos()
				chunk = ply:GetChunk()
			else
				local vbsp_client = ply:GetNWEntity("INFMAP_VBSP_CLIENT")
				if !IsValid(vbsp_client) then
					continue -- where the fuck are we?
				end

				pos = INFMAP.VBSP.to_world(vbsp_client) * ply:INFMAP_EyePos()
				chunk = vbsp_client:GetChunk()
			end

			if !chunk then continue end

			for _, heightmap in ipairs(heightmaps) do
				if !heightmap.INFMAP_HEIGHTMAP_SAMPLER or !heightmap.INFMAP_HEIGHTMAP_SAMPLER.metadata then continue end

				local pos_local = INFMAP.unlocalize(pos - heightmap:INFMAP_GetPos(), chunk - heightmap:GetChunk())
				traverse_collision(heightmap, heightmap.INFMAP_HEIGHTMAP_QUADTREE, pos_local)
			end
		end

		--print("heightmaps parsed in " .. (SysTime() - s) * 1000 .. "ms")
	end)

	return
end

------------------
-- CLIENT LOGIC --
------------------
local function generate_tree(heightmap, tree)
	local s = SysTime()
	
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
		mesh.Normal(0, 0, 1)
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

local imesh_queue = INFMAP.Queue()
local function traverse_render(heightmap, tree, pos)
	if !tree.queued then
		tree.queued = true
		imesh_queue:insert({heightmap, tree})
	end

	if !tree.imesh then 
		return 
	end
	
	if !tree:should_split_pos(pos, 2) then
		tree.imesh:Draw()
		tree.children = nil
		return
	end
	
	local children = tree.children
	if !children then
		tree:split()
		children = tree.children
		tree.imesh:Draw()
	else
		for i = 1, 4 do
			if !children[i].imesh then
				tree.imesh:Draw()
				return
			end
		end
	end

	for i = 1, 4 do
		traverse_render(heightmap, children[i], pos)
	end
end

function ENT:Draw()
	-- meshes aren't ready yet
	if !self.INFMAP_HEIGHTMAP_SAMPLER.metadata then return end

	local quadtree = self.INFMAP_HEIGHTMAP_QUADTREE
	local local_player = LocalPlayer()

	-- figure out where to do LODs
	local offset
	if local_player:IsChunkValid() then
		offset = INFMAP.unlocalize(
			local_player:INFMAP_EyePos() - self:INFMAP_GetPos(), 
			local_player:GetChunk() - self:GetChunk()
		)
	else
		local vbsp_client = local_player:GetNWEntity("INFMAP_VBSP_CLIENT")
		if !IsValid(vbsp_client) then
			return -- where the fuck are we?
		end

		offset = INFMAP.unlocalize(
			INFMAP.VBSP.to_world(vbsp_client) * local_player:INFMAP_EyePos(),
			vbsp_client:GetChunk() - self:GetChunk()
		)
	end

	cam.PushModelMatrix(self:GetWorldTransformMatrix())
		render.OverrideDepthEnable(true, true)

		--render.SetMaterial(Material("models/wireframe"))
		--render.SetMaterial(Material("models/props_combine/combine_interface_disp"))
		render.SetMaterial(self.INFMAP_HEIGHTMAP_MATERIAL)
		traverse_render(self, quadtree, offset)

		-- TODO: better flashlight
		render.SetMaterial(self.INFMAP_HEIGHTMAP_MATERIAL_FLASHLIGHT)
		render.RenderFlashlights(function()
			traverse_render(self, quadtree, offset)
		end)

		render.OverrideDepthEnable(false, false)
	cam.PopModelMatrix()

	--local mins, maxs = self:INFMAP_GetRenderBounds()
	--debugoverlay.Box(self:INFMAP_GetPos(), mins, maxs, 0.1, Color(255, 0, 255, 0))
end

-- rendering
hook.Add("PostDrawOpaqueRenderables", "infmap_heightmap", function(_, _, sky3d)
	-- build heightmap (if applicable)
	local new_tree = imesh_queue:remove()
	if new_tree then
		validate_tree(new_tree[1], new_tree[2])
		generate_tree(new_tree[1], new_tree[2])
		--print("mesh generation with " .. RESOLUTION .. " points took " .. (SysTime() - s) * 1000 .. "ms")
	end
end)