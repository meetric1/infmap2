-- merges 2 contraptions into the same chunk (ent1 -> ent2)
function INFMAP.merge_constraints(ent1_constrained, ent2_constrained)
	if ent1_constrained == ent2_constrained then 
		return false
	end

	local ent2 = ent2_constrained.parent
	local chunk_valid = ent2:IsChunkValid()
	local chunk_offset = ent2:GetChunk()
	
	for e, _ in pairs(ent1_constrained) do
		if !isentity(e) then continue end

		ent2_constrained[e] = true
		e.INFMAP_CONSTRAINTS = ent2_constrained
		local chunk = e:GetChunk() - chunk_offset
		if !chunk:IsZero() then
			INFMAP.unfucked_setpos(e, INFMAP.unlocalize(e:INFMAP_GetPos(), chunk))
			e:SetChunk(chunk_valid and chunk_offset or nil)
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
		if !INFMAP.merge_constraints(ent.INFMAP_CONSTRAINTS, prev.INFMAP_CONSTRAINTS) then
			return
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