-- VBSP - SERVER
-- handles teleportation and sets up clientside VBSP object, also controls PVS

ENT.Type = "brush" -- serverside ONLY
ENT.PrintName = "infmap_vbsp"

if !INFMAP or CLIENT then return end

function ENT:KeyValue(key, value)
    if key == "chunk" then
		self.INFMAP_VBSP_CHUNK = INFMAP.Vector(value)
    elseif key == "position" then
		self.INFMAP_VBSP_POS = Vector(value)
		self.INFMAP_VBSP_ANG = Angle()
	elseif key == "networkdist" then
		local value = tonumber(value) or 2^15
		self.INFMAP_VBSP_FARZ = value * value
	end
end

-- uhh...
function ENT:VBSPOffset()
	return self:INFMAP_GetPos() + self:OBBCenter()
end

function ENT:SetVBSPPos(pos)
	self.INFMAP_VBSP_POS = pos
	self.INFMAP_VBSP_CLIENT:INFMAP_SetPos(self.INFMAP_VBSP_POS + INFMAP.chunk_origin)
end

function ENT:SetVBSPChunk(chunk)
	self.INFMAP_VBSP_CHUNK = chunk
	self.INFMAP_VBSP_CLIENT:SetChunk(chunk)
end

function ENT:SetVBSPAngles(ang)
	self.INFMAP_VBSP_ANG = ang
	self.INFMAP_VBSP_CLIENT:SetAngles(ang)
end

function ENT:Initialize()
	local vbsp_client = ents.Create("infmap_vbsp_client")
	local center = self:OBBCenter()
	local mins = self:OBBMins()
	local maxs = self:OBBMaxs()
	self.INFMAP_VBSP_MAXS = maxs - center
	self.INFMAP_VBSP_MINS = mins - center
	vbsp_client:SetVBSPPos(self:VBSPOffset())
	vbsp_client:SetVBSPSize((maxs - mins) / 2)
	vbsp_client:SetVBSPFarZ(self.INFMAP_VBSP_FARZ)
	vbsp_client:Spawn()
	self.INFMAP_VBSP_CLIENT = vbsp_client

	-- update client vbsp
	self:SetVBSPPos(self.INFMAP_VBSP_POS)
	self:SetVBSPAngles(self.INFMAP_VBSP_ANG)
	self:SetVBSPChunk(self.INFMAP_VBSP_CHUNK)
end

function ENT:StartTouch(ent)
	if !ent:IsPlayer() then return end
	
	ent:SetNWEntity("INFMAP_VBSP_CLIENT", self.INFMAP_VBSP_CLIENT)
end

-- VBSP -> INFMAP
function ENT:EndTouch(ent)
	if ent:IsMarkedForDeletion() or ent:IsChunkValid() then return end

	INFMAP.validate_constraints(ent)
	if INFMAP.filter_teleport(ent, true) then return end

	if ent:IsPlayer() then 
		ent:DropObject()
	end

	-- project to infmap, localize to relevant chunk (incase vbsp intersects a chunk border)
	local translation = INFMAP.VBSP.to_world(self.INFMAP_VBSP_CLIENT)
	local _, chunk_offset = INFMAP.localize(translation * ent:INFMAP_GetPos())
	local translation_offset = Matrix()
	translation_offset:SetTranslation(INFMAP.unlocalize(vector_origin, -chunk_offset))
	translation_offset:Mul(translation)
	INFMAP.translate_constraints(ent.INFMAP_CONSTRAINED, translation_offset, self.INFMAP_VBSP_CHUNK + chunk_offset)
end

-- INFMAP -> VBSP
function ENT:Think()
	local mins = self.INFMAP_VBSP_MINS
	local maxs = self.INFMAP_VBSP_MAXS

	-- TODO: INFMAP_VBSP_CHECK on entities instead of per-frame check
	for ent, _ in pairs(INFMAP.wrapped_ents) do
		if !ent:InChunk(self.INFMAP_VBSP_CHUNK) then continue end

		local vbsp_client = self.INFMAP_VBSP_CLIENT
		local pos = vbsp_client:INFMAP_WorldToLocal(ent:INFMAP_GetPos())
		if !INFMAP.aabb_intersect_aabb(pos, pos, mins, maxs) then continue end

		INFMAP.validate_constraints(ent)
		if INFMAP.filter_teleport(ent) then continue end

		if ent:IsPlayer() then ent:DropObject() end
		INFMAP.translate_constraints(ent.INFMAP_CONSTRAINED, INFMAP.VBSP.to_local(vbsp_client), nil)
	end

	--self:SetVBSPAngles(Angle(0, 45, 180))
	self:SetVBSPAngles(Angle(CurTime() * 1, CurTime() * 2, CurTime() * 3))
	--self:NextThink(CurTime())
	--return true
end

hook.Add("OnChunkUpdate", "infmap_vbsp", function(ent, chunk, prev_chunk)
	if !ent:IsPlayer() then return end

	-- which vbsps should be added to this players PVS?
	local check = {}
	if chunk then
		for _, vbsp in ipairs(ents.FindByClass("infmap_vbsp")) do -- TODO: findbyclass is slow
			if INFMAP.unlocalize(vector_origin, vbsp.INFMAP_VBSP_CHUNK - chunk):LengthSqr() <= vbsp.INFMAP_VBSP_FARZ then
				check[#check + 1] = vbsp
			end
		end
	end
	ent.INFMAP_VBSP_CHECK = #check > 0 and check or nil
end)

hook.Add("SetupPlayerVisibility", "infmap_vbsp", function(ply, view_entity)
	if !ply:IsChunkValid() then
		-- VBSP -> INFMAP
		AddOriginToPVS(INFMAP.chunk_origin)
	else
		-- INFMAP -> VBSP
		local check = ply.INFMAP_VBSP_CHECK
		if !check then return end

		local eye_pos_world = ply:INFMAP_EyePos()
		for _, vbsp in ipairs(check) do
			-- project into local space, clamp, then project to vbsp space
			local eye_pos_local = INFMAP.unlocalize(eye_pos_world, ply:GetChunk() - vbsp.INFMAP_VBSP_CHUNK)
			eye_pos_local = vbsp.INFMAP_VBSP_CLIENT:INFMAP_WorldToLocal(eye_pos_local)

			local mins, maxs = vbsp.INFMAP_VBSP_MINS, vbsp.INFMAP_VBSP_MAXS
			eye_pos_local[1] = math.Clamp(eye_pos_local[1], mins[1], maxs[1])
			eye_pos_local[2] = math.Clamp(eye_pos_local[2], mins[2], maxs[2])
			eye_pos_local[3] = math.Clamp(eye_pos_local[3], mins[3], maxs[3])
			eye_pos_local:Add(vbsp:VBSPOffset())
			AddOriginToPVS(eye_pos_local)
			
			-- debug (project back to worldspace for viewing pleasure)
			--eye_pos_local:Sub(vbsp:VBSPOffset())
			--eye_pos_local:Set(vbsp.INFMAP_VBSP_CLIENT:INFMAP_LocalToWorld(eye_pos_local))
			--debugoverlay.Sphere(eye_pos_local, 10, 1, Color(255, 0, 255, 0), true)
			--debugoverlay.Box(vbsp.INFMAP_VBSP_CLIENT:INFMAP_GetPos(), mins, maxs, 1, Color(255, 0, 255, 0))
		end
	end
end)