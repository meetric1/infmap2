-- infmap vector class, since the gmod vector class is slow as fuck and imprecise
local INFMAP_VECTOR_FUNCS = {
	["IsZero"] = function(a)
		return a[1] == 0 and a[2] == 0 and a[3] == 0
	end
}
local INFMAP_VECTOR = {
	["__add"] = function(a, b)
		return INFMAP.Vector(a[1] + b[1], a[2] + b[2], a[3] + b[3])
	end,
	["__sub"] = function(a, b)
		return INFMAP.Vector(a[1] - b[1], a[2] - b[2], a[3] - b[3])
	end,
	["__mul"] = function(a, b)
		return INFMAP.Vector(a[1] * b[1], a[2] * b[2], a[3] * b[3])
	end,
	["__div"] = function(a, b)
		return INFMAP.Vector(a[1] / b[1], a[2] / b[2], a[3] / b[3])
	end,
	["__unm"] = function(a)
		return INFMAP.Vector(-a[1], -a[2], -a[3])
	end,
	["__eq"] = function(a, b)
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end,
	["__tostring"] = function(a)
		return a[1] .. " " .. a[2] .. " " .. a[3]
	end,
	["__index"] = function(a, k)
		return INFMAP_VECTOR_FUNCS[k]
	end,
	["__newindex"] = function(a, k, v)

	end,
}

-- INFMAP_VECTOR typechecking- use during development to ensure we don't fuck anything up
if game.SinglePlayer() then
	for k, v in pairs(INFMAP_VECTOR) do
		INFMAP_VECTOR[k] = function(a, b)
			if k != "__index" and (getmetatable(a) != INFMAP_VECTOR or (b and getmetatable(b) != INFMAP_VECTOR)) then
				ErrorNoHaltWithStack(string.format("INVALID OPERATION: %s(%s, %s)", k, type(a), type(b)))
			end
			return v(a, b)
		end
	end
end

function INFMAP.Vector(x, y, z)
	if getmetatable(x) == INFMAP_VECTOR then
		return setmetatable({x[1], x[2], x[3]}, INFMAP_VECTOR)
	else
		-- clamp vector to 2^53, our limit
		-- 255^6*127 is technically the maximum we can network but wrapping breaks down at 2^53
		-- 2^53 lets us go up to about 400 light years in each direction, which imo is plenty of room
		x = math.Clamp(tonumber(x) or 0, -2^53+1, 2^53-1)
		y = math.Clamp(tonumber(y) or 0, -2^53+1, 2^53-1)
		z = math.Clamp(tonumber(z) or 0, -2^53+1, 2^53-1)
		return setmetatable({x, y, z}, INFMAP_VECTOR)
	end
end

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