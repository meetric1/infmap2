local ENTITY = FindMetaTable("Entity")
function ENTITY:GetChunk()
	return INFMAP.Vector(self.INFMAP_CHUNK)
end

function ENTITY:IsChunkValid()
	return self.INFMAP_CHUNK != nil
end


local PHYSOBJ = FindMetaTable("PhysObj")
function PHYSOBJ:IsChunkValid()
	local ent = self:GetEntity()
	return IsValid(ent) and ent.INFMAP_CHUNK != nil or false
end


-- may run hundreds of times per frame
hook.Add("ShouldCollide", "infmap_shouldcollide", function(ent1, ent2)
	--if ent1 == game.GetWorld() or ent2 == game.GetWorld() then return end
	
	-- GetChunk creates a vector, we need to use the cached version for performance. This hook can run hundreds of times per second
	if ent1.INFMAP_CHUNK != ent2.INFMAP_CHUNK then return false end
end)