---------------
-- RENDERING --
---------------
-- when bounding box is outside of world bounds the object isn't rendered
-- to combat this we locally "shrink" the bounds so they are right infront of the players eyes
-- TODO: this kinda sucks. should we do our own culling?
local force_renderbounds = {}
hook.Add("RenderScene", "infmap_renderbounds", function(eye_pos, eye_ang, fov)
	for ent, _ in pairs(force_renderbounds) do
		if !ent.INFMAP_RENDER_BOUNDS then continue end

		-- calculate prop dir with minimal GC overhead
		local dir = ent:INFMAP_GetPos()
		dir:Add(ent.INFMAP_RENDER_OFFSET)
		dir:Sub(eye_pos)
		local shrink = 100 / dir:Length() -- TODO: non arbitrary distance
		dir:Mul(shrink)

		-- creates 2 vectors (fuck!)
		local min, max = ent:GetRotatedAABB(ent.INFMAP_RENDER_BOUNDS[1], ent.INFMAP_RENDER_BOUNDS[2])
		min:Mul(shrink)
		max:Mul(shrink)

		-- redo renderbounds
		dir:Add(eye_pos)

		--debugoverlay.Box(dir, min, max, 0, Color(0, 255, 0, 0))

		min:Add(dir)
		max:Add(dir)
		ent:INFMAP_SetRenderBoundsWS(min, max)

		--local min, max = ent:GetRotatedAABB(ent.INFMAP_RENDER_BOUNDS[1], ent.INFMAP_RENDER_BOUNDS[2])
		--debugoverlay.Box(ent:INFMAP_GetPos(), min, max, 0, Color(255, 0, 255, 0))
	end
end)

-------------
-- GLOBALS --
-------------
-- TODO: physgun glow probably shows up in other chunks
local ENTITY = FindMetaTable("Entity")
function ENTITY:SetChunk(chunk)
	local err, prevent = INFMAP.hook_run_safe("OnChunkUpdate", self, chunk, self.INFMAP_CHUNK)
	if !err and prevent then return end

	self.INFMAP_CHUNK = chunk
	self:INFMAP___newindex("RenderOverride", self.INFMAP_RenderOverride) -- self.RenderOverride = self.INFMAP_RenderOverride

	local lp = LocalPlayer()
	local offset = self:GetChunk() - lp:GetChunk()
	if !lp:IsChunkValid() or offset:IsZero() or INFMAP.filter_render(self) then
		if self.INFMAP_RENDER_BOUNDS then
			self:INFMAP_SetRenderBounds(self.INFMAP_RENDER_BOUNDS[1], self.INFMAP_RENDER_BOUNDS[2])
			self.INFMAP_RENDER_BOUNDS = nil
		end

		self.CalcAbsolutePosition = nil
		self:DisableMatrix("RenderMultiply")
		self:SetLOD(-1)

		force_renderbounds[self] = nil
	else
		-- visually offset entity
		self.INFMAP_RENDER_BOUNDS = self.INFMAP_RENDER_BOUNDS or {self:INFMAP_GetRenderBounds()}
		self.INFMAP_RENDER_OFFSET = INFMAP.unlocalize(vector_origin, offset)

		-- "RenderMultiply" does not work on some entities, so we need a full cam detour
		if INFMAP.filter_render_fancy(self) then
			local render_func = self.INFMAP_RenderOverride or self.DrawModel
			self:INFMAP___newindex("RenderOverride", function(self, flags) -- self.RenderOverride = function
				cam.Start3D(EyePos() - self.INFMAP_RENDER_OFFSET)
					render_func(self, flags == 0 and 1 or flags)
				cam.End3D()
			end)
		else
			-- we need to orient the matrix back, since it has already been rotated
			-- (SELF * INV_ANG * TRANSLATE * ANG)
			local offset_ang = Matrix()
			local offset_pos = Matrix()
			offset_pos:SetTranslation(self.INFMAP_RENDER_OFFSET)

			-- TODO: do we need a CalcAbsolutePosition detour?
			self.CalcAbsolutePosition = function(self, pos, ang)
				offset_pos:SetAngles(ang)
				offset_ang:Identity()
				offset_ang:SetAngles(ang)
				offset_ang:Invert()
				offset_ang:Mul(offset_pos)

				self:EnableMatrix("RenderMultiply", offset_ang)
			end

			self:CalcAbsolutePosition(self:INFMAP_GetPos(), self:GetAngles())
			self:SetLOD(0)
		end

		force_renderbounds[self] = true
	end

	-- if our local client updated we need to update everything else
	if self != lp then return end

	lp:SetCustomCollisionCheck(chunk and true or false)

	for _, ent in ents.Iterator() do
		if ent == lp or INFMAP.filter_render(ent) then continue end
		ent:SetChunk(ent.INFMAP_CHUNK) -- force update
	end
end

---------
-- NET --
---------
local function network_var_changed(ent, name, old, new, recurse)
	if name != "INFMAP_CHUNK" then return end

	-- "IT CHANGES CLASS MID-FUCKING EXECUTION??"
	if !ent:GetModel() and !recurse then
		timer.Simple(0, function()
			network_var_changed(ent, name, old, new, true)
		end)

		return
	end

	ent:SetChunk(INFMAP.decode_vector(new))
end
hook.Add("EntityNetworkedVarChanged", "infmap_nw2", network_var_changed)


-----------
-- DEBUG --
-----------
-- (abhorrent code.. remove when we don't need it anymore)
local debug_enabled = CreateClientConVar("infmap_debug", "0", true, false)
local maxsize = Vector(1, 1, 1) * 2^14
local function concat_vector(v)
	if !v then return "nil" end

	return string.format("%i %i %i", v[1], v[2], v[3])
end

hook.Add("PostDrawOpaqueRenderables", "infmap_debug", function()
	if !debug_enabled:GetBool() then return end

	local lp = LocalPlayer()
	local cs = Vector(1, 1, 1) * INFMAP.chunk_size
	local co = INFMAP.unlocalize(vector_origin, lp:GetChunk())--chunk_offset * INFMAP.chunk_size * 2
	
	render.DrawWireframeSphere(Vector(), 10, 10, 10, Color(255, 0, 0, 255), true)
	render.DrawWireframeBox(INFMAP.chunk_origin, Angle(), -cs, cs, Color(255, 255, 255, 0), true)
	
	--render.DrawWireframeBox(Vector(), Angle(), -cs - co, cs - co, black, true)
	render.DrawWireframeBox(Vector(), Angle(), -maxsize - co, maxsize - co, Color(0, 0, 255, 255), true)

	--print(INFMAP.unlocalize(INFMAP.localize(EyePos())))

	--[[
	local sun = Vector(1,1,1):GetNormalized()
	for _, brush in ipairs(game.GetWorld():GetBrushSurfaces()) do
		local vertices = brush:GetVertices()
		for i = 3, #vertices do
			local color = ((vertices[1] - vertices[2]):GetNormalized():Cross((vertices[1] - vertices[3]):GetNormalized())):Dot(sun)
			debugoverlay.Triangle(vertices[1], vertices[i - 1], vertices[i], 0, Color(255 * color, 0, 0, 100))
		end
	end]]

	for _, vbsp in ipairs(ents.FindByClass("infmap_vbsp_client")) do
		local size = vbsp:GetVBSPSize() / 2
		render.DrawWireframeBox(
			vbsp:GetPos(), 
			Angle(), 
			-size, 
			size, 
			Color(0, 255, 0),
			true
		)

		render.DrawWireframeBox(
			vbsp:GetVBSPPos(), 
			Angle(), 
			-size, 
			size, 
			Color(255, 0, 0),
			true
		)
	end

	cam.Start2D()
		draw.DrawText("client chunk: " .. concat_vector(lp.INFMAP_CHUNK), "TargetID", nil, 130)
		draw.DrawText("client pos: " .. concat_vector(lp:INFMAP_GetPos()), "TargetID", nil, 150)
		draw.DrawText("server pos: " .. concat_vector(INFMAP.unlocalize(lp:INFMAP_GetPos(), lp:GetChunk())), "TargetID", nil, 170)
	cam.End2D()
end)