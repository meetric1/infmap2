AddCSLuaFile()

INFMAP = INFMAP or {
	chunk_origin = Vector(1500, 0, 0),
	chunk_size = 1000
}

-- Add required files for clients
--resource.AddWorkshop("2905327911")

-- Load the files
local function load_folder(dir)
	local files, dirs = file.Find(dir .. "*","LUA")

	-- reoccur in directory
	if dirs then
		for _, d in ipairs(dirs) do
			load_folder(dir .. d .. "/")
		end
	end

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
end

load_folder("infmap/")

hook.Add("InitPostEntity", "infmap_init", function()
	-- globals set inside of entities/infmap.lua
	INFMAP.chunk_origin = GetGlobalVector("INFMAP_CHUNK_ORIGIN")
	INFMAP.chunk_size = GetGlobalFloat("INFMAP_CHUNK_SIZE")

	--if INFMAP.chunk_size != 0 then
	--	load_folder("infmap/")
	--end
end)