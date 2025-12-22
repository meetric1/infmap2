---------------------
-- ENTITY WRAPPING --
---------------------
-- which entities should be checked to be wrapped, per frame
local check_ents = {}
local function check_ent(ent)
	if !INFMAP.filter_teleport(ent) then
		check_ents[ent] = true
		return true
	else
		check_ents[ent] = nil
		return false
	end
end

-- physgun support
local function validate_pickup(ent)
	INFMAP.validate_constraints(ent)

	if ent.INFMAP_CONSTRAINTS then
		ent.INFMAP_CONSTRAINTS.parent = ent
		check_ent(ent)
	end
end

local player_pickups = {}
local function player_pickup(ply, ent) -- key = player, value = prop
	player_pickups[ply] = ent
	validate_pickup(ent)
end

local function player_drop(ply, ent) 
	player_pickups[ply] = nil
end

hook.Add("OnPhysgunPickup", "infmap_pickup", player_pickup)
hook.Add("PhysgunDrop", "infmap_pickup", player_drop)
hook.Add("GravGunOnPickedUp", "infmap_pickup", player_pickup)
hook.Add("GravGunOnDropped", "infmap_pickup", player_drop)
hook.Add("OnPlayerPhysicsPickup", "infmap_pickup", player_pickup)
hook.Add("OnPlayerPhysicsDrop", "infmap_pickup", player_drop)

-- wrapping logic
local function update_entity(ent, chunk)
	for _, e in ipairs(ent.INFMAP_CONSTRAINTS) do
		-- wrap
		local chunk_offset = e:GetChunk() - chunk
		local pos = INFMAP.unlocalize(e:INFMAP_GetPos(), chunk_offset)

		e:SetChunk(chunk)
		INFMAP.unfucked_setpos(e, pos)
	end
end

-- revalidator, just incase an entity for whatever reason becomes wrappable again
timer.Create("infmap_wrap", 10, 0, function()
	for _, ent in ents.Iterator() do
		check_ent(ent)
	end
end)

-- actual wrapping (teleporting)
hook.Add("Think", "infmap_wrap", function()
	for ent, _ in pairs(check_ents) do
		if !IsValid(ent) then
			check_ents[ent] = nil
			continue
		end
		
		if INFMAP.in_chunk(ent:INFMAP_GetPos()) or ent:IsPlayerHolding() then continue end
		INFMAP.validate_constraints(ent)
		if !check_ent(ent) then continue end

		-- time to teleport
		local _, chunk = INFMAP.localize(ent:INFMAP_GetPos())
		chunk = chunk + ent:GetChunk()

		-- hook support (slow..)
		--local err, prevent = INFMAP.hook_run_safe("OnChunkWrap", ent, chunk)
		--if !err and prevent then continue end

		-- teleport
		update_entity(ent, chunk)

		-- if we're holding something, force it into our chunk
		if ent:IsPlayer() then 
			local holding = player_pickups[ent]
			if IsValid(holding) then
				validate_pickup(holding)
				update_entity(holding, chunk)
			end
		end
	end
end)

-----------------
-- CONSTRAINTS --
-----------------
-- rest of the algorithm in sv_infmap_detours.lua!
hook.Add("EntityRemoved", "infmap_constraint", function(ent)
	if !IsValid(ent) or !ent:IsConstraint() then return end

	for _, e in ipairs({ent.Ent1, ent.Ent2}) do
		if !IsValid(e) then continue end
		
		local constraints = e.INFMAP_CONSTRAINTS
		if !constraints then continue end -- duh, already invalid
		
		-- invalidate constraints
		for _, e in ipairs(constraints) do
			e.INFMAP_CONSTRAINTS = nil
			check_ent(e)
		end
	end
end)

---------------------
-- ENTITY SPAWNING --
---------------------
hook.Add("PlayerSpawn", "infmap_respawn", function(ply)
	ply:SetChunk(nil)
end)

-- incase players leave a vehicle fast as fuck and revalidator doesn't catch them in time
hook.Add("PlayerLeaveVehicle", "infmap_respawn", function(ply)
	check_ent(ply)
end)

--[[
hook.Add("OnEntityCreated", "infmap_spawn", function(ent)
	-- TODO: proper prop spawn chunk handling
	if !INFMAP.filter_general(ent) and !ent:IsChunkValid() then
		ent:SetChunk(vector_origin)
	end
end)]]

-------------
-- GLOBALS --
-------------
local ENTITY = FindMetaTable("Entity")
function ENTITY:SetChunk(chunk)
	local prev_chunk = self.INFMAP_CHUNK
	if chunk == prev_chunk then return end

	local err, prevent = INFMAP.hook_run_safe("OnChunkUpdate", self, chunk, prev_chunk)
	if !err and prevent then return end

	if chunk != nil then
		chunk = INFMAP.Vector(chunk) -- copy
	end
	
	self:SetNW2String("INFMAP_CHUNK", INFMAP.encode_vector(chunk))
	self.INFMAP_CHUNK = chunk -- !!!CACHED FOR HIGH PERFORMANCE USE ONLY!!!
	self:SetCustomCollisionCheck(chunk != nil)
	INFMAP.update_cross_chunk_collision(self)
	check_ent(self)

	-- parent support (recursive)
	for _, ent in ipairs(self:GetChildren()) do
		if INFMAP.filter_general(ent) then continue end
		
		ent:SetChunk(chunk)
	end
end