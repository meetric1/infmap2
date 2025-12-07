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
function INFMAP.merge_constraints(ent1_constrained, ent2_constrained)
	if ent1_constrained == ent2_constrained then 
		return false
	end

	local ent2_chunk = ent2_constrained.parent:GetChunk()
	for _, e in ipairs(ent1_constrained) do
		table.insert(ent2_constrained, e)
		e.INFMAP_CONSTRAINTS = ent2_constrained

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
		if !INFMAP.merge_constraints(ent.INFMAP_CONSTRAINTS, prev.INFMAP_CONSTRAINTS) then return end
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