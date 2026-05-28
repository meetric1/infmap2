AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_lod"

if !INFMAP then return end

-- can't do it in Initialize, since the VBSP might not be ready yet
function ENT:Think()
	local pos = self:INFMAP_GetPos()

	-- figure out where we are (which vbsp are we in?), set chunk (and position) accordingly
	local vbsps = ents.FindByClass("infmap_vbsp")
	for _, vbsp in ipairs(vbsps) do
		local vbsp_client = vbsp.INFMAP_VBSP_CLIENT
		if !vbsp_client then continue end

		local vbsp_pos = vbsp:INFMAP_GetPos()
		local vbsp_mins = vbsp:OBBMins()
		local vbsp_maxs = vbsp:OBBMaxs()
 		vbsp_mins:Add(vbsp_pos)
		vbsp_maxs:Add(vbsp_pos)

		-- Ah! you Found it!
		if INFMAP.aabb_intersect_aabb(pos, pos, vbsp_mins, vbsp_maxs) then
			self:INFMAP_SetPos(INFMAP.VBSP.to_world(vbsp_client) * pos)
			self:SetAngles(vbsp_client:GetAngles())
			self:SetChunk(vbsp_client:GetChunk())
			self:SetParent(vbsp_client)

			break
		end
	end

	self:AddEFlags(EFL_NO_THINK_FUNCTION)
end

function ENT:Draw()
	-- if our virtual camera is rendering, don't draw the LOD its situated in
	if INFMAP.VBSP.rendering then 
		local vbsp_client = LocalPlayer():GetNW2Entity("INFMAP_VBSP_CLIENT")
		if self:GetParent() == vbsp_client then return end 
	end

	self:DrawModel()
end
