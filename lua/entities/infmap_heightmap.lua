AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "infmap_heightmap"

if !INFMAP then return end

function ENT:KeyValue(key, value)
	print(self, key, value)
end

function ENT:Initialize()

end