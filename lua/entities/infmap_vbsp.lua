AddCSLuaFile()

ENT.Type = "brush"
ENT.Base = "base_brush"
ENT.PrintName = "infmap_vbsp"

function ENT:Initialize()
    self:SetTrigger(true)
end

function ENT:StartTouch(ent)

end

function ENT:EndTouch(ent)
	if ent:IsMarkedForDeletion() then return end

	print("EndTouch", self, ent)
end

function ENT:KeyValue(key, value)
    if key == "chunk" then
		self.INFMAP_VBSP_CHUNK = Vector(string.Split(value, " "))
    elseif key == "position" then
        self.INFMAP_VBSP_POS = Vector(string.Split(value, " "))
    end
end