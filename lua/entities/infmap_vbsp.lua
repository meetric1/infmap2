-- VBSP - SERVER
-- handles teleportation and sets up clientside VBSP object

ENT.Type = "brush"
--ENT.Base = "anim"
ENT.PrintName = "infmap_vbsp"

local function update_entity(ent, offset, chunk)
	for e, _ in pairs(ent.INFMAP_CONSTRAINTS) do
		if !isentity(e) then continue end

		e:ForcePlayerDrop()
		e:SetChunk(chunk)
		INFMAP.unfucked_setpos(e, e:INFMAP_GetPos() + offset)
	end
end

function ENT:KeyValue(key, value)
    if key == "chunk" then
		self:SetChunk(INFMAP.Vector(value))
    elseif key == "position" then
		self.INFMAP_VBSP_POS = Vector(value)
    end
end

function ENT:Initialize()
	local center = self:OBBCenter()
	local mins = self:OBBMins()
	local maxs = self:OBBMaxs()
	local pos_local = self:INFMAP_GetPos() + center
	local pos_world = self.INFMAP_VBSP_POS + INFMAP.chunk_origin

	local client_vbsp = ents.Create("infmap_vbsp_client")
	client_vbsp:INFMAP_SetPos(pos_world)
	client_vbsp:SetVBSPPos(pos_local)
	client_vbsp:SetVBSPSize(maxs - mins)
	client_vbsp:SetChunk(self:GetChunk())
	client_vbsp:Spawn()

	self.INFMAP_VBSP_OFFSET = pos_local - pos_world
	self.INFMAP_VBSP_MAXS = maxs - self.INFMAP_VBSP_OFFSET
	self.INFMAP_VBSP_MINS = mins - self.INFMAP_VBSP_OFFSET

	self.INFMAP_VBSP_CLIENT = client_vbsp
	self.INFMAP_VBSP_CHECK = {}
end

-- normal coordinates -> infmap coordinates
function ENT:EndTouch(ent)
	if ent:IsMarkedForDeletion() then return end

	INFMAP.validate_constraints(ent)
	ent = ent.INFMAP_CONSTRAINTS.parent
	if INFMAP.filter_teleport(ent, true) then return end

	update_entity(ent, -self.INFMAP_VBSP_OFFSET, self:GetChunk())
end

-- infmap coordinates -> normal coordinates
function ENT:Think()
	local mins = self.INFMAP_VBSP_MINS
	local maxs = self.INFMAP_VBSP_MAXS
	
	for ent, _ in pairs(self.INFMAP_VBSP_CHECK) do
		local pos = ent:INFMAP_GetPos()
		if !INFMAP.aabb_intersect_aabb(pos, pos, mins, maxs) then continue end

		INFMAP.validate_constraints(ent)
		if INFMAP.filter_teleport(ent) then continue end

		update_entity(ent, self.INFMAP_VBSP_OFFSET, nil)
		self.INFMAP_VBSP_CHECK[ent] = false
	end

	self:NextThink(CurTime())
	return true
end

hook.Add("OnChunkUpdate", "infmap_vbsp", function(ent, chunk, prev_chunk)
	-- TODO: optimize (use hash table)
	for _, vbsp in ipairs(ents.FindByClass("infmap_vbsp")) do
		if !vbsp.INFMAP_VBSP_CHECK then continue end

		if prev_chunk == vbsp:GetChunk() then
			vbsp.INFMAP_VBSP_CHECK[ent] = nil
		end

		if chunk == vbsp:GetChunk() then
			vbsp.INFMAP_VBSP_CHECK[ent] = true
		end
	end
end)