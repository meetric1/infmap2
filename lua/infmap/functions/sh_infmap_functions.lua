local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_Clamp = math.Clamp
local string_char = string.char
local string_byte = string.byte

-- useful functions used throughout the lua

-- little endian encoding, in base 255 (since we can't represent 0x00 in a string)
-- encoded using 7 bytes per number (since double can only represent integers to 2^53)
	-- giving us a maximum positive and negative value of 255^6 * 127, which is just shy of 2^55
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

		for _ = 1, 6 do
			str = str .. string_char(num % 255 + 1)
			num = math_floor(num / 255)
		end

		if negative then
			str = str .. string_char(num % 127 + 1 + 0x80)
		else
			str = str .. string_char(num % 127 + 1)
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
		local num = string_byte(str, index, index) - 1
		if num >= 0x80 then
			negative = true
			num = num - 0x80
		end
		index = index - 1

		for _ = 1, 6 do
			num = num * 255
			num = num + string_byte(str, index, index) - 1
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

function INFMAP.clamp_to_bounds(pos)
	return Vector(
		math_Clamp(pos[1], -2^14+1, 2^14-1),
		math_Clamp(pos[2], -2^14+1, 2^14-1),
		math_Clamp(pos[3], -2^14+1, 2^14-1)
	)
end

-- Is the position within source bounds
function INFMAP.in_bounds(pos)
	return (
		pos[1] > -2^14 and pos[1] < 2^14 and
		pos[2] > -2^14 and pos[2] < 2^14 and
		pos[3] > -2^14 and pos[3] < 2^14
	)
end

-- Is this position in a chunk?
function INFMAP.in_chunk(pos, size)
	local chunk_size = size or INFMAP.chunk_size
	local chunk_origin = INFMAP.chunk_origin
	local x = pos[1] - chunk_origin[1]
	local y = pos[2] - chunk_origin[2]
	local z = pos[3] - chunk_origin[3]

	return (
		x >= -chunk_size and x <= chunk_size and
		y >= -chunk_size and y <= chunk_size and
		z >= -chunk_size and z <= chunk_size
	)
end

function INFMAP.localize(pos, size)
	local chunk_origin = INFMAP.chunk_origin
	local x = pos[1] - chunk_origin[1]
	local y = pos[2] - chunk_origin[2]
	local z = pos[3] - chunk_origin[3]

	local chunk_size = size or INFMAP.chunk_size
	local chunk_size2 = chunk_size * 2
	local chunk_size2_inv = 1 / chunk_size2

	-- calculate chunk offset
	local chunk_offset = INFMAP.Vector(
		math_floor((x + chunk_size) * chunk_size2_inv),
		math_floor((y + chunk_size) * chunk_size2_inv),
		math_floor((z + chunk_size) * chunk_size2_inv)
	)

	-- calculate localized position
	-- wrap coords, we offset vector so coords are 0 to x * 2 instead of -x to x during modulo
	local offset = Vector(
		((x + chunk_size) % chunk_size2) - chunk_size,
		((y + chunk_size) % chunk_size2) - chunk_size,
		((z + chunk_size) % chunk_size2) - chunk_size
	)
	offset:Add(chunk_origin)

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
		max_b[1] >= min_a[1] and min_b[1] <= max_a[1] and
		max_b[2] >= min_a[2] and min_b[2] <= max_a[2] and
		max_b[3] >= min_a[3] and min_b[3] <= max_a[3]
	)
end

-- adapted from https://gist.github.com/DomNomNom/46bb1ce47f68d255fd5d
function INFMAP.ray_intersect_aabb(ray_pos, ray_dir, box_min, box_max)
    local tmin = (box_min - ray_pos) tmin:Div(ray_dir)
    local tmax = (box_max - ray_pos) tmax:Div(ray_dir)
    local t1_x = math_min(tmin[1], tmax[1])
    local t1_y = math_min(tmin[2], tmax[2])
    local t1_z = math_min(tmin[3], tmax[2])
    local t2_x = math_max(tmin[1], tmax[1])
    local t2_y = math_max(tmin[2], tmax[2])
    local t2_z = math_max(tmin[3], tmax[3])
    local tnear = math_max(math_max(t1_x, t1_y), t1_z)
    local tfar = math_min(math_min(t2_x, t2_y), t2_z)
    return tnear, tfar
end

-- we need filters, as there are a *lot* of weird exceptions
-- blacklist of all the classes that are useless (never wrapped)
INFMAP.filter_classes = {
	["infmap"] = true,
	["infmap_clone"] = true,
	["infmap_vbsp"] = true,
	["physgun_beam"] = true,
	["worldspawn"] = true,
	["gmod_hands"] = true,
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
	["sky_camera"] = true,
	["logic_collision_pair"] = true,
	["lvs_wheeldrive_steerhandler"] = true,
}

-- base filter - nothing gets through this
function INFMAP.filter_general(ent)
	if ent:IsWorld() then return true end
	if SERVER and ent:IsConstraint() then return true end
	if INFMAP.filter_classes[ent:GetClass()] then return true end

	return false
end

-- constraint filter - which entities should we ignore during constraint parsing
function INFMAP.filter_constraint_parsing(ent)
	if IsValid(ent:GetParent()) then return true end

	return INFMAP.filter_general(ent)
end

-- blacklist
INFMAP.filter_teleport_classes = {
	["rpg_missile"] = true,
	["crossbow_bolt"] = true,
	["prop_vehicle_jeep"] = true, -- super fucked
	["infmap_vbsp_client"] = true,
	["infmap_lod"] = true,
}

-- teleport filter - which objects shouldnt be wrapped?
function INFMAP.filter_teleport(ent, ignore)
	if !ignore and !ent:IsChunkValid() then return true end

	if ent:IsPlayer() and !ent:Alive() then return true end
	if ent.INFMAP_CONSTRAINED and (ent.INFMAP_CONSTRAINED.parent != ent) then return true end
	if INFMAP.filter_teleport_classes[ent:GetClass()] then return true end

	return INFMAP.filter_constraint_parsing(ent)
end

-- collision filter - which entities shouldnt have cross-chunk collision?
function INFMAP.filter_collision(ent)
	if ent:IsPlayer() or ent:IsWeapon() then return true end
	if ent:BoundingRadius() < 10 then return true end -- no tiny props, too much compute
	if INFMAP.filter_teleport_classes[ent:GetClass()] then return true end

	return INFMAP.filter_general(ent)
end

-- renderer filter - which entities shouldnt be rendered?
function INFMAP.filter_render(ent, ignore)
	if !ignore and !ent:IsChunkValid() then return true end

	if ent:GetNoDraw() then return true end

	return INFMAP.filter_general(ent)
end

-- fancy render filter - some entities require a full "fancy" rendering detour using the cam library
--function INFMAP.filter_render_fancy(ent)
--	if ent:IsPlayer() then return true end
--	if ent:IsWeapon() then return true end
--	if ent:IsRagdoll() then return true end
--
--	return false
--end

-- lighting breaks.. FIXME!
function INFMAP.filter_render_fancy(ent)
	return true
end

-- constraint filter- what constraints aren't actually constraints?
function INFMAP.filter_constraint(ent)
	if ent:GetClass() == "logic_collision_pair" then return true end

	return false
end

-- safe hook call, for easy API implementation
-- will throw error, but does not halt infmap codebase
function INFMAP.hook_run_safe(hook_name, ...)
	local succ, ret = pcall(function(...) return hook.Run(hook_name, ...) end, ...)
	local err = !succ

	if err then
		ErrorNoHaltWithStack(ret)
	end

	return err, ret
end
-- INFMAP.hook_run_safe = hook.Run

-- algorithm to split concave shapes given a set of triangles
-- tris are in the format {pos1, pos2, pos3, ...}
-- code based on Glass: Rewrite
function INFMAP.split_concave(tris, plane_pos, plane_dir)
	plane_dir = plane_dir:GetNormalized()

	local split_tris = {}
	local intersect = util.IntersectRayWithPlane

	local function inside(p)
		return (p - plane_pos):Dot(plane_dir) >= 0
	end

	-- sutherland-hodgman
	local function clip(poly)
		local result = {}

		for i = 1, #poly do
			local a = poly[i] -- current
			local b = poly[i % #poly + 1] -- previous
			local a_in = inside(a)
			local b_in = inside(b)

			if a_in and b_in then
				result[#result + 1] = b
			elseif a_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
			elseif b_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
				result[#result + 1] = b
			end
		end

		return result
	end

	for i = 1, #tris, 3 do
		local poly = clip({
			tris[i    ],
			tris[i + 1],
			tris[i + 2]
		})

		for j = 2, #poly - 1 do
			split_tris[#split_tris + 1] = poly[1    ]
			split_tris[#split_tris + 1] = poly[j    ]
			split_tris[#split_tris + 1] = poly[j + 1]
		end
	end

	return split_tris
end
