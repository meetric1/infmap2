AddCSLuaFile()

ENT.Type = "anim"
--ENT.Base = "base_gmodentity"

ENT.Category		= "Other"
ENT.PrintName		= "Clone"
ENT.Author			= "Meetric"
ENT.Purpose			= ""
ENT.Instructions	= ""
ENT.Spawnable		= false

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "ReferenceParent")
end

function ENT:InitializePhysics(parent_phys)
	if !IsValid(parent_phys) then return end

	parent.INFMAP_REFERENCE_PARENT_PHYSOBJ = parent_phys
	if bit.band(parent:GetSolidFlags(), FSOLID_CUSTOMRAYTEST + FSOLID_CUSTOMBOXTEST) == 0 then -- EnableCustomCollisions == false
		if SERVER then
			self:PhysicsInit(SOLID_VPHYSICS)
		end
		return
	end

	local convexes = parent_phys:GetMesh()
	if !convexes then 
		if SERVER then 
			SafeRemoveEntity(self) 
		end 
	else
		self:PhysicsFromMesh(convexes)
		self:EnableCustomCollisions(true)
	end
end

function ENT:UpdatePhysics()
	local self_phys = self:GetPhysicsObject()
	if !IsValid(self_phys) then return end

	-- update physics (if parent changed)
	local parent_phys = self:GetReferenceParent():GetPhysicsObject()
	if self.INFMAP_REFERENCE_PARENT_PHYSOBJ != parent_phys then
		self:InitializePhysics(parent_phys)
	end

	-- update position
	if SERVER then
		local pos = INFMAP.unlocalize(parent:INFMAP_GetPos(), parent:GetChunk() - self:GetChunk())
		if util.IsInWorld(pos) then
			self_phys:INFMAP_SetPos(pos)
			self_phys:SetAngles(parent:GetAngles())
		else
			SafeRemoveEntity(self)
		end
	elseif IsValid(parent_phys) then
		self_phys:INFMAP_SetPos(self:INFMAP_GetPos())
		self_phys:SetAngles(self:GetAngles())
	end

	-- update other info
	self_phys:EnableMotion(false)
	self:SetCollisionGroup(parent:GetCollisionGroup())
	self:SetMoveType(parent:GetMoveType())
end


function ENT:Initialize()
	local parent = self:GetReferenceParent()

	if CLIENT then return end
	
	self:SetModel(parent:GetModel())
	self:SetSolid(SOLID_VPHYSICS)
	self:SetNoDraw(true) -- TODO: Does this break the client?

	parent:DeleteOnRemove(self)
	self:UpdatePhysics()
end

ENT.Think = ENT.UpdatePhysics

hook.Add("PhysgunPickup", "infmap_clone_disablepickup", function(_, ent)
	if ent:GetClass() == "infmap_clone" then
		return false 
	end
end)