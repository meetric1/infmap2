-- R16 sampler
local INFMAP_SAMPLER_FUNCS = {
	["sample"] = function(self, x, y, point)
		x = (    x) * self.res
		y = (1 - y) * self.res

		local function get_data(x, y)
			x = math.Clamp(x, 0, self.res - 1) -- clampU
			y = math.Clamp(y, 0, self.res - 1) -- clampV

			local i = (y * self.res + x) * 2 + 1 -- stride of 2 + lua is 1 indexed
			return (
				string.byte(self.metadata[i + 1]) * 2^8 + -- up << 8 + low
				string.byte(self.metadata[i    ])
			)
		end

		if point then
			-- Point filtering
			return get_data(x, y)
		else
			-- Bilinear filtering
			local x_fract = x % 1
			local y_fract = y % 1
			local x_offset = x_fract >= 0.5 and 1 or -1
			local y_offset = y_fract >= 0.5 and 1 or -1
			local x_dist = math.abs(x_fract - 0.5)
			local y_dist = math.abs(y_fract - 0.5)
			local c00 = get_data(x,            y           )
			local c10 = get_data(x + x_offset, y           )
			local c01 = get_data(x           , y + y_offset)
			local c11 = get_data(x + x_offset, y + y_offset)
			return (
				(c00 * (1 - x_dist) + c10 * x_dist) * (1 - y_dist) +
				(c01 * (1 - x_dist) + c11 * x_dist) * (    y_dist)
			)
		end
	end
}

local INFMAP_SAMPLER = {
	["__index"] = INFMAP_SAMPLER_FUNCS
}

function INFMAP.Sampler(path)
	if !file.Exists(path, "GAME") then 
		error("Invalid path!") 
	end

	local sampler = setmetatable({}, INFMAP_SAMPLER)
	file.AsyncRead(path, "GAME", function(file_name, game_path, status, data)
		if status != FSASYNC_OK then return end

		local res = math.sqrt(#data / 2) -- stride of 2
		if math.floor(res) != res then 
			error("Invalid data!") 
		end

		sampler.metadata = data
		sampler.res = res
	end)

	-- TODO: do we need this?
	--if SERVER then
	--	resource.AddSingleFile(path)
	--end

	return sampler
end