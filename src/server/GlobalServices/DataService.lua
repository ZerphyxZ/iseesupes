--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileStore = require(script.Parent.Parent.Modules.ProfileService)
local ProfileTemplate = require(ReplicatedStorage.Shared.Utils.ProfileTemplate)
local RewardTiming = require(ReplicatedStorage.Shared.Utils.RewardTiming)
local LeaderstatsSync = require(script.Parent.Parent.Modules.LeaderstatsSync)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local TreadmillConfigs = require(ReplicatedStorage.Shared.Configs.TreadmillConfigs)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local ThrustConfigs = SpeedConfigs.Thrust
assert(ThrustConfigs, "[iseesupes] SpeedConfigs.Thrust missing — run `rojo serve` and connect the Rojo plugin, then Play again.")

local DATA_VERSION = "iseesupes_v4"

local PlayerDataStore = ProfileStore.GetProfileStore(DATA_VERSION, ProfileTemplate)

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		DataReplicated = Knit.CreateSignal(),
		ThrustChanged = Knit.CreateSignal(),
		ThrustDepleted = Knit.CreateSignal(),
	},
})

local profiles: { [Player]: any } = {}
local lastThrustReplicateAt: { [Player]: number } = {}
local lobbySpawnPart: BasePart? = nil

local function replicateData(player: Player, profile: any)
	ThrustConfigs.EnsureFuelDefaults(profile.Data)
	LeaderstatsSync.Apply(player, profile.Data)
	DataService.Client.DataReplicated:Fire(player, profile.Data)
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
	if lobbySpawnPart and lobbySpawnPart.Parent then
		return lobbySpawnPart
	end

	local worldCfg = TreadmillConfigs.World
	local map = Workspace:FindFirstChild(worldCfg.MapFolderName)
	if map then
		local spawn = map:FindFirstChild(worldCfg.KickSpawnPartName)
		if spawn and spawn:IsA("BasePart") then
			lobbySpawnPart = spawn
			return spawn
		end
	end

	local rootStart = Workspace:FindFirstChild(worldCfg.KickSpawnPartName)
	if rootStart and rootStart:IsA("BasePart") then
		lobbySpawnPart = rootStart
		return rootStart
	end

	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			lobbySpawnPart = child
			return child
		end
	end

	return nil
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
	return true
end

function DataService:ApplyUpgradedMax(player: Player, newMax: number): boolean
	local data = self:GetData(player)
	if not data then
		return false
	end
	ThrustConfigs.EnsureFuelDefaults(data)
	data.ThrustMax = newMax
	data.ThrustCurrent = math.min(data.ThrustCurrent, data.ThrustMax)
	replicateThrust(player)
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
	if not root or not spawn then
		return
	end

	root.CFrame = spawn.CFrame + TreadmillConfigs.Gameplay.KickTeleportOffset
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
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

local function onPlayerAdded(player: Player)
	local profile = PlayerDataStore:LoadProfileAsync(tostring(player.UserId), "ForceLoad")
	if not profile then
		player:Kick("Could not load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	ThrustConfigs.MigrateProfile(profile.Data)
	TrailConfigs.EnsureDefaultTrail(profile.Data)

	-- Re-apply any purchased Thrust upgrade tier so ThrustMax is correct after relog.
	local savedTier = profile.Data.ThrustUpgradeTier
	if type(savedTier) == "number" and savedTier > 0 then
		local bonus = ThrustUpgradeConfigs.GetTotalBonusForTier(savedTier)
		profile.Data.ThrustMax = ThrustConfigs.BaseMaxFuel + bonus
	end

	ThrustConfigs.RefillToMax(profile.Data)
	SpeedConfigs.SyncLevelFromSpeed(profile.Data)
	RewardTiming.ensureAnchor(profile.Data)

	profile:ListenToRelease(function()
		profiles[player] = nil
		player:Kick("Session ended. Please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:Release()
		return
	end

	profiles[player] = profile
	setupThrustPowerAttribute(player)
	replicateData(player, profile)
	print("[iseesupes] Profile loaded for", player.Name)

	player.CharacterAdded:Connect(function()
		task.defer(refillThrustOnRespawn, player)
	end)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Release()
		profiles[player] = nil
	end
	lastThrustReplicateAt[player] = nil
end

function DataService:GetProfile(player: Player): any?
	return profiles[player]
end

function DataService:GetData(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService:Replicate(player: Player)
	local profile = profiles[player]
	if profile then
		replicateData(player, profile)
	end
end

function DataService.Client:RequestData(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	ThrustConfigs.EnsureFuelDefaults(profile.Data)
	return profile.Data
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
		-- Don't refill while Superman flight (E key) is active
		if player:GetAttribute("DjAbilityPhase") ~= nil then
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

		data.ThrustCurrent = math.min(data.ThrustMax, data.ThrustCurrent + rate * dt)

		local now = os.clock()
		local last = lastThrustReplicateAt[player] or 0
		if now - last >= ThrustConfigs.ReplicateMinInterval then
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
end

return DataService
