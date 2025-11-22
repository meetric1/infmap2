AddCSLuaFile()

ENT.Type = "brush"
--ENT.Base = "base_brush"
ENT.PrintName = "infmap"

function ENT:Initialize()
    self:SetTrigger(true)

	SetGlobalVector("INFMAP_CHUNK_ORIGIN", self:GetPos())
	SetGlobalFloat("INFMAP_CHUNK_SIZE", self:OBBMaxs()[1])
	INFMAP.init()
end

function ENT:StartTouch(ent)

end

function ENT:EndTouch(ent)

end

function ENT:KeyValue(key, value)

end