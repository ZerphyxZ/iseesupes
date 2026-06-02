--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local CharacterMovementSpeed = require(ReplicatedStorage.Shared.Utils.CharacterMovementSpeed)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)

local ZONE_ATTR = LevelDesignConfigs.ZoneMarkerAttribute
local LEGACY_ZONE_ATTR = LevelDesignConfigs.LegacyZoneMarkerAttribute
local ZONE_TAGS = { LevelDesignConfigs.ZoneCollectionTag, LevelDesignConfigs.LegacyZoneCollectionTag }

local DataService: any = nil

local LevelDesignService = Knit.CreateService({
	Name = "LevelDesignService",
	Client = {},
})

local touchedDebounce: { [Player]: { [Instance]: number } } = {}
local DEBOUNCE_SEC = 0.35

local function shouldApplyZone(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end
	if part:GetAttribute(ZONE_ATTR) == true or part:GetAttribute(LEGACY_ZONE_ATTR) == true then
		return true
	end
	for _, tag in ZONE_TAGS do
		if CollectionService:HasTag(part, tag) then
			return true
		end
	end
	return false
end

local function onZoneTouched(part: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	local perPlayer = touchedDebounce[player]
	if not perPlayer then
		perPlayer = {}
		touchedDebounce[player] = perPlayer
	end
	local last = perPlayer[part]
	if last and now - last < DEBOUNCE_SEC then
		return
	end
	perPlayer[part] = now

	LevelDesignTuning.copyDesignAttributes(part, player)
	if DataService then
		CharacterMovementSpeed.applyToPlayer(player, DataService:GetData(player))
	end
	if RunService:IsStudio() then
		print("[iseesupes] Zone tuning applied:", LevelDesignTuning.formatActiveTuning(player))
	end
end

local function bindZone(part: BasePart)
	if part:GetAttribute("_LevelDesignBound") then
		return
	end
	part:SetAttribute("_LevelDesignBound", true)
	part.Touched:Connect(function(hit)
		onZoneTouched(part, hit)
	end)
end

local function scanForZones(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") and shouldApplyZone(desc) then
			bindZone(desc)
		end
	end
end

--- Studio: Properties panel edits the client Player; gameplay reads the server Player.
function LevelDesignService.Client:SyncAttribute(player: Player, attributeName: string, value: number)
	if not RunService:IsStudio() then
		return
	end
	if LevelDesignTuning.setTuningAttribute(player, attributeName, value) then
		if DataService then
			CharacterMovementSpeed.applyToPlayer(player, DataService:GetData(player))
		end
		print("[iseesupes] Tuning synced →", attributeName, "=", value, "|", LevelDesignTuning.formatActiveTuning(player))
	end
end

function LevelDesignService:KnitStart()
	DataService = Knit.GetService("DataService")

	local function onPlayer(player: Player)
		LevelDesignTuning.applyDefaults(player)
		LevelDesignTuning.printStudioGuide(player)

		player.CharacterAdded:Connect(function()
			LevelDesignTuning.syncAttributesToCharacter(player)
		end)
		if player.Character then
			LevelDesignTuning.syncAttributesToCharacter(player)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		touchedDebounce[player] = nil
	end)

	scanForZones(Workspace)
	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and shouldApplyZone(desc) then
			bindZone(desc)
		end
	end)

	for _, tag in ZONE_TAGS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("BasePart") then
				bindZone(inst)
			end
		end)

		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") then
				bindZone(inst)
			end
		end
	end

	print("[iseesupes] LevelDesignService ready — Studio edits sync to server automatically.")
end

return LevelDesignService
