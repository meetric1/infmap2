-- VBSP - CLIENT
-- handles rendering and visuals

AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_vbsp_client"

if !INFMAP then return end

function ENT:Initialize()
	self:SetNotSolid(true)
	--self:SetNoDraw(true)

	if SERVER then return end

	local size = self:GetVBSPSize() / 2
	self:SetRenderBounds(-size, size)
end

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "VBSPPos")
	self:NetworkVar("Vector", 1, "VBSPSize")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:Draw()
	-- all entities in here SHOULD have invalid chunks
	local size = self:GetVBSPSize() / 2
	local vbsp_pos = self:GetVBSPPos()
	local force_draw = ents.FindInBox(vbsp_pos - size, vbsp_pos + size)
	
	cam.Start3D(EyePos() + vbsp_pos - self:GetPos())
	for _, ent in ipairs(force_draw) do
		if INFMAP.filter_render(ent, true) then continue end
		
		ent:DrawModel()
	end
	cam.End3D()
end

--[[

-- renderview test (not working)
local drawing = false
hook.Add("PreDrawEffects", "infmap_test", function()
	--do return end
	render.SetColorMaterial()
	render.DrawSphere(Vector(), 100, 10, 10)

	if drawing then return end

	drawing = true
	RENDERVIEW_DRAWING = true
	cam.Start2D()
	--render.PushRenderTarget(render.GetMorphTex0())
	--cam.PushModelMatrix(Matrix(), true)
	render.RenderView({
		origin = Vector(0, 0, 0),
		angles = Angle(0, 0, 0),
		w = ScrW() / 4,
		h = ScrH() / 4,
		drawviewmodel = false,
	})
	--cam.PopModelMatrix()
	--render.PopRenderTarget()
	cam.End2D()
	--RENDERVIEW_DRAWING = false
	drawing = false
end)

]]