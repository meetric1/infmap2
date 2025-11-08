-- setting position kills all velocity
local source_bounds = 2^14 - 64
local math_Clamp = math.Clamp
local function unfucked_setpos(ent, pos)
	pos[1] = math_Clamp(pos[1], -source_bounds, source_bounds)
	pos[2] = math_Clamp(pos[2], -source_bounds, source_bounds)
	pos[3] = math_Clamp(pos[3], -source_bounds, source_bounds)

	-- ragdoll moment
	if ent:IsRagdoll() then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys = ent:GetPhysicsObjectNum(i)
			local vel = phys:GetVelocity()
			local diff = phys:INFMAP_GetPos() - ent:INFMAP_GetPos()
		
			phys:INFMAP_SetPos(pos + diff)
			phys:SetVelocity(vel)
		end

		ent:INFMAP_SetPos(pos)
	else
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then 
			local vel = phys:GetVelocity()
			ent:INFMAP_SetPos(pos)
			phys:SetVelocity(vel)
		else
			ent:INFMAP_SetPos(pos)
		end
	end
end

-----------------
-- CONSTRAINTS --
-----------------

-- merges entity
local function merge(ent, constrained, offset)
	constrained[ent] = true
	ent.INFMAP_CONSTRAINED = constrained
	local chunk = ent:GetChunk() chunk:Sub(offset)
	unfucked_setpos(ent, INFMAP.unlocalize(ent:INFMAP_GetPos(), chunk))
	ent:SetChunk(offset)
end

-- welcome to my insanely fuckass algorithm
local function validate_constraints(ent, prev)
	if INFMAP.filter_constraint(ent) then return end

	if !ent.INFMAP_CONSTRAINED then
		ent.INFMAP_CONSTRAINED = {[ent] = true, ["parent"] = ent}
	end

	if IsValid(prev) then
		local prev_constrained = prev.INFMAP_CONSTRAINED
		local ent_constrained = ent.INFMAP_CONSTRAINED
		if prev_constrained == ent_constrained then
			-- already checked
			return 
		end

		-- merge ent_constrained -> prev_constrained
		local chunk_offset = prev:GetChunk()
		for e, _ in pairs(ent_constrained) do
			if !isentity(e) then continue end

			merge(e, prev_constrained, chunk_offset)
		end

		-- flip
		prev_constrained.parent = ent_constrained.parent
	end

	-- recurse
	for _, constrained in ipairs(constraint.GetTable(ent)) do
		for _, e in pairs(constrained.Entity) do
			e = e.Entity
			if e == ent then continue end

			validate_constraints(e, ent)
		end
	end
end

local function invalidate_constraints(ent)
	local invalid_constrained = ent.INFMAP_CONSTRAINED
	if !invalid_constrained then return end -- duh, invalid

	for e, _ in pairs(invalid_constrained) do
		if !IsValid(e) or !isentity(e) then continue end

		e.INFMAP_CONSTRAINED = nil
	end
end

local function try_constraint(ent, func)
	if !ent:IsConstraint() then return end

	-- use Ent2 first, since usually its Ent1 (smaller thing) being constrained to Ent2 (bigger thing)
	for _, e in ipairs({ent.Ent2, ent.Ent1}) do
		if IsValid(e) and e.INFMAP_CONSTRAINED and !INFMAP.filter_constraint(e) then
			func(e)
		end
	end
end

hook.Add("OnEntityCreated", "infmap_spawn", function(ent)
	-- TODO: proper prop spawn chunk handling
	--if !INFMAP.filter_general(ent) and !ent:IsChunkValid() then
	--	ent:SetChunk(vector_origin)
	--end

	timer.Simple(0, function()
		if !IsValid(ent) then return end

		try_constraint(ent, validate_constraints)
	end)
end)

hook.Add("EntityRemoved", "infmap_remove", function(ent)
	if !IsValid(ent) then return end

	try_constraint(ent, invalidate_constraints)
end)

---------------------
-- PHYSGUN SUPPORT --
---------------------

local player_pickups = {}
local function player_pickup(ply, ent) -- key = player, value = prop
	player_pickups[ply] = ent
	if ent.INFMAP_CONSTRAINED then
		ent.INFMAP_CONSTRAINED.parent = ent
	end
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
	local chunk_offset = Vector()
	for z = -1, 1 do 
		for y = -1, 1 do 
			for x = -1, 1 do
				-- never clone in the same chunk the object is already in
				if x == 0 and y == 0 and z == 0 then continue end

				i = i + 1

				-- if in chunk next to it, clone
				chunk_offset:SetUnpacked(x, y, z)
				local chunk_max = INFMAP.unlocalize(INFMAP.chunk_origin, chunk_offset)
				local chunk_min = chunk_max - chunk_size
				chunk_max:Add(chunk_size)

				if INFMAP.aabb_intersect_aabb(aabb_min, aabb_max, chunk_min, chunk_max) then
					-- dont clone 2 times
					local stored = ent.INFMAP_CLONES[i]
					local offset = ent:GetChunk() offset:Add(chunk_offset) -- GetChunk + chunk_offset (fast)

					if IsValid(stored) then
						if stored:GetChunk() != offset then
							-- somehow, someway, our entity got teleported and its clones did not get properly cleared
							SafeRemoveEntity(stored)
						else
							continue
						end
					end

					local clone = ents.Create("infmap_clone")
					clone:SetReferenceParent(ent)
					clone:SetChunk(offset)
					clone:Spawn()
					ent.INFMAP_CLONES[i] = clone
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

local function update_entity(ent, chunk_offset)
	for e, _ in pairs(ent.INFMAP_CONSTRAINED) do
		if !isentity(e) then continue end

		-- sorry other players..
		if e != ent then
			e:ForcePlayerDrop()
		end

		-- wrap
		local chunk = e:GetChunk() chunk:Sub(chunk_offset)
		local pos = INFMAP.unlocalize(e:INFMAP_GetPos(), chunk)
		e:SetChunk(chunk_offset)
		unfucked_setpos(e, pos)
	end
end

-- which entities should be checked per frame (optimization filter)
local check_ents = {}
timer.Create("infmap_localize_check", 0.1, 0, function()
	check_ents = {}

	for _, ent in ents.Iterator() do
		update_cross_chunk_collision(ent)

		if !ent:GetVelocity():IsZero() and !INFMAP.filter_teleport(ent) then 
			table.insert(check_ents, ent)
		end
	end
end)

-- do actual teleporting
hook.Add("Think", "infmap_localize", function()
	for _, ent in ipairs(check_ents) do
		if !IsValid(ent) then continue end
		if INFMAP.in_chunk(ent:INFMAP_GetPos()) or ent:IsPlayerHolding() or INFMAP.filter_teleport(ent) then continue end

		-- the ONLY place that can validate an entities constraints is right before a teleport
		validate_constraints(ent)
		if INFMAP.filter_teleport(ent) then continue end -- required secondary check just incase the constraint table updated

		-- time to teleport
		local _, chunk_offset = INFMAP.localize(ent:INFMAP_GetPos())
		chunk_offset:Add(ent:GetChunk())
		update_entity(ent, chunk_offset)

		-- if we're holding something, force it into our chunk
		if ent:IsPlayer() then 
			local holding = player_pickups[ent]
			if IsValid(holding) then
				validate_constraints(holding)
				holding.INFMAP_CONSTRAINED.parent = holding
				update_entity(holding, chunk_offset)
			end
		end
	end
end)

hook.Add("PlayerSpawn", "infmap_respawn", function(ply, trans)
	if ply:IsChunkValid() and !trans then
		ply:SetChunk(vector_origin)
	end
end)

-------------
-- GLOBALS --
-------------
local ENTITY = FindMetaTable("Entity")

local nil_chunk = Vector(math.huge)
function ENTITY:SetChunk(chunk)
	-- !!!HACK!!! we need to tell the client to invalidate this entities chunk
	-- to avoid extra netmessage spaz and to ensure packets arrive at the same time, we send a predetermined invalid chunk to the client
	-- the client will then see this and set their chunk to nil
	if chunk == nil then
		self:SetNW2Vector("INFMAP_CHUNK", nil_chunk)
		invalidate_constraints(self)
	else
		chunk = Vector(chunk)	-- copy
		self:SetNW2Vector("INFMAP_CHUNK", chunk)
	end

	self.INFMAP_CHUNK = chunk	-- !!!CACHED FOR HIGH PERFORMANCE USE ONLY!!!
	self:SetCustomCollisionCheck(chunk != nil)
	update_cross_chunk_collision(self)

	-- parent support (recursive)
	for _, ent in ipairs(self:GetChildren()) do
		if INFMAP.filter_general(ent) or ent.INFMAP_CHUNK == chunk then continue end
		
		ent:SetChunk(chunk)
	end
end