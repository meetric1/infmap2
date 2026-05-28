-- VBSP - CLIENT
-- handles rendering and visuals

AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_vbsp_client"

if !INFMAP then return end

INFMAP.VBSP = {
	["to_local"] = function(vbsp_client) -- INFMAP -> VBSP
		local translate1 = Matrix()
		translate1:SetTranslation(vbsp_client:INFMAP_GetPos())
		translate1:SetAngles(vbsp_client:GetAngles())
		translate1:Invert()

		local translate2 = Matrix()
		translate2:SetTranslation(vbsp_client:GetVBSPPos())
		translate2:Mul(translate1)

		return translate2
	end,
	["to_world"] = function(vbsp_client) -- VBSP -> INFMAP
		local translate1 = Matrix()
		translate1:SetTranslation(-vbsp_client:GetVBSPPos())

		local translate2 = Matrix()
		translate2:SetTranslation(vbsp_client:INFMAP_GetPos())
		translate2:SetAngles(vbsp_client:GetAngles())
		translate2:Mul(translate1)

		return translate2
	end,
	["rotate"] = function(mat, ang)
		mat:Rotate(ang)
		return mat:GetAngles()
	end
}

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "VBSPPos")
	self:NetworkVar("Vector", 1, "VBSPSize")
	self:NetworkVar("Float", 0, "VBSPFarZ")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:Initialize()
	self:SetNotSolid(true)
	--self:SetNoDraw(true)

	if SERVER then return end

	local size = self:GetVBSPSize()
	self:SetRenderBounds(-size, size)
	self.INFMAP_VBSP_CHECK = {}
end

-- visuals- no server
if SERVER then return end

-- VBSP -> INFMAP
local rendering = false
local framebuffer = GetRenderTarget("infmap_vbsp_framebuffer", ScrW(), ScrH())
local view = {
	drawviewmodel = false,
	--viewid = 1 -- VIEW_3DSKY
}

hook.Add("RenderScene", "infmap_vbsp_client", function(eye_pos, eye_angles, fov)
	if !util.IsSkyboxVisibleFromPoint(eye_pos) then return end

	local local_player = LocalPlayer()
	local vbsp_client = local_player:GetNW2Entity("INFMAP_VBSP_CLIENT")
	if !IsValid(vbsp_client) then return end
	--print(vbsp_client)

	if local_player:GetChunkInternal() == nil and local_player:GetChunk() != vbsp_client:GetChunk() then
		local_player:SetChunk(vbsp_client:GetChunk())
	end

	local mat = INFMAP.VBSP.to_world(vbsp_client)
	eye_pos:Mul(mat)
	view.origin = eye_pos
	view.angles = INFMAP.VBSP.rotate(mat, eye_angles)
	view.fov    = fov

	-- DEPTH IS BROKEN INSIDE VIRTUAL CAMERA
	-- this BREAKS planet atmosphere rendering
	-- TODO: better way to read depth (INTZ?)
	-- VIEWID = 0 fixes this issue, but breaks pixvis handles. Wtf
	--[[
	render.PushRenderTarget(render.GetResolvedFullFrameDepth())
		render.Clear(0, 0, 0, 0)
	render.PopRenderTarget()
	]]

	render.PushRenderTarget(framebuffer)
		rendering = true
		INFMAP.draw_render_bounds(eye_pos)
		render.RenderView(view)
		rendering = false
	render.PopRenderTarget()
end)

hook.Add("PostDraw2DSkyBox", "infmap_vbsp_client", function()
	local vbsp_client = LocalPlayer():GetNW2Entity("INFMAP_VBSP_CLIENT")
	if !IsValid(vbsp_client) then return end

	render.DrawTextureToScreen(framebuffer)
end)

-- INFMAP -> VBSP
function ENT:Draw()
	if rendering then return end

	local local_player = LocalPlayer()
	if !local_player:IsChunkValid() then return end

	-- all entities in here SHOULD have invalid chunks
	local size = self:GetVBSPSize()
	local vbsp_pos = self:GetVBSPPos()
	local vbsp_ang = self:GetAngles()
	local force_draw = ents.FindInBox(vbsp_pos - size, vbsp_pos + size) -- TODO: slow

	local to_local = INFMAP.VBSP.to_local(self)
	local offset_pos = to_local * INFMAP.unlocalize(EyePos(), local_player:GetChunk() - self:GetChunk())
	local offset_ang = INFMAP.VBSP.rotate(to_local, EyeAngles())
	cam.Start3D(offset_pos, offset_ang)
	for _, ent in ipairs(force_draw) do
		if INFMAP.filter_render(ent, true) then continue end
		
		ent:DrawModel()
	end
	cam.End3D()

	--debugoverlay.Box(vbsp_pos, -size, size, 0.1, Color(255, 0, 255, 0))

	--self:DrawModel()
end
