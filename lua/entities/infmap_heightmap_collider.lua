AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "terrain_heightmap_collider"

if !INFMAP then return end

-- vector objects are slow as shit
local vertices = {}
for i = 1, 17 * 17 do
	vertices[i] = Vector()
end

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Heightmap")
	self:NetworkVar("String", 0, "Path")
end

function ENT:InitializePhysics()
	local heightmap = self:GetHeightmap()
	if !IsValid(heightmap) then return end

	local quadtree = heightmap.INFMAP_HEIGHTMAP_QUADTREE
	if !quadtree then return end

	-- tree may exist, but we haven't generated metadata
	local tree = quadtree:traverse_path(self:GetPath())
	if !tree or !tree.metadata then return end

	local skip = 1
	local metadata = tree.metadata
	local res = math.sqrt(#metadata)
	local res_1 = res - 1
	local scale = tree.size / res_1
	local res_skip = res_1 / skip + 1
	assert(res_skip == math.floor(res_skip))

	local offset_z = INFMAP.unlocalize(vector_origin, heightmap:GetChunk() - self:GetChunk())[3]
	local i = 1
	for y = 0, res_1, skip do
		for x = 0, res_1, skip do
			local px = x * scale
			local py = y * scale
			local pz = metadata[(y * res + x) + 1] + offset_z
			vertices[i]:SetUnpacked(px, py, pz)
			i = i + 1
		end
	end

	local triangles = {}
	for y = 0, res_skip - 2 do
		local table_insert = table.insert
		for x = 0, res_skip - 2 do
			-- heightmap 
			local p00 = vertices[(y    ) * res_skip + (x    ) + 1]
			local p10 = vertices[(y    ) * res_skip + (x + 1) + 1]
			local p01 = vertices[(y + 1) * res_skip + (x    ) + 1]
			local p11 = vertices[(y + 1) * res_skip + (x + 1) + 1]

			if x % 2 == y % 2 then
				table_insert(triangles, p00)
				table_insert(triangles, p01)
				table_insert(triangles, p11)
				table_insert(triangles, p00)
				table_insert(triangles, p11)
				table_insert(triangles, p10)
			else
				table_insert(triangles, p10)
				table_insert(triangles, p00)
				table_insert(triangles, p01)
				table_insert(triangles, p10)
				table_insert(triangles, p01)
				table_insert(triangles, p11)
			end
		end
	end

	-- cutoff
	--local chunk_top = INFMAP.chunk_origin + Vector(0, 0, INFMAP.chunk_size)
	--local chunk_bottom = INFMAP.chunk_origin - Vector(0, 0, INFMAP.chunk_size)
	--triangles = INFMAP.split_concave(triangles, chunk_top, Vector(0, 0, -1))
	--triangles = INFMAP.split_concave(triangles, chunk_bottom, Vector(0, 0, 1))

	self:PhysicsFromMesh(triangles)
	self:EnableCustomCollisions(true)
	self:GetPhysicsObject():EnableMotion(false)
	self:AddEFlags(EFL_NO_THINK_FUNCTION)

	if SERVER then
		INFMAP.update_cross_chunk_collision(self)
	end
	
	--print("physmesh generation with " .. #triangles .. " points took " .. (SysTime() - s) * 1000 .. "ms")

	--[[
	if SERVER then
		for i = 1, #triangles, 3 do
			local p1 = self:INFMAP_LocalToWorld(triangles[i    ]) + VectorRand()
			local p2 = self:INFMAP_LocalToWorld(triangles[i + 1]) + VectorRand()
			local p3 = self:INFMAP_LocalToWorld(triangles[i + 2]) + VectorRand()
			debugoverlay.Triangle(p1, p2, p3, 10, Color(0, 255, 255, 100))
		end
	end]]
end

if CLIENT then
	function ENT:Initialize()
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
	end

	function ENT:Think()
		if !IsValid(self:GetPhysicsObject()) then
			self:InitializePhysics()
		end

		-- scatter generation time across multiple frames
		self:SetNextClientThink(CurTime() + 0.5 + math.random() * 0.5)
		return true
	end
else
	function ENT:Initialize()
		self:SetNoDraw(true)
		self:SetModel("models/props_c17/FurnitureCouch002a.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:InitializePhysics()
	end
end

hook.Add("PhysgunPickup", "infmap_heightmap_disablepickup", function(_, ent)
	if ent:GetClass() == "infmap_heightmap_collider" then
		return false 
	end
end)