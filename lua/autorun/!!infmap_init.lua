AddCSLuaFile()

-- ~15 ms check
local str = file.Read("maps/" .. game.GetMap() .. ".bsp", "GAME")
local ch = string.find(str, "\n\"classname\" \"infmap\"")
if !ch then return end

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