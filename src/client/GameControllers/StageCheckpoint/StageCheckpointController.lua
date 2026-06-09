--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local StageCheckpointConfigs = require(ReplicatedStorage.Shared.Configs.StageCheckpointConfigs)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local StageCheckpointDebug = require(ReplicatedStorage.Shared.Utils.StageCheckpointDebug)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
local SupermanGroundVfx = require(script.Parent.Parent.Parent.Modules.SupermanGroundVfx)

local StageCheckpointController = Knit.CreateController({ Name = "StageCheckpointController" })

local player = Players.LocalPlayer

local activeBarTweens: { [number]: Tween } = {}
local localHp: { [number]: number } = {}
local gateBaselineColors: { [number]: Color3 } = {}
local lastSyncNextMeltGate: number? = nil

local MELT_HIGHLIGHT_NAME = "GateMeltHeat"

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function ensureGateBaseline(stageNum: number, gatePart: BasePart)
	if gateBaselineColors[stageNum] then
		return
	end
	gateBaselineColors[stageNum] = gatePart.Color
end

local function removeGateMeltHighlight(gatePart: BasePart)
	local existing = gatePart:FindFirstChild(MELT_HIGHLIGHT_NAME)
	if existing then
		existing:Destroy()
	end
end

local function resetGateMeltVisual(stageNum: number, gatePart: BasePart)
	local baseline = gateBaselineColors[stageNum]
	if baseline then
		gatePart.Color = baseline
	else
		gatePart.Color = StageCheckpointConfigs.GateMeltVisuals.ColdColor
	end
	removeGateMeltHighlight(gatePart)
end

local function applyGateMeltHeatVisual(stageNum: number, hp01: number)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return
	end

	ensureGateBaseline(stageNum, gatePart)
	local baseline = gateBaselineColors[stageNum] or StageCheckpointConfigs.GateMeltVisuals.ColdColor
	local visuals = StageCheckpointConfigs.GateMeltVisuals
	local heat = math.clamp(1 - hp01, 0, 1)

	if heat <= 0.01 then
		resetGateMeltVisual(stageNum, gatePart)
		return
	end

	gatePart.Color = lerpColor(baseline, visuals.HotColor, heat)

	if heat < visuals.HeatThreshold then
		removeGateMeltHighlight(gatePart)
		return
	end

	local highlight = gatePart:FindFirstChild(MELT_HIGHLIGHT_NAME) :: Highlight?
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = MELT_HIGHLIGHT_NAME
		highlight.Adornee = gatePart
		highlight.Parent = gatePart
	end
	highlight.FillColor = visuals.HighlightFillColor
	highlight.OutlineColor = visuals.HighlightOutlineColor
	highlight.FillTransparency = StageCheckpointConfigs.getGateHeatFillTransparency(heat)
	highlight.OutlineTransparency = 0.25 + (1 - heat) * 0.45
end

function StageCheckpointController:GetNextMeltGateStage(): number?
	return lastSyncNextMeltGate
end

local function getRequirementForGate(gatePart: BasePart, stageNum: number?): number?
	if stageNum then
		local fromConfig = StageCheckpointConfigs.GetGateSpeedRequirement(stageNum)
		if fromConfig then
			return fromConfig
		end
	end

	local attrName = StageCheckpointConfigs.RequirementAttribute
	local fromAttr = gatePart:GetAttribute(attrName)
	if typeof(fromAttr) == "number" and fromAttr > 0 then
		return fromAttr
	end
	local fromLabel = StageCheckpointWorld.readRequirement(gatePart)
	if fromLabel and fromLabel > 0 then
		return fromLabel
	end
	if stageNum and StageCheckpointConfigs.DefaultMinSpeedXp then
		if stageNum == StageCheckpointConfigs.FirstGateStage then
			return StageCheckpointConfigs.DefaultMinSpeedXp
		end
	end
	return nil
end

local function tweenBar(stageNum: number, hp01: number)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return
	end
	local progress = StageCheckpointWorld.getBarProgressFrame(gatePart)
	if not progress then
		return
	end

	local clamped = math.clamp(hp01, 0, 1)
	localHp[stageNum] = clamped
	local targetSize = UDim2.new(clamped, 0, 1, 0)

	local existing = activeBarTweens[stageNum]
	if existing then
		existing:Cancel()
	end

	local tween = TweenService:Create(
		progress,
		TweenInfo.new(StageCheckpointConfigs.BarTweenDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	activeBarTweens[stageNum] = tween
	tween:Play()
	tween.Completed:Once(function()
		if activeBarTweens[stageNum] == tween then
			activeBarTweens[stageNum] = nil
		end
	end)
end

local function hideGateForLocalPlayer(stageNum: number, instant: boolean?)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return
	end

	local duration = if instant then 0 else (StageCheckpointConfigs.GateBreakHideDuration or 0.22)
	if duration <= 0 then
		gatePart.LocalTransparencyModifier = 1
	else
		TweenService:Create(
			gatePart,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ LocalTransparencyModifier = 1 }
		):Play()
	end

	local progress = StageCheckpointWorld.getBarProgressFrame(gatePart)
	if progress then
		if duration <= 0 then
			progress.Size = UDim2.new(0, 0, 1, 0)
		else
			TweenService:Create(
				progress,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, 0, 1, 0) }
			):Play()
		end
	end
	StageCheckpointWorld.disableXpOverlay(gatePart)
	StageCheckpointWorld.setGateInteractionEnabled(gatePart, false)
	StageCheckpointDebug.logAlways(string.format("[BarUI] hideGate stage=%d (cleared/broken, XP disabled)", stageNum))
end

local function showGateForLocalPlayer(stageNum: number)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return
	end
	StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
	StageCheckpointWorld.setGateInteractionEnabled(gatePart, true)
	gatePart.LocalTransparencyModifier = 0
end

local function refreshGateUi(stageNum: number, hp01: number?)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return
	end

	local requirement = getRequirementForGate(gatePart, stageNum)
	if not requirement then
		StageCheckpointDebug.logAlways(string.format(
			"refreshGateUi stage=%d FAIL: no requirement attr=%s label=%s",
			stageNum,
			tostring(gatePart:GetAttribute(StageCheckpointConfigs.RequirementAttribute)),
			tostring(StageCheckpointWorld.getRequirementLabel(gatePart) and StageCheckpointWorld.getRequirementLabel(gatePart).Text)
		))
		return
	end

	local resolvedHp = if hp01 ~= nil then hp01 else (localHp[stageNum] or 1)
	if resolvedHp <= 0.01 then
		StageCheckpointWorld.applyGateUi(gatePart, requirement, 0, "refreshGateUi → EMPTY")
		StageCheckpointWorld.disableXpOverlay(gatePart)
		StageCheckpointWorld.setGateInteractionEnabled(gatePart, false)
		resetGateMeltVisual(stageNum, gatePart)
		return
	end

	StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
	StageCheckpointWorld.setGateInteractionEnabled(gatePart, true)
	StageCheckpointDebug.log(string.format(
		"refreshGateUi stage=%d req=%d hp=%.2f label->%s",
		stageNum,
		requirement,
		resolvedHp,
		StageCheckpointWorld.formatRequirementText(requirement)
	), "client:ui:" .. tostring(stageNum), 1)
	StageCheckpointWorld.applyGateUi(gatePart, requirement, resolvedHp, "refreshGateUi")
	applyGateMeltHeatVisual(stageNum, resolvedHp)
end

type GateSyncEntry = {
	hp01: number,
	requirement: number?,
	cleared: boolean,
	isNextTarget: boolean?,
}

local function applyGateFromSync(
	stageNum: number,
	requirement: number,
	hp01: number?,
	cleared: boolean,
	isNextTarget: boolean?,
	logContext: string
)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return false
	end

	if cleared then
		localHp[stageNum] = 0
		StageCheckpointWorld.applyGateVisualState(gatePart, requirement, "broken", 0, logContext)
		resetGateMeltVisual(stageNum, gatePart)
	elseif isNextTarget then
		local resolvedHp = if hp01 ~= nil then hp01 else 1
		localHp[stageNum] = resolvedHp
		StageCheckpointWorld.applyGateVisualState(gatePart, requirement, "active", resolvedHp, logContext)
		tweenBar(stageNum, resolvedHp)
		applyGateMeltHeatVisual(stageNum, resolvedHp)
	else
		localHp[stageNum] = 1
		StageCheckpointWorld.applyGateVisualState(gatePart, requirement, "future", 1, logContext)
		resetGateMeltVisual(stageNum, gatePart)
	end
	return true
end

local resyncGeneration = 0

local function restoreLocalGatePartDefaults(stageNum: number)
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return false
	end
	local requirement = getRequirementForGate(gatePart, stageNum)
	StageCheckpointWorld.restoreGatePartLockedVisual(gatePart, requirement, 1, "LocalSessionRestore")
	resetGateMeltVisual(stageNum, gatePart)
	localHp[stageNum] = 1
	return true
end

local function restoreAllLocalGateDefaults()
	for stageNum = StageCheckpointConfigs.FirstGateStage, StageCheckpointConfigs.MaxGateStage do
		restoreLocalGatePartDefaults(stageNum)
	end
end

local function applyServerGateSync(sync: {
	sessionBrokenCount: number,
	nextMeltGate: number?,
	gates: { [number]: GateSyncEntry },
})
	lastSyncNextMeltGate = sync.nextMeltGate
	local serverGateCount = StageCheckpointDebug.countKeys(sync.gates)
	local localStages = StageCheckpointWorld.getLocalGateStageNumbers()
	StageCheckpointDebug.logAlways(string.format(
		"applyServerGateSync sessionBroken=%d nextMeltGate=%s gateEntries=%d localParts=[%s]",
		sync.sessionBrokenCount,
		tostring(sync.nextMeltGate),
		serverGateCount,
		StageCheckpointDebug.formatStageList(localStages)
	))

	local applied = 0
	local missingPart = 0
	local missingReq = 0

	for stageNum, state in sync.gates do
		local gatePart = StageCheckpointWorld.getGatePart(stageNum)
		if not gatePart then
			missingPart += 1
			StageCheckpointDebug.log(string.format(
				"sync stage=%d skipped: part not on client yet cleared=%s next=%s hp01=%.2f",
				stageNum,
				tostring(state.cleared),
				tostring(state.isNextTarget),
				state.hp01
			), "sync:missingPart:" .. tostring(stageNum), 4)
			continue
		end

		local requirement = state.requirement or getRequirementForGate(gatePart, stageNum)
		if not requirement then
			missingReq += 1
			StageCheckpointDebug.logAlways(string.format(
				"sync stage=%d skipped: no requirement — %s",
				stageNum,
				StageCheckpointWorld.describeLocalGate(stageNum)
			))
			continue
		end

		if applyGateFromSync(
			stageNum,
			requirement,
			state.hp01,
			state.cleared,
			state.isNextTarget,
			"ClientSync"
		) then
			applied += 1
		end
	end

	StageCheckpointDebug.logAlways(string.format(
		"applyServerGateSync done applied=%d missingPart=%d missingReq=%d",
		applied,
		missingPart,
		missingReq
	))

	if sync.nextMeltGate then
		local nextState = sync.gates[sync.nextMeltGate]
		local req = if nextState then nextState.requirement else nil
		local nextPart = StageCheckpointWorld.getGatePart(sync.nextMeltGate)
		StageCheckpointDebug.logAlways(string.format(
			"Melt gate %d with heat vision (F)%s%s",
			sync.nextMeltGate,
			if req then " Min " .. tostring(req) .. " Speed XP" else "",
			if nextPart then "" else " — walk closer; gate not streamed yet"
		))
	end
end

local function clearLocalGateState()
	for _, tween in activeBarTweens do
		tween:Cancel()
	end
	table.clear(activeBarTweens)
	table.clear(localHp)
	table.clear(gateBaselineColors)
end

local function pullServerGateSync()
	local data = DataLib.GetData()
	if not data then
		StageCheckpointDebug.logAlways("GetGateSync skipped: profile not loaded yet")
		return
	end

	local service = Knit.GetService("StageCheckpointService")
	service:GetGateSync()
		:andThen(function(sync: {
			sessionBrokenCount: number,
			nextMeltGate: number?,
			gates: { [number]: GateSyncEntry },
		})
			if not StageCheckpointWorld.getFolder() then
				StageCheckpointDebug.logAlways("GetGateSync response ignored: StageCheckpoints folder missing")
				return
			end
			applyServerGateSync(sync)
		end)
		:catch(function(err)
			warn("[iseesupes][StageCheckpoint] GetGateSync failed:", err)
		end)
end

local function scheduleGateResyncPulls()
	resyncGeneration += 1
	local generation = resyncGeneration

	local function tryPull()
		if generation ~= resyncGeneration then
			return
		end
		pullServerGateSync()
	end

	tryPull()
	for _, delay in { 0.35, 0.9, 2.0 } do
		task.delay(delay, tryPull)
	end
end

local function onCheckpointBroken(stageNum: number, hitPos: Vector3, hitNormal: Vector3)
	localHp[stageNum] = 0
	tweenBar(stageNum, 0)

	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if gatePart then
		StageCheckpointWorld.disableXpOverlay(gatePart)
		StageCheckpointWorld.setGateInteractionEnabled(gatePart, false)
		gatePart.LocalTransparencyModifier = 1
	end

	if gatePart then
		SupermanGroundVfx.spawnGateMetalMelt(
			gatePart,
			hitPos,
			hitNormal,
			StageCheckpointConfigs.MetalMeltChipCount
		)
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local rayResult = workspace:Raycast(hitPos - hitNormal * 0.05, hitNormal * 0.1, params)
		if rayResult then
			SupermanGroundVfx.spawnMetalMeltAt(rayResult, StageCheckpointConfigs.MetalMeltChipCount)
		else
			local syntheticPart = Instance.new("Part")
			syntheticPart.Size = Vector3.new(4, 8, 0.5)
			syntheticPart.Anchored = true
			syntheticPart.CFrame = CFrame.new(hitPos, hitPos + hitNormal)
			syntheticPart.Material = Enum.Material.Metal
			syntheticPart.Color = StageCheckpointConfigs.GateMeltVisuals.ColdColor
			syntheticPart.Parent = workspace
			local syntheticResult = {
				Position = hitPos,
				Normal = hitNormal,
				Instance = syntheticPart,
				Material = Enum.Material.Metal,
			} :: any
			SupermanGroundVfx.spawnMetalMeltAt(syntheticResult, StageCheckpointConfigs.MetalMeltChipCount)
			syntheticPart:Destroy()
		end
	end

	task.delay(StageCheckpointConfigs.GateBreakHideDelay or 0.08, function()
		hideGateForLocalPlayer(stageNum, false)
	end)
end

function StageCheckpointController:KnitStart()
	local service = Knit.GetService("StageCheckpointService")
	local SkipStageService = Knit.GetService("SkipStageService")
	local folderWatchBound = false
	local profileReady = false

	local function bindFolderStreamingResync()
		if folderWatchBound then
			return
		end
		local folder = StageCheckpointWorld.getFolder()
		if not folder then
			return
		end
		folderWatchBound = true
		folder.ChildAdded:Connect(function(child)
			if not child:IsA("BasePart") then
				return
			end
			local stageNum = tonumber(child.Name)
			if not stageNum or not StageCheckpointWorld.isMeltGateStage(stageNum) then
				return
			end
			StageCheckpointDebug.logAlways(string.format(
				"Gate part streamed in: stage=%d — restoring + re-syncing UI",
				stageNum
			))
			task.defer(function()
				restoreLocalGatePartDefaults(stageNum)
				scheduleGateResyncPulls()
			end)
		end)
	end

	local function onDataOrFolderReady(data: any?)
		if not StageCheckpointWorld.getFolder() then
			return
		end
		bindFolderStreamingResync()
		if not data then
			StageCheckpointDebug.logAlways("onDataOrFolderReady: folder ok, waiting for profile data")
			return
		end
		pullServerGateSync()
	end

	local function onProfileDataChanged(data: any)
		if not data or profileReady then
			return
		end
		profileReady = true
		onDataOrFolderReady(data)
	end

	task.defer(function()
		for _ = 1, 24 do
			if StageCheckpointWorld.getFolder() then
				StageCheckpointDebug.logAlways("StageCheckpointController: map folder found, syncing gates")
				onDataOrFolderReady(DataLib.GetData())
				return
			end
			task.wait(0.25)
		end
		StageCheckpointDebug.logAlways("StageCheckpointController: gave up waiting for StageCheckpoints folder")
	end)

	DataLib.OnChanged(onProfileDataChanged)

	if DataLib.GetData() and StageCheckpointWorld.getFolder() then
		onProfileDataChanged(DataLib.GetData())
	end

	service.CheckpointHpChanged:Connect(function(stageNum: number, hp01: number)
		StageCheckpointDebug.log(string.format("CheckpointHpChanged stage=%d hp=%.2f", stageNum, hp01), "client:hp", 0.3)
		refreshGateUi(stageNum, hp01)
		tweenBar(stageNum, hp01)
		applyGateMeltHeatVisual(stageNum, hp01)
	end)

	service.CheckpointBroken:Connect(function(stageNum: number, hitPos: Vector3, hitNormal: Vector3)
		StageCheckpointDebug.logAlways(string.format("CheckpointBroken stage=%d pos=%s", stageNum, tostring(hitPos)))
		onCheckpointBroken(stageNum, hitPos, hitNormal)
		scheduleGateResyncPulls()
	end)

	service.SpeedRequirementFailed:Connect(function(_stageNum: number, requirement: number, playerSpeed: number)
		local need = math.max(0, math.ceil(requirement - playerSpeed))
		NotificationManager.show(
			"Need "
				.. NumberFormatter.Format(need)
				.. " more Speed XP to melt this barrier",
			"Info"
		)
	end)

	local function onSessionGateRestoreRequested(source: string)
		StageCheckpointDebug.logAlways("Gate session restore (" .. source .. ")")
		clearLocalGateState()
		restoreAllLocalGateDefaults()
		scheduleGateResyncPulls()
	end

	service.SessionGatesReset:Connect(function()
		onSessionGateRestoreRequested("SessionGatesReset")
	end)

	SkipStageService.StageChanged:Connect(function(_newStage: number)
		scheduleGateResyncPulls()
	end)

	player.CharacterAdded:Connect(function()
		task.delay(0.3, function()
			if DataLib.GetData() then
				onSessionGateRestoreRequested("CharacterAdded")
			end
		end)
	end)

	service.GateMeltBlocked:Connect(function(stageNum: number, reason: string)
		if reason == "broken" then
			NotificationManager.show("Gate " .. tostring(stageNum) .. " already broken this run", "Info")
		elseif reason == "wrong_gate" then
			NotificationManager.show(
				"Melt gate "
					.. tostring(lastSyncNextMeltGate or "?")
					.. " first (you aimed at gate "
					.. tostring(stageNum)
					.. ")",
				"Info"
			)
		end
	end)

	print("[iseesupes] StageCheckpointController ready.")
end

return StageCheckpointController
