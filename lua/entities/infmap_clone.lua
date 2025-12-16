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

if CLIENT then return end -- later..

-- EnableCustomCollisions == true
local function custom_collisions_enabled(ent)
	return bit.band(ent:GetSolidFlags(), FSOLID_CUSTOMRAYTEST + FSOLID_CUSTOMBOXTEST) != 0
end

function ENT:InitializePhysics(parent)
	local parent_phys = parent:GetPhysicsObject()
	if !IsValid(parent_phys) then return end

	local parent_phys_old = self.INFMAP_REFERENCE_PARENT_PHYSOBJ
	if IsValid(parent_phys_old) and parent_phys_old == parent_phys then return end
	
	-- time to revalidate..
	if custom_collisions_enabled(parent) then
		local convexes = parent_phys:GetMesh()
		if convexes then
			self:PhysicsFromMesh(convexes)
			self:EnableCustomCollisions(true)
		else
			self:PhysicsDestroy()
		end
	end
	
	self.INFMAP_REFERENCE_PARENT_PHYSOBJ = parent_phys
end

function ENT:UpdatePhysics()
	local parent = self:GetReferenceParent()
	if !IsValid(parent) then
		self:Remove()
		return 
	end

	self:SetSolid(parent:GetSolid())
	self:SetCollisionGroup(parent:GetCollisionGroup())
	self:SetMoveType(parent:GetMoveType())
	self:InitializePhysics(parent)

	local self_phys = self:GetPhysicsObject()
	if !IsValid(self_phys) then return end

	-- update position
	self_phys:EnableMotion(false)
	if SERVER then
		local pos = INFMAP.unlocalize(parent:INFMAP_GetPos(), parent:GetChunk() - self:GetChunk())
		self:INFMAP_SetPos(pos)
		self:SetAngles(parent:GetAngles())
		--debugoverlay.Box(pos, self:OBBMins(), self:OBBMaxs())
	else
		self_phys:INFMAP_SetPos(self:INFMAP_GetPos())
		self_phys:SetAngles(self:GetAngles())
	end
end

function ENT:Initialize()
	local parent = self:GetReferenceParent()
	self:SetModel(parent:GetModel())
	self:SetNoDraw(true)
	parent:DeleteOnRemove(self)
end

ENT.Think = ENT.UpdatePhysics

hook.Add("PhysgunPickup", "infmap_clone_disablepickup", function(_, ent)
	if ent:GetClass() == "infmap_clone" then
		return false 
	end
end)