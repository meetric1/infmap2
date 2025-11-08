AddCSLuaFile()

ENT.Type = "brush"
ENT.Base = "base_brush"
ENT.PrintName = "infmap"

function ENT:Initialize()
    self:SetTrigger(true)
	
	local pos = self:GetPos() + self:OBBCenter()
	local size = self:OBBMaxs()[1]
	SetGlobalVector("INFMAP_CHUNK_ORIGIN", pos)
	SetGlobalFloat("INFMAP_CHUNK_SIZE", size)
end

function ENT:StartTouch(ent)

end

function ENT:EndTouch(ent)

end

function ENT:KeyValue(key, value)
	
end