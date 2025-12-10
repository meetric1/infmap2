local QUADTREE_FUNCS = {
	["should_split_pos"] = function(self, pos, extra)
		if self.size < 1000 then return false end
		--if self.size > 2000 then return true end

		local wiggle = self.size * (extra or 1) -- split wiggle room
		--local wiggle = math.min(self.size + (self.pos[3] - pos[3] + 1000), self.size)
		local diff_x = pos[1] - self.pos[1]
		local diff_y = pos[2] - self.pos[2]
		
		local min = -wiggle
		if diff_x < min or diff_y < min then return false end 

		local max = self.size + wiggle
		if diff_x > max or diff_y > max then return false end

		return true
	end,
	["traverse"] = function(self, func)
		if func(self) then return end

		local children = self.children
		if children then
			children[1]:traverse(func)
			children[2]:traverse(func)
			children[3]:traverse(func)
			children[4]:traverse(func)
		end
	end,
	["split"] = function(self)
		if self.children then return end -- we're already split

		local size = self.size / 2
		local x, y, z = self.pos[1], self.pos[2], self.pos[3]
		self.children = {
			INFMAP.Quadtree({x,               y, z}, size, self.path .. "1"),
			INFMAP.Quadtree({x + size,        y, z}, size, self.path .. "2"),
			INFMAP.Quadtree({x,        y + size, z}, size, self.path .. "3"),
			INFMAP.Quadtree({x + size, y + size, z}, size, self.path .. "4")
		}
	end,
	["split_pos"] = function(self, pos)
		if !should_split_pos(self, pos) then return end

		-- recursively split
		self:split()
		self.children[1]:split_pos(pos)
		self.children[2]:split_pos(pos)
		self.children[3]:split_pos(pos)
		self.children[4]:split_pos(pos)
	end,
	["traverse_path"] = function(self, path)
		for i = 1, #path do
			self:split()
			self = self.children[tonumber(path[i])]
		end

		return self
	end,
}

local QUADTREE = {
	["__index"] = QUADTREE_FUNCS
}

function INFMAP.Quadtree(pos, size, path)
	return setmetatable({pos = {pos[1], pos[2], pos[3]}, size = size, path = path or ""}, QUADTREE)
end