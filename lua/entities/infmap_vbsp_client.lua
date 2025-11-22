AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_vbsp_client"

function ENT:Initialize()
	self:SetNotSolid(true)
	--self:SetNoDraw(true)
end

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "VBSPPos")
	self:NetworkVar("Vector", 1, "VBSPSize")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

-- TODO: draw logic (waiting for vbsp models..)

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