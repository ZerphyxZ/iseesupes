--!strict

-- Logs stage progression to Roblox Analytics (Creator Dashboard → Funnels → StageProgress).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FunnelAnalyticsConfigs = require(ReplicatedStorage.Shared.Configs.FunnelAnalyticsConfigs)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)

local FunnelAnalyticsService = Knit.CreateService({
	Name = "FunnelAnalyticsService",
	Client = {},
})

local DataService: any = nil
local lastProximityHintAt: { [number]: number } = {}
local lastPollSkipAt: { [number]: number } = {}
local lastStageSkipAt: { [number]: number } = {}
local joinSnapshotLogged: { [number]: boolean } = {}
local joinStatusLogged: { [number]: boolean } = {}
local startupDiagnosticsDone = false
local pollStartedAtStart = false
local gatePartCache: { [number]: BasePart? } = {}
local gatePartCacheReady = false

local function getCachedGatePart(stageNum: number): BasePart?
	if not gatePartCacheReady then
		local maxStage = FunnelAnalyticsConfigs.MaxStage or 9
		for n = 1, maxStage do
			gatePartCache[n] = StageCheckpointWorld.getGatePart(n)
		end
		gatePartCacheReady = true
	end
	return gatePartCache[stageNum]
end

local onPlayerFunnelContextImpl: (player: Player, data: any) -> ()

local THROTTLE_SKIP_SECONDS = 10

local function shouldDebugStageVisit(): boolean
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	if visitCfg and visitCfg.DebugPrint == true then
		return true
	end
	return FunnelAnalyticsConfigs.DebugPrint == true and RunService:IsStudio()
end

local function shouldDebugStageVisitVerbose(): boolean
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	return shouldDebugStageVisit() and visitCfg and visitCfg.DebugPrintVerbose == true
end

local function shouldDebugOnboarding(): boolean
	local onboardingCfg = FunnelAnalyticsConfigs.Onboarding
	if onboardingCfg and onboardingCfg.DebugPrint == true then
		return true
	end
	return FunnelAnalyticsConfigs.DebugPrint == true and RunService:IsStudio()
end

local function shouldDebugOnboardingVerbose(): boolean
	local onboardingCfg = FunnelAnalyticsConfigs.Onboarding
	return shouldDebugOnboarding() and onboardingCfg and onboardingCfg.DebugPrintVerbose == true
end

local function shouldPrintJoinLeave(): boolean
	if FunnelAnalyticsConfigs.DebugPrintJoinLeave == true then
		return true
	end
	return FunnelAnalyticsConfigs.DebugPrint == true and RunService:IsStudio()
end

local function shouldPrintHealth(): boolean
	if FunnelAnalyticsConfigs.DebugPrintHealth == true then
		return true
	end
	return shouldDebugStageVisit() or shouldDebugOnboarding()
end

local function throttleSkip(uid: number, bucket: { [number]: number }): boolean
	local now = os.clock()
	local last = bucket[uid] or 0
	if now - last < THROTTLE_SKIP_SECONDS then
		return false
	end
	bucket[uid] = now
	return true
end

local function clampStage(stage: number): number
	local maxStage = FunnelAnalyticsConfigs.MaxStage or 9
	return math.clamp(math.floor(stage), 1, maxStage)
end

local function getAnalyticsMaxStageLogged(data: any): number
	local logged = data.AnalyticsMaxStageLogged
	if type(logged) == "number" then
		return math.max(0, math.floor(logged))
	end
	return 0
end

local function shouldSendToRoblox(): boolean
	if FunnelAnalyticsConfigs.Enabled ~= true then
		return false
	end
	if RunService:IsStudio() then
		return FunnelAnalyticsConfigs.SendInStudio == true
	end
	return true
end

local function logPlayerJoinSnapshot(player: Player, data: any)
	if not shouldPrintJoinLeave() then
		return
	end
	if joinSnapshotLogged[player.UserId] then
		return
	end
	joinSnapshotLogged[player.UserId] = true

	local visitLogged = getAnalyticsMaxStageLogged(data)
	local maxStage = if type(data.MaxStage) == "number" then math.floor(data.MaxStage) else 0
	local stage = if type(data.Stage) == "number" then math.floor(data.Stage) else 0
	local onboardingLogged = if type(data.OnboardingStepLogged) == "number" then math.floor(data.OnboardingStepLogged) else 0
	local tutorialStep = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	local thrustIntro = data.TutorialThrustShopIntroShown == true

	print(
		string.format(
			"[StageFunnel] JOIN | %s | AnalyticsMaxStageLogged=%d | MaxStage=%d | Stage=%d",
			player.Name,
			visitLogged,
			maxStage,
			stage
		)
	)
	print(
		string.format(
			"[OnboardingFunnel] JOIN | %s | OnboardingStepLogged=%d | TutorialStep=%d | thrustIntro=%s",
			player.Name,
			onboardingLogged,
			tutorialStep,
			tostring(thrustIntro)
		)
	)
end

local function logPlayerLeaveSnapshot(player: Player)
	if not shouldPrintJoinLeave() then
		return
	end
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		print(string.format("[StageFunnel] LEAVE | %s | (no profile)", player.Name))
		return
	end
	local data = profile.Data
	local visitLogged = getAnalyticsMaxStageLogged(data)
	local maxStage = if type(data.MaxStage) == "number" then math.floor(data.MaxStage) else 0
	local onboardingLogged = if type(data.OnboardingStepLogged) == "number" then math.floor(data.OnboardingStepLogged) else 0
	local tutorialStep = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1

	print(
		string.format(
			"[StageFunnel] LEAVE | %s | AnalyticsMaxStageLogged=%d | MaxStage=%d",
			player.Name,
			visitLogged,
			maxStage
		)
	)
	print(
		string.format(
			"[OnboardingFunnel] LEAVE | %s | OnboardingStepLogged=%d | TutorialStep=%d",
			player.Name,
			onboardingLogged,
			tutorialStep
		)
	)
end

local function logFunnelStatusOnJoin(player: Player, data: any)
	if joinStatusLogged[player.UserId] then
		return
	end
	joinStatusLogged[player.UserId] = true

	local visitLogged = getAnalyticsMaxStageLogged(data)
	local gameplayMax = if type(data.MaxStage) == "number" then math.floor(data.MaxStage) else 0
	local maxStageCap = FunnelAnalyticsConfigs.MaxStage or 9
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	local radius = if visitCfg and type(visitCfg.ProximityRadius) == "number" then visitCfg.ProximityRadius else 40

	if shouldDebugStageVisit() then
		if visitLogged >= maxStageCap then
			print(
				string.format(
					"[StageFunnel] STATUS | %s | logged=%d | gameplay MaxStage=%d | (all stages logged)",
					player.Name,
					visitLogged,
					gameplayMax
				)
			)
		else
			local nextGate = visitLogged + 1
			print(
				string.format(
					"[StageFunnel] STATUS | %s | logged=%d | gameplay MaxStage=%d | next gate=%d (need dist <= %.0f)",
					player.Name,
					visitLogged,
					gameplayMax,
					nextGate,
					radius
				)
			)
		end
	end

	if shouldDebugOnboarding() then
		local derive = FunnelAnalyticsConfigs.DeriveOnboardingStep(data)
		local onboardingLogged = if type(data.OnboardingStepLogged) == "number" then math.floor(data.OnboardingStepLogged) else 0
		local statusNote = if derive <= onboardingLogged then "(caught up)" else string.format("(pending steps %d..%d)", onboardingLogged + 1, derive)
		print(
			string.format(
				"[OnboardingFunnel] STATUS | %s | logged=%d | derive=%d | %s",
				player.Name,
				onboardingLogged,
				derive,
				statusNote
			)
		)
	end
end

local function logFunnelStep(player: Player, stepNum: number)
	local funnelName = FunnelAnalyticsConfigs.FunnelName or "StageProgress"
	local stepName = "Stage " .. tostring(stepNum)

	if FunnelAnalyticsConfigs.DebugPrint == true then
		print("[iseesupes][Funnel]", player.Name, funnelName, "step", stepNum, stepName)
	end

	if not shouldSendToRoblox() then
		return
	end

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, nil, stepNum, stepName)
	end)
	if not ok then
		if shouldDebugStageVisit() or FunnelAnalyticsConfigs.DebugPrint == true then
			warn(string.format("[StageFunnel] ERROR | LogFunnelStepEvent step %d failed: %s", stepNum, tostring(err)))
		end
	end
end

--- Log funnel steps (logged+1 .. stage) once per player. Updates AnalyticsMaxStageLogged only
--- (does not change gameplay MaxStage). Called on gate proximity, win claims, or join backfill.
function FunnelAnalyticsService:recordStageReached(player: Player, stage: number, source: string?)
	if not player.Parent then
		return
	end

	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		if shouldDebugStageVisit() then
			warn("[StageFunnel] SKIP | no profile |", player.Name, "| src=", source or "?")
		end
		return
	end

	local data = profile.Data
	onPlayerFunnelContextImpl(player, data)

	local targetStage = clampStage(stage)
	local logged = getAnalyticsMaxStageLogged(data)
	if targetStage <= logged then
		if shouldDebugStageVisitVerbose() and throttleSkip(player.UserId, lastStageSkipAt) then
			print(
				string.format(
					"[StageFunnel] SKIP | %s | already at %d (requested %d) | src=%s",
					player.Name,
					logged,
					targetStage,
					source or "?"
				)
			)
		elseif shouldDebugStageVisit() then
			print(
				string.format(
					"[StageFunnel] OK | %s | already logged through stage %d | src=%s",
					player.Name,
					logged,
					source or "?"
				)
			)
		end
		return
	end

	if shouldDebugStageVisit() then
		print(
			string.format(
				"[StageFunnel] RECORD | %s | logged %d -> %d | gap-fill steps %d..%d | src=%s",
				player.Name,
				logged,
				targetStage,
				logged + 1,
				targetStage,
				source or "unknown"
			)
		)
	end

	for stepNum = logged + 1, targetStage do
		logFunnelStep(player, stepNum)
		if shouldDebugStageVisit() then
			print(string.format("[StageFunnel]   -> LogFunnelStepEvent step %d (Stage %d)", stepNum, stepNum))
		end
	end

	data.AnalyticsMaxStageLogged = targetStage

	if shouldDebugStageVisit() then
		local gameplayMax = if type(data.MaxStage) == "number" then math.floor(data.MaxStage) else 0
		print(
			string.format(
				"[StageFunnel] OK | %s | AnalyticsMaxStageLogged=%d | gameplay MaxStage=%d",
				player.Name,
				targetStage,
				gameplayMax
			)
		)
	end
end

--- Backfill funnel steps for players who reached stages before analytics shipped.
function FunnelAnalyticsService:syncStagesFromProfile(player: Player)
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return
	end

	local data = profile.Data
	onPlayerFunnelContextImpl(player, data)

	local profileMax = type(data.MaxStage) == "number" and math.floor(data.MaxStage) or 0
	local visitLogged = getAnalyticsMaxStageLogged(data)
	local maxStage = math.max(profileMax, visitLogged)
	if maxStage < 1 then
		return
	end

	if maxStage <= visitLogged then
		return
	end

	if shouldDebugStageVisit() then
		print(
			string.format(
				"[StageFunnel] BACKFILL | %s | MaxStage=%d visitLogged=%d -> record %d",
				player.Name,
				profileMax,
				visitLogged,
				maxStage
			)
		)
	end

	FunnelAnalyticsService:recordStageReached(player, maxStage, "join_backfill")
end

local function getPlayerHrp(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function pollStageVisits()
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	if not visitCfg or visitCfg.Enabled ~= true then
		return
	end
	local radius = if type(visitCfg.ProximityRadius) == "number" then visitCfg.ProximityRadius else 40
	local maxStage = FunnelAnalyticsConfigs.MaxStage or 9

	for _, player in Players:GetPlayers() do
		if not player.Parent then
			continue
		end
		local hrp = getPlayerHrp(player)
		if not hrp then
			if shouldDebugStageVisitVerbose() and throttleSkip(player.UserId, lastPollSkipAt) then
				print(string.format("[StageFunnel] SKIP | %s | poll: no HRP", player.Name))
			end
			continue
		end
		local profile = DataService and DataService:GetProfile(player)
		if not profile then
			if shouldDebugStageVisitVerbose() and throttleSkip(player.UserId, lastPollSkipAt) then
				print(string.format("[StageFunnel] SKIP | %s | poll: no profile", player.Name))
			end
			continue
		end
		onPlayerFunnelContextImpl(player, profile.Data)
		local logged = getAnalyticsMaxStageLogged(profile.Data)
		local highestNearby = logged
		local hrpPos = hrp.Position
		local nearestStage: number? = nil
		local nearestDist = math.huge
		for stageNum = logged + 1, maxStage do
			local gatePart = getCachedGatePart(stageNum)
			if not gatePart then
				continue
			end
			local closest = gatePart:GetClosestPointOnSurface(hrpPos)
			local dist = (closest - hrpPos).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearestStage = stageNum
			end
			if dist <= radius then
				highestNearby = math.max(highestNearby, stageNum)
				if shouldDebugStageVisit() then
					print(
						string.format(
							"[StageFunnel] PROXIMITY | %s | gate %d | dist=%.1f | radius=%.0f | logged=%d",
							player.Name,
							stageNum,
							dist,
							radius,
							logged
						)
					)
				end
			end
		end
		if highestNearby > logged then
			FunnelAnalyticsService:recordStageReached(player, highestNearby, "gate_proximity")
		elseif shouldDebugStageVisitVerbose() and nearestStage and logged < maxStage then
			local uid = player.UserId
			local now = os.clock()
			local last = lastProximityHintAt[uid] or 0
			if now - last >= 5 then
				lastProximityHintAt[uid] = now
				print(
					string.format(
						"[StageFunnel] NEAR | %s | next gate %d | dist=%.1f | need <= %.0f | logged=%d",
						player.Name,
						nearestStage,
						nearestDist,
						radius,
						logged
					)
				)
			end
		end
	end
end

local function logStageGateMap(): number
	local maxStage = FunnelAnalyticsConfigs.MaxStage or 9
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	local radius = if visitCfg and type(visitCfg.ProximityRadius) == "number" then visitCfg.ProximityRadius else 40
	local found = 0
	local verbose = shouldDebugStageVisitVerbose()
	if verbose then
		print("[StageFunnel] === Gate map (StageProgress proximity funnel) ===")
	end
	for stageNum = 1, maxStage do
		local gatePart = StageCheckpointWorld.getGatePart(stageNum)
		if gatePart then
			found += 1
			if verbose then
				print(
					string.format(
						"[StageFunnel]   gate %d OK @ %s",
						stageNum,
						tostring(gatePart.Position)
					)
				)
			end
		else
			warn(string.format("[StageFunnel]   gate %d MISSING (no StageCheckpoints/%d)", stageNum, stageNum))
		end
	end
	if shouldDebugStageVisit() or shouldPrintHealth() then
		print(
			string.format(
				"[StageFunnel] READY | gates=%d/%d | radius=%.0f | poll=%.1fs | Studio analytics send=%s",
				found,
				maxStage,
				radius,
				if visitCfg and type(visitCfg.PollIntervalSeconds) == "number" then visitCfg.PollIntervalSeconds else 0.5,
				tostring(FunnelAnalyticsConfigs.SendInStudio == true)
			)
		)
		if verbose then
			print("[StageFunnel] Walk/fly within radius of each gate to log Stage 1..N (look for PROXIMITY + RECORD lines)")
		end
	end
	return found
end

local function logStartupHealth(gateCount: number, pollStarted: boolean)
	if not shouldPrintHealth() then
		return
	end

	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	local onboardingCfg = FunnelAnalyticsConfigs.Onboarding
	local visitEnabled = visitCfg and visitCfg.Enabled == true
	local onboardingEnabled = onboardingCfg and onboardingCfg.Enabled == true

	print(
		string.format(
			"[Funnel] HEALTH | Enabled=%s | StageVisit=%s | Onboarding=%s | SendInStudio=%s",
			tostring(FunnelAnalyticsConfigs.Enabled == true),
			tostring(visitEnabled),
			tostring(onboardingEnabled),
			tostring(FunnelAnalyticsConfigs.SendInStudio == true)
		)
	)

	if pollStarted and visitCfg then
		print(
			string.format(
				"[Funnel] HEALTH | StageProgress poll=STARTED interval=%.1f radius=%.0f",
				if type(visitCfg.PollIntervalSeconds) == "number" then visitCfg.PollIntervalSeconds else 0.5,
				if type(visitCfg.ProximityRadius) == "number" then visitCfg.ProximityRadius else 40
			)
		)
	else
		warn("[StageFunnel] POLL DISABLED — proximity stage funnel OFF (win-button/skip still log)")
	end

	if FunnelAnalyticsConfigs.Enabled ~= true then
		warn("[Funnel] WARN funnel disabled — no analytics will be sent")
	end
	if not visitEnabled then
		warn("[Funnel] WARN proximity stage funnel OFF — only win-button/skip will log StageProgress")
	end
	if not onboardingEnabled then
		warn("[Funnel] WARN onboarding funnel OFF — tutorial steps will not log")
	end
	if gateCount == 0 then
		warn("[Funnel] WARN no StageCheckpoints gates — StageProgress proximity will never advance")
	end

	print("[Funnel] === How to read Output ===")
	print("[Funnel]   Stage OK:      PROXIMITY -> RECORD -> LogFunnelStepEvent -> OK")
	print("[Funnel]   Stage stuck:   NEAR dist not decreasing | gate MISSING | POLL DISABLED")
	print("[Funnel]   Onboarding OK: OnboardingFunnel RECORD -> LogOnboardingFunnelStepEvent -> OK")
	print("[Funnel]   Paste lines starting with [StageFunnel] or [OnboardingFunnel]")
end

local function ensureStartupDiagnostics()
	if startupDiagnosticsDone then
		return
	end
	startupDiagnosticsDone = true
	local gateCount = logStageGateMap()
	logStartupHealth(gateCount, pollStartedAtStart)
end

onPlayerFunnelContextImpl = function(player: Player, data: any)
	ensureStartupDiagnostics()
	logFunnelStatusOnJoin(player, data)
	logPlayerJoinSnapshot(player, data)
end

local function startStageVisitPolling(): boolean
	local visitCfg = FunnelAnalyticsConfigs.StageVisit
	if not visitCfg or visitCfg.Enabled ~= true then
		return false
	end
	local interval = if type(visitCfg.PollIntervalSeconds) == "number" then visitCfg.PollIntervalSeconds else 0.5
	if RunService:IsStudio() then
		interval = math.max(interval, 1)
	end
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < interval then
			return
		end
		accum = 0
		pollStageVisits()
	end)
	return true
end

local function logOnboardingStep(player: Player, stepNum: number)
	local cfg = FunnelAnalyticsConfigs.Onboarding
	local stepName = (cfg and cfg.Steps and cfg.Steps[stepNum]) or ("Step " .. tostring(stepNum))

	if FunnelAnalyticsConfigs.DebugPrint == true then
		print("[iseesupes][Onboarding]", player.Name, "step", stepNum, stepName)
	end

	if not shouldSendToRoblox() then
		return
	end

	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNum, stepName)
	end)
	if not ok then
		if shouldDebugOnboarding() or FunnelAnalyticsConfigs.DebugPrint == true then
			warn(
				string.format(
					"[OnboardingFunnel] ERROR | LogOnboardingFunnelStepEvent step %d failed: %s",
					stepNum,
					tostring(err)
				)
			)
		end
	end
end

--- Derives the onboarding step from profile data and logs any unlogged steps.
--- Called from DataService:Replicate — integer compares only, so the hot path
--- stays cheap; actual logging happens at most 7 times per player lifetime.
function FunnelAnalyticsService:syncOnboardingFromData(player: Player, data: any)
	local cfg = FunnelAnalyticsConfigs.Onboarding
	if not cfg or cfg.Enabled ~= true then
		if shouldDebugOnboarding() then
			print("[OnboardingFunnel] SKIP | disabled")
		end
		return
	end
	if not player.Parent then
		if shouldDebugOnboarding() then
			print("[OnboardingFunnel] SKIP | no player")
		end
		return
	end

	onPlayerFunnelContextImpl(player, data)

	local target = FunnelAnalyticsConfigs.DeriveOnboardingStep(data)
	local logged = if type(data.OnboardingStepLogged) == "number" then data.OnboardingStepLogged else 0
	if target <= logged then
		if shouldDebugOnboardingVerbose() then
			print(
				string.format(
					"[OnboardingFunnel] SKIP | %s | target %d <= logged %d",
					player.Name,
					target,
					logged
				)
			)
		end
		return
	end

	local tutorialStep = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	local thrustIntro = data.TutorialThrustShopIntroShown == true

	if shouldDebugOnboarding() then
		print(
			string.format(
				"[OnboardingFunnel] RECORD | %s | logged %d -> %d | gap-fill %d..%d | derive=%d | TutorialStep=%d thrustIntro=%s",
				player.Name,
				logged,
				target,
				logged + 1,
				target,
				target,
				tutorialStep,
				tostring(thrustIntro)
			)
		)
	end

	for stepNum = logged + 1, target do
		local stepName = (cfg.Steps and cfg.Steps[stepNum]) or ("Step " .. tostring(stepNum))
		logOnboardingStep(player, stepNum)
		if shouldDebugOnboarding() then
			print(
				string.format(
					"[OnboardingFunnel]   -> LogOnboardingFunnelStepEvent step %d %s",
					stepNum,
					stepName
				)
			)
		end
	end
	data.OnboardingStepLogged = target

	if shouldDebugOnboarding() then
		print(string.format("[OnboardingFunnel] OK | %s | OnboardingStepLogged=%d", player.Name, target))
	end
end

function FunnelAnalyticsService:KnitStart()
	DataService = Knit.GetService("DataService")
	pollStartedAtStart = startStageVisitPolling()
	Players.PlayerRemoving:Connect(function(player)
		logPlayerLeaveSnapshot(player)
		lastProximityHintAt[player.UserId] = nil
		lastPollSkipAt[player.UserId] = nil
		lastStageSkipAt[player.UserId] = nil
		joinSnapshotLogged[player.UserId] = nil
		joinStatusLogged[player.UserId] = nil
	end)
	StudioLog.ready("FunnelAnalyticsService", "(funnel: " .. (FunnelAnalyticsConfigs.FunnelName or "") .. ")")
end

return FunnelAnalyticsService
