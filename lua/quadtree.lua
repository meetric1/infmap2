local quadtree = {}
local function Quadtree(pos, size)
	return setmetatable({pos = pos, size = size}, quadtree)
end

local function should_split_pos(self, pos, extra)
	if self.size < 50 then return false end
	--if self.size > 2000 then return true end

	local wiggle = self.size + (extra or 0)	-- split wiggle room
	--local wiggle = math.min(self.size + (self.pos[3] - pos[3] + 1000), self.size)
	local diff = pos - self.pos
	
	local min = -wiggle
	if diff[1] < min or diff[2] < min then return false end 

	local max = self.size + wiggle
	if diff[1] > max or diff[2] > max then return false end

	return true
end

local function traverse(self, func, path)
	path = path or ""
	if func(self, path) then return end

	if !self.children then return end
	traverse(self.children[1], func, path .. "1")
	traverse(self.children[2], func, path .. "2")
	traverse(self.children[3], func, path .. "3")
	traverse(self.children[4], func, path .. "4")
end

local function split(self)
	if self.children then return end -- we're already split
	
	local size = self.size / 2
	local offset = self.pos
	self.children = {
		Quadtree(offset                     , size),
		Quadtree(offset + Vector(size, 0   ), size),
		Quadtree(offset + Vector(0   , size), size),
		Quadtree(offset + Vector(size, size), size)
	}
end

local function split_pos(self, pos)
	if !should_split_pos(self, pos) then return end

	-- recursively split
	self:split()
	self.children[1]:split_pos(pos)
	self.children[2]:split_pos(pos)
	self.children[3]:split_pos(pos)
	self.children[4]:split_pos(pos)
end

local function path(self, path)
	local branch = self
	for i = 1, #path do
		-- invalid
		if !branch.children then 
			print("INVALID PATH " .. path .. " AT DEPTH " .. i)
			return nil
		end

		local char = tonumber(path[i])
		branch = branch.children[char]
	end

	return branch
end

quadtree.__index = {
	should_split_pos = should_split_pos,
	traverse = traverse,
	split = split,
	split_pos = split_pos,
	path = path
}

return Quadtree