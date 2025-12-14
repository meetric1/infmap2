---------------
-- RENDERING --
---------------
-- when bounding box is outside of world bounds the object isn't rendered
-- to combat this we locally "shrink" the bounds so they are right infront of the players eyes
-- TODO: NeedsDepthPass to set bounds, for RenderView "support"
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

local function enable_render_offset(ent, chunk_offset)
	-- visually offset entity
	ent.INFMAP_RENDER_BOUNDS = ent.INFMAP_RENDER_BOUNDS or {ent:INFMAP_GetRenderBounds()}
	ent.INFMAP_RENDER_OFFSET = INFMAP.unlocalize(vector_origin, chunk_offset)

	-- "RenderMultiply" does not work on some entities, so we need a full cam detour
	if INFMAP.filter_render_fancy(ent) then
		local render_func = ent.INFMAP_RenderOverride or ent.DrawModel
		ent:INFMAP___newindex("RenderOverride", function(self, flags) -- ent.RenderOverride = function
			cam.Start3D(EyePos() - self.INFMAP_RENDER_OFFSET)
				render_func(self, flags == 0 and 1 or flags)
			cam.End3D()
		end)
	else
		-- we need to orient the matrix back, since it has already been rotated
		-- (SELF * INV_ANG * TRANSLATE * ANG)
		local offset_ang = Matrix()
		local offset_pos = Matrix()
		offset_pos:SetTranslation(ent.INFMAP_RENDER_OFFSET)

		-- TODO: do we need a CalcAbsolutePosition detour?
		ent.CalcAbsolutePosition = function(self, pos, ang)
			offset_pos:SetAngles(ang)
			offset_ang:Identity()
			offset_ang:SetAngles(ang)
			offset_ang:Invert()
			offset_ang:Mul(offset_pos)

			self:EnableMatrix("RenderMultiply", offset_ang)
		end

		ent:SetLOD(0)
		ent:CalcAbsolutePosition(ent:INFMAP_GetPos(), ent:GetAngles())
		ent:INFMAP___newindex("RenderOverride", ent.INFMAP_RenderOverride) -- ent.RenderOverride = ent.INFMAP_RenderOverride
	end

	force_renderbounds[ent] = true
end

local function disable_render_offset(ent)
	if ent.INFMAP_RENDER_BOUNDS then
		ent:INFMAP_SetRenderBounds(ent.INFMAP_RENDER_BOUNDS[1], ent.INFMAP_RENDER_BOUNDS[2])
		ent.INFMAP_RENDER_BOUNDS = nil
	end

	ent.CalcAbsolutePosition = nil

	ent:SetLOD(-1)
	ent:DisableMatrix("RenderMultiply")
	ent:INFMAP___newindex("RenderOverride", ent.INFMAP_RenderOverride) -- ent.RenderOverride = ent.INFMAP_RenderOverride

	force_renderbounds[ent] = nil
end

-------------
-- GLOBALS --
-------------
-- TODO: physgun glow shows up in other chunks
local ENTITY = FindMetaTable("Entity")
function ENTITY:SetChunk(chunk)
	local prev_chunk = self.INFMAP_CHUNK
	if !chunk and !prev_chunk then return end

	local err, prevent = INFMAP.hook_run_safe("OnChunkUpdate", self, chunk, prev_chunk)
	if !err and prevent then return end

	self.INFMAP_CHUNK = chunk

	-- offset rendering (or dont. idc)
	local local_player = LocalPlayer()
	if !chunk or !local_player:IsChunkValid() or INFMAP.filter_render(self) then
		disable_render_offset(self)
	else
		local chunk_offset = chunk - local_player:GetChunk()
		if !chunk_offset:IsZero() then
			enable_render_offset(self, chunk_offset)
		else
			disable_render_offset(self)
		end
	end

	-- if our local client updated we need to update everything else
	if self != local_player then return end

	local_player:SetCustomCollisionCheck(chunk and true or false)
	for _, ent in ents.Iterator() do
		if ent == local_player or INFMAP.filter_render(ent) then continue end

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
	local chunk = lp:GetChunk() or INFMAP.Vector()
	local cs = Vector(1, 1, 1) * INFMAP.chunk_size
	local co = INFMAP.unlocalize(vector_origin, chunk)--chunk_offset * INFMAP.chunk_size * 2
	
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
		local size = vbsp:GetVBSPSize()
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

	for _, heightmap in ipairs(ents.FindByClass("infmap_heightmap_collider")) do
		render.DrawWireframeBox(heightmap:GetPos(), Angle(), heightmap:OBBMins(), heightmap:OBBMaxs(), Color(255, 127, 0), true)
	end

	cam.Start2D()
		draw.DrawText("client chunk: " .. concat_vector(lp.INFMAP_CHUNK), "TargetID", nil, 130)
		draw.DrawText("client pos: " .. concat_vector(lp:INFMAP_GetPos()), "TargetID", nil, 150)
		draw.DrawText("server pos: " .. concat_vector(INFMAP.unlocalize(lp:INFMAP_GetPos(), chunk)), "TargetID", nil, 170)
	cam.End2D()
end)