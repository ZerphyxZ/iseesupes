--!strict

-- Client hazard touches (long jump / flight use client-owned physics; server Touched may not fire).
-- Reports hit to server; mirrors knockback + death when server confirms.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterStance = require(ReplicatedStorage.Shared.Utils.CharacterStance)
local KillPartConfigs = require(ReplicatedStorage.Shared.Configs.KillPartConfigs)

local KillPartController = Knit.CreateController({ Name = "KillPartController" })

local player = Players.LocalPlayer
local hazardTags: { string } = {}
local touchConn: RBXScriptConnection? = nil
local reportCooldownUntil = 0

local function buildHazardTags()
	table.clear(hazardTags)
	table.insert(hazardTags, KillPartConfigs.Tag or "KillPart")
	local obstacleTag = KillPartConfigs.ObstacleTag
	if type(obstacleTag) == "string" and obstacleTag ~= "" then
		local duplicate = false
		for _, existing in hazardTags do
			if existing == obstacleTag then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(hazardTags, obstacleTag)
		end
	end
end

local function isHazardInstance(instance: Instance): boolean
	for _, tag in hazardTags do
		if CollectionService:HasTag(instance, tag) then
			return true
		end
	end
	local model = instance:FindFirstAncestorOfClass("Model")
	if model then
		for _, tag in hazardTags do
			if CollectionService:HasTag(model, tag) then
				return true
			end
		end
	end
	return false
end

local function getObstacleHitOptions(): CharacterStance.ObstacleHitOptions
	return {
		knockbackHorizontal = KillPartConfigs.KnockbackHorizontal or 80,
		knockbackVertical = KillPartConfigs.KnockbackVertical or 30,
	}
end

local function mirrorHazardHit(hazardPart: BasePart?)
	local character = player.Character
	if not character or not hazardPart or not hazardPart:IsA("BasePart") then
		return
	end
	if not isHazardInstance(hazardPart) then
		return
	end
	CharacterStance.applyObstacleStyleHit(character, hazardPart, getObstacleHitOptions())
end

local function onCharacterTouched(hit: BasePart)
	if not hit or not hit.Parent then
		return
	end
	if not isHazardInstance(hit) then
		return
	end

	local now = os.clock()
	if now < reportCooldownUntil then
		return
	end
	reportCooldownUntil = now + (KillPartConfigs.TouchDebounce or 1.5)

	local TreadmillService = Knit.GetService("TreadmillService")
	pcall(function()
		TreadmillService:ReportKillPartHit(hit)
	end)
end

local function setupCharacter(character: Model)
	if touchConn then
		touchConn:Disconnect()
		touchConn = nil
	end
	reportCooldownUntil = 0

	local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	touchConn = hrp.Touched:Connect(onCharacterTouched)
end

function KillPartController:KnitStart()
	buildHazardTags()

	local TreadmillService = Knit.GetService("TreadmillService")

	TreadmillService.HazardHit:Connect(function(hazardPart: BasePart?)
		mirrorHazardHit(hazardPart)
	end)

	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end

	StudioLog.ready("KillPartController")
end

return KillPartController
