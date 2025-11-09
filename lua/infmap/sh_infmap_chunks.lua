-- infmap vector class, since the gmod vector class is slow as fuck and imprecise
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
	["__eq"] = function(a, b)
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end,
	["__tostring"] = function(a)
		return a[1] .. " " .. a[2] .. " " .. a[3]
	end,
	["__newindex"] = function(a, k, v)

	end,
}

-- INFMAP_VECTOR typechecking- use during development to ensure we don't fuck anything up
if true then
	for k, v in pairs(INFMAP_VECTOR) do
		if k == "__tostring" or k == "__newindex" then continue end

		INFMAP_VECTOR[k] = function(a, b)
			if getmetatable(a) != INFMAP_VECTOR or getmetatable(b) != INFMAP_VECTOR then
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
		-- clamp vector to 255^7, our network limit
		-- this doesn't really matter though because we can't do chunk wrapping past 2^53 anyways
		x = math.Clamp(tonumber(x) or 0, -255^7+5, 255^7-5)
		y = math.Clamp(tonumber(y) or 0, -255^7+5, 255^7-5)
		z = math.Clamp(tonumber(z) or 0, -255^7+5, 255^7-5)
		return setmetatable({x, y, z}, INFMAP_VECTOR)
	end
end

-- little endian encoding in base 255 (since we can't represent 0x00 in a string)
-- this gets us up to 7.0e16 (which is about 0.2e16 smaller than what a full 7 bytes could represent (7.2e16))
	-- (which still gives us a span of like 7,738 light years, so its like whatever)
function INFMAP.encode_vector(vec)
	if vec == nil then return "" end

	local bytes = {}
	local header = 0
	for i = 1, 3 do
		local num = vec[i]
		if num < 0 then
			header = (header + 2^(i - 1)) -- (header |= (1 << (i - 1)))
			num = -num
		end

		for i = 1, 7 do
			bytes[#bytes + 1] = (num % 255) + 1
			num = math.floor(num / 255)
		end
	end

	bytes[#bytes + 1] = header + 0x80
	return string.char(unpack(bytes))
end

function INFMAP.decode_vector(str)
	if #str <= 0 then return nil end
	local vec = INFMAP.Vector()

	local bytes = {string.byte(str, 1, #str)}
	local header = bytes[#bytes] - 0x80
	local index = #bytes
	for i = 3, 1, -1 do
		local num = 0
		for i = 1, 7 do
			index = index - 1
			num = num * 255
			num = num + (bytes[index] - 1)
		end

		if (bit.band(header, 2^(i - 1))) != 0 then -- if (header & (1 << (i - 1)))
			vec[i] = -num
		else
			vec[i] = num
		end
	end

	return vec
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