-- clones collision of other entites
-- useful so you dont fall through objects at chunk bounderies

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
	local parent_phys = parent:GetPhysicsObject()
	if !IsValid(parent_phys) then return end

	local parent_phys_old = self.INFMAP_REFERENCE_PARENT_PHYSOBJ
	if IsValid(parent_phys_old) and parent_phys_old == parent_phys then return end
	
	self.INFMAP_REFERENCE_PARENT_PHYSOBJ = parent_phys
	-- EnableCustomCollisions == false
	if bit.band(parent:GetSolidFlags(), FSOLID_CUSTOMRAYTEST + FSOLID_CUSTOMBOXTEST) == 0 then
		if SERVER then
			self:PhysicsInit(SOLID_VPHYSICS)
		end
	else
		local convexes = parent_phys:GetMesh()
		if !convexes then
			if SERVER then
				self:PhysicsInit(SOLID_NONE)
			end 
		else
			self:PhysicsFromMesh(convexes)
			self:EnableCustomCollisions(true)
		end
	end
end

function ENT:UpdatePhysics()
	local parent = self:GetReferenceParent()
	if !IsValid(parent) then return end

	self:SetSolid(parent:GetSolid())
	self:SetCollisionGroup(parent:GetCollisionGroup())
	self:SetMoveType(parent:GetMoveType())
	self:InitializePhysics(parent)

	local self_phys = self:GetPhysicsObject()
	if !IsValid(self_phys) then return end

	-- freeze
	self_phys:EnableMotion(false)
	
	-- update position
	if SERVER then
		local pos = INFMAP.unlocalize(parent:INFMAP_GetPos(), parent:GetChunk() - self:GetChunk())
		self:INFMAP_SetPos(pos)
		self:SetAngles(parent:GetAngles())
		--debugoverlay.Box(pos, self:OBBMins(), self:OBBMaxs())
	elseif IsValid(self_phys) then
		self_phys:INFMAP_SetPos(self:INFMAP_GetPos())
		self_phys:SetAngles(self:GetAngles())
	end
end

function ENT:Initialize()
	if CLIENT then return end

	local parent = self:GetReferenceParent()
	self:SetModel(parent:GetModel())
	self:SetNoDraw(true)
	self:UpdatePhysics()
	parent:DeleteOnRemove(self)
end

function ENT:Think()
	self:UpdatePhysics()
	
	if CLIENT then
		self:SetNextClientThink(CurTime() + 1/4)
		return true
	end
end

hook.Add("PhysgunPickup", "infmap_clone_disablepickup", function(_, ent)
	if ent:GetClass() == "infmap_clone" then
		return false 
	end
end)