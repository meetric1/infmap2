-- VBSP - CLIENT
-- handles rendering and visuals

AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_vbsp_client"

if !INFMAP then return end

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "VBSPPos")
	self:NetworkVar("Vector", 1, "VBSPSize")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

local vbsps = {}
function ENT:Initialize()
	self:SetNotSolid(true)
	--self:SetNoDraw(true)

	if SERVER then return end

	local size = self:GetVBSPSize()
	self:SetRenderBounds(-size, size)
	self.INFMAP_VBSP_CHECK = {}
	vbsps[INFMAP.encode_vector(self:GetChunk())] = self
end

-- INFMAP -> VBSP
function ENT:Draw()
	-- all entities in here SHOULD have invalid chunks
	local size = self:GetVBSPSize()
	local vbsp_pos = self:GetVBSPPos()
	local force_draw = ents.FindInBox(vbsp_pos - size, vbsp_pos + size)
	cam.Start3D(EyePos() + vbsp_pos - self:GetPos())
	for _, ent in ipairs(force_draw) do
		if INFMAP.filter_render(ent, true) then continue end
		
		ent:DrawModel()
	end
	cam.End3D()

	--self:DrawModel()
end

function ENT:Remove()
	vbsps[INFMAP.encode_vector(self:GetChunk())] = nil
end

-- VBSP -> INFMAP
hook.Add("PostDraw2DSkyBox", "infmap_vbsp_client", function()
	local local_player = LocalPlayer()
	if local_player:IsChunkValid() then return end

	local vbsp = local_player:GetNWEntity("INFMAP_VBSP")
	if !IsValid(vbsp) then return end
	
	local origin = INFMAP.chunk_origin
	cam.Start3D(EyePos() - vbsp:GetVBSPPos() + origin)
	for ent, _ in pairs(vbsp.INFMAP_VBSP_CHECK) do
		if INFMAP.filter_render(ent) or !ent:InChunk(vbsp) then continue end
		
		ent:DrawModel()
	end
	cam.End3D()
end)

hook.Add("OnChunkUpdate", "infmap_vbsp_client", function(ent, chunk, prev_chunk)
	if string.find(ent:GetClass(), "infmap") then return end
	
	-- old
	local vbsp = vbsps[INFMAP.encode_vector(prev_chunk)]
	if IsValid(vbsp) and vbsp.INFMAP_VBSP_CHECK then
		vbsp.INFMAP_VBSP_CHECK[ent] = nil
	end
	
	-- new
	vbsp = vbsps[INFMAP.encode_vector(chunk)]
	if IsValid(vbsp) and vbsp.INFMAP_VBSP_CHECK then
		vbsp.INFMAP_VBSP_CHECK[ent] = true
	end
end)


-- renderview test (not working)
--[[
local drawing = false
hook.Add("PostRender", "infmap_test", function()
	--do return end
	cam.Start3D()
	render.SetColorMaterial()
	render.DrawSphere(Vector(), 100, 10, 10)
	cam.End3D()
	if drawing then return end

	drawing = true
	--RENDERVIEW_DRAWING = true
	cam.Start2D()
	--render.PushRenderTarget(render.GetMorphTex0())
	--cam.PushModelMatrix(Matrix(), true)
	render.RenderView({
		origin = Vector(0, 0, 0),
		angles = Angle(0, 0, 0),
		w = ScrW() / 4,
		h = ScrH() / 4,
		drawviewmodel = false,
		viewid = 0
	})
	--cam.PopModelMatrix()
	--render.PopRenderTarget()
	cam.End2D()
	--RENDERVIEW_DRAWING = false
	drawing = false
end)
]]
