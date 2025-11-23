AddCSLuaFile()

-- need to get entity data before map entities have initialized
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

local infmap = string.find(lump0_data, "\n\"classname\" \"infmap\"")
if !infmap then return end

INFMAP = INFMAP or {
	init = function()
		INFMAP.chunk_origin = GetGlobalVector("INFMAP_CHUNK_ORIGIN")
		INFMAP.chunk_size = GetGlobalFloat("INFMAP_CHUNK_SIZE")
	end
}

-- globals set inside of entities/infmap.lua
hook.Add("InitPostEntity", "infmap_init", INFMAP.init)

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