--AddCSLuaFile()

ENT.Type = "brush"
--ENT.Base = "base_brush"
ENT.PrintName = "infmap_vbsp"

local function update_entity(ent, offset, chunk)
	for e, _ in pairs(ent.INFMAP_CONSTRAINTS) do
		if !isentity(e) then continue end

		e:ForcePlayerDrop()
		e:SetChunk(chunk)
		INFMAP.unfucked_setpos(e, e:INFMAP_GetPos() + offset)
	end
end

local function get_offset(ent)
	return ent:INFMAP_GetPos() - ent:GetVBSPPos() + ent:OBBCenter()
end

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "VBSPPos")
end

function ENT:Initialize()
    self:SetTrigger(true)
	self.INFMAP_VBSP_CHECK = {}
end

function ENT:KeyValue(key, value)
    if key == "chunk" then
		self:SetChunk(INFMAP.Vector(value))
    elseif key == "position" then
		self:SetVBSPPos(Vector(value))
    end
end

-- normal coordinates -> infmap coordinates
function ENT:EndTouch(ent)
	if ent:IsMarkedForDeletion() then return end

	INFMAP.validate_constraints(ent)
	ent = ent.INFMAP_CONSTRAINTS.parent

	if INFMAP.filter_teleport(ent, true) then return end

	update_entity(ent, -get_offset(self), self:GetChunk())
end

-- infmap coordinates -> normal coordinates
function ENT:Think()
	local mins = self:OBBMins()
	local maxs = self:OBBMaxs()
	local center = self:GetVBSPPos() - self:OBBCenter()
	mins:Add(center)
	maxs:Add(center)
	
	for ent, _ in pairs(self.INFMAP_VBSP_CHECK) do
		local pos = ent:INFMAP_GetPos()
		if !INFMAP.aabb_intersect_aabb(pos, pos, mins, maxs) then continue end

		INFMAP.validate_constraints(ent)
		if INFMAP.filter_teleport(ent) then continue end

		update_entity(ent, get_offset(self), nil)
		self.INFMAP_VBSP_CHECK[ent] = false
	end

	debugoverlay.Box(
		INFMAP.unlocalize(vector_origin, self:GetChunk() - Entity(1):GetChunk()), 
		mins, 
		maxs, 
		0.25, 
		Color(0, 255, 0, 0)
	)

	debugoverlay.Box(
		INFMAP.unlocalize(vector_origin, -Entity(1):GetChunk()), 
		self:OBBMins(), 
		self:OBBMaxs(), 
		0.25, 
		Color(255, 0, 0, 0)
	)

	self:NextThink(CurTime())
	return true
end

hook.Add("OnChunkUpdate", "infmap_vbsp", function(ent, chunk, prev_chunk)
	-- TODO: optimize (use hash table)
	for _, vbsp in ipairs(ents.FindByClass("infmap_vbsp")) do
		if prev_chunk == vbsp:GetChunk() then
			vbsp.INFMAP_VBSP_CHECK[ent] = nil
		end

		if chunk == vbsp:GetChunk() then
			vbsp.INFMAP_VBSP_CHECK[ent] = true
		end
	end
end)