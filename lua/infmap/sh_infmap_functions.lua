-- useful functions used throughout the lua

-- little endian encoding, in base 255 (since we can't represent 0x00 in a string)
-- encoded using 7 bytes per number (since double can only represent integers to 2^53)
	-- giving us a maximum positive and negative value of 255^6 * 127, which is just shy of 2^(7*8-1)
function INFMAP.encode_vector(vec)
	if vec == nil then return "" end
	local str = ""

	for i = 1, 3 do
		local negative = false
		local num = vec[i]
		if num < 0 then
			negative = true
			num = -num
		end

		for i = 1, 6 do
			str = str .. string.char(num % 255 + 1)
			num = math.floor(num / 255)
		end

		if negative then
			str = str .. string.char(num % 127 + 1 + 0x80)
		else
			str = str .. string.char(num % 127 + 1)
		end
	end

	return str
end

function INFMAP.decode_vector(str)
	if #str <= 0 then return nil end
	local vec = INFMAP.Vector()

	local index = #str
	for i = 3, 1, -1 do
		local negative = false
		local num = string.byte(str, index, index) - 1
		if num >= 0x80 then
			negative = true
			num = num - 0x80
		end
		index = index - 1

		for i = 1, 6 do
			num = num * 255
			num = num + string.byte(str, index, index) - 1
			index = index - 1
		end
		
		if negative then
			vec[i] = -num
		else
			vec[i] = num
		end
	end

	return vec
end

-- setting position kills all velocity
function INFMAP.unfucked_setpos(ent, pos)
	-- clamp to source bounds
	pos = Vector(
		math.Clamp(pos[1], -2^14+64, 2^14-64),
		math.Clamp(pos[2], -2^14+64, 2^14-64),
		math.Clamp(pos[3], -2^14+64, 2^14-64)
	)

	-- ragdoll moment
	if ent:IsRagdoll() then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys = ent:GetPhysicsObjectNum(i)
			local vel = phys:GetVelocity()
			local diff = phys:INFMAP_GetPos() - ent:INFMAP_GetPos()
		
			phys:INFMAP_SetPos(pos + diff)
			phys:SetVelocity(vel)
		end

		--ent:INFMAP_SetPos(pos)
	else
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then 
			local vel = phys:GetVelocity()
			ent:INFMAP_SetPos(pos)
			phys:SetVelocity(vel)
		else
			ent:INFMAP_SetPos(pos)
		end
	end
end

-- Is this position in a chunk?
local pos_local = Vector() -- avoid creating vector object (yes, they are that expensive..)
function INFMAP.in_chunk(pos, size)
	local chunk_size = size or INFMAP.chunk_size
	pos_local:Set(pos)
	pos_local:Sub(INFMAP.chunk_origin)

	return (
		pos_local[1] > -chunk_size and pos_local[1] < chunk_size and 
		pos_local[2] > -chunk_size and pos_local[2] < chunk_size and 
		pos_local[3] > -chunk_size and pos_local[3] < chunk_size
	)
end

function INFMAP.localize(pos, size)
	pos_local:Set(pos)
	pos_local:Sub(INFMAP.chunk_origin) -- pos_local = pos - INFMAP.chunk_origin (fast)

	local chunk_size = size or INFMAP.chunk_size
	local chunk_size2 = chunk_size * 2
	local chunk_size2_inv = 1 / chunk_size2
	
	-- calculate chunk offset
	local chunk_offset = INFMAP.Vector(
		math.floor((pos_local[1] + chunk_size) * chunk_size2_inv), 
		math.floor((pos_local[2] + chunk_size) * chunk_size2_inv), 
		math.floor((pos_local[3] + chunk_size) * chunk_size2_inv)
	)

	-- calculate localized position
	local offset = Vector(pos_local)
	
	-- wrap coords, we offset vector so coords are 0 to x * 2 instead of -x to x during modulo
	offset[1] = ((offset[1] + chunk_size) % chunk_size2) - chunk_size
	offset[2] = ((offset[2] + chunk_size) % chunk_size2) - chunk_size
	offset[3] = ((offset[3] + chunk_size) % chunk_size2) - chunk_size
	offset:Add(INFMAP.chunk_origin)

	return offset, chunk_offset
end

function INFMAP.unlocalize(pos, chunk)
	local chunk_size_2 = INFMAP.chunk_size * 2

	return Vector(
		chunk[1] * chunk_size_2 + pos[1],
		chunk[2] * chunk_size_2 + pos[2],
		chunk[3] * chunk_size_2 + pos[3]
	)
end

-- replace with util.IsBoxIntersectingBox if desired
function INFMAP.aabb_intersect_aabb(min_a, max_a, min_b, max_b)
	return (
		(max_b[1] >= min_a[1] and min_b[1] <= max_a[1]) and 
		(max_b[2] >= min_a[2] and min_b[2] <= max_a[2]) and 
		(max_b[3] >= min_a[3] and min_b[3] <= max_a[3])
	)
end

-- we need more filters, as there are a *lot* of weird exceptions. we need:
	-- general class filter
	-- cross chunk collision filter
	-- rendering filter
	-- should teleport filter
	-- constraint filter
	-- valid constraint filter

-- blacklist of all the classes that are useless (never wrapped)
INFMAP.class_filter = INFMAP.class_filter or {
	["infmap"] = true,
	["infmap_clone"] = true,
	["infmap_vbsp"] = true,
	["physgun_beam"] = true,
	["worldspawn"] = true,
	["info_particle_system"] = true,
	["phys_spring"] = true,
	["predicted_viewmodel"] = true,
	["env_projectedtexture"] = true,
	["keyframe_rope"] = true,
	["hl2mp_ragdoll"] = true,
	["env_skypaint"] = true,
	["shadow_control"] = true,
	["player_pickup"] = true,
	["env_sun"] = true,
	["info_player_start"] = true,
	["scene_manager"] = true,
	["ai_network"] = true,
	["network"] = true,
	["gmod_gamerules"] = true,
	["player_manager"] = true,
	["soundent"] = true,
	["env_flare"] = true,
	["_firesmoke"] = true,
	["func_brush"] = true,
	["logic_auto"] = true,
	["light_environment"] = true,
	["env_laserdot"] = true,
	["env_smokestack"] = true,
	["env_rockettrail"] = true,
	["env_fog_controller"] = true,
	["sizehandler"] = true,
	["player_pickup"] = true,
	["phys_spring"] = true,
	["sky_camera"] = true,
	["logic_collision_pair"] = true,
}

-- base filter - nothing gets through this
function INFMAP.filter_general(ent)
	if ent:IsWorld() then return true end
	if ent.IsConstraint and ent:IsConstraint() then return true end
	if INFMAP.class_filter[ent:GetClass()] then return true end
	
	return false
end

-- blacklist
INFMAP.teleport_class_filter = {
	["rpg_missile"] = true,
	["crossbow_bolt"] = true,
	["prop_vehicle_jeep"] = true, -- super fucked
}

-- teleport filter - which objects shouldnt be wrapped?
function INFMAP.filter_teleport(ent)
	if !ent:IsChunkValid() then return true end
	if IsValid(ent:GetParent()) then return true end
	if ent:IsPlayer() and !ent:Alive() then return true end
	if ent.INFMAP_CONSTRAINTS and (ent.INFMAP_CONSTRAINTS.parent != ent) then return true end
	if INFMAP.teleport_class_filter[ent:GetClass()] then return true end

	return INFMAP.filter_general(ent)
end

-- collision filter - which entities shouldnt have cross-chunk collision?
function INFMAP.filter_collision(ent)
	if ent:IsPlayer() then return true end -- too bitchy
	if !ent:GetModel() then return true end
	if !ent:IsChunkValid() then return true end
	if IsValid(ent:GetParent()) then return true end
	if ent:BoundingRadius() < 10 then return true end -- no tiny props, too much compute
	if INFMAP.teleport_class_filter[ent:GetClass()] then return true end

	return INFMAP.filter_general(ent)
end

-- renderer filter - which entities shouldnt be rendered?
function INFMAP.filter_render(ent)
	if ent:GetNoDraw() then return true end
	if !ent:IsChunkValid() then return true end

	return INFMAP.filter_general(ent)
end

-- fancy render filter - some entities require a full "fancy" rendering detour using the cam library
function INFMAP.filter_render_fancy(ent)
	if ent:IsPlayer() then return true end
	if ent:IsWeapon() then return true end
	if ent:IsRagdoll() then return true end

	return false
end

-- constraint filter - which entities should we ignore during constraint parsing
function INFMAP.filter_constraint_parsing(ent)
	if !ent:IsChunkValid() then return true end
	if IsValid(ent:GetParent()) then return true end

	return INFMAP.filter_general(ent)
end

-- constraint filter- what constraints aren't actually constraints?
function INFMAP.filter_constraint(ent)
	if ent:GetClass() == "logic_collision_pair" then return true end

	return false
end

-- algorithm to split concave (and convex) shapes given a set of triangles
-- tris are in the format {{pos = value}, {pos = value2}}
-- code based on Glass: Rewrite
/*
function INFMAP.split_concave(tris, plane_pos, plane_dir)
	if !tris then return {} end

	local plane_dir = plane_dir:GetNormalized()     -- normalize plane direction
	local split_tris = {}
	local plane_points = {}

	-- loop through all triangles in the mesh
	local util_IntersectRayWithPlane = util.IntersectRayWithPlane
	local table_insert = function(tbl, obj) 
		tbl[#tbl + 1] = obj
	end

	for i = 1, #tris, 3 do
		local pos1 = tris[i    ]
		local pos2 = tris[i + 1]
		local pos3 = tris[i + 2]
		if pos1.pos then pos1 = pos1.pos end
		if pos2.pos then pos2 = pos2.pos end
		if pos3.pos then pos3 = pos3.pos end

		-- get points that are valid sides of the plane
		local pos1_valid = (pos1 - plane_pos):Dot(plane_dir) > 0
		local pos2_valid = (pos2 - plane_pos):Dot(plane_dir) > 0
		local pos3_valid = (pos3 - plane_pos):Dot(plane_dir) > 0
		
		-- if all points should be kept, add triangle
		if pos1_valid and pos2_valid and pos3_valid then 
			table_insert(split_tris, pos1)
			table_insert(split_tris, pos2)
			table_insert(split_tris, pos3)
			continue
		end
		
		-- if none of the points should be kept, skip triangle
		if !pos1_valid and !pos2_valid and !pos3_valid then 
			continue 
		end
		
		-- all possible states of the intersected triangle
		local new_tris = {}
		local point1
		local point2
		local is_flipped = false
		if pos1_valid then
			if pos2_valid then      -- pos1 = valid, pos2 = valid, pos3 = invalid
				point1 = util_IntersectRayWithPlane(pos1, pos3 - pos1, plane_pos, plane_dir)
				point2 = util_IntersectRayWithPlane(pos2, pos3 - pos2, plane_pos, plane_dir)
				if !point1 then point1 = pos3 end
				if !point2 then point2 = pos3 end
				table_insert(new_tris, pos1)
				table_insert(new_tris, pos2)
				table_insert(new_tris, point1)
				table_insert(new_tris, point2)
				table_insert(new_tris, point1)
				table_insert(new_tris, pos2)
				is_flipped = true
			elseif pos3_valid then  -- pos1 = valid, pos2 = invalid, pos3 = valid
				point1 = util_IntersectRayWithPlane(pos1, pos2 - pos1, plane_pos, plane_dir)
				point2 = util_IntersectRayWithPlane(pos3, pos2 - pos3, plane_pos, plane_dir)
				if !point1 then point1 = pos2 end
				if !point2 then point2 = pos2 end
				table_insert(new_tris, point1)
				table_insert(new_tris, pos3)
				table_insert(new_tris, pos1)
				table_insert(new_tris, pos3)
				table_insert(new_tris, point1)
				table_insert(new_tris, point2)
			else                    -- pos1 = valid, pos2 = invalid, pos3 = invalid
				point1 = util_IntersectRayWithPlane(pos1, pos2 - pos1, plane_pos, plane_dir)
				point2 = util_IntersectRayWithPlane(pos1, pos3 - pos1, plane_pos, plane_dir)
				if !point1 then point1 = pos2 end
				if !point2 then point2 = pos3 end
				table_insert(new_tris, pos1)
				table_insert(new_tris, point1)
				table_insert(new_tris, point2)
			end
		elseif pos2_valid then
			if pos3_valid then      -- pos1 = invalid, pos2 = valid, pos3 = valid
				point1 = util_IntersectRayWithPlane(pos2, pos1 - pos2, plane_pos, plane_dir)
				point2 = util_IntersectRayWithPlane(pos3, pos1 - pos3, plane_pos, plane_dir)
				if !point1 then point1 = pos1 end
				if !point2 then point2 = pos1 end
				table_insert(new_tris, pos2)
				table_insert(new_tris, pos3)
				table_insert(new_tris, point1)
				table_insert(new_tris, point2)
				table_insert(new_tris, point1)
				table_insert(new_tris, pos3)
				is_flipped = true 
			else                    -- pos1 = invalid, pos2 = valid, pos3 = invalid
				point1 = util_IntersectRayWithPlane(pos2, pos1 - pos2, plane_pos, plane_dir)
				point2 = util_IntersectRayWithPlane(pos2, pos3 - pos2, plane_pos, plane_dir)
				if !point1 then point1 = pos1 end
				if !point2 then point2 = pos3 end
				table_insert(new_tris, point2)
				table_insert(new_tris, point1)
				table_insert(new_tris, pos2)
				is_flipped = true
			end
		else                       -- pos1 = invalid, pos2 = invalid, pos3 = valid
			point1 = util_IntersectRayWithPlane(pos3, pos1 - pos3, plane_pos, plane_dir)
			point2 = util_IntersectRayWithPlane(pos3, pos2 - pos3, plane_pos, plane_dir)
			if !point1 then point1 = pos1 end
			if !point2 then point2 = pos2 end
			table_insert(new_tris, pos3)
			table_insert(new_tris, point1)
			table_insert(new_tris, point2)
		end
	
		table.Add(split_tris, new_tris)
		if is_flipped then
			table_insert(plane_points, point1)
			table_insert(plane_points, point2)
		else
			table_insert(plane_points, point2)
			table_insert(plane_points, point1)
		end
	end
	
	-- uncomment for convex shapes
	--[[
	-- add triangles inside of the object
	-- each 2 points is an edge, create a triangle between the egde and first point
	-- start at index 4 since the first edge (1-2) cant exist since we are wrapping around the first point
	for i = 4, #plane_points, 2 do
		table_insert(split_tris, plane_points[1    ])
		table_insert(split_tris, plane_points[i - 1])
		table_insert(split_tris, plane_points[i    ])
	end]]

	return split_tris
end*/