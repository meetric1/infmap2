local ENTITY = FindMetaTable("Entity")

-- you should never call this manually
-- TODO: physgun glow probably shows up in other chunks
function ENTITY:SetChunk(chunk)
	local err, prevent = pcall(function() hook.Run("OnChunkUpdate", self, chunk, self.INFMAP_CHUNK) end)
	if !err and prevent then return end

	self.INFMAP_CHUNK = chunk
	self:INFMAP___newindex("RenderOverride", self.INFMAP_RenderOverride) -- self.RenderOverride = self.INFMAP_RenderOverride

	local lp = LocalPlayer()
	local offset = self:GetChunk() - lp:GetChunk()
	if !lp:IsChunkValid() or offset:IsZero() or INFMAP.filter_render(self) then
		self.CalcAbsolutePosition = nil

		if self.INFMAP_RENDER_BOUNDS then
			self:INFMAP_SetRenderBounds(unpack(self.INFMAP_RENDER_BOUNDS))
			self.INFMAP_RENDER_BOUNDS = nil
		end

		self:DisableMatrix("RenderMultiply")
		self:SetLOD(-1)
	else
		-- visually offset entity
		self.INFMAP_RENDER_OFFSET = INFMAP.unlocalize(vector_origin, offset)
		self.INFMAP_RENDER_BOUNDS = self.INFMAP_RENDER_BOUNDS or {self:INFMAP_GetRenderBounds()}

		if INFMAP.filter_render_fancy(self) then
			local render_func = self.INFMAP_RenderOverride or self.DrawModel
			self:INFMAP___newindex("RenderOverride", function(self, flags)
				cam.Start3D(EyePos() - self.INFMAP_RENDER_OFFSET)
					render_func(self, flags)
				cam.End3D()
			end)
		else
			-- raw position offset
			local offset_pos = Matrix()
			offset_pos:SetTranslation(self.INFMAP_RENDER_OFFSET)

			-- we need to orient the matrix back, since it has already been rotated
			-- (SELF * INV_ANG * TRANSLATE * ANG)
			local offset_ang = Matrix()
			
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
	end

	-- our local client updated? Shit! We need to update everything else
	if self != lp then return end

	lp:SetCustomCollisionCheck(chunk and true or false)

	for _, ent in ents.Iterator() do
		if ent == lp then continue end	-- gulp

		-- force update
		ent:SetChunk(ent.INFMAP_CHUNK)
	end
end

local function network_var_changed(ent, name, old, new, recurse)
	if name != "INFMAP_CHUNK" then return end

	-- "IT CHANGES CLASS MID-FUCKING EXECUTION??"
	if !ent:GetModel() and recurse != true then
		timer.Simple(0, function()
			network_var_changed(ent, name, old, new, true)
		end)

		return
	end

	ent:SetChunk(INFMAP.decode_vector(new))
end

hook.Add("EntityNetworkedVarChanged", "infmap_nw2", network_var_changed)

-- when bounding box is outside of world bounds the object isn't rendered
-- to combat this we locally "shrink" the bounds so they are right infront of the players eyes
hook.Add("RenderScene", "infmap_renderbounds", function(eye_pos, eye_ang, fov)
	for _, ent in ents.Iterator() do
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


-----------
-- DEBUG --
-----------
-- (abhorrent code.. remove when we don't need it anymore)
local debug_enabled = CreateClientConVar("infmap_debug", "0", true, false)
local maxsize = Vector(1, 1, 1) * 2^14

hook.Add("PostDrawOpaqueRenderables", "infmap_debug", function()
	if !debug_enabled:GetBool() then return end

	local cs = Vector(1, 1, 1) * INFMAP.chunk_size
	local co = INFMAP.unlocalize(vector_origin, LocalPlayer():GetChunk())--chunk_offset * INFMAP.chunk_size * 2
	
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
end)