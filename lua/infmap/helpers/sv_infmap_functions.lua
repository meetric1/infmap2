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
end

-- merges 2 contraptions into the same chunk (ent1 -> ent2)
function INFMAP.merge_constraints(ent1_constrained, ent2_constrained)
	if ent1_constrained == ent2_constrained then 
		return false
	end

	local ent2 = ent2_constrained.parent
	local ent2_chunk = ent2:GetChunk()
	for e, _ in pairs(ent1_constrained) do
		if !isentity(e) then continue end

		ent2_constrained[e] = true
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
		ent.INFMAP_CONSTRAINTS = {[ent] = true, ["parent"] = ent}
	end

	if IsValid(prev) then
		local ent_constrained = ent.INFMAP_CONSTRAINTS
		local prev_constrained = prev.INFMAP_CONSTRAINTS
		if ent_constrained == prev_constrained then return end

		for e, _ in pairs(ent_constrained) do
			if !isentity(e) then continue end

			prev_constrained[e] = true
			e.INFMAP_CONSTRAINTS = prev_constrained
		end
	end

	-- recurse
	for _, constrained in ipairs(constraint.GetTable(ent)) do
		if INFMAP.filter_constraint(constrained.Constraint) then continue end

		for _, e in pairs(constrained.Entity) do
			e = e.Entity

			if e == ent then continue end
			INFMAP.validate_constraints(e, ent)
		end
	end
end

function INFMAP.invalidate_constraints(ent)
	local constrained = ent.INFMAP_CONSTRAINTS
	if !constrained then return end -- duh, already invalid

	for e, _ in pairs(constrained) do
		if !IsValid(e) or !isentity(e) then continue end

		e.INFMAP_CONSTRAINTS = nil
		e.INFMAP_DIRTY_WRAP = true -- for teleporting
	end
end