-- setting position kills all velocity
local function translate_ent(ent, translation, old_vel, old_angvel)
	-- ragdoll moment
	if ent:IsRagdoll() then
		ErrorNoHaltWithStack("IMPLEMENT ME")
	else
		-- translate angles (if applicable)
		local translation_angles = translation:GetAngles()
		if !translation_angles:IsZero() then
			-- setup rotation matrix
			local ang_mat = Matrix()
			ang_mat:SetAngles(translation_angles)
			
			-- translate real angle
			if ent:IsPlayer() then
				-- correct velocity
				-- "If applied to a player, this will actually ADD velocity"
				local old_vel = ent:GetVelocity()
				old_vel:Mul(ang_mat)
				old_vel:Sub(ent:GetVelocity()) 
				ent:SetVelocity(old_vel)

				-- player (use eye angles instead)
				ang_mat:Rotate(ent:EyeAngles())
				local ang = ang_mat:GetAngles()-- ang[3] = 0
				ent:SetEyeAngles(ang)
			else
				-- correct velocity
				if old_vel and old_angvel then
					old_vel:Mul(ang_mat)
					old_angvel:Mul(ang_mat)
				end

				-- entity
				ang_mat:Rotate(ent:GetAngles())
				local ang = ang_mat:GetAngles()
				ent:SetAngles(ang)
			end
		end
		
		-- translate position
		-- !!!WARNING!!! clamp_pos can cause undefined behavior with constraints
		local pos = ent:INFMAP_GetPos() 
		pos:Mul(translation)
		ent:INFMAP_SetPos(INFMAP.clamp_pos(pos))

		-- reset velocities back
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then
			phys:SetVelocity(old_vel)
			phys:SetAngleVelocity(old_angvel)
		end
	end

	-- force drop, for the rare case where 2 players are holding the same object
	local ent_chunk = ent:GetChunk()
	for _, ply in player.Iterator() do
		if !ply:InChunk(ent_chunk) then
			ply:DropObject(ent)
		end
	end
end

function INFMAP.translate_constraints(system, translation, chunk)
	-- old comapat
	if isvector(translation) then
		local t = translation
		translation = Matrix()
		translation:SetTranslation(t)
	end

	-- save old velocities
	local velocities = {}
	local ang_velocities = {}
	for i, ent in ipairs(system) do
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then
			velocities[i] = phys:GetVelocity()
			ang_velocities[i] = phys:GetAngleVelocity()
		end
	end

	for i, ent in ipairs(system) do
		ent:SetChunk(chunk)
		translate_ent(ent, translation, velocities[i], ang_velocities[i])
	end
end

-- merges 2 contraptions into the same chunk (ent1 -> ent2)
function INFMAP.merge_constraints(ent1, ent2)
	local ent1_constraints = ent1.INFMAP_CONSTRAINED
	local ent2_constraints = ent2.INFMAP_CONSTRAINED
	if !ent1_constraints or !ent2_constraints or ent1_constraints == ent2_constraints then 
		return false
	end
	
	-- merge systems
	for _, e in ipairs(ent1_constraints) do
		table.insert(ent2_constraints, e)
		e.INFMAP_CONSTRAINED = ent2_constraints
	end

	-- localize old system into new
	local ent1_chunk = ent1:GetChunk()
	local ent2_chunk = ent2:GetChunk()
	if ent1_chunk and ent2_chunk and ent1_chunk != ent2_chunk then
		local offset = INFMAP.unlocalize(vector_origin, ent1_chunk - ent2_chunk)
		INFMAP.translate_constraints(ent1_constraints, offset, ent2_chunk)
	end

	return true
end

-- recursive search through contraption
-- table of ents, with "parent" being the main entity to check
function INFMAP.validate_constraints(ent, prev)
	if INFMAP.filter_constraint_parsing(ent) then return end
	if ent.INFMAP_CONSTRAINED then return end -- already scanned

	ent.INFMAP_CONSTRAINED = {[1] = ent, ["parent"] = ent}

	if IsValid(prev) then
		if !INFMAP.merge_constraints(ent, prev) then return end
	end

	-- recurse
	for _, constraints in ipairs(constraint.GetTable(ent)) do
		if INFMAP.filter_constraint(constraints.Constraint) then continue end

		for _, e in pairs(constraints.Entity) do
			e = e.Entity

			if e == ent then continue end
			INFMAP.validate_constraints(e, ent)
		end
	end
end

-- collision with props crossing through chunk bounderies
function INFMAP.update_cross_chunk_collision(ent)
	local aabb_min, aabb_max = ent:INFMAP_WorldSpaceAABB()
	local chunk = ent:GetChunk()
	local _, chunk_min = INFMAP.localize(aabb_min)
	local _, chunk_max = INFMAP.localize(aabb_max)
	if !chunk or (chunk_min == chunk and chunk_max == chunk) or INFMAP.filter_collision(ent) then
		-- inside of area that cloning doesn't happen (or invalidated), remove all clones
		if ent.INFMAP_CLONES then
			for _, e in pairs(ent.INFMAP_CLONES) do
				SafeRemoveEntity(e)
			end
			ent.INFMAP_CLONES = nil
		end
	else
		chunk_min = chunk_min + chunk
		chunk_max = chunk_max + chunk
		ent.INFMAP_CLONES = ent.INFMAP_CLONES or {}

		-- clean unused clones
		for i, clone in pairs(ent.INFMAP_CLONES) do
			local chunk = clone:GetChunk()
			if !INFMAP.aabb_intersect_aabb(chunk, chunk, chunk_min, chunk_max) then
				SafeRemoveEntity(clone)
				ent.INFMAP_CLONES[i] = nil
			end
		end

		for z = chunk_min[3], chunk_max[3] do
			for y = chunk_min[2], chunk_max[2] do
				for x = chunk_min[1], chunk_max[1] do
					local chunk_offset = INFMAP.Vector(x, y, z)
					if chunk_offset == chunk then continue end -- never self-clone
				
					-- dont clone 2 times
					local i = INFMAP.encode_vector(chunk_offset)
					local stored = ent.INFMAP_CLONES[i]
					if IsValid(stored) then continue end

					local clone = ents.Create("infmap_clone")
					clone:SetReferenceParent(ent)
					clone:SetChunk(chunk_offset)
					clone:Spawn()
					ent.INFMAP_CLONES[i] = clone
				end
			end 
		end
	end
end
