-- VBSP - SERVER
-- handles teleportation and sets up clientside VBSP object, also controls PVS

ENT.Type = "brush"
ENT.PrintName = "infmap_vbsp"

if !INFMAP then return end

-- TODO: physgun support
local function update_entity(ent, offset, chunk)
	for _, e in ipairs(ent.INFMAP_CONSTRAINTS) do
		if e:IsPlayer() then e:DropObject() end
		e:ForcePlayerDrop()

		e:SetChunk(chunk)
		INFMAP.unfucked_setpos(e, e:INFMAP_GetPos() + offset)
	end
end

function ENT:KeyValue(key, value)
    if key == "chunk" then
		self.INFMAP_VBSP_CHUNK = INFMAP.Vector(value)
    elseif key == "position" then
		self.INFMAP_VBSP_POS = Vector(value) -- May be nil
	elseif key == "networkdist" then
		local value = tonumber(value) or 2^15
		self.INFMAP_VBSP_FARZ = value * value
	end
end

local vbsps = {}
function ENT:Initialize()
	local center = self:OBBCenter()
	local mins = self:OBBMins()
	local maxs = self:OBBMaxs()
	local pos_local = self:INFMAP_GetPos() + center
	local pos_world = (self.INFMAP_VBSP_POS or Vector()) + INFMAP.chunk_origin

	local client_vbsp = ents.Create("infmap_vbsp_client")
	client_vbsp:INFMAP_SetPos(pos_world)
	client_vbsp:SetVBSPPos(pos_local)
	client_vbsp:SetVBSPSize((maxs - mins) / 2)
	client_vbsp:SetChunk(self.INFMAP_VBSP_CHUNK)
	--client_vbsp:SetModel("models/sstrp/mcculloch.mdl")
	client_vbsp:Spawn()

	self.INFMAP_VBSP_CHECK = {}
	self.INFMAP_VBSP_OFFSET = pos_local - pos_world
	self.INFMAP_VBSP_MAXS = maxs - self.INFMAP_VBSP_OFFSET
	self.INFMAP_VBSP_MINS = mins - self.INFMAP_VBSP_OFFSET
	self.INFMAP_VBSP_CLIENT = client_vbsp

	vbsps[INFMAP.encode_vector(self.INFMAP_VBSP_CHUNK)] = self
end

function ENT:StartTouch(ent)
	if !ent:IsPlayer() then return end

	ent:SetNWEntity("INFMAP_VBSP", self.INFMAP_VBSP_CLIENT)
end

-- normal coordinates -> infmap coordinates
function ENT:EndTouch(ent)
	if ent:IsMarkedForDeletion() or ent:IsChunkValid() then return end

	INFMAP.validate_constraints(ent)
	if !ent.INFMAP_CONSTRAINTS then return end
	
	ent = ent.INFMAP_CONSTRAINTS.parent
	if INFMAP.filter_teleport(ent, true) then return end

	update_entity(ent, -self.INFMAP_VBSP_OFFSET, self.INFMAP_VBSP_CHUNK)
end

-- infmap coordinates -> normal coordinates
function ENT:Think()
	local mins = self.INFMAP_VBSP_MINS
	local maxs = self.INFMAP_VBSP_MAXS
	
	for ent, _ in pairs(self.INFMAP_VBSP_CHECK) do
		if !IsValid(ent) then
			self.INFMAP_VBSP_CHECK[ent] = nil
		else
			local pos = ent:INFMAP_GetPos()
			if !INFMAP.aabb_intersect_aabb(pos, pos, mins, maxs) then continue end

			INFMAP.validate_constraints(ent)
			if INFMAP.filter_teleport(ent) then continue end

			update_entity(ent, self.INFMAP_VBSP_OFFSET, nil)
		end
	end

	self:NextThink(CurTime())
	return true
end

hook.Add("OnChunkUpdate", "infmap_vbsp", function(ent, chunk, prev_chunk)
	if string.find(ent:GetClass(), "infmap") then return end

	-- old
	local vbsp = vbsps[INFMAP.encode_vector(prev_chunk)]
	if IsValid(vbsp) and vbsp.INFMAP_VBSP_CHECK then
		vbsp.INFMAP_VBSP_CHECK[ent] = nil
	end
	
	-- new
	vbsp = vbsps[INFMAP.encode_vector(chunk)]
	if IsValid(vbsp) and vbsp.INFMAP_VBSP_CHECK then
		vbsp.INFMAP_VBSP_CHECK[ent] = true
	end

	if !ent:IsPlayer() then return end

	-- which vbsps should be added to this players PVS?	
	local check = {}
	if chunk then
		for _, vbsp in pairs(vbsps) do
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

		local eye_pos_local = ply:INFMAP_EyePos()
		for _, vbsp in ipairs(check) do
			local mins, maxs = vbsp.INFMAP_VBSP_MINS, vbsp.INFMAP_VBSP_MAXS
			local eye_pos_world = INFMAP.unlocalize(eye_pos_local, ply:GetChunk() - vbsp.INFMAP_VBSP_CHUNK)
			eye_pos_world[1] = math.Clamp(eye_pos_world[1], mins[1], maxs[1])
			eye_pos_world[2] = math.Clamp(eye_pos_world[2], mins[2], maxs[2])
			eye_pos_world[3] = math.Clamp(eye_pos_world[3], mins[3], maxs[3])
			eye_pos_world:Add(vbsp.INFMAP_VBSP_OFFSET)

			AddOriginToPVS(eye_pos_world)

			--eye_pos_world = eye_pos_world - vbsp.INFMAP_VBSP_OFFSET
			--debugoverlay.Sphere(eye_pos_world, 10, 1, Color(255, 0, 255, 0), true)
			--debugoverlay.Box(vector_origin, mins, maxs, 1, Color(255, 0, 255, 0))
		end
	end
end)