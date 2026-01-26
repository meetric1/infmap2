-- helper func
local function detour(metatable, func_name, detoured_func, force)
	local original_func_name = "INFMAP_" .. func_name
	local original_func = metatable[original_func_name] or metatable[func_name]

	metatable[original_func_name] = original_func
	metatable[func_name] = force and detoured_func or function(self, ...)
		if self:IsChunkValid() and LocalPlayer():IsChunkValid() then
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

detour(ENTITY, "SetPos", function(self, pos)
	self:INFMAP_SetPos(INFMAP.clamp_pos(pos)) -- shut console up
end)

detour(ENTITY, "GetPos", function(self)
	return INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetChunk() - LocalPlayer():GetChunk())
end)

detour(ENTITY, "WorldToLocal", function(self, pos)
	return self:INFMAP_WorldToLocal(INFMAP.unlocalize(pos, LocalPlayer():GetChunk() - self:GetChunk()))
end)

detour(ENTITY, "LocalToWorld", function(self, pos)
	return INFMAP.unlocalize(self:INFMAP_LocalToWorld(pos), self:GetChunk() - LocalPlayer():GetChunk())
end)

detour(ENTITY, "EyePos", function(self)
	return INFMAP.unlocalize(self:INFMAP_EyePos(), self:GetChunk() - LocalPlayer():GetChunk())
end)

detour(ENTITY, "GetWorldTransformMatrix", function(self)
	local world_transform_matrix = self:INFMAP_GetWorldTransformMatrix()
	world_transform_matrix:Translate(INFMAP.unlocalize(vector_origin, self:GetChunk() - LocalPlayer():GetChunk()))
	return world_transform_matrix
end)

detour(ENTITY, "GetRenderBounds", function(self)
	if self.INFMAP_RENDER_BOUNDS then
		return Vector(self.INFMAP_RENDER_BOUNDS[1]), Vector(self.INFMAP_RENDER_BOUNDS[2])
	else
		return self:INFMAP_GetRenderBounds()
	end
end, true)

detour(ENTITY, "SetRenderBounds", function(self, mins, maxs, add)
	if self.INFMAP_RENDER_BOUNDS then
		add = add or vector_origin

		self.INFMAP_RENDER_BOUNDS = {
			mins - add,
			maxs + add
		}
	else
		self:INFMAP_SetRenderBounds(mins, maxs, add)
	end
end, true)

detour(ENTITY, "SetRenderBoundsWS", function(self, mins, maxs, add)
	if self.INFMAP_RENDER_BOUNDS then
		add = add or vector_origin

		local inv_model_matrix = self:GetWorldTransformMatrix() -- DETOURED
		inv_model_matrix:Invert()

		mins = inv_model_matrix * (mins - add)
		maxs = inv_model_matrix * (maxs + add)

		-- swap if mins > maxs
		if mins[1] > maxs[1] then mins[1], maxs[1] = maxs[1], mins[1] end
		if mins[2] > maxs[2] then mins[2], maxs[2] = maxs[2], mins[2] end
		if mins[3] > maxs[3] then mins[3], maxs[3] = maxs[3], mins[3] end

		self.INFMAP_RENDER_BOUNDS = {mins, maxs}
	else
		self:INFMAP_SetRenderBoundsWS(mins, maxs, add)
	end
end, true)

-- really horrible RenderOverride detour
detour(ENTITY, "__newindex", function(self, key, value)
	if key == "RenderOverride" then
		self.INFMAP_RenderOverride = value
		self:SetChunk(self.INFMAP_CHUNK) -- force update
		return
	end

	self:INFMAP___newindex(key, value)
end, true)

---------------------
-- PHYSOBJ DETOURS --
---------------------
local PHYSOBJ = FindMetaTable("PhysObj")

detour(PHYSOBJ, "GetPos", function(self)
	return INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetEntity():GetChunk() - LocalPlayer():GetChunk())
end)

detour(PHYSOBJ, "SetPos", function(self, pos)
	self:INFMAP_SetPos(INFMAP.clamp_pos(pos)) -- shut console up
end)

---------------------
-- GENERAL DETOURS --
---------------------
-- disable client traces shot from other chunks
hook.Add("EntityFireBullets", "infmap_bullet_detour", function(ent, data)
	if LocalPlayer():InChunk(ent) then
		data.Tracer = 0
		return true
	end
end)