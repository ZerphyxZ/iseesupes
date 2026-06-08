--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)
local StageCheckpointConfigs = require(ReplicatedStorage.Shared.Configs.StageCheckpointConfigs)
local StageCheckpointCollision = require(ReplicatedStorage.Shared.Utils.StageCheckpointCollision)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local StageCheckpointDebug = require(ReplicatedStorage.Shared.Utils.StageCheckpointDebug)

local StageCheckpointService = Knit.CreateService({
	Name = "StageCheckpointService",
	Client = {
		CheckpointHpChanged = Knit.CreateSignal(), -- (stageNum: number, hp01: number)
		CheckpointBroken = Knit.CreateSignal(), -- (stageNum: number, hitPos: Vector3, hitNormal: Vector3)
		SpeedRequirementFailed = Knit.CreateSignal(), -- (stageNum: number, requirement: number, playerSpeed: number)
		GateMeltBlocked = Knit.CreateSignal(), -- (stageNum: number, reason: string)
		SessionGatesReset = Knit.CreateSignal(), -- fired when session gates lock again (join / death / lobby spawn)
	},
})

local DataService: any = nil
local SkipStageService: any = nil

local playerHp: { [number]: { [number]: number } } = {}
local brokenGates: { [number]: { [number]: boolean } } = {}
local lastInsufficientSpeedToast: { [number]: number } = {}
local lastGateMeltBlockedToast: { [number]: number } = {}
local lastDamageTick: { [number]: { [number]: number } } = {}

local function getPlayerSpeed(player: Player): number
	local profile = DataService and DataService:GetProfile(player)
	if not profile or type(profile.Data.Speed) ~= "number" then
		return 0
	end
	return profile.Data.Speed
end

local function ensurePlayerState(player: Player)
	local uid = player.UserId
	if not playerHp[uid] then
		playerHp[uid] = {}
	end
	if not brokenGates[uid] then
		brokenGates[uid] = {}
	end
	if not lastDamageTick[uid] then
		lastDamageTick[uid] = {}
	end
end

local function isBrokenForPlayer(player: Player, stageNum: number): boolean
	ensurePlayerState(player)
	return brokenGates[player.UserId][stageNum] == true
end

local function getHp(player: Player, stageNum: number): number
	ensurePlayerState(player)
	local hp = playerHp[player.UserId][stageNum]
	if hp == nil then
		return StageCheckpointConfigs.MaxHp
	end
	return hp
end

local function setHp(player: Player, stageNum: number, hp: number)
	ensurePlayerState(player)
	playerHp[player.UserId][stageNum] = math.clamp(hp, 0, StageCheckpointConfigs.MaxHp)
end

local function markBroken(player: Player, stageNum: number)
	ensurePlayerState(player)
	brokenGates[player.UserId][stageNum] = true
	setHp(player, stageNum, 0)
	StageCheckpointCollision.allowPassThrough(player, stageNum)
end

local function maybeToastGateMeltBlocked(player: Player, stageNum: number, reason: string)
	local uid = player.UserId
	local now = os.clock()
	local last = lastGateMeltBlockedToast[uid] or 0
	if now - last < StageCheckpointConfigs.InsufficientSpeedToastCooldown then
		return
	end
	lastGateMeltBlockedToast[uid] = now
	StageCheckpointService.Client.GateMeltBlocked:Fire(player, stageNum, reason)
end

function StageCheckpointService:MarkGateCleared(player: Player, stageNum: number)
	if not StageCheckpointWorld.getGatePart(stageNum) then
		StageCheckpointDebug.logAlways("MarkGateCleared: no gate part for stage " .. tostring(stageNum))
		return
	end
	StageCheckpointDebug.logAlways(string.format("MarkGateCleared player=%s stage=%d", player.Name, stageNum))
	markBroken(player, stageNum)
	StageCheckpointService.Client.CheckpointHpChanged:Fire(player, stageNum, 0)
end

local function getNextSessionMeltGate(player: Player): number?
	for stageNum = StageCheckpointConfigs.FirstGateStage, StageCheckpointConfigs.MaxGateStage do
		if not isBrokenForPlayer(player, stageNum) then
			return stageNum
		end
	end
	return nil
end

local function getSessionBrokenCount(player: Player): number
	local count = 0
	for stageNum = StageCheckpointConfigs.FirstGateStage, StageCheckpointConfigs.MaxGateStage do
		if isBrokenForPlayer(player, stageNum) then
			count += 1
		end
	end
	return count
end

local function buildGateSyncForPlayer(player: Player)
	local nextGate = getNextSessionMeltGate(player)
	local gates: { [number]: { hp01: number, requirement: number?, cleared: boolean, isNextTarget: boolean } } = {}

	for _, stageNum in StageCheckpointWorld.getAllGateStageNumbers() do
		local broken = isBrokenForPlayer(player, stageNum)
		local isNextTarget = nextGate ~= nil and stageNum == nextGate
		local hp = if broken then 0 else getHp(player, stageNum)
		gates[stageNum] = {
			hp01 = hp / StageCheckpointConfigs.MaxHp,
			requirement = StageCheckpointWorld.getCachedRequirement(stageNum),
			cleared = broken,
			isNextTarget = isNextTarget,
		}
	end

	return getSessionBrokenCount(player), nextGate, gates
end

local function logNextSessionGate(player: Player)
	local nextGate = getNextSessionMeltGate(player)
	if nextGate then
		local req = StageCheckpointWorld.getCachedRequirement(nextGate)
		StageCheckpointDebug.logAlways(string.format(
			"Session melt target player=%s gate=%d req=%s (break with heat vision — not from saved data)",
			player.Name,
			nextGate,
			tostring(req)
		))
	else
		StageCheckpointDebug.logAlways(string.format(
			"Session complete player=%s — all gates 1-%d broken this run",
			player.Name,
			StageCheckpointConfigs.MaxGateStage
		))
	end
end

local function resetSessionGatesForPlayer(player: Player)
	StageCheckpointDebug.logAlways(string.format(
		"ResetSessionGates player=%s — all walls locked FULL bar until laser breaks them (ignores saved Stage)",
		player.Name
	))

	local uid = player.UserId
	brokenGates[uid] = {}
	playerHp[uid] = {}
	lastDamageTick[uid] = {}

	StageCheckpointCollision.resetAllGatesForPlayer(player)

	for _, stageNum in StageCheckpointWorld.getAllGateStageNumbers() do
		local gatePart = StageCheckpointWorld.getGatePart(stageNum)
		local req = StageCheckpointWorld.getCachedRequirement(stageNum)
		if gatePart and req and StageCheckpointWorld.hasGateUi(gatePart) then
			StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
			StageCheckpointWorld.applyGateUi(gatePart, req, 1, "ServerSessionReset")
		end
	end

	logNextSessionGate(player)
end

function StageCheckpointService:ResetSessionGatesForPlayer(player: Player)
	if not player.Parent then
		return
	end
	resetSessionGatesForPlayer(player)
	StageCheckpointService.Client.SessionGatesReset:Fire(player)
end

function StageCheckpointService.Client:GetGateSync(player: Player)
	local sessionBrokenCount, nextMeltGate, gates = buildGateSyncForPlayer(player)
	local gateCount = StageCheckpointDebug.countKeys(gates)
	StageCheckpointDebug.logAlways(string.format(
		"GetGateSync player=%s sessionBroken=%d nextMeltGate=%s gateEntries=%d",
		player.Name,
		sessionBrokenCount,
		tostring(nextMeltGate),
		gateCount
	))
	for stageNum, state in gates do
		StageCheckpointDebug.log(string.format(
			"GetGateSync gate stage=%d broken=%s next=%s hp01=%.2f req=%s",
			stageNum,
			tostring(state.cleared),
			tostring(state.isNextTarget),
			state.hp01,
			tostring(state.requirement)
		), "GetGateSync:" .. tostring(stageNum), 8)
	end
	return {
		sessionBrokenCount = sessionBrokenCount,
		nextMeltGate = nextMeltGate,
		gates = gates,
	}
end

local function computeDamagePerSecond(playerSpeed: number, requirement: number): number
	if playerSpeed < requirement or requirement <= 0 then
		return 0
	end
	local speedRatio = playerSpeed / requirement
	return StageCheckpointConfigs.BaseDamagePerSecond * speedRatio
end

local function maybeToastInsufficientSpeed(player: Player, stageNum: number, requirement: number, playerSpeed: number)
	local uid = player.UserId
	local now = os.clock()
	local last = lastInsufficientSpeedToast[uid] or 0
	if now - last < StageCheckpointConfigs.InsufficientSpeedToastCooldown then
		return
	end
	lastInsufficientSpeedToast[uid] = now
	StageCheckpointService.Client.SpeedRequirementFailed:Fire(player, stageNum, requirement, playerSpeed)
end

function StageCheckpointService:breakGate(player: Player, stageNum: number, rayResult: RaycastResult)
	if isBrokenForPlayer(player, stageNum) then
		StageCheckpointDebug.log("breakGate skipped (already broken)", player.Name .. ":break", 2)
		return
	end

	StageCheckpointDebug.logAlways(string.format(
		"BREAK gate player=%s stage=%d hit=%s",
		player.Name,
		stageNum,
		tostring(rayResult.Instance:GetFullName())
	))
	markBroken(player, stageNum)

	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	local req = StageCheckpointWorld.getCachedRequirement(stageNum)
	if gatePart and req and StageCheckpointWorld.hasGateUi(gatePart) then
		StageCheckpointWorld.applyGateUi(gatePart, req, 0, "ServerBreakGate")
	end

	if SkipStageService and SkipStageService.AdvanceStageForPlayer then
		SkipStageService:AdvanceStageForPlayer(player, stageNum)
	end

	StageCheckpointService.Client.CheckpointHpChanged:Fire(player, stageNum, 0)
	StageCheckpointService.Client.CheckpointBroken:Fire(
		player,
		stageNum,
		rayResult.Position,
		rayResult.Normal
	)
end

function StageCheckpointService:tryDamageFromHit(player: Player, rayResult: RaycastResult?)
	if not HeatVisionConfigs.CheckpointDamageEnabled then
		StageCheckpointDebug.log("tryDamage: CheckpointDamageEnabled=false", player.Name .. ":disabled", 3)
		return
	end
	if not rayResult then
		return
	end

	local stageNum, gatePart = StageCheckpointWorld.getCheckpointFromHit(rayResult.Instance)
	if not stageNum then
		return
	end
	if not StageCheckpointWorld.isMeltGateStage(stageNum) then
		return
	end

	StageCheckpointDebug.log(string.format(
		"tryDamage START stage=%d player=%s speed=%d sessionBroken=%d nextGate=%s broken=%s",
		stageNum,
		player.Name,
		math.floor(getPlayerSpeed(player)),
		getSessionBrokenCount(player),
		tostring(getNextSessionMeltGate(player)),
		tostring(isBrokenForPlayer(player, stageNum))
	), player.Name .. ":tryStart:" .. tostring(stageNum), 0.25)

	StageCheckpointDebug.log(string.format(
		"Ray hit checkpoint stage=%d part=%s material=%s",
		stageNum,
		rayResult.Instance:GetFullName(),
		tostring(rayResult.Material)
	), player.Name .. ":hit", 0.5)

	if isBrokenForPlayer(player, stageNum) then
		StageCheckpointDebug.log(string.format("tryDamage stage=%d blocked: already broken this run", stageNum), player.Name .. ":broken", 2)
		maybeToastGateMeltBlocked(player, stageNum, "broken")
		return
	end

	local nextGate = getNextSessionMeltGate(player)
	if nextGate == nil or stageNum ~= nextGate then
		StageCheckpointDebug.logAlways(string.format(
			"tryDamage stage=%d blocked: melt gate %s first (session order from start)",
			stageNum,
			tostring(nextGate)
		))
		maybeToastGateMeltBlocked(player, stageNum, "wrong_gate")
		return
	end

	local requirement = StageCheckpointWorld.getCachedRequirement(stageNum)
	if not requirement or requirement <= 0 then
		StageCheckpointDebug.logAlways(string.format(
			"tryDamage stage=%d FAIL: no cached requirement (label=%s attr=%s)",
			stageNum,
			tostring(if gatePart then StageCheckpointWorld.readRequirement(gatePart) else nil),
			tostring(if gatePart then gatePart:GetAttribute(StageCheckpointConfigs.RequirementAttribute) else nil)
		))
		return
	end

	local playerSpeed = getPlayerSpeed(player)
	if playerSpeed < requirement then
		StageCheckpointDebug.log(string.format(
			"tryDamage stage=%d blocked: speed=%d < req=%d",
			stageNum,
			math.floor(playerSpeed),
			requirement
		), player.Name .. ":speed", 1.5)
		maybeToastInsufficientSpeed(player, stageNum, requirement, playerSpeed)
		return
	end

	local uid = player.UserId
	ensurePlayerState(player)
	local now = os.clock()
	local lastTick = lastDamageTick[uid][stageNum] or 0
	if now - lastTick < StageCheckpointConfigs.DamageTickInterval then
		return
	end
	local elapsed = if lastTick > 0 then math.min(now - lastTick, 0.25) else StageCheckpointConfigs.DamageTickInterval
	lastDamageTick[uid][stageNum] = now

	local damageRate = computeDamagePerSecond(playerSpeed, requirement)
	local hp = getHp(player, stageNum) - damageRate * elapsed
	if hp <= 0 then
		self:breakGate(player, stageNum, rayResult)
		return
	end

	setHp(player, stageNum, hp)
	local hp01 = hp / StageCheckpointConfigs.MaxHp
	StageCheckpointDebug.log(string.format(
		"Damage stage=%d hp=%.1f/%.0f (%.0f%%) speed=%d req=%d dps=%.1f",
		stageNum,
		hp,
		StageCheckpointConfigs.MaxHp,
		hp01 * 100,
		math.floor(playerSpeed),
		requirement,
		damageRate
	), player.Name .. ":dmg", 0.4)
	StageCheckpointService.Client.CheckpointHpChanged:Fire(player, stageNum, hp01)
end

function StageCheckpointService:KnitStart()
	DataService = Knit.GetService("DataService")
	SkipStageService = Knit.GetService("SkipStageService")

	local gates = StageCheckpointWorld.prepareGateParts()
	StageCheckpointDebug.logAlways(string.format("KnitStart prepared %d melt gate(s) (stages %d-%d)", #StageCheckpointWorld.getAllStageNumbers(), StageCheckpointConfigs.FirstGateStage, StageCheckpointConfigs.MaxGateStage))
	for stageNum in gates do
		StageCheckpointCollision.registerGateGroup(stageNum)
	end
	StageCheckpointCollision.init()

	for _, player in Players:GetPlayers() do
		task.defer(function()
			if DataService:GetProfile(player) then
				self:ResetSessionGatesForPlayer(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local deadline = os.clock() + 15
			while os.clock() < deadline do
				if DataService:GetProfile(player) then
					self:ResetSessionGatesForPlayer(player)
					return
				end
				task.wait(0.25)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		playerHp[uid] = nil
		brokenGates[uid] = nil
		lastDamageTick[uid] = nil
		lastInsufficientSpeedToast[uid] = nil
	end)

	print("[StageCheckpointService] ready.")
end

return StageCheckpointService
