--!strict

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local TreadmillConfigs = require(ReplicatedStorage.Shared.Configs.TreadmillConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local CharacterStance = require(ReplicatedStorage.Shared.Utils.CharacterStance)

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
--- One purchase prompt per locked-treadmill contact; cleared when the player steps off.
local lockedTreadmillSessions: { [Player]: { tierKey: string, model: Model, prompted: boolean } } = {}
local modelNameToTier: { [string]: TreadmillTier } = {}
local treadmillsFolder: Folder? = nil
local kickSpawnPart: BasePart? = nil

local DataService: any = nil
local DoubleJumpService: any = nil
local SuperJumpService: any = nil

local KillPartConfigs = {
	Tag = "KillPart",
	RagdollDuration = 1.25,
	TouchDebounce = 1.5,
}
pcall(function()
	KillPartConfigs = require(ReplicatedStorage.Shared.Configs.KillPartConfigs)
end)

local killCooldownUntil: { [Player]: number } = {}
local killTouchConns: { [Instance]: RBXScriptConnection } = {}

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

	kickSpawnPart = MapWorld.resolveLobbySpawn(kickSpawnPart)
	if not kickSpawnPart then
		warn(
			"[iseesupes] TreadmillService: lobby spawn not found under Workspace.Map (Start or SpawnLocation)."
		)
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

local function getProductIdForTier(tier: TreadmillTier): number
	local product = ProductConfigs.GetTreadmillProductForTier(tier.Key)
	if product then
		return product.Id
	end
	return 0
end

local function playerHasTierAccess(player: Player, tier: TreadmillTier): boolean
	if not ProductConfigs.GetTreadmillProductForTier(tier.Key) then
		return true
	end
	if not DataService then
		return false
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end
	local owned = profile.Data.OwnedTreadmills
	return typeof(owned) == "table" and owned[tier.Key] == true
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

local function clearLockedTreadmillSession(player: Player)
	lockedTreadmillSessions[player] = nil
end

--- Prompts at most once per stand-on; no spawn teleport (player stays on the belt).
local function tryPromptLockedTreadmill(player: Player, treadmillModel: Model, tier: TreadmillTier)
	local session = lockedTreadmillSessions[player]
	if session and session.model == treadmillModel and session.tierKey == tier.Key and session.prompted then
		return
	end

	lockedTreadmillSessions[player] = {
		tierKey = tier.Key,
		model = treadmillModel,
		prompted = true,
	}

	TreadmillService.Client.AccessDenied:Fire(player, tier.Key, tier.DisplayName)

	local productId = getProductIdForTier(tier)
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	end
end

local function awardTreadmillTick(player: Player, tier: TreadmillTier)
	if not DataService then
		return
	end

	local mult = tier.Multiplier
	local speedXp = GameplayCfg.SpeedXpPerTick or 0
	if speedXp > 0 and DataService then
		local profile = DataService:GetProfile(player)
		if profile then
			local data = profile.Data
			if type(data.Speed) ~= "number" then
				data.Speed = 0
			end
			data.Speed += speedXp * mult
			local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
			SpeedConfigs.SyncLevelFromSpeed(data)
			DataService:Replicate(player)
		end
	end
end

-- [ TICK ] -------------------------------------------------------------------

local function clearPlayerTreadmill(player: Player)
	local previous = activeTreadmills[player]
	if previous then
		removeHighlight(previous)
		activeTreadmills[player] = nil
		fireActiveTreadmill(player, nil)
	end
	clearLockedTreadmillSession(player)
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
				if previousModel and previousModel ~= treadmillModel then
					removeHighlight(previousModel)
					activeTreadmills[player] = nil
					fireActiveTreadmill(player, nil)
				end
				tryPromptLockedTreadmill(player, treadmillModel, tier)
				continue
			end

			clearLockedTreadmillSession(player)

			if previousModel ~= treadmillModel then
				if previousModel then
					removeHighlight(previousModel)
				end
				activeTreadmills[player] = treadmillModel
				applyHighlight(treadmillModel, tier.HighlightColor)
				fireActiveTreadmill(player, tier)
			end

			if shouldAwardPoints and tier then
				awardTreadmillTick(player, tier)
			end
		else
			clearLockedTreadmillSession(player)
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

-- [ KILL PARTS ] ---------------------------------------------------------------

local function getKillSpawnCFrame(): CFrame?
	local offset = GameplayCfg.KickTeleportOffset
	local spawn = MapWorld.resolveLobbySpawn(kickSpawnPart)
	if spawn then
		kickSpawnPart = spawn
		return spawn.CFrame + offset
	end
	return nil
end

local function getCharacterFromKillHit(hit: BasePart): Model?
	local parent = hit.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
		return parent
	end
	return hit:FindFirstAncestorOfClass("Model")
end

local function applyKillRagdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
	end)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	for _, desc in character:GetDescendants() do
		if desc:IsA("Motor6D") then
			desc.Enabled = false
		end
	end
end

function TreadmillService:RespawnFromKillPart(player: Player)
	if not player.Parent then
		return
	end

	-- End any active flight/jump session BEFORE LoadCharacter so the session is
	-- properly cleaned up (PHASE_ATTR cleared, AbilityEnded fired). Without this,
	-- the kill ragdoll never triggers Humanoid.Died (Health > 0) and the stale
	-- DJ session leaks into the new respawned character → prone/crying pose.
	if DoubleJumpService and DoubleJumpService._endAbility then
		pcall(function() DoubleJumpService:_endAbility(player) end)
	end
	if SuperJumpService and SuperJumpService._endAbility then
		pcall(function() SuperJumpService:_endAbility(player) end)
	end
	player:SetAttribute("ForceStandUp", true)
	task.delay(0.2, function()
		if player.Parent then
			player:SetAttribute("ForceStandUp", nil)
		end
	end)

	player:LoadCharacter()

	local character = player.Character
	if not character then
		character = player.CharacterAdded:Wait()
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spawnCf = getKillSpawnCFrame()
	if spawnCf then
		local upright = CharacterStance.buildUprightCFrame(root, spawnCf)
		CharacterStance.resetToStanding(character, upright)
	end

	if DataService then
		DataService:RefillThrustToMax(player)
	end
end

local function onKillPartPlayerKilled(player: Player, character: Model)
	local now = os.clock()
	if (killCooldownUntil[player] or 0) > now then
		return
	end
	killCooldownUntil[player] = now + KillPartConfigs.TouchDebounce

	applyKillRagdoll(character)

	task.delay(KillPartConfigs.RagdollDuration, function()
		if not player.Parent then
			return
		end
		TreadmillService:RespawnFromKillPart(player)
	end)
end

local function onKillPartTouched(killPart: BasePart, hit: BasePart)
	if not hit or not hit.Parent then
		return
	end
	if hit:IsDescendantOf(killPart) then
		return
	end

	local character = getCharacterFromKillHit(hit)
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	onKillPartPlayerKilled(player, character)
end

local function bindKillPartPart(part: BasePart)
	if killTouchConns[part] then
		return
	end

	part.CanTouch = true
	killTouchConns[part] = part.Touched:Connect(function(hit)
		onKillPartTouched(part, hit)
	end)
end

local function bindKillPart(instance: Instance)
	if instance:IsA("BasePart") then
		bindKillPartPart(instance)
		return
	end

	if instance:IsA("Model") then
		local found = false
		for _, desc in instance:GetDescendants() do
			if desc:IsA("BasePart") then
				found = true
				bindKillPartPart(desc)
			end
		end
		if not found then
			warn("[iseesupes] KillPart: tagged model has no BasePart:", instance:GetFullName())
		end
		return
	end

	warn("[iseesupes] KillPart: unsupported tagged type:", instance:GetFullName())
end

local function unbindKillPart(instance: Instance)
	if instance:IsA("BasePart") then
		local conn = killTouchConns[instance]
		if conn then
			conn:Disconnect()
			killTouchConns[instance] = nil
		end
		return
	end

	for _, desc in instance:GetDescendants() do
		if desc:IsA("BasePart") then
			local conn = killTouchConns[desc]
			if conn then
				conn:Disconnect()
				killTouchConns[desc] = nil
			end
		end
	end
end

local function initKillParts()
	local tag = KillPartConfigs.Tag
	for _, instance in CollectionService:GetTagged(tag) do
		bindKillPart(instance)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bindKillPart)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbindKillPart)
end

function TreadmillService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function() DoubleJumpService = Knit.GetService("DoubleJumpService") end)
	pcall(function() SuperJumpService = Knit.GetService("SuperJumpService") end)

	buildTierLookups()
	resolveWorldInstances()
	indexStudioTreadmills()
	initKillParts()

	RunService.Heartbeat:Connect(checkTreadmills)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerTreadmill(player)
		clearLockedTreadmillSession(player)
		killCooldownUntil[player] = nil
	end)

	print("[iseesupes] TreadmillService ready. KillPart tag:", KillPartConfigs.Tag)
end

return TreadmillService
