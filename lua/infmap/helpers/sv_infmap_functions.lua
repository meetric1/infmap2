-- setting position kills all velocity
function INFMAP.unfucked_setpos(ent, pos)
	pos = INFMAP.clamp_pos(pos)

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

	-- for the rare case where 2 players are holding the same object
	for _, ply in player.Iterator() do
		if !ent:InChunk(ply) then
			ply:DropObject(ent)
		end
	end
end

-- merges 2 contraptions into the same chunk (ent1 -> ent2)
function INFMAP.merge_constraints(ent1, ent2)
	local ent1_constraints = ent1.INFMAP_CONSTRAINTS
	local ent2_constraints = ent2.INFMAP_CONSTRAINTS
	if !ent1_constraints or !ent2_constraints or ent1_constraints == ent2_constraints then 
		return false
	end

	local ent2_chunk = ent2:GetChunk()
	for _, e in ipairs(ent1_constraints) do
		table.insert(ent2_constraints, e)
		e.INFMAP_CONSTRAINTS = ent2_constraints

		-- localize ent
		if ent2_chunk then
			local chunk_offset = (e:GetChunk() or ent2_chunk) - ent2_chunk
			if !chunk_offset:IsZero() then
				INFMAP.unfucked_setpos(e, INFMAP.unlocalize(e:INFMAP_GetPos(), chunk_offset))
				e:SetChunk(ent2_chunk)
			end
		end
	end

	return true
end

-- recursive search through contraption
-- table of ents, with "parent" being the main entity to check
function INFMAP.validate_constraints(ent, prev)
	if INFMAP.filter_constraint_parsing(ent) then return end

	-- TODO: optimize (don't need to initialize ent table if prev exists)
	if !ent.INFMAP_CONSTRAINTS then
		ent.INFMAP_CONSTRAINTS = {[1] = ent, ["parent"] = ent}
	end

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
	if INFMAP.filter_collision(ent) or chunk_min == chunk_max then
		-- outside of area for cloning to happen (or invalidated), remove all clones
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
		for z = chunk_min[3], chunk_max[3] do
			for y = chunk_min[2], chunk_max[2] do
				for x = chunk_min[1], chunk_max[1] do
					local chunk_offset = INFMAP.Vector(x, y, z)
					if chunk_offset == chunk then continue end -- never self-clone
				
					-- dont clone 2 times
					local i = INFMAP.encode_vector(chunk_offset)
					local stored = ent.INFMAP_CLONES[i]
					if IsValid(stored) then
						stored:SetChunk(chunk_offset)
					else
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
end
