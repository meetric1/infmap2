-- helper func
local function detour(metatable, func_name, detoured_func)
	local original_func_name = "INFMAP_" .. func_name
	local original_func = metatable[original_func_name] or metatable[func_name]

	metatable[original_func_name] = original_func
	metatable[func_name] = function(self, ...)
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
	local pos, chunk = INFMAP.localize(pos)
	self:SetChunk(chunk)
	self:INFMAP_SetPos(pos)
end)

detour(ENTITY, "WorldSpaceAABB", function(self)
	local mins, maxs = self:INFMAP_WorldSpaceAABB()
	return INFMAP.unlocalize(mins, self:GetChunk()), INFMAP.unlocalize(maxs, self:GetChunk())
end)

detour(ENTITY, "LocalToWorld", function(self, pos)
	return INFMAP.unlocalize(self:INFMAP_LocalToWorld(pos), self:GetChunk())
end)

detour(ENTITY, "WorldToLocal", function(self, pos)
	return self:INFMAP_WorldToLocal(-INFMAP.unlocalize(-pos, self:GetChunk()))
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
	local pos, chunk = INFMAP.localize(pos)
	self:GetEntity():SetChunk(chunk)
	self:INFMAP_SetPos(pos)
end)

---------------------
-- GENERAL DETOURS --
---------------------
-- pickups (health/ammo/objects)
local function player_should_pickup(ply, ent)
	if ply:IsChunkValid() and ent:IsChunkValid() and ply:GetChunk() != ent:GetChunk() then
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
	if ply:IsChunkValid() and ent:IsChunkValid() and ply:GetChunk() != ent:GetChunk() then
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

-------------------
-- ADDON DETOURS --
-------------------
hook.Add("Initialize", "infmap_wire_detour", function()
	if WireLib then	-- wiremod unclamp
		function WireLib.clampPos(pos)
			return Vector(pos)
		end
	end

	if SF then	-- starfall unclamp
		function SF.clampPos(pos)
			return pos 
		end
	end
end)