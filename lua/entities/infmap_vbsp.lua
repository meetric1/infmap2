-- VBSP - SERVER
-- handles teleportation and sets up clientside VBSP object, also controls PVS

ENT.Type = "brush"
ENT.PrintName = "infmap_vbsp"

if !INFMAP then return end

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

hook.Add("SetupPlayerVisibility", "infmap_vbsp", function(ply, view_entity)
	if !ply:IsChunkValid() then
		AddOriginToPVS(INFMAP.chunk_origin)
	else
		for _, vbsp in ipairs(ents.FindByClass("infmap_vbsp")) do
			-- TODO: optimize (if far away.. don't bother. also, use existing defined MINS MAXS)
			local pos = vbsp:INFMAP_GetPos()
			local mins, maxs = vbsp:OBBMins() * 0.99, vbsp:OBBMaxs() * 0.99 -- TODO: come on xal... we need wiggle room
			mins:Add(pos)
			maxs:Add(pos)
			
			local eye_pos = INFMAP.unlocalize(ply:INFMAP_EyePos() + vbsp.INFMAP_VBSP_OFFSET, ply:GetChunk() - vbsp:GetChunk())
			eye_pos[1] = math.Clamp(eye_pos[1], mins[1], maxs[1])
			eye_pos[2] = math.Clamp(eye_pos[2], mins[2], maxs[2])
			eye_pos[3] = math.Clamp(eye_pos[3], mins[3], maxs[3])

			AddOriginToPVS(eye_pos)

			--eye_pos = eye_pos - vbsp.INFMAP_VBSP_OFFSET
			--debugoverlay.Sphere(eye_pos, 10, 1, Color(255, 0, 255, 0), true)
			--debugoverlay.Box(vector_origin, mins, maxs, 1, Color(255, 0, 255, 0))
		end
	end
end)