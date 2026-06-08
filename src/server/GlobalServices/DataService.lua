--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileStore = require(script.Parent.Parent.Modules.ProfileService)
local ProfileTemplate = require(ReplicatedStorage.Shared.Utils.ProfileTemplate)
local RewardTiming = require(ReplicatedStorage.Shared.Utils.RewardTiming)
local LeaderstatsSync = require(script.Parent.Parent.Modules.LeaderstatsSync)
local CharacterMovementSpeed = require(ReplicatedStorage.Shared.Utils.CharacterMovementSpeed)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local CharacterStance = require(ReplicatedStorage.Shared.Utils.CharacterStance)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local TreadmillConfigs = require(ReplicatedStorage.Shared.Configs.TreadmillConfigs)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local ThrustConfigs = SpeedConfigs.Thrust
assert(
	ThrustConfigs,
	"[iseesupes] SpeedConfigs.Thrust missing — run `rojo serve` and connect the Rojo plugin, then Play again."
)

local LeaderboardConfigs = require(ReplicatedStorage.Shared.Configs.LeaderboardConfigs)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)

-- Bump when you need a fresh ProfileStore namespace (e.g. testing saves from scratch).
local DATA_VERSION = "iseesupes_v99"

local PlayerDataStore = ProfileStore.GetProfileStore(DATA_VERSION, ProfileTemplate.Data)

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		DataReplicated = Knit.CreateSignal(),
		ThrustChanged = Knit.CreateSignal(),
		ThrustDepleted = Knit.CreateSignal(),
	},
})

local profiles: { [Player]: any } = {}
local studioProfileReloading: { [Player]: boolean } = {}
local lastThrustReplicateAt: { [Player]: number } = {}
local lobbySpawnPart: BasePart? = nil
local orderedStoreCache: { [string]: OrderedDataStore? } = {}
local pendingLeaderboardSave: { [Player]: thread } = {}
local pendingSaveStartedAt: { [Player]: number } = {}
local lastLeaderboardScores: { [Player]: { [string]: number } } = {}

local LEADERBOARD_SAVE_DEBOUNCE = 20
local LEADERBOARD_SAVE_MAX_WAIT = 45

local function getOrderedStore(storeName: string): OrderedDataStore?
	if orderedStoreCache[storeName] ~= nil then
		return orderedStoreCache[storeName]
	end
	local ok, ods = pcall(function()
		return DataStoreService:GetOrderedDataStore(storeName)
	end)
	if ok and ods then
		orderedStoreCache[storeName] = ods
		return ods
	end
	orderedStoreCache[storeName] = nil
	return nil
end

local function snapshotLeaderboardScores(data: any): { [string]: number }
	local snap: { [string]: number } = {}
	for boardKey, config in LeaderboardConfigs.Boards do
		local score = config.GetScore(data)
		snap[boardKey] = if type(score) == "number" then math.floor(score) else 0
	end
	return snap
end

local function clearGlobalLeaderboardScores(player: Player)
	local userKey = tostring(player.UserId)
	for _, config in LeaderboardConfigs.Boards do
		local ods = getOrderedStore(config.StoreName)
		if ods then
			pcall(function()
				ods:SetAsync(userKey, 0)
			end)
		end
	end
end

local function syncLeaderboards(player: Player, refreshBoardKeys: { string }?)
	task.defer(function()
		local ok, leaderboardService = pcall(function()
			return Knit.GetService("LeaderboardService")
		end)
		if not ok or not leaderboardService then
			return
		end
		leaderboardService:SavePlayer(player, refreshBoardKeys)
		if refreshBoardKeys then
			for _, boardKey in refreshBoardKeys do
				local config = LeaderboardConfigs.Boards[boardKey]
				if config then
					leaderboardService:UpdateDisplay(config)
				end
			end
		else
			leaderboardService:RefreshAllDisplays()
		end
	end)
end

local function pushLeaderboardScores(player: Player, refreshBoardKeys: { string }?)
	local profile = profiles[player]
	if profile then
		lastLeaderboardScores[player] = snapshotLeaderboardScores(profile.Data)
	end

	local ok, leaderboardService = pcall(function()
		return Knit.GetService("LeaderboardService")
	end)
	if not ok or not leaderboardService then
		return
	end

	local saveKeys = refreshBoardKeys or { "Speed" }
	leaderboardService:SavePlayer(player, saveKeys)
end

local function scheduleLeaderboardSave(player: Player, profile: any)
	local snap = snapshotLeaderboardScores(profile.Data)
	local previous = lastLeaderboardScores[player]
	if previous then
		local changed = false
		for boardKey, score in snap do
			if previous[boardKey] ~= score then
				changed = true
				break
			end
		end
		if not changed then
			return
		end
	end

	local pending = pendingLeaderboardSave[player]
	if pending then
		-- Speed changes constantly on the treadmill; do not cancel the timer each time or ODS never updates.
		local started = pendingSaveStartedAt[player] or os.clock()
		if os.clock() - started >= LEADERBOARD_SAVE_MAX_WAIT then
			task.cancel(pending)
			pendingLeaderboardSave[player] = nil
			pendingSaveStartedAt[player] = nil
			pushLeaderboardScores(player, { "Speed" })
		end
		return
	end

	lastLeaderboardScores[player] = snap
	pendingSaveStartedAt[player] = os.clock()
	pendingLeaderboardSave[player] = task.delay(LEADERBOARD_SAVE_DEBOUNCE, function()
		pendingLeaderboardSave[player] = nil
		pendingSaveStartedAt[player] = nil
		pushLeaderboardScores(player, { "Speed" })
	end)
end

local function bindProfileSaveSanitize(profile: any)
	local save = profile.Save
	profile.Save = function(self: any)
		ProfileTemplate.sanitizeForStore(self.Data)
		return save(self)
	end
end

local function applyMovementSpeed(player: Player, profile: any?)
	local resolved = profile or profiles[player]
	local data = if resolved then resolved.Data else nil
	CharacterMovementSpeed.applyToPlayer(player, data)
end

local function hasAnyUnlockedAvatar(data: any): boolean
	local unlocked = data.UnlockedAvatars
	if typeof(unlocked) ~= "table" then
		return false
	end
	for _, owned in unlocked do
		if owned == true then
			return true
		end
	end
	return false
end

--- Step 4 (CoreDone) is set when the player unlocks/equips via UpgradeWins Button1 (after unlock so repairTutorialStep does not revert).
local function repairTutorialStep(data: any)
	if data.TutorialStep ~= TutorialConfigs.Step.CoreDone then
		return
	end
	local wins = if type(data.Wins) == "number" then math.floor(data.Wins) else 0
	if wins < TutorialConfigs.MinWinsForUpgradeStep then
		return
	end
	if hasAnyUnlockedAvatar(data) then
		return
	end
	data.TutorialStep = TutorialConfigs.Step.UpgradeAvatar
end

local function migrateFlyTutorialFlags(data: any)
	if type(data.TutorialFlyIntroShown) ~= "boolean" then
		data.TutorialFlyIntroShown = false
	end
	if type(data.TutorialLowThrustFlyHintShown) ~= "boolean" then
		data.TutorialLowThrustFlyHintShown = false
	end
end

local function migrateFlyTutorialStep(data: any)
	migrateFlyTutorialFlags(data)
	local step = data.TutorialStep
	if data.TutorialFlyIntroShown == true then
		if step < TutorialConfigs.Step.Complete then
			data.TutorialStep = TutorialConfigs.Step.Complete
		end
		return
	end
	if step >= TutorialConfigs.Step.Complete then
		data.TutorialStep = TutorialConfigs.Step.GoStage1
		return
	end
	if step == TutorialConfigs.Step.CoreDone and data.TutorialThrustShopIntroShown == true then
		data.TutorialStep = TutorialConfigs.Step.GoStage1
	end
end

local function migrateTutorialStep(data: any)
	migrateFlyTutorialFlags(data)
	local step = data.TutorialStep
	if
		type(step) == "number"
		and step >= TutorialConfigs.Step.GoTreadmill
		and step <= TutorialConfigs.Step.Complete
	then
		repairTutorialStep(data)
		migrateFlyTutorialStep(data)
		return
	end

	local level = if type(data.Level) == "number" then math.floor(data.Level) else 1
	local wins = if type(data.Wins) == "number" then math.floor(data.Wins) else 0

	if wins >= TutorialConfigs.MinWinsForUpgradeStep then
		data.TutorialStep = TutorialConfigs.Step.UpgradeAvatar
	elseif level >= TutorialConfigs.MinLevelForClaimStep then
		data.TutorialStep = TutorialConfigs.Step.ClaimWins
	else
		data.TutorialStep = TutorialConfigs.Step.GoTreadmill
	end
end

local function evaluateTutorialStep(data: any): boolean
	if type(data.TutorialStep) ~= "number" then
		migrateTutorialStep(data)
	end
	if type(data.TutorialThrustHintShown) ~= "boolean" then
		data.TutorialThrustHintShown = false
	end
	if type(data.TutorialThrustShopIntroShown) ~= "boolean" then
		data.TutorialThrustShopIntroShown = false
	end
	migrateFlyTutorialFlags(data)

	local step = data.TutorialStep
	if step >= TutorialConfigs.Step.CoreDone then
		migrateFlyTutorialStep(data)
		step = data.TutorialStep
	end
	if step >= TutorialConfigs.Step.CoreDone then
		return false
	end

	local changed = false
	local level = if type(data.Level) == "number" then math.floor(data.Level) else 1
	local wins = if type(data.Wins) == "number" then math.floor(data.Wins) else 0

	if level >= TutorialConfigs.MinLevelForClaimStep and step < TutorialConfigs.Step.ClaimWins then
		data.TutorialStep = TutorialConfigs.Step.ClaimWins
		changed = true
		step = data.TutorialStep
	end

	if wins >= TutorialConfigs.MinWinsForUpgradeStep and step < TutorialConfigs.Step.UpgradeAvatar then
		data.TutorialStep = TutorialConfigs.Step.UpgradeAvatar
		changed = true
	end

	return changed
end

local function replicateData(player: Player, profile: any)
	ThrustConfigs.EnsureFuelDefaults(profile.Data)
	repairTutorialStep(profile.Data)
	evaluateTutorialStep(profile.Data)
	LeaderstatsSync.Apply(player, profile.Data)
	applyMovementSpeed(player, profile)
	DataService.Client.DataReplicated:Fire(player, profile.Data)
end

local function countUnlockedAvatars(data: any): number
	local unlocked = data.UnlockedAvatars
	if type(unlocked) ~= "table" then
		return 0
	end
	local n = 0
	for _, owned in unlocked do
		if owned == true then
			n += 1
		end
	end
	return n
end

local function logProfileJoinDiagnostics(player: Player, profile: any, odsRestoreRan: boolean, odsRestoredAny: boolean)
	local data = profile.Data
	print(
		"[iseesupes] Profile join:",
		player.Name,
		"| DATA_VERSION=",
		DATA_VERSION,
		"|",
		ProfileTemplate.describeStats(data),
		"| avatars=",
		countUnlockedAvatars(data),
		"| RestoreFromOdsOnJoin=",
		tostring(LeaderboardConfigs.RestoreFromOdsOnJoin == true),
		"| odsReconcileRan=",
		tostring(odsRestoreRan),
		"| odsRestoredAny=",
		tostring(odsRestoredAny)
	)
end

-- One-time per DATA_VERSION: optionally pull higher global ODS scores into profile after store migrations.
local function reconcileProfileFromLeaderboards(player: Player, profile: any): (boolean, boolean)
	local data = profile.Data
	if data.LeaderboardOdsVersion == DATA_VERSION then
		return false, false
	end

	local restoreFromOds = LeaderboardConfigs.RestoreFromOdsOnJoin == true
	local userKey = tostring(player.UserId)
	local restoredAny = false

	if restoreFromOds then
		for boardKey, config in LeaderboardConfigs.Boards do
			local profileKey = config.ProfileKey
			local current = config.GetScore(data)
			if type(current) ~= "number" then
				if type(data[profileKey]) ~= "number" then
					data[profileKey] = 0
				end
				current = 0
			end

			local ods = getOrderedStore(config.StoreName)
			if not ods then
				continue
			end

			local ok, stored = pcall(function()
				return ods:GetAsync(userKey)
			end)
			if not ok or type(stored) ~= "number" then
				continue
			end

			local storedScore = math.max(0, math.floor(stored))
			if storedScore > current then
				data[profileKey] = storedScore
				restoredAny = true
				print(
					"[iseesupes] Restored",
					storedScore,
					config.ProfileKey,
					"from global leaderboard for",
					player.Name,
					"(",
					boardKey,
					")"
				)
			end
		end
	end

	data.LeaderboardOdsVersion = DATA_VERSION
	if restoredAny then
		SpeedConfigs.SyncLevelFromSpeed(data)
		replicateData(player, profile)
	end
	return true, restoredAny
end

local function replicateThrustOnly(player: Player, profile: any)
	local data = profile.Data
	ThrustConfigs.EnsureFuelDefaults(data)
	DataService.Client.ThrustChanged:Fire(player, data.ThrustCurrent, data.ThrustMax)
end

local function replicateThrust(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	replicateThrustOnly(player, profile)
end

-- Reads the ThrustPower attribute and applies it as the player's max fuel.
local function applyThrustPower(player: Player, refill: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	local power = player:GetAttribute(ThrustConfigs.PowerAttribute)
	if typeof(power) ~= "number" then
		power = nil
	end
	ThrustConfigs.ApplyPower(profile.Data, power, refill)
	replicateThrust(player)
end

-- Creates the ThrustPower attribute (so it shows in the Properties panel) and
-- keeps max fuel synced when it is edited live.
local function setupThrustPowerAttribute(player: Player)
	local data = profiles[player] and profiles[player].Data
	if not data then
		return
	end

	local attr = ThrustConfigs.PowerAttribute
	if typeof(player:GetAttribute(attr)) ~= "number" then
		ThrustConfigs.EnsureFuelDefaults(data)
		player:SetAttribute(attr, data.ThrustMax)
	end

	applyThrustPower(player, true)

	player:GetAttributeChangedSignal(attr):Connect(function()
		applyThrustPower(player, true)
	end)
end

local function resolveLobbySpawn(): BasePart?
	local spawn = MapWorld.resolveLobbySpawn(lobbySpawnPart)
	if spawn then
		lobbySpawnPart = spawn
	end
	return spawn
end

function DataService:GetFuel(player: Player): (number, number)
	local data = self:GetData(player)
	if not data then
		return 0, ThrustConfigs.BaseMaxFuel
	end
	ThrustConfigs.EnsureFuelDefaults(data)
	return data.ThrustCurrent, data.ThrustMax
end

function DataService:AddFuel(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local data = self:GetData(player)
	if not data then
		return false
	end

	ThrustConfigs.EnsureFuelDefaults(data)
	local before = data.ThrustCurrent
	data.ThrustCurrent = math.min(data.ThrustMax, data.ThrustCurrent + amount)
	if data.ThrustCurrent == before then
		return false
	end

	replicateThrust(player)
	return true
end

function DataService:TryConsumeThrust(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	if player:GetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute) == true then
		return true
	end

	local data = self:GetData(player)
	if not data then
		return false
	end

	ThrustConfigs.EnsureFuelDefaults(data)
	if data.ThrustCurrent < amount then
		data.ThrustCurrent = 0
		replicateThrust(player)
		return false
	end

	data.ThrustCurrent -= amount
	local now = os.clock()
	local last = lastThrustReplicateAt[player] or 0
	if now - last >= ThrustConfigs.ReplicateMinInterval then
		lastThrustReplicateAt[player] = now
		replicateThrust(player)
	end
	return true
end

function DataService:CanStartFlight(player: Player): boolean
	if player:GetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute) == true then
		return true
	end
	local current, _max = self:GetFuel(player)
	return current >= ThrustConfigs.MinFuelToStartFlight
end

function DataService:TrySpendWins(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local profile = profiles[player]
	if not profile then
		return false
	end

	local data = profile.Data
	if type(data.Wins) ~= "number" then
		data.Wins = 0
	end
	if data.Wins < amount then
		return false
	end

	data.Wins -= amount
	replicateData(player, profile)
	syncLeaderboards(player, { "Wins" })
	return true
end

function DataService:AddWins(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local profile = profiles[player]
	if not profile then
		return false
	end

	local data = profile.Data
	if type(data.Wins) ~= "number" then
		data.Wins = 0
	end
	data.Wins += amount
	replicateData(player, profile)
	syncLeaderboards(player, { "Wins" })
	return true
end

function DataService:ApplyUpgradedMax(player: Player, newMax: number): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	ThrustConfigs.EnsureFuelDefaults(data)
	data.ThrustMax = newMax
	data.ThrustCurrent = newMax
	player:SetAttribute(ThrustConfigs.PowerAttribute, newMax)
	replicateData(player, profile)
	return true
end

function DataService:RefillThrustToMax(player: Player): boolean
	local data = self:GetData(player)
	if not data then
		return false
	end

	ThrustConfigs.RefillToMax(data)
	replicateThrust(player)
	return true
end

function DataService:OnFlightDrained(player: Player)
	DataService.Client.ThrustDepleted:Fire(player)
end

function DataService:TeleportToLobby(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spawn = resolveLobbySpawn()
	if not root then
		return
	end
	if not spawn then
		warn(
			"[iseesupes] TeleportToLobby: no spawn under Workspace.Map (add Start or SpawnLocation; see WorldMapConfigs.LobbySpawnPartNames)"
		)
		return
	end

	pcall(function()
		local dj = Knit.GetService("DoubleJumpService")
		if dj and dj.ForceEndForLobby then
			dj:ForceEndForLobby(player)
		end
	end)
	pcall(function()
		local sj = Knit.GetService("SuperJumpService")
		if sj and sj._endAbility then
			sj:_endAbility(player)
		end
	end)
	pcall(function()
		local hv = Knit.GetService("HeatVisionService")
		if hv and hv.ForceEndForLobby then
			hv:ForceEndForLobby(player)
		end
	end)

	player:SetAttribute("ForceStandUp", true)
	task.delay(0.15, function()
		if player.Parent then
			player:SetAttribute("ForceStandUp", nil)
		end
	end)

	local spawnCf = spawn.CFrame + TreadmillConfigs.Gameplay.KickTeleportOffset
	local upright = CharacterStance.buildUprightCFrame(root, spawnCf)
	CharacterStance.resetToStanding(character, upright)

	local ok, godSpeed = pcall(function()
		return Knit.GetService("GodSpeedAuraService")
	end)
	if ok and godSpeed and godSpeed.ClearRunBuff then
		godSpeed:ClearRunBuff(player)
	end

	task.delay(0.1, function()
		if not player.Parent then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local uprightRetry = CharacterStance.buildUprightCFrame(hrp, spawnCf)
		CharacterStance.resetToStanding(char, uprightRetry)
	end)

	pcall(function()
		local stageCheckpoint = Knit.GetService("StageCheckpointService")
		if stageCheckpoint and stageCheckpoint.ResetSessionGatesForPlayer then
			stageCheckpoint:ResetSessionGatesForPlayer(player)
		end
	end)
end

local function refillThrustOnRespawn(player: Player)
	for _ = 1, 30 do
		if DataService:RefillThrustToMax(player) then
			return
		end
		if not player.Parent then
			return
		end
		task.wait(0.1)
	end
end

local function bindProfileReleaseListener(player: Player, profile: any)
	profile:ListenToRelease(function()
		profiles[player] = nil
		if studioProfileReloading[player] then
			return
		end
		player:Kick("Session ended. Please rejoin.")
	end)
end

local function repairEquippedAvatarOwnership(data: any)
	local avatarId = data.EquippedAvatar
	if typeof(avatarId) ~= "string" or avatarId == "" then
		return
	end
	if type(data.UnlockedAvatars) ~= "table" then
		data.UnlockedAvatars = {}
	end
	if data.UnlockedAvatars[avatarId] ~= true then
		data.UnlockedAvatars[avatarId] = true
	end
end

local function applyProfileMigrations(profile: any)
	ProfileTemplate.sanitizeForStore(profile.Data)
	ThrustConfigs.MigrateProfile(profile.Data)
	TrailConfigs.EnsureDefaultTrail(profile.Data)

	local data = profile.Data
	local totalBonus = 0
	local purchases = data.ThrustUpgradePurchases
	if type(purchases) == "table" then
		for tier, cfg in ThrustUpgradeConfigs.Tiers do
			local count = purchases[tier] or 0
			if type(count) == "number" and count > 0 then
				totalBonus += (cfg.FuelBonus or 0) * math.floor(count)
			end
		end
	end
	if totalBonus <= 0 then
		local savedTier = data.ThrustUpgradeTier
		if type(savedTier) == "number" and savedTier > 0 then
			totalBonus = ThrustUpgradeConfigs.GetTotalBonusForTier(savedTier)
		end
	end
	if totalBonus > 0 then
		data.ThrustMax = ThrustConfigs.BaseMaxFuel + totalBonus
	end

	ThrustConfigs.RefillToMax(profile.Data)
	SpeedConfigs.SyncLevelFromSpeed(profile.Data)
	RewardTiming.ensureAnchor(profile.Data)
	migrateTutorialStep(profile.Data)
	evaluateTutorialStep(profile.Data)
	if type(profile.Data.TutorialThrustShopIntroShown) ~= "boolean" then
		profile.Data.TutorialThrustShopIntroShown = false
	end
	repairEquippedAvatarOwnership(profile.Data)
	if type(profile.Data.AnalyticsMaxStageLogged) ~= "number" then
		profile.Data.AnalyticsMaxStageLogged = 0
	end
end

local function assignActiveProfile(player: Player, profile: any)
	profiles[player] = profile
	bindProfileSaveSanitize(profile)
	bindProfileReleaseListener(player, profile)
	setupThrustPowerAttribute(player)
	replicateData(player, profile)
	task.defer(function()
		local ok, upgradeWins = pcall(function()
			return Knit.GetService("UpgradeWinsService")
		end)
		if ok and upgradeWins and upgradeWins.ScheduleEquipFromProfile then
			upgradeWins:ScheduleEquipFromProfile(player)
		end
	end)
	task.defer(function()
		local okFunnel, funnelSvc = pcall(function()
			return Knit.GetService("FunnelAnalyticsService")
		end)
		if okFunnel and funnelSvc and funnelSvc.syncStagesFromProfile then
			funnelSvc:syncStagesFromProfile(player)
		end
	end)
	task.spawn(function()
		local odsRan, odsRestored = reconcileProfileFromLeaderboards(player, profile)
		logProfileJoinDiagnostics(player, profile, odsRan, odsRestored)
		lastLeaderboardScores[player] = snapshotLeaderboardScores(profile.Data)
		syncLeaderboards(player)
	end)
end

local function waitForActiveProfileRelease(player: Player, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while profiles[player] ~= nil and os.clock() < deadline do
		task.wait(0.05)
	end
	if profiles[player] ~= nil then
		return false
	end
	-- Let ProfileService finish the release save before wiping the key.
	task.wait(1)
	return true
end

local function finishStudioReset(player: Player, profile: any)
	clearGlobalLeaderboardScores(player)
	lastLeaderboardScores[player] = snapshotLeaderboardScores(profile.Data)
	replicateData(player, profile)
	syncLeaderboards(player)
	print("[iseesupes] Studio profile reset for", player.Name, "→", ProfileTemplate.describeStats(profile.Data))
end

local function onPlayerAdded(player: Player)
	local profile = PlayerDataStore:LoadProfileAsync(tostring(player.UserId), "ForceLoad")
	if not profile then
		player:Kick("Could not load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	applyProfileMigrations(profile)

	if player.Parent ~= Players then
		profile:Release()
		return
	end

	assignActiveProfile(player, profile)
	print("[iseesupes] Profile loaded for", player.Name)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			refillThrustOnRespawn(player)
			applyMovementSpeed(player, profile)
		end)
	end)

	for _, attrName in
		{
			LevelDesignConfigs.Speed.MultiplierAttribute,
			LevelDesignConfigs.Speed.OverrideAttribute,
		}
	do
		player:GetAttributeChangedSignal(attrName):Connect(function()
			applyMovementSpeed(player, profile)
		end)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		ProfileTemplate.sanitizeForStore(profile.Data)
		profile:Release()
		profiles[player] = nil
	end
	lastThrustReplicateAt[player] = nil
	local pendingSave = pendingLeaderboardSave[player]
	if pendingSave then
		task.cancel(pendingSave)
		pendingLeaderboardSave[player] = nil
	end
	pendingSaveStartedAt[player] = nil
	lastLeaderboardScores[player] = nil
	studioProfileReloading[player] = nil
end

function DataService:GetProfile(player: Player): any?
	return profiles[player]
end

function DataService:GetData(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService:AdvanceTutorialFromUpgradeWinsTouch(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if type(data.TutorialStep) ~= "number" then
		migrateTutorialStep(data)
	end
	if data.TutorialStep ~= TutorialConfigs.Step.UpgradeAvatar then
		return false
	end
	data.TutorialStep = TutorialConfigs.Step.CoreDone
	replicateData(player, profile)
	return true
end

function DataService:AdvanceTutorialToGoStage1(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if type(data.TutorialStep) ~= "number" then
		migrateTutorialStep(data)
	end
	if data.TutorialStep ~= TutorialConfigs.Step.CoreDone then
		return false
	end
	data.TutorialStep = TutorialConfigs.Step.GoStage1
	replicateData(player, profile)
	return true
end

function DataService:AdvanceTutorialComplete(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if type(data.TutorialStep) ~= "number" then
		migrateTutorialStep(data)
	end
	if data.TutorialStep ~= TutorialConfigs.Step.GoStage1 then
		return false
	end
	data.TutorialStep = TutorialConfigs.Step.Complete
	data.TutorialFlyIntroShown = true
	replicateData(player, profile)
	return true
end

function DataService:MarkTutorialFlyIntroShown(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if data.TutorialFlyIntroShown == true then
		return false
	end
	data.TutorialFlyIntroShown = true
	if data.TutorialStep == TutorialConfigs.Step.GoStage1 then
		data.TutorialStep = TutorialConfigs.Step.Complete
	end
	replicateData(player, profile)
	return true
end

function DataService:MarkTutorialLowThrustFlyHintShown(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if data.TutorialLowThrustFlyHintShown == true then
		return false
	end
	data.TutorialLowThrustFlyHintShown = true
	replicateData(player, profile)
	return true
end

function DataService:MarkTutorialThrustHintShown(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if data.TutorialThrustHintShown == true then
		return false
	end
	data.TutorialThrustHintShown = true
	replicateData(player, profile)
	return true
end

function DataService:MarkTutorialThrustShopIntroShown(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local data = profile.Data
	if data.TutorialThrustShopIntroShown == true then
		return false
	end
	data.TutorialThrustShopIntroShown = true
	replicateData(player, profile)
	return true
end

function DataService:Replicate(player: Player)
	local profile = profiles[player]
	if profile then
		replicateData(player, profile)
		scheduleLeaderboardSave(player, profile)
	end
end

--- Force-save the player's profile to live DataStore immediately.
--- Use after critical purchases (avatar unlock, aura buy) so the data is durable
--- even if the session ends abruptly (Studio Play Solo stop, crash, etc.).
function DataService:ForceSave(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	ProfileTemplate.sanitizeForStore(profile.Data)
	pcall(function()
		profile:Save()
	end)
end

function DataService:NotifyLeaderboards(player: Player, refreshBoardKeys: { string }?)
	local profile = profiles[player]
	if profile then
		lastLeaderboardScores[player] = snapshotLeaderboardScores(profile.Data)
	end
	syncLeaderboards(player, refreshBoardKeys)
end

function DataService.Client:RequestData(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	ThrustConfigs.EnsureFuelDefaults(profile.Data)
	return profile.Data
end

function DataService.Client:MarkTutorialThrustHintShown(player: Player)
	DataService:MarkTutorialThrustHintShown(player)
end

function DataService.Client:MarkTutorialThrustShopIntroShown(player: Player)
	DataService:MarkTutorialThrustShopIntroShown(player)
end

function DataService.Client:AdvanceTutorialToGoStage1(player: Player)
	DataService:AdvanceTutorialToGoStage1(player)
end

function DataService.Client:AdvanceTutorialComplete(player: Player)
	DataService:AdvanceTutorialComplete(player)
end

function DataService.Client:MarkTutorialFlyIntroShown(player: Player)
	DataService:MarkTutorialFlyIntroShown(player)
end

function DataService.Client:MarkTutorialLowThrustFlyHintShown(player: Player)
	DataService:MarkTutorialLowThrustFlyHintShown(player)
end

--- Studio only: reset profile to defaults, zero global leaderboard entries, replicate HUD, refresh boards.
--- wipeSavedData: also calls ProfileStore:WipeProfileAsync (persistent delete in current DATA_VERSION store).
function DataService:ResetProfileForStudioTest(player: Player, wipeSavedData: boolean?): boolean
	if not RunService:IsStudio() then
		warn("[iseesupes] ResetProfileForStudioTest is Studio-only.")
		return false
	end

	local profile = profiles[player]
	if not profile then
		warn("[iseesupes] ResetProfileForStudioTest: no profile for", player.Name)
		return false
	end

	local userKey = tostring(player.UserId)

	if wipeSavedData == true then
		-- Wipe removes the DataStore key; saving on the old session afterward crashes ProfileService.
		studioProfileReloading[player] = true
		profile:Release()
		if not waitForActiveProfileRelease(player, 12) then
			studioProfileReloading[player] = nil
			warn("[iseesupes] ResetProfileForStudioTest: timed out waiting for profile release for", player.Name)
			return false
		end

		local wiped = PlayerDataStore:WipeProfileAsync(userKey)
		studioProfileReloading[player] = nil
		if not wiped then
			warn("[iseesupes] WipeProfileAsync failed for", player.Name)
		end

		if not player.Parent then
			return false
		end

		local newProfile = PlayerDataStore:LoadProfileAsync(userKey, "ForceLoad")
		if not newProfile then
			warn("[iseesupes] ResetProfileForStudioTest: could not reload profile for", player.Name)
			return false
		end

		newProfile:AddUserId(player.UserId)
		newProfile:Reconcile()
		applyProfileMigrations(newProfile)
		assignActiveProfile(player, newProfile)
		finishStudioReset(player, newProfile)
		return true
	end

	ProfileTemplate.applyTo(profile.Data)
	profile.Data.LeaderboardOdsVersion = DATA_VERSION
	applyProfileMigrations(profile)
	profile:Save()
	finishStudioReset(player, profile)
	return true
end

function DataService.Client:ResetProfileForStudioTest(player: Player, wipeSavedData: boolean?): boolean
	if not RunService:IsStudio() then
		return false
	end
	return DataService:ResetProfileForStudioTest(player, wipeSavedData)
end

--- Studio: Properties edits the client Player; apply ThrustPower on the authoritative server copy.
function DataService.Client:SyncThrustPower(player: Player, power: number)
	if not RunService:IsStudio() then
		return
	end
	if typeof(power) ~= "number" then
		return
	end

	local attr = ThrustConfigs.PowerAttribute
	player:SetAttribute(attr, power)
	applyThrustPower(player, true)
end

local function tickPassiveRefill(dt: number)
	local rate = ThrustConfigs.PassiveRefillRate
	if not rate or rate <= 0 then
		return
	end

	for _, player in Players:GetPlayers() do
		-- Refill on ground during landing; block only in-air thrust phases.
		if ThrustConfigs.BlocksPassiveRefill(player:GetAttribute("DjAbilityPhase")) then
			continue
		end

		local profile = profiles[player]
		if not profile then
			continue
		end

		local data = profile.Data
		ThrustConfigs.EnsureFuelDefaults(data)
		if data.ThrustCurrent >= data.ThrustMax then
			continue
		end

		local wasBelowMax = data.ThrustCurrent < data.ThrustMax
		data.ThrustCurrent = math.min(data.ThrustMax, data.ThrustCurrent + rate * dt)

		local now = os.clock()
		local reachedMax = wasBelowMax and data.ThrustCurrent >= data.ThrustMax
		local last = lastThrustReplicateAt[player] or 0
		if reachedMax or now - last >= ThrustConfigs.ReplicateMinInterval then
			lastThrustReplicateAt[player] = now
			replicateThrustOnly(player, profile)
		end
	end
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	RunService.Heartbeat:Connect(tickPassiveRefill)

	task.spawn(function()
		while true do
			task.wait(15)
			for _, profile in profiles do
				ProfileTemplate.sanitizeForStore(profile.Data)
			end
		end
	end)
end

return DataService
