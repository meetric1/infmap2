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

end

function ENT:KeyValue(key, value)
    if key == "chunk" then
        -- Vector or possibly string of chunk pos
    elseif key == "position" then
        -- Local to chunk
    end
end