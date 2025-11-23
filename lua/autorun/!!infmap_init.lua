AddCSLuaFile()

-- we need to get entity data before map entities have initialized
-- otherwise, detours and related infmap functions will break
-- ~1 ms check
local map = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
if map:Read(4) != "VBSP" then return end -- wtf?

local map_version = map:ReadLong()
local lump0_offset = map:ReadLong()
local lump0_length = map:ReadLong()
map:Seek(lump0_offset)

local lump0_data = map:Read(lump0_length)
map:Close()

local infmap_start = string.find(lump0_data, [["classname" "infmap"]])
if !infmap_start then return end

local infmap_end = infmap_start
while lump0_data[infmap_end] != "}" do
	infmap_end = infmap_end + 1
end

while lump0_data[infmap_start] != "{" do
	infmap_start = infmap_start - 1
end

local infmap_data = {}
for k, v in string.sub(lump0_data, infmap_start, infmap_end):gmatch([["(.-)"%s+"(.-)"]]) do
	infmap_data[k] = v
end

------------
-- INFMAP --
------------

INFMAP = INFMAP or {
	chunk_origin = Vector(infmap_data["origin"]),
	chunk_size = (infmap_data["size"] or 10000) / 2
}

-- Add required files for clients
--resource.AddWorkshop("2905327911")

-- Load the files
local function load_folder(dir)
	local files, dirs = file.Find(dir .. "*","LUA")

	-- load files
	if files then
		for _, f in ipairs(files) do
			local prefix = string.lower(string.sub(f, 1, 2))
			if prefix != "sv" then
				AddCSLuaFile(dir .. f)
			end

			if  (           prefix == "sh") or 
				(SERVER and prefix == "sv") or
				(CLIENT and prefix == "cl") 
			then
				include(dir .. f)
			end
		end
	end

	-- reoccur in directory
	if dirs then
		for _, d in ipairs(dirs) do
			load_folder(dir .. d .. "/")
		end
	end
end

load_folder("infmap/")