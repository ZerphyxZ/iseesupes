--!strict

-- Logs stage progression to Roblox Analytics (Creator Dashboard → Funnels → StageProgress).

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FunnelAnalyticsConfigs = require(ReplicatedStorage.Shared.Configs.FunnelAnalyticsConfigs)

local FunnelAnalyticsService = Knit.CreateService({
	Name = "FunnelAnalyticsService",
	Client = {},
})

local DataService: any = nil

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
	if not ok and FunnelAnalyticsConfigs.DebugPrint == true then
		warn("[iseesupes][Funnel] LogFunnelStepEvent failed:", err)
	end
end

--- Log funnel steps (logged+1 .. stage) once per player. Call when MaxStage increases or on join backfill.
function FunnelAnalyticsService:recordStageReached(player: Player, stage: number)
	if not player.Parent then
		return
	end

	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return
	end

	local data = profile.Data
	local targetStage = clampStage(stage)
	local logged = getAnalyticsMaxStageLogged(data)
	if targetStage <= logged then
		return
	end

	for stepNum = logged + 1, targetStage do
		logFunnelStep(player, stepNum)
	end

	data.AnalyticsMaxStageLogged = targetStage
end

--- Backfill funnel steps for players who reached stages before analytics shipped.
function FunnelAnalyticsService:syncStagesFromProfile(player: Player)
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return
	end

	local maxStage = type(profile.Data.MaxStage) == "number" and math.floor(profile.Data.MaxStage) or 0
	if maxStage < 1 then
		return
	end

	FunnelAnalyticsService:recordStageReached(player, maxStage)
end

local function logOnboardingStep(player: Player, stepNum: number)
	local cfg = FunnelAnalyticsConfigs.Onboarding
	local stepName = (cfg.Steps and cfg.Steps[stepNum]) or ("Step " .. tostring(stepNum))

	if FunnelAnalyticsConfigs.DebugPrint == true then
		print("[iseesupes][Onboarding]", player.Name, "step", stepNum, stepName)
	end

	if not shouldSendToRoblox() then
		return
	end

	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, stepNum, stepName)
	end)
	if not ok and FunnelAnalyticsConfigs.DebugPrint == true then
		warn("[iseesupes][Onboarding] LogOnboardingFunnelStepEvent failed:", err)
	end
end

--- Derives the onboarding step from profile data and logs any unlogged steps.
--- Called from DataService:Replicate — integer compares only, so the hot path
--- stays cheap; actual logging happens at most 7 times per player lifetime.
function FunnelAnalyticsService:syncOnboardingFromData(player: Player, data: any)
	local cfg = FunnelAnalyticsConfigs.Onboarding
	if not cfg or cfg.Enabled ~= true then
		return
	end
	if not player.Parent then
		return
	end

	local target = FunnelAnalyticsConfigs.DeriveOnboardingStep(data)
	local logged = if type(data.OnboardingStepLogged) == "number" then data.OnboardingStepLogged else 0
	if target <= logged then
		return
	end

	for stepNum = logged + 1, target do
		logOnboardingStep(player, stepNum)
	end
	data.OnboardingStepLogged = target
end

function FunnelAnalyticsService:KnitStart()
	DataService = Knit.GetService("DataService")
	print("[iseesupes] FunnelAnalyticsService ready (funnel:", FunnelAnalyticsConfigs.FunnelName, ")")
end

return FunnelAnalyticsService
