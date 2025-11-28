-----------------
-- CONSTRAINTS --
-----------------
-- rest of the algorithm in sv_infmap_detours.lua!
hook.Add("EntityRemoved", "infmap_constraint", function(ent)
	if !IsValid(ent) or !ent:IsConstraint() then return end

	for _, e in ipairs({ent.Ent1, ent.Ent2}) do
		if !IsValid(e) then continue end
		
		INFMAP.invalidate_constraints(e)
	end
end)

---------------------
-- PHYSGUN SUPPORT --
---------------------
local function validate_pickup(ent)
	INFMAP.validate_constraints(ent)

	if ent.INFMAP_CONSTRAINTS then
		ent.INFMAP_CONSTRAINTS.parent = ent
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

---------------------------
-- CROSS-CHUNK COLLISION --
---------------------------
-- collision with props crossing through chunk bounderies
local function update_cross_chunk_collision(ent, disable)
	if INFMAP.filter_collision(ent) or INFMAP.in_chunk(ent:INFMAP_GetPos(), INFMAP.chunk_size - ent:BoundingRadius()) then
		-- outside of area for cloning to happen (or invalidated), remove all clones
		if ent.INFMAP_CLONES then
			for _, e in pairs(ent.INFMAP_CLONES) do
				SafeRemoveEntity(e)
			end
			ent.INFMAP_CLONES = nil
		end

		return
	end

	ent.INFMAP_CLONES = ent.INFMAP_CLONES or {}

	local i = 0
	local aabb_min, aabb_max = ent:INFMAP_WorldSpaceAABB()
	local chunk_size = Vector(INFMAP.chunk_size, INFMAP.chunk_size, INFMAP.chunk_size)
	for z = -1, 1 do 
		for y = -1, 1 do 
			for x = -1, 1 do
				-- never clone in the same chunk the object is already in
				if x == 0 and y == 0 and z == 0 then continue end

				i = i + 1

				-- if in chunk next to it, clone
				local chunk_offset = INFMAP.Vector(x, y, z)
				local chunk_max = INFMAP.unlocalize(INFMAP.chunk_origin, chunk_offset)
				local chunk_min = chunk_max - chunk_size
				chunk_max:Add(chunk_size)

				if INFMAP.aabb_intersect_aabb(aabb_min, aabb_max, chunk_min, chunk_max) then
					-- dont clone 2 times
					local stored = ent.INFMAP_CLONES[i]
					local offset = ent:GetChunk() + chunk_offset

					if IsValid(stored) then
						stored:SetChunk(offset)
					else
						local clone = ents.Create("infmap_clone")
						clone:SetReferenceParent(ent)
						clone:SetChunk(offset)
						clone:Spawn()
						ent.INFMAP_CLONES[i] = clone
					end
				else
					if !IsValid(ent.INFMAP_CLONES[i]) then continue end

					-- remove cloned object if its moved out of chunk
					SafeRemoveEntity(ent.INFMAP_CLONES[i])
					ent.INFMAP_CLONES[i] = nil
				end
			end 
		end 
	end
end

---------------------
-- ENTITY WRAPPING --
---------------------
-- entity teleporting logic
local function update_entity(ent, chunk)
	for e, _ in pairs(ent.INFMAP_CONSTRAINTS) do
		if !isentity(e) then continue end

		-- sorry other players..
		if e != ent then
			e:ForcePlayerDrop()
		end

		-- wrap
		local chunk_offset = e:GetChunk() - chunk
		local pos = INFMAP.unlocalize(e:INFMAP_GetPos(), chunk_offset)
		e:SetChunk(chunk)
		INFMAP.unfucked_setpos(e, pos)
	end
end

-- which entities should be checked per frame (optimization filter)
-- TODO: should we refactor this?
local check_ents = {}
timer.Create("infmap_wrap_check", 0.1, 0, function()
	check_ents = {}

	for _, ent in ents.Iterator() do
		update_cross_chunk_collision(ent)

		if (!ent:GetVelocity():IsZero() or ent.INFMAP_DIRTY_WRAP) and !INFMAP.filter_teleport(ent) then 
			table.insert(check_ents, ent)
		end

		ent.INFMAP_DIRTY_WRAP = nil -- TODO: REMOVE ME!! We should be directly shoving into check_ents
	end
end)

-- wrapping (teleporting)
hook.Add("Think", "infmap_wrap", function()
	for _, ent in ipairs(check_ents) do
		if !IsValid(ent) then continue end
		if INFMAP.in_chunk(ent:INFMAP_GetPos()) or ent:IsPlayerHolding() then continue end

		INFMAP.validate_constraints(ent)
		if INFMAP.filter_teleport(ent) then continue end -- required check just incase the constraint table updated

		-- time to teleport
		local _, chunk = INFMAP.localize(ent:INFMAP_GetPos())
		chunk = chunk + ent:GetChunk()

		-- hook support (slow..)
		local err, prevent = INFMAP.hook_run_safe("OnChunkWrap", ent, chunk)
		if !err and prevent then continue end

		-- teleport
		update_entity(ent, chunk)

		-- if we're holding something, force it into our chunk
		if ent:IsPlayer() then 
			local holding = player_pickups[ent]
			if IsValid(holding) then
				validate_pickup(holding)
				update_entity(holding, chunk)

				-- for the rare case where 2 players are holding the same object
				for p, e in pairs(player_pickups) do if e == holding and p != ent then p:DropObject() end end
			end
		end
	end
end)

---------------------
-- ENTITY SPAWNING --
---------------------
--[[
hook.Add("PlayerSpawn", "infmap_respawn", function(ply, trans)
	if ply:IsChunkValid() and !trans then
		ply:SetChunk(INFMAP.Vector())
	end
end)

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
	local err, prevent = INFMAP.hook_run_safe("OnChunkUpdate", self, chunk, self.INFMAP_CHUNK)
	if !err and prevent then return end
	
	if chunk != nil then
		chunk = INFMAP.Vector(chunk) -- copy
	end

	self:SetNW2String("INFMAP_CHUNK", INFMAP.encode_vector(chunk))
	self.INFMAP_CHUNK = chunk -- !!!CACHED FOR HIGH PERFORMANCE USE ONLY!!!
	self:SetCustomCollisionCheck(chunk != nil)
	update_cross_chunk_collision(self)

	-- parent support (recursive)
	for _, ent in ipairs(self:GetChildren()) do
		if INFMAP.filter_general(ent) or ent:InChunk(chunk) then continue end
		
		ent:SetChunk(chunk)
	end
end