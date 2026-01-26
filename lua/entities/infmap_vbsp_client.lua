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

-- INFMAP -> VBSP
function ENT:Draw()
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

-- VBSP -> INFMAP
-- Skybox doesn't change orientation, so we need to draw it manually ourselves
local sky_convar = GetConVar("sv_skyname")
local sky_name = nil
local sky_materials = {}
local sky_directions = {
	Vector(-1,  0,  0),
	Vector( 1,  0,  0),
	Vector( 0, -1,  0),
	Vector( 0,  1,  0),
	Vector( 0,  0, -1),
	Vector( 0,  0,  1),
}

local function update_sky()
	local new_sky_name = sky_convar:GetString()
	if sky_name == new_sky_name then return end
	sky_name = new_sky_name

	local prefix = "skybox/" .. sky_name
	sky_materials[1] = Material(prefix .. "rt")
	sky_materials[2] = Material(prefix .. "lf")
	sky_materials[3] = Material(prefix .. "bk")
	sky_materials[4] = Material(prefix .. "ft")
	sky_materials[5] = Material(prefix .. "up")
	sky_materials[6] = Material(prefix .. "dn")
end

local function draw_sky()
	for i, dir in ipairs(sky_directions) do
		render.SetMaterial(sky_materials[i])
		--render.SetMaterial(Material("hunter/myplastic"))
		render.DrawQuadEasy(EyePos() - dir * 9.96, dir, 20, 20, color_white, i >= 5 and 0 or 180)
	end
end

hook.Add("PostDraw2DSkyBox", "infmap_vbsp_client", function()
	local local_player = LocalPlayer()
	if local_player:IsChunkValid() then return end

	local vbsp_client = local_player:GetNWEntity("INFMAP_VBSP_CLIENT")
	if !IsValid(vbsp_client) then return end

	local to_world = INFMAP.VBSP.to_world(vbsp_client)
	local offset_ang = INFMAP.VBSP.rotate(Matrix(to_world), EyeAngles())
	cam.Start3D(nil, offset_ang)
		update_sky()
		draw_sky()
	cam.End3D()

	for _, ent in ents.Iterator() do
		if ent:IsDormant() or INFMAP.filter_render(ent) or INFMAP.filter_teleport(ent) then
			continue
		end

		local offset_pos = INFMAP.unlocalize(
			to_world * EyePos(),
			vbsp_client:GetChunk() - ent:GetChunk()
		)

		cam.Start3D(offset_pos, offset_ang)
			ent:DrawModel()
		cam.End3D()
	end
end)