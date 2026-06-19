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
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local TreadmillConfigs = require(ReplicatedStorage.Shared.Configs.TreadmillConfigs)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local ThrustConfigs = SpeedConfigs.Thrust
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
assert(
	ThrustConfigs,
	"[iseesupes] SpeedConfigs.Thrust missing — run `rojo serve` and connect the Rojo plugin, then Play again."
)

local LeaderboardConfigs = require(ReplicatedStorage.Shared.Configs.LeaderboardConfigs)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local TutorialFlightAssist = require(ReplicatedStorage.Shared.Utils.TutorialFlightAssist)

-- Bump when you need a fresh ProfileStore namespace (e.g. testing saves from scratch).
local DATA_VERSION = "iseesupes_v99"

local PlayerDataStore = ProfileStore.GetProfileStore(DATA_VERSION, ProfileTemplate.Data)

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		DataReplicated = Knit.CreateSignal(),
		ThrustChanged = Knit.CreateSignal(),
		SolarChanged = Knit.CreateSignal(),
		ThrustDepleted = Knit.CreateSignal(),
	},
})

local profiles: { [Player]: any } = {}
local studioProfileReloading: { [Player]: boolean } = {}
local lastThrustReplicateAt: { [Player]: number } = {}
local lastSolarReplicateAt: { [Player]: number } = {}
local lobbySpawnPart: BasePart? = nil
local orderedStoreCache: { [string]: OrderedDataStore? } = {}
local pendingLeaderboardSave: { [Player]: thread } = {}
local tutorialFlightAssistActive: { [Player]: boolean } = {}
local pendingSaveStartedAt: { [Player]: number } = {}
local lastLeaderboardScores: { [Player]: { [string]: number } } = {}

local DJ_PHASE_ATTR = "DjAbilityPhase"
local SJ_PHASE_ATTR = "SjAbilityPhase"

local doubleJumpService: any = nil
local superJumpService: any = nil

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
		-- Fly intro can be seen early (wall break unlocks at Level 2), so do not
		-- fast-forward players still doing the core tutorial, and let CoreDone
		-- play the thrust shop intro before completing.
		if step < TutorialConfigs.Step.CoreDone then
			return
		end
		if step == TutorialConfigs.Step.CoreDone and data.TutorialThrustShopIntroShown ~= true then
			return
		end
		return
	end
	if step >= TutorialConfigs.Step.Complete then
		if data.TutorialThrustShopIntroShown ~= true then
			data.TutorialStep = TutorialConfigs.Step.GoStage1
		end
		return
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

local funnelService: any = nil

local function hasTutorialInfiniteThrust(player: Player): boolean
	if player:GetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute) == true then
		return true
	end
	local assist = TutorialConfigs.FlightAssist
	if not assist or assist.Enabled == false or assist.InfiniteThrust ~= true then
		return false
	end
	return TutorialFlightAssist.isActiveForPlayer(player)
end

local function syncTutorialFlightAssist(player: Player, data: any)
	local attr = TutorialFlightAssist.getAttributeName()
	local shouldAssist = TutorialFlightAssist.isActiveForData(data)
	local wasActive = tutorialFlightAssistActive[player] == true

	if shouldAssist then
		player:SetAttribute(attr, true)
		if not wasActive and TutorialConfigs.FlightAssist.RefillThrustOnStepEnter == true then
			DataService:RefillThrustToMax(player)
		end
	else
		player:SetAttribute(attr, nil)
	end

	tutorialFlightAssistActive[player] = shouldAssist
end

local function replicateData(player: Player, profile: any)
	ThrustConfigs.EnsureFuelDefaults(profile.Data)
	HeatVisionConfigs.ensureSolarDefaults(profile.Data)
	repairTutorialStep(profile.Data)
	evaluateTutorialStep(profile.Data)
	LeaderstatsSync.Apply(player, profile.Data)
	applyMovementSpeed(player, profile)
	if funnelService then
		funnelService:syncOnboardingFromData(player, profile.Data)
	end
	syncTutorialFlightAssist(player, profile.Data)
	DataService.Client.DataReplicated:Fire(player, profile.Data)
	DataService.Client.SolarChanged:Fire(player, profile.Data.SolarCurrent, profile.Data.SolarMax)
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
	if not StudioLog.isEnabled("ProfileJoin") then
		return
	end
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

local function replicateSolarOnly(player: Player, profile: any)
	local data = profile.Data
	HeatVisionConfigs.ensureSolarDefaults(data)
	DataService.Client.SolarChanged:Fire(player, data.SolarCurrent, data.SolarMax)
end

local function replicateSolar(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	replicateSolarOnly(player, profile)
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

local function isPlayerGrounded(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function hasActiveFlightSession(player: Player): boolean
	if doubleJumpService and doubleJumpService.HasActiveSession and doubleJumpService:HasActiveSession(player) then
		return true
	end
	if superJumpService and superJumpService.HasActiveSession and superJumpService:HasActiveSession(player) then
		return true
	end
	return false
end

local function clearOrphanAbilityPhases(player: Player)
	if hasActiveFlightSession(player) then
		return
	end
	if player:GetAttribute(DJ_PHASE_ATTR) ~= nil then
		player:SetAttribute(DJ_PHASE_ATTR, nil)
	end
	if player:GetAttribute(SJ_PHASE_ATTR) ~= nil then
		player:SetAttribute(SJ_PHASE_ATTR, nil)
	end
end

--- Ground safety: bump thrust to min-start when grounded and depleted.
local function ensureGroundFlyableThrust(player: Player, data: any): boolean
	ThrustConfigs.EnsureFuelDefaults(data)
	local minStart = ThrustConfigs.GetEffectiveMinFuelToStart(data.ThrustMax)
	if data.ThrustCurrent >= minStart then
		return false
	end
	if not isPlayerGrounded(player) then
		return false
	end
	data.ThrustCurrent = minStart
	return true
end

-- Creates the ThrustPower attribute (so it shows in the Properties panel) and
-- keeps max fuel synced when it is edited live.
local function setupThrustPowerAttribute(player: Player)
	local data = profiles[player] and profiles[player].Data
	if not data then
		return
	end

	local attr = ThrustConfigs.PowerAttribute
	ThrustConfigs.EnsureFuelDefaults(data)
	player:SetAttribute(attr, data.ThrustMax)

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
	if hasTutorialInfiniteThrust(player) then
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

--- Kryptonite stages: wipe all thrust instantly (flight dies right after takeoff).
function DataService:DrainThrust(player: Player)
	local data = self:GetData(player)
	if not data then
		return
	end
	ThrustConfigs.EnsureFuelDefaults(data)
	if data.ThrustCurrent <= 0 then
		return
	end
	data.ThrustCurrent = 0
	replicateThrust(player)
end

function DataService:CanStartFlight(player: Player): boolean
	if player:GetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute) == true then
		return true
	end
	if hasTutorialInfiniteThrust(player) then
		return true
	end
	local current, max = self:GetFuel(player)
	return current >= ThrustConfigs.GetEffectiveMinFuelToStart(max)
end

function DataService:GetSolar(player: Player): (number, number)
	local data = self:GetData(player)
	if not data then
		local base = HeatVisionConfigs.SolarEnergy.BaseMax or 60
		return 0, base
	end
	HeatVisionConfigs.ensureSolarDefaults(data)
	return data.SolarCurrent, data.SolarMax
end

function DataService:TryConsumeSolar(player: Player, amount: number): boolean
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

	HeatVisionConfigs.ensureSolarDefaults(data)
	if data.SolarCurrent < amount then
		data.SolarCurrent = 0
		replicateSolar(player)
		return false
	end

	data.SolarCurrent -= amount
	local now = os.clock()
	local last = lastSolarReplicateAt[player] or 0
	if now - last >= ThrustConfigs.ReplicateMinInterval then
		lastSolarReplicateAt[player] = now
		replicateSolar(player)
	end
	return true
end

function DataService:CanStartSolar(player: Player): boolean
	if player:GetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute) == true then
		return true
	end
	local current, max = self:GetSolar(player)
	return current >= HeatVisionConfigs.getEffectiveMinSolarToStart(max)
end

function DataService:RefillSolarToMax(player: Player): boolean
	local data = self:GetData(player)
	if not data then
		return false
	end

	HeatVisionConfigs.refillSolarToMax(data)
	replicateSolar(player)
	return true
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
		if sj and sj.ForceEndForLobby then
			sj:ForceEndForLobby(player)
		elseif sj and sj._endAbility then
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

local function refillEnergyOnRespawn(player: Player)
	for _ = 1, 30 do
		local thrustOk = DataService:RefillThrustToMax(player)
		local solarOk = DataService:RefillSolarToMax(player)
		if thrustOk and solarOk then
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
	HeatVisionConfigs.migrateSolarProfile(profile.Data)
	TrailConfigs.EnsureDefaultTrail(profile.Data)

	local data = profile.Data
	local totalBonus = ThrustUpgradeConfigs.GetTotalBonusFromPurchases(data)
	if totalBonus <= 0 then
		local savedTier = data.ThrustUpgradeTier
		if type(savedTier) == "number" and savedTier > 0 then
			totalBonus = ThrustUpgradeConfigs.GetTotalBonusForTier(savedTier)
		end
	end
	local rebirthBonus = RebirthConfigs.GetThrustBonus(data.Rebirths)
	data.ThrustMax = ThrustConfigs.ClampMax(ThrustConfigs.BaseMaxFuel + totalBonus + rebirthBonus)

	ThrustConfigs.RefillToMax(profile.Data)
	HeatVisionConfigs.refillSolarToMax(profile.Data)
	SpeedConfigs.SyncLevelFromSpeed(profile.Data)
	RewardTiming.ensureAnchor(profile.Data)
	if type(data.StarterPackAnchorTime) ~= "number" then
		if type(data.RewardsAnchorTime) == "number" then
			data.StarterPackAnchorTime = data.RewardsAnchorTime
		else
			data.StarterPackAnchorTime = os.time()
		end
	end
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
	profile.Data.ThrustUpgradePurchases = nil
	profile.Data.ThrustUpgradeTier = 0

	applyProfileMigrations(profile)

	profile.Data.TutorialStep = TutorialConfigs.Step.GoTreadmill
	profile.Data.TutorialThrustHintShown = false
	profile.Data.TutorialThrustShopIntroShown = false
	profile.Data.TutorialFlyIntroShown = false
	profile.Data.TutorialLowThrustFlyHintShown = false

	-- ThrustPower lives on the Player and survives profile wipe; stale values override profile max.
	player:SetAttribute(ThrustConfigs.PowerAttribute, profile.Data.ThrustMax)

	setupThrustPowerAttribute(player)
	ThrustConfigs.RefillToMax(profile.Data)
	HeatVisionConfigs.refillSolarToMax(profile.Data)
	replicateThrust(player)

	pcall(function()
		Knit.GetService("DoubleJumpService"):ForceEndForLobby(player)
	end)
	pcall(function()
		local sj = Knit.GetService("SuperJumpService")
		if sj and sj.ForceEndForLobby then
			sj:ForceEndForLobby(player)
		end
	end)
	ensureGroundFlyableThrust(player, profile.Data)
	replicateThrust(player)

	clearGlobalLeaderboardScores(player)
	lastLeaderboardScores[player] = snapshotLeaderboardScores(profile.Data)
	replicateData(player, profile)
	syncLeaderboards(player)
	-- Push fresh login-reward state so the client popup retries after the reset.
	pcall(function()
		Knit.GetService("LoginRewardService"):PushStateServer(player)
	end)
	StudioLog.print("ProfileJoin", "[iseesupes] Studio profile reset for", player.Name, "→", ProfileTemplate.describeStats(profile.Data))
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
	StudioLog.print("ProfileJoin", "[iseesupes] Profile loaded for", player.Name)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			refillEnergyOnRespawn(player)
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
	lastSolarReplicateAt[player] = nil
	local pendingSave = pendingLeaderboardSave[player]
	if pendingSave then
		task.cancel(pendingSave)
		pendingLeaderboardSave[player] = nil
	end
	pendingSaveStartedAt[player] = nil
	lastLeaderboardScores[player] = nil
	studioProfileReloading[player] = nil
	tutorialFlightAssistActive[player] = nil
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
	if data.TutorialStep >= TutorialConfigs.Step.GoStage1 then
		return false
	end
	if data.TutorialStep < TutorialConfigs.Step.ClaimWins then
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

function DataService:AdvanceTutorialCompleteFromCoreDone(player: Player): boolean
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
	data.TutorialStep = TutorialConfigs.Step.Complete
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
	replicateData(player, profile)
	return true
end

--- Player setting: persist AutoFly on/off so it sticks across sessions. The default (ON)
--- lives in ProfileTemplate; the client seeds its AutoFly attribute from this on join.
function DataService:SetAutoFlyEnabled(player: Player, enabled: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local value = enabled == true
	local data = profile.Data
	if data.AutoFlyEnabled == value then
		return false
	end
	data.AutoFlyEnabled = value
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

function DataService.Client:AdvanceTutorialCompleteFromCoreDone(player: Player)
	DataService:AdvanceTutorialCompleteFromCoreDone(player)
end

function DataService.Client:MarkTutorialFlyIntroShown(player: Player)
	DataService:MarkTutorialFlyIntroShown(player)
end

function DataService.Client:MarkTutorialLowThrustFlyHintShown(player: Player)
	DataService:MarkTutorialLowThrustFlyHintShown(player)
end

function DataService.Client:SetAutoFlyEnabled(player: Player, enabled: boolean)
	DataService:SetAutoFlyEnabled(player, enabled == true)
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

local function tickThrustRefill(dt: number)
	for _, player in Players:GetPlayers() do
		local profile = profiles[player]
		if not profile then
			continue
		end

		clearOrphanAbilityPhases(player)

		local djPhase = player:GetAttribute(DJ_PHASE_ATTR)
		local sjPhase = player:GetAttribute(SJ_PHASE_ATTR)
		if ThrustConfigs.IsInFlightRefillPhase(djPhase, sjPhase) and hasActiveFlightSession(player) then
			continue
		end

		local data = profile.Data
		ThrustConfigs.EnsureFuelDefaults(data)

		if ensureGroundFlyableThrust(player, data) then
			lastThrustReplicateAt[player] = os.clock()
			replicateThrustOnly(player, profile)
			continue
		end

		if data.ThrustCurrent <= 0 then
			data.ThrustCurrent = ThrustConfigs.GetEffectiveMinFuelToStart(data.ThrustMax)
			lastThrustReplicateAt[player] = os.clock()
			replicateThrustOnly(player, profile)
			continue
		end
		if data.ThrustCurrent >= data.ThrustMax then
			continue
		end

		local rate = SpeedConfigs.GetPassiveRefillRate(SpeedConfigs.GetPlayerLevel(player), data.ThrustMax)
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

local function tickSolarRefill(dt: number)
	for _, player in Players:GetPlayers() do
		local djPhase = player:GetAttribute(DJ_PHASE_ATTR)
		local sjPhase = player:GetAttribute(SJ_PHASE_ATTR)
		if not ThrustConfigs.IsInFlightRefillPhase(djPhase, sjPhase) then
			continue
		end

		local profile = profiles[player]
		if not profile then
			continue
		end

		local data = profile.Data
		HeatVisionConfigs.ensureSolarDefaults(data)
		if data.SolarCurrent >= data.SolarMax then
			continue
		end

		local rate = HeatVisionConfigs.getSolarFlightRefillRate()
		local wasBelowMax = data.SolarCurrent < data.SolarMax
		data.SolarCurrent = math.min(data.SolarMax, data.SolarCurrent + rate * dt)

		local now = os.clock()
		local reachedMax = wasBelowMax and data.SolarCurrent >= data.SolarMax
		local last = lastSolarReplicateAt[player] or 0
		if reachedMax or now - last >= ThrustConfigs.ReplicateMinInterval then
			lastSolarReplicateAt[player] = now
			replicateSolarOnly(player, profile)
		end
	end
end

function DataService:KnitStart()
	pcall(function()
		funnelService = Knit.GetService("FunnelAnalyticsService")
	end)
	pcall(function()
		doubleJumpService = Knit.GetService("DoubleJumpService")
	end)
	pcall(function()
		superJumpService = Knit.GetService("SuperJumpService")
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	RunService.Heartbeat:Connect(function(dt)
		tickThrustRefill(dt)
		tickSolarRefill(dt)
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			local list = {}
			for _, profile in profiles do
				table.insert(list, profile)
			end
			if #list == 0 then
				continue
			end
			local index = 1
			local conn: RBXScriptConnection?
			conn = RunService.Heartbeat:Connect(function()
				if not conn then
					return
				end
				if index > #list then
					conn:Disconnect()
					conn = nil
					return
				end
				ProfileTemplate.sanitizeForStore(list[index].Data)
				index += 1
			end)
		end
	end)
end

return DataService
