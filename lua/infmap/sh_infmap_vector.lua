AddCSLuaFile()

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
	["__newindex"] = function(a, k, v)

	end,
	["__index"] = INFMAP_VECTOR_FUNCS
}

-- INFMAP.Vector creation
local math_Clamp = math.Clamp
function INFMAP.Vector(x, y, z)
	if getmetatable(x) == INFMAP_VECTOR then
		x, y, z = x[1], x[2], x[3]
	elseif isstring(x) then
		x, y, z = unpack(string.Split(x, " "))
	end

	-- clamp vector to 2^53, our limit
	-- 255^6 * 127 is technically the maximum we can network but wrapping breaks down at 2^53
	-- 2^53 lets us go up to about 400 light years in each direction, which imo is plenty of room
	x = math_Clamp(tonumber(x) or 0, -2^53+1, 2^53-1)
	y = math_Clamp(tonumber(y) or 0, -2^53+1, 2^53-1)
	z = math_Clamp(tonumber(z) or 0, -2^53+1, 2^53-1)
	return setmetatable({x, y, z}, INFMAP_VECTOR)
end



-- INFMAP_VECTOR typechecking- use during development to ensure we don't fuck anything up
if game.SinglePlayer() then
	-- method detours
	for k, v in pairs(INFMAP_VECTOR) do
		if !isfunction(v) then continue end
		
		INFMAP_VECTOR[k] = function(a, b)
			if getmetatable(a) != INFMAP_VECTOR or (b and getmetatable(b) != INFMAP_VECTOR) then
				ErrorNoHaltWithStack(string.format("INVALID OPERATION: %s(%s, %s)", k, type(a), type(b)))
			end
			return v(a, b)
		end
	end

	-- creation detour
	local INFMAP_Vector = INFMAP.Vector
	function INFMAP.Vector(x, ...)
		if x and !isnumber(x) and getmetatable(x) != INFMAP_VECTOR and !isstring(x) then
			ErrorNoHaltWithStack(string.format("INVALID OPERATION: INFMAP.Vector(%s)", type(x)))
		end

		return INFMAP_Vector(x, ...)
	end
end