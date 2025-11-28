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

-- mostly to shut the console up
local math_Clamp = math.Clamp
local function clamp_vector(pos)
	return Vector(
		math_Clamp(pos[1], -2^14+64, 2^14-64), 
		math_Clamp(pos[2], -2^14+64, 2^14-64), 
		math_Clamp(pos[3], -2^14+64, 2^14-64)
	)
end

--------------------
-- ENTITY DETOURS --
--------------------
local ENTITY = FindMetaTable("Entity")

detour(ENTITY, "SetPos", function(self, pos)
	self:INFMAP_SetPos(clamp_vector(pos))
end)

detour(ENTITY, "GetPos", function(self)
	return INFMAP.unlocalize(self:INFMAP_GetPos(), self:GetChunk() - LocalPlayer():GetChunk())
end)

detour(ENTITY, "GetRenderBounds", function(self)
	if self.INFMAP_RENDER_BOUNDS then
		return Vector(self.INFMAP_RENDER_BOUNDS[1]), Vector(self.INFMAP_RENDER_BOUNDS[2])
	else
		return self:INFMAP_GetRenderBounds()
	end
end)

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
end)

detour(ENTITY, "SetRenderBoundsWS", function(self, mins, maxs, add)
	if self.INFMAP_RENDER_BOUNDS then
		add = add or vector_origin

		local inv_model_matrix = self:GetWorldTransformMatrix()
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
end)

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

detour(PHYSOBJ, "SetPos", function(self, pos)
	self:INFMAP_SetPos(clamp_vector(pos))
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