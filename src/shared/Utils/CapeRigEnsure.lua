--!strict

-- Ensures Suit/UT/Cape (skinned cape + bones) exists on the live character when morphing from showcase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)

local CapeRigEnsure = {}

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, name in segments do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function hasSkinnedCape(character: Model): boolean
	for _, segments in GlideVfxConfigs.CapeSearchPaths do
		local found = resolvePath(character, segments)
		if found then
			for _, desc in found:GetDescendants() do
				if desc:IsA("Bone") then
					return true
				end
			end
			if found:IsA("MeshPart") then
				for _, child in found:GetChildren() do
					if child:IsA("Bone") then
						return true
					end
				end
			end
		end
	end
	return false
end

local function findTemplateUt(template: Model): Instance?
	return resolvePath(template, { "Suit", "UT" }) or resolvePath(template, { "UT" })
end

local function ensureSuitFolder(character: Model): Instance
	local suit = character:FindFirstChild("Suit")
	if suit then
		return suit
	end
	suit = Instance.new("Model")
	suit.Name = "Suit"
	suit.Parent = character
	return suit
end

local function debugLog(...)
	local cfg = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)
	if not cfg.Debug then
		return
	end
	print("[iseesupes][CapeRigEnsure]", ...)
end

local function findCapeTorsoWeld(cape: BasePart, torso: BasePart): WeldConstraint?
	for _, desc in cape:GetDescendants() do
		if desc:IsA("WeldConstraint") then
			local weld = desc :: WeldConstraint
			local p0, p1 = weld.Part0, weld.Part1
			if (p0 == cape or p1 == cape) and (p0 == torso or p1 == torso) then
				return weld
			end
		end
	end
	for _, child in torso:GetChildren() do
		if child:IsA("WeldConstraint") then
			local weld = child :: WeldConstraint
			local p0, p1 = weld.Part0, weld.Part1
			if (p0 == cape or p1 == cape) and (p0 == torso or p1 == torso) then
				return weld
			end
		end
	end
	return nil
end

function CapeRigEnsure.findCapeMotor(cape: BasePart, torso: BasePart?): Motor6D?
	local motorName = GlideVfxConfigs.CapeMotorName
	local onCape = cape:FindFirstChild(motorName)
	if onCape and onCape:IsA("Motor6D") then
		return onCape
	end
	if torso then
		local onTorso = torso:FindFirstChild(motorName)
		if onTorso and onTorso:IsA("Motor6D") then
			return onTorso
		end
	end
	return nil
end

function CapeRigEnsure.ensureCapeMotor(character: Model, cape: BasePart): Motor6D?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end

	local existing = CapeRigEnsure.findCapeMotor(cape, torso)
	if existing and existing.Part0 == torso and existing.Part1 == cape then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local weld = findCapeTorsoWeld(cape, torso)
	local motor = Instance.new("Motor6D")
	motor.Name = GlideVfxConfigs.CapeMotorName
	motor.Part0 = torso
	motor.Part1 = cape
	motor.Transform = CFrame.new()

	if weld then
		motor.C0 = torso.CFrame:Inverse() * cape.CFrame
		motor.C1 = CFrame.new()
		weld:Destroy()
	else
		motor.C0 = torso.CFrame:Inverse() * cape.CFrame
		motor.C1 = CFrame.new()
	end

	motor.Parent = cape
	debugLog("ensureCapeMotor", character.Name, "C0 ok")
	return motor
end

function CapeRigEnsure.ensureOnCharacter(character: Model, template: Model): boolean
	if hasSkinnedCape(character) then
		debugLog("already has cape", character.Name)
		return true
	end

	local templateUt = findTemplateUt(template)
	if not templateUt then
		return false
	end

	local suit = ensureSuitFolder(character)
	local existingUt = suit:FindFirstChild("UT")
	if existingUt then
		existingUt:Destroy()
	end

	local clone = templateUt:Clone()
	clone.Name = "UT"
	clone.Parent = suit

	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
		end
		if desc:IsA("WeldConstraint") and upperTorso and upperTorso:IsA("BasePart") then
			local weld = desc :: WeldConstraint
			if weld.Part0 and weld.Part0.Name == "Cape" then
				weld.Part1 = upperTorso
			end
		end
	end

	local ok = hasSkinnedCape(character)
	debugLog("cloned UT onto", character.Name, "ok=", ok)
	return ok
end

return CapeRigEnsure
