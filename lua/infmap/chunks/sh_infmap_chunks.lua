-- For JIT optimization purposes, "INFMAP_CHUNK" is hardcoded here

------------
-- ENTITY --
------------
local ENTITY = FindMetaTable("Entity")

function ENTITY:GetChunk()
	return self.INFMAP_CHUNK and INFMAP.Vector(self.INFMAP_CHUNK) or nil
end

function ENTITY:GetChunkInternal()
	return self.INFMAP_CHUNK
end

function ENTITY:GetChunkNetworked()
	return INFMAP.decode_vector(self:GetNW2String("INFMAP_CHUNK"))
end

function ENTITY:SetChunkInternal(vec)
	self.INFMAP_CHUNK = vec
end

function ENTITY:SetChunkNetworked(vec)
	self:SetNW2String("INFMAP_CHUNK", INFMAP.encode_vector(vec))
end

function ENTITY:IsChunkValid()
	return self.INFMAP_CHUNK != nil
end

function ENTITY:InChunk(x)
	if isentity(x) then
		return self.INFMAP_CHUNK == x.INFMAP_CHUNK
	else
		return self.INFMAP_CHUNK == x
	end
end

-------------
-- PHYSOBJ --
-------------
local PHYSOBJ = FindMetaTable("PhysObj")

function PHYSOBJ:IsChunkValid()
	return self:GetEntity():IsChunkValid()
end

-- may run hundreds of times per frame
hook.Add("ShouldCollide", "infmap_shouldcollide", function(ent1, ent2)
	--if ent1 == game.GetWorld() or ent2 == game.GetWorld() then return end

	-- Use the cached version for performance. This hook can run hundreds of times per second
	if ent1.INFMAP_CHUNK != ent2.INFMAP_CHUNK then return false end
end)
