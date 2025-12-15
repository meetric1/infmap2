-- simple queue implementation
local INFMAP_QUEUE_FUNCTIONS = {
	["insert"] = function(self, v)
		local r = self.r + 1
		self.r = r
		self[r] = v
	end,
	["remove"] = function(self)
		local l = self.l
		local v = self[l]
		self[l] = nil
		l = l + 1
		if self:is_empty() then
			l = 0
			self.r = -1
		end
		self.l = l
		return v
	end,
	["is_empty"] = function(self)
		return self.l > self.r
	end
}

local INFMAP_QUEUE = {
	["__index"] = INFMAP_QUEUE_FUNCTIONS
}

function INFMAP.Queue()
	return setmetatable({["l"] = 0, ["r"] = -1}, INFMAP_QUEUE)
end