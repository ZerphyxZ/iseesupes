--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local TreadmillConfigs = require(ReplicatedStorage.Shared.Configs.TreadmillConfigs)

type TreadmillTier = TreadmillConfigs.TreadmillTier

local WorldCfg = TreadmillConfigs.World
local GameplayCfg = TreadmillConfigs.Gameplay

local HIGHLIGHT_NAME = "ActiveHighlight"

local TreadmillService = Knit.CreateService({
	Name = "TreadmillService",
	Client = {
		ActiveTreadmillChanged = Knit.CreateSignal(),
		AccessDenied = Knit.CreateSignal(),
	},
})

local activeTreadmills: { [Player]: Model } = {}
local modelNameToTier: { [string]: TreadmillTier } = {}
local treadmillsFolder: Folder? = nil
local kickSpawnPart: BasePart? = nil

local MonetizationService: any = nil
local DataService: any = nil

local timeAccumulator = 0

-- [ INIT ] -------------------------------------------------------------------

local function buildTierLookups()
	table.clear(modelNameToTier)
	for _, tier in TreadmillConfigs.Tiers do
		modelNameToTier[tier.ModelName] = tier
	end
end

local function resolveWorldInstances()
	local map = Workspace:FindFirstChild(WorldCfg.MapFolderName)
	if not map then
		warn(
			"[iseesupes] TreadmillService: Workspace.",
			WorldCfg.MapFolderName,
			"not found. Place treadmills under Map.Treadmills."
		)
		return
	end

	local folder = map:FindFirstChild(WorldCfg.TreadmillsFolderName)
	if folder and folder:IsA("Folder") then
		treadmillsFolder = folder
	else
		warn(
			"[iseesupes] TreadmillService:",
			WorldCfg.MapFolderName,
			".",
			WorldCfg.TreadmillsFolderName,
			"not found."
		)
	end

	kickSpawnPart = Workspace:FindFirstChild(WorldCfg.KickSpawnPartName) :: BasePart?
	if not kickSpawnPart then
		warn("[iseesupes] TreadmillService: kick spawn part", WorldCfg.KickSpawnPartName, "not found in Workspace.")
	end
end

local function indexStudioTreadmills()
	if not treadmillsFolder then
		return
	end

	for _, child in treadmillsFolder:GetChildren() do
		if child:IsA("Model") then
			local tier = modelNameToTier[child.Name]
			if not tier then
				warn(
					"[iseesupes] TreadmillService: no config for model",
					child.Name,
					"— add a tier in TreadmillConfigs.Tiers."
				)
			end
		end
	end
end

-- [ HELPERS ] ----------------------------------------------------------------

local function getTierForModel(model: Model): TreadmillTier?
	return modelNameToTier[model.Name]
end

local function getTreadmillFromPart(part: BasePart): (Model?, TreadmillTier?)
	if not treadmillsFolder then
		return nil, nil
	end

	local parent: Instance? = part
	while parent and parent ~= Workspace do
		if parent:IsA("Model") and parent.Parent == treadmillsFolder then
			return parent, getTierForModel(parent)
		end
		parent = parent.Parent
	end
	return nil, nil
end

local function getGamepassIdForTier(tier: TreadmillTier): number
	if not tier.GamepassKey then
		return 0
	end
	for _, pass in ProductConfigs.Gamepasses do
		if pass.Key == tier.GamepassKey then
			return pass.Id
		end
	end
	return 0
end

local function playerHasTierAccess(player: Player, tier: TreadmillTier): boolean
	if not tier.GamepassKey then
		return true
	end
	if not MonetizationService then
		return false
	end
	return MonetizationService:PlayerOwnsGamepass(player, tier.GamepassKey) == true
end

local function applyHighlight(model: Model, color: Color3)
	local highlight = model:FindFirstChild(HIGHLIGHT_NAME) :: Highlight?
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = HIGHLIGHT_NAME
		highlight.FillTransparency = 0.8
		highlight.OutlineTransparency = 0.2
		highlight.Parent = model
	end
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Enabled = true
end

local function removeHighlight(model: Model)
	local highlight = model:FindFirstChild(HIGHLIGHT_NAME) :: Highlight?
	if highlight then
		highlight.Enabled = false
	end
end

local function fireActiveTreadmill(player: Player, tier: TreadmillTier?)
	if tier then
		TreadmillService.Client.ActiveTreadmillChanged:Fire(player, tier.Key, tier.Multiplier)
	else
		TreadmillService.Client.ActiveTreadmillChanged:Fire(player, nil, 1)
	end
end

local function kickFromTreadmill(player: Player, tier: TreadmillTier)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not kickSpawnPart then
		return
	end

	root.CFrame = kickSpawnPart.CFrame + GameplayCfg.KickTeleportOffset

	TreadmillService.Client.AccessDenied:Fire(player, tier.Key, tier.DisplayName, tier.GamepassKey)

	local passId = getGamepassIdForTier(tier)
	if passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end
end

local function addSpeedPoints(player: Player)
	if not DataService then
		return
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local data = profile.Data
	local amount = GameplayCfg.PointsPerTick
	if typeof(data.SpeedPoints) ~= "number" then
		data.SpeedPoints = 0
	end
	data.SpeedPoints += amount
	DataService:Replicate(player)
end

-- [ TICK ] -------------------------------------------------------------------

local function clearPlayerTreadmill(player: Player)
	local previous = activeTreadmills[player]
	if previous then
		removeHighlight(previous)
		activeTreadmills[player] = nil
		fireActiveTreadmill(player, nil)
	end
end

local function checkTreadmills(deltaTime: number)
	if not treadmillsFolder then
		return
	end

	timeAccumulator += deltaTime
	local shouldAwardPoints = false
	if timeAccumulator >= GameplayCfg.TickRate then
		shouldAwardPoints = true
		timeAccumulator = 0
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			clearPlayerTreadmill(player)
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not rootPart then
			clearPlayerTreadmill(player)
			continue
		end

		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { character }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local rayResult = Workspace:Raycast(
			rootPart.Position,
			Vector3.new(0, -GameplayCfg.RaycastDistance, 0),
			rayParams
		)
		local floorPart = if rayResult then rayResult.Instance else nil

		local treadmillModel: Model? = nil
		local tier: TreadmillTier? = nil
		if floorPart and floorPart:IsA("BasePart") then
			treadmillModel, tier = getTreadmillFromPart(floorPart)
		end

		local previousModel = activeTreadmills[player]

		if treadmillModel and tier then
			if not playerHasTierAccess(player, tier) then
				kickFromTreadmill(player, tier)
				if previousModel then
					clearPlayerTreadmill(player)
				end
				continue
			end

			if previousModel ~= treadmillModel then
				if previousModel then
					removeHighlight(previousModel)
				end
				activeTreadmills[player] = treadmillModel
				applyHighlight(treadmillModel, tier.HighlightColor)
				fireActiveTreadmill(player, tier)
			end

			if shouldAwardPoints then
				addSpeedPoints(player)
			end
		else
			if previousModel then
				clearPlayerTreadmill(player)
			end
		end
	end
end

-- [ PUBLIC API ] -------------------------------------------------------------

function TreadmillService:GetMultiplier(player: Player): number
	local model = activeTreadmills[player]
	if not model then
		return 1
	end
	local tier = getTierForModel(model)
	return if tier then tier.Multiplier else 1
end

function TreadmillService:GetActiveTierKey(player: Player): string?
	local model = activeTreadmills[player]
	if not model then
		return nil
	end
	local tier = getTierForModel(model)
	return if tier then tier.Key else nil
end

function TreadmillService:IsOnTreadmill(player: Player): boolean
	return activeTreadmills[player] ~= nil
end

function TreadmillService.Client:GetMultiplier(player: Player): number
	return TreadmillService:GetMultiplier(player)
end

function TreadmillService.Client:GetActiveTierKey(player: Player): string?
	return TreadmillService:GetActiveTierKey(player)
end

function TreadmillService:KnitStart()
	MonetizationService = Knit.GetService("MonetizationService")
	DataService = Knit.GetService("DataService")

	buildTierLookups()
	resolveWorldInstances()
	indexStudioTreadmills()

	RunService.Heartbeat:Connect(checkTreadmills)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerTreadmill(player)
	end)

	print("[iseesupes] TreadmillService ready.")
end

return TreadmillService
