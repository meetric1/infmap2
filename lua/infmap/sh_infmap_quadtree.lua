local QUADTREE_FUNCS = {
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
	["traverse_path"] = function(self, path, split)
		if split then
			for i = 1, #path do
				self:split()
				self = self.children[tonumber(path[i])]
			end
		else
			for i = 1, #path do
				if !self.children then return nil end
				self = self.children[tonumber(path[i])]
			end
		end

		return self
	end,
}

local QUADTREE = {
	["__index"] = QUADTREE_FUNCS
}

function INFMAP.Quadtree(pos, size, path)
	path = path or ""
	return setmetatable({
		["pos"] = {pos[1], pos[2], pos[3]},
		["size"] = size,
		["path"] = path
	}, QUADTREE)
end
