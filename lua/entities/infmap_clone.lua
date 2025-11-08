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

function ENT:InitializePhysics(parent)
	local phys = parent:GetPhysicsObject()
	parent.INFMAP_PHYSOBJ = phys

	if !phys:IsValid() then
		if SERVER then 
			SafeRemoveEntity(self)
		else
			self:PhysicsInit(SOLID_VPHYSICS)
		end

		return 
	end
	
	local convexes = phys:GetMesh()
	if !convexes then
		if SERVER then 
			SafeRemoveEntity(self) 
		end

		return
	end

	self:EnableCustomCollisions(true)
	self:PhysicsFromMesh(convexes)

	local phys = self:GetPhysicsObject()
	if phys:IsValid() then
		phys:EnableMotion(false)
	end
end

function ENT:Initialize()
	local parent = self:GetReferenceParent()

	if CLIENT then return end
	
	self:SetModel(parent:GetModel())
	self:SetCollisionGroup(parent:GetCollisionGroup())
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetNoDraw(true)	-- TODO: Does this break the client?
end

function ENT:Think()
	local parent = self:GetReferenceParent()
	if !IsValid(parent) then
		if SERVER then 
			SafeRemoveEntity(self)
		end
		
		return
	end

	local self_phys = self:GetPhysicsObject()
	local parent_phys = parent:GetPhysicsObject()
	local self_phys_valid = self_phys:IsValid()
	local parent_phys_valid = parent_phys:IsValid()

	if !self_phys_valid or (parent_phys_valid and parent_phys != parent.INFMAP_PHYSOBJ) then
		self:InitializePhysics(parent)
	end

	local pos = INFMAP.unlocalize(parent:INFMAP_GetPos(), parent:GetChunk() - self:GetChunk())
	local ang = parent:GetAngles()
	if SERVER then
		self:INFMAP_SetPos(pos)
		self:SetAngles(ang)
	elseif self_phys_valid then
		self_phys:INFMAP_SetPos(pos)
		self_phys:SetAngles(ang)
		self_phys:EnableMotion(false)
	end
	
	--debugoverlay.BoxAngles(self:INFMAP_GetPos(), self:OBBMins(), self:OBBMaxs(), self:GetAngles(), 0.1, Color(255, 127, 0, 0))
end

hook.Add("PhysgunPickup", "infmap_clone_disablepickup", function(_, ent)
	if ent:GetClass() == "infmap_clone" then
		return false 
	end
end)