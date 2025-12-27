-- helper func
local function detour(metatable, func_name, detoured_func, force)
	local original_func_name = "INFMAP_" .. func_name
	local original_func = metatable[original_func_name] or metatable[func_name]

	metatable[original_func_name] = original_func
	metatable[func_name] = force and detoured_func or function(self, ...)
		if self:IsChunkValid() then
			return detoured_func(self, ...)
		else
			return original_func(self, ...)
		end
	end
end

--------------------
-- ENTITY DETOURS --
--------------------
local ENTITY = FindMetaTable("Entity")

detour(ENTITY, "GetPos", function(self)
	return INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetChunk())
end)

detour(ENTITY, "SetPos", function(self, pos)
	if INFMAP.in_bounds(pos) then
		self:SetChunk(nil)
		self:INFMAP_SetPos(pos)
	else
		local pos, chunk = INFMAP.localize(pos)
		self:SetChunk(chunk)
		self:INFMAP_SetPos(pos)
	end
end, true)

detour(ENTITY, "WorldSpaceAABB", function(self)
	local mins, maxs = self:INFMAP_WorldSpaceAABB()
	return INFMAP.unlocalize(mins, self:GetChunk()), INFMAP.unlocalize(maxs, self:GetChunk())
end)

detour(ENTITY, "LocalToWorld", function(self, pos)
	return INFMAP.unlocalize(self:INFMAP_LocalToWorld(pos), self:GetChunk())
end)

detour(ENTITY, "WorldToLocal", function(self, pos)
	return self:INFMAP_WorldToLocal(INFMAP.unlocalize(pos, -self:GetChunk()))
end)

detour(ENTITY, "WorldSpaceCenter", function(self)
	return INFMAP.unlocalize(self:INFMAP_WorldSpaceCenter(), self:GetChunk())
end)

detour(ENTITY, "EyePos", function(self)
	return INFMAP.unlocalize(self:INFMAP_EyePos(), self:GetChunk())
end)

detour(ENTITY, "NearestPoint", function(self, pos)
	local pos, chunk = INFMAP.localize(pos)
	return INFMAP.unlocalize(self:INFMAP_NearestPoint(pos), chunk)
end)

---------------------
-- VEHICLE DETOURS --
---------------------
local VEHICLE = FindMetaTable("Vehicle")

detour(VEHICLE, "SetPos", ENTITY.SetPos, true)

------------------------
-- CONSTRAINT DETOURS --
------------------------
local constraint_localize = {
	"attachpoint", 
	"springaxis", 
	"slideaxis", 
	"hingeaxis", 
	"axis", 
	"position2"
}

-- !!!HACK!!! GetPhysConstraintObjects and GetConstrainedEntities return `nil` before :Spawn is called, requiring a detour
detour(ENTITY, "SetPhysConstraintObjects", function(self, phys1, phys2)
	if !INFMAP.filter_constraint(self) then
		local ent1 = phys1:GetEntity()
		local ent2 = phys2:GetEntity()
		if IsValid(ent1) and IsValid(ent2) then
			self.INFMAP_PHYS_CONSTRAINT_OBJECTS = {ent1, ent2}
		end
	end

	self:INFMAP_SetPhysConstraintObjects(phys1, phys2)
end, true)

detour(ENTITY, "Spawn", function(self)
	if !self.INFMAP_PHYS_CONSTRAINT_OBJECTS then 
		self:INFMAP_Spawn()
		return
	end

	-- STOP!!! we're about to create a constraint with 2 entities, we need to localize all the data
	local ent1, ent2 = self.INFMAP_PHYS_CONSTRAINT_OBJECTS[1], self.INFMAP_PHYS_CONSTRAINT_OBJECTS[2]
	
	-- localize prop locations
	INFMAP.validate_constraints(ent1)
	INFMAP.validate_constraints(ent2)
	INFMAP.merge_constraints(ent1, ent2)

	-- Localize constraint data
	if self:IsChunkValid() then
		self:INFMAP_SetPos(INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetChunk() - ent1:GetChunk()))

		local keys = self:GetKeyValues()
		local chunk_offset = -ent1:GetChunk() -- constraints are localized around ent1
		for _, str in ipairs(constraint_localize) do
			local pos = keys[str]
			if pos then
				self:SetKeyValue(str, tostring(INFMAP.unlocalize(Vector(pos), chunk_offset)))
				break
			end
		end
	end
	
	-- Spawn
	self:INFMAP_Spawn()
end, true)

--------------------
-- PLAYER DETOURS --
--------------------
local PLAYER = FindMetaTable("Player")

detour(PLAYER, "GetShootPos", function(self)
	return INFMAP.unlocalize(self:INFMAP_GetShootPos(), self:GetChunk())
end)

---------------------
-- PHYSOBJ DETOURS --
---------------------
local PHYSOBJ = FindMetaTable("PhysObj")

detour(PHYSOBJ, "GetPos", function(self, pos)
	return INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetEntity():GetChunk())
end)

detour(PHYSOBJ, "SetPos", function(self, pos)
	local ent = self:GetEntity()
	if INFMAP.in_bounds(pos) then
		ent:SetChunk(nil)
		self:INFMAP_SetPos(pos)
	else
		local pos, chunk = INFMAP.localize(pos)
		ent:SetChunk(chunk)
		self:INFMAP_SetPos(pos)
	end
end)

detour(PHYSOBJ, "LocalToWorld", function(self, pos)
	return INFMAP.unlocalize(self:INFMAP_LocalToWorld(pos), self:GetEntity():GetChunk())
end)

detour(PHYSOBJ, "WorldToLocal", function(self, pos)
	return self:INFMAP_WorldToLocal(INFMAP.unlocalize(pos, -self:GetEntity():GetChunk()))
end)

---------------------
-- GENERAL DETOURS --
---------------------
-- pickups (health/ammo/objects)
local function player_should_pickup(ply, ent)
	if !ply:InChunk(ent) then
		return false
	end
end

hook.Add("PlayerCanPickupWeapon", "infmap_pickup", player_should_pickup)
hook.Add("PlayerCanPickupItem", "infmap_pickup", player_should_pickup)
hook.Add("GravGunPickupAllowed", "infmap_pickup", player_should_pickup)

-- explosions and fire damage
hook.Add("EntityTakeDamage", "infmap_damage_detour", function(ply, dmg)
	if !dmg:IsExplosionDamage() and !dmg:IsDamageType(DMG_BURN) then return end

	local ent = dmg:GetInflictor()
	if !ply:InChunk(ent) then
		return true
	end
end)

-- bullets are handled in C++, so ensure they are localized
hook.Add("EntityFireBullets", "infmap_bullet_detour", function(ent, bullet)
	if !ent:IsChunkValid() then return end

	local pos, chunk = INFMAP.localize(bullet.Src)
	bullet.Src = pos
	return true
end)

-- insaneeely slow, but we don't have a choice
local function detour_filter(filter, start_chunk)
	local new_filter = nil

	if isfunction(filter) then 
		new_filter = function(e)
			return e:GetChunk() == start_chunk and filter(e)
		end
	elseif istable(filter) then
		local lookup = {}
		for _, e in ipairs(filter) do 
			lookup[e] = true 
		end

		new_filter = function(e)
			return e:GetChunk() == start_chunk and !lookup[e]
		end
	else -- probably an entity, or nil
		new_filter = function(e)
			return e != filter and e:GetChunk() == start_chunk
		end
	end

	return new_filter
end

-- traces
local function detour_trace(trace_func, data, extra)
	local old_start = data.start

	-- early check, incase we're in source bounds...
	if INFMAP.in_bounds(old_start) then
		return trace_func(data, extra)
	end

	-- store original data that will be overwritten
	local old_endpos = data.endpos
	local old_filter = data.filter

	-- localize start and end position of trace
	local start, start_chunk = INFMAP.localize(old_start)
	data.start = start
	data.endpos = INFMAP.unlocalize(old_endpos, -start_chunk)
	data.filter = detour_filter(old_filter, start_chunk)

	-- TRACE
	local hit_data = trace_func(data, extra)

	-- unlocalize result data
	hit_data.HitPos = INFMAP.unlocalize(hit_data.HitPos, start_chunk)
	hit_data.StartPos = INFMAP.unlocalize(hit_data.StartPos, start_chunk)

	-- custom infmap logic
	local hit_entity = hit_data.Entity
	if IsValid(hit_entity) and hit_entity:GetClass() == "infmap_clone" then
		hit_data.Entity = hit_entity:GetReferenceParent()
	end

	-- restore data (since we modified table)
	data.start = old_start
	data.endpos = old_endpos
	data.filter = old_filter

	return hit_data
end

detour(util, "TraceLine", function(data)
	return detour_trace(util.INFMAP_TraceLine, data)
end, true)

-------------------
-- ADDON DETOURS --
-------------------
-- toolgun
hook.Add("PreRegisterSWEP", "infmap_toolgundetour", function(SWEP, class)
    if class == "gmod_tool" then
		detour(SWEP, "DoShootEffect", function(self, pos, ...)
			self:INFMAP_DoShootEffect(INFMAP.unlocalize(pos, -self:GetOwner():GetChunk()), ...)
		end)
	end
end)

-- wire
hook.Add("Initialize", "infmap_wire_detour", function()
	if WireLib then	-- wiremod unclamp
		function WireLib.clampPos(pos)
			return Vector(pos)
		end
	end

	if SF and string.find(SF.Version, "Neostarfall") then -- neosf unclamp
		function SF.clampPos(pos)
			return pos 
		end
	end
end)