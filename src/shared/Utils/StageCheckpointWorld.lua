--!strict

local MapWorld = require(script.Parent.MapWorld)
local StageCheckpointConfigs = require(script.Parent.Parent.Configs.StageCheckpointConfigs)
local StageCheckpointDebug = require(script.Parent.StageCheckpointDebug)

local StageCheckpointWorld = {}

local requirementCache: { [number]: number } = {}

local function parseRequirementText(text: string): number?
	-- Prefer plain numbers (Studio-authored min Speed XP). Ignore progress strings like "0/5".
	if string.find(text, "/") then
		return nil
	end
	local digits = string.match(text, "%d+")
	if not digits then
		return nil
	end
	return tonumber(digits)
end

function StageCheckpointWorld.readRequirementFromGate(gatePart: BasePart): number?
	local attrName = StageCheckpointConfigs.RequirementAttribute
	local fromAttr = gatePart:GetAttribute(attrName)
	if typeof(fromAttr) == "number" and fromAttr > 0 then
		return fromAttr
	end
	return StageCheckpointWorld.readRequirement(gatePart)
end

function StageCheckpointWorld.getFolder(): Instance?
	local folder = MapWorld.findChildInMap(StageCheckpointConfigs.FolderName)
	if folder then
		return folder
	end
	local map = MapWorld.getMapFolder()
	if map then
		local inMap = map:FindFirstChild(StageCheckpointConfigs.FolderName)
		if inMap then
			return inMap
		end
	end
	return workspace:FindFirstChild(StageCheckpointConfigs.FolderName)
end

function StageCheckpointWorld.isMeltGateStage(stageNum: number): boolean
	local cfg = StageCheckpointConfigs
	return stageNum >= cfg.FirstGateStage and stageNum <= cfg.MaxGateStage
end

function StageCheckpointWorld.getGatePart(stageNum: number): BasePart?
	if not StageCheckpointWorld.isMeltGateStage(stageNum) then
		return nil
	end
	local folder = StageCheckpointWorld.getFolder()
	if not folder then
		return nil
	end
	local child = folder:FindFirstChild(tostring(stageNum))
	if not child then
		return nil
	end
	if child:IsA("BasePart") then
		return child
	end
	return child:FindFirstChildWhichIsA("BasePart", true)
end

function StageCheckpointWorld.getCheckpointFromHit(part: Instance): (number?, BasePart?)
	local folder = StageCheckpointWorld.getFolder()
	if not folder then
		return nil, nil
	end

	local stageEntry: Instance? = nil
	local stageNum: number? = nil
	local current: Instance? = part
	while current and current ~= folder do
		if current.Parent == folder then
			local num = tonumber(current.Name)
			if num and StageCheckpointWorld.isMeltGateStage(num) then
				stageNum = num
				stageEntry = current
				break
			end
		end
		current = current.Parent
	end

	if not stageNum or not stageEntry then
		return nil, nil
	end

	if stageEntry:IsA("BasePart") then
		return stageNum, stageEntry
	end

	local gatePart = stageEntry:FindFirstChildWhichIsA("BasePart", true)
	if gatePart then
		return stageNum, gatePart
	end
	return stageNum, nil
end

function StageCheckpointWorld.isCheckpointHit(part: Instance): boolean
	local stageNum = StageCheckpointWorld.getCheckpointFromHit(part)
	return stageNum ~= nil
end

function StageCheckpointWorld.getStageEntryFromPart(part: Instance): (number?, Instance?)
	local folder = StageCheckpointWorld.getFolder()
	if not folder then
		return nil, nil
	end

	local current: Instance? = part
	while current and current ~= folder do
		if current.Parent == folder then
			local stageNum = tonumber(current.Name)
			if stageNum and StageCheckpointWorld.isMeltGateStage(stageNum) then
				return stageNum, current
			end
		end
		current = current.Parent
	end
	return nil, nil
end

--- Spawn pads under each stage entry (SkipStageService) — not real flight floor while gliding.
function StageCheckpointWorld.isCheckpointSpawnPart(part: Instance): boolean
	local _, entry = StageCheckpointWorld.getStageEntryFromPart(part)
	if not entry then
		return false
	end

	local current: Instance? = part
	while current and current ~= entry do
		if current.Name == "Spawn" and current:IsA("BasePart") then
			return true
		end
		current = current.Parent
	end
	return part.Name == "Spawn" and part:IsA("BasePart")
end

function StageCheckpointWorld.getFlightProbeFolder(): Instance?
	return StageCheckpointWorld.getFolder()
end

function StageCheckpointWorld.getBarProgressFrame(gatePart: BasePart): Frame?
	local paths = StageCheckpointConfigs.UiPaths
	local xp = gatePart:FindFirstChild(paths.SurfaceGui)
	if not xp or not xp:IsA("SurfaceGui") then
		return nil
	end
	local wrapper = xp:FindFirstChild(paths.Wrapper)
	if not wrapper then
		return nil
	end
	local bar = wrapper:FindFirstChild(paths.Bar)
	if not bar then
		return nil
	end
	local progress = bar:FindFirstChild(paths.Progress)
	if progress and progress:IsA("Frame") then
		return progress
	end
	return nil
end

function StageCheckpointWorld.readRequirement(gatePart: BasePart): number?
	local paths = StageCheckpointConfigs.UiPaths
	local xp = gatePart:FindFirstChild(paths.SurfaceGui)
	if not xp then
		return nil
	end
	local wrapper = xp:FindFirstChild(paths.Wrapper)
	if not wrapper then
		return nil
	end
	local bar = wrapper:FindFirstChild(paths.Bar)
	if not bar then
		return nil
	end
	local requirement = bar:FindFirstChild(paths.Requirement)
	if requirement and requirement:IsA("TextLabel") then
		return parseRequirementText(requirement.Text)
	end
	return nil
end

function StageCheckpointWorld.getRequirementLabel(gatePart: BasePart): TextLabel?
	local paths = StageCheckpointConfigs.UiPaths
	local xp = gatePart:FindFirstChild(paths.SurfaceGui)
	if not xp then
		return nil
	end
	local wrapper = xp:FindFirstChild(paths.Wrapper)
	if not wrapper then
		return nil
	end
	local bar = wrapper:FindFirstChild(paths.Bar)
	if not bar then
		return nil
	end
	local requirement = bar:FindFirstChild(paths.Requirement)
	if requirement and requirement:IsA("TextLabel") then
		return requirement
	end
	return nil
end

function StageCheckpointWorld.formatRequirementText(requirement: number): string
	return "Min " .. tostring(math.floor(requirement))
end

function StageCheckpointWorld.applyGateUi(gatePart: BasePart, requirement: number, hp01: number, logContext: string?)
	local reqLabel = StageCheckpointWorld.getRequirementLabel(gatePart)
	if reqLabel then
		reqLabel.Text = StageCheckpointWorld.formatRequirementText(requirement)
	end
	local progress = StageCheckpointWorld.getBarProgressFrame(gatePart)
	local clamped = math.clamp(hp01, 0, 1)
	if progress then
		progress.Size = UDim2.new(clamped, 0, 1, 0)
	end

	if logContext and StageCheckpointConfigs.Debug then
		local xp = gatePart:FindFirstChild(StageCheckpointConfigs.UiPaths.SurfaceGui)
		local xpEnabled = if xp and xp:IsA("SurfaceGui") then xp.Enabled else "noXP"
		local progressSize = if progress then tostring(progress.Size) else "noProgressFrame"
		StageCheckpointDebug.logAlways(string.format(
			"[BarUI] %s stage=%s req=%d hp=%.2f (%s) XP.Enabled=%s Progress.Size=%s part=%s",
			logContext,
			gatePart.Name,
			requirement,
			clamped,
			if clamped >= 0.99 then "FULL" elseif clamped <= 0.01 then "EMPTY" else "PARTIAL",
			tostring(xpEnabled),
			progressSize,
			gatePart:GetFullName()
		))
	end
end

function StageCheckpointWorld.getNextMeltGateStage(currentStage: number): number?
	local nextStage = currentStage + 1
	if nextStage > StageCheckpointConfigs.MaxGateStage then
		return nil
	end
	return nextStage
end

function StageCheckpointWorld.restoreGatePartLockedVisual(
	gatePart: BasePart,
	requirement: number?,
	hp01: number?,
	logContext: string?
)
	gatePart.LocalTransparencyModifier = 0
	StageCheckpointWorld.setGateInteractionEnabled(gatePart, true)
	StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
	if requirement and requirement > 0 then
		StageCheckpointWorld.applyGateUi(gatePart, requirement, hp01 or 1, logContext or "RestoreLockedVisual")
	end
end

function StageCheckpointWorld.setGateInteractionEnabled(gatePart: BasePart, enabled: boolean)
	gatePart.CanQuery = enabled
	gatePart.CanCollide = enabled
	gatePart.CanTouch = false
end

function StageCheckpointWorld.setXpOverlayEnabled(gatePart: BasePart, enabled: boolean)
	local xp = gatePart:FindFirstChild(StageCheckpointConfigs.UiPaths.SurfaceGui)
	if xp and xp:IsA("SurfaceGui") then
		xp.Enabled = enabled
	end
end

function StageCheckpointWorld.ensureXpOverlayEnabled(gatePart: BasePart)
	StageCheckpointWorld.setXpOverlayEnabled(gatePart, true)
end

function StageCheckpointWorld.disableXpOverlay(gatePart: BasePart)
	StageCheckpointWorld.setXpOverlayEnabled(gatePart, false)
end

function StageCheckpointWorld.applyGateVisualState(
	gatePart: BasePart,
	requirement: number,
	state: "broken" | "active" | "future",
	hp01Override: number?,
	logContext: string
)
	if state == "broken" then
		StageCheckpointWorld.applyGateUi(gatePart, requirement, 0, logContext .. " → BROKEN (beam cleared)")
		StageCheckpointWorld.disableXpOverlay(gatePart)
		StageCheckpointWorld.setGateInteractionEnabled(gatePart, false)
		gatePart.LocalTransparencyModifier = 1
	elseif state == "active" then
		StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
		StageCheckpointWorld.setGateInteractionEnabled(gatePart, true)
		local hp01 = if hp01Override ~= nil then hp01Override else 1
		StageCheckpointWorld.applyGateUi(gatePart, requirement, hp01, logContext .. " → ACTIVE melt with F")
		gatePart.LocalTransparencyModifier = 0
	else
		StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
		StageCheckpointWorld.setGateInteractionEnabled(gatePart, true)
		StageCheckpointWorld.applyGateUi(gatePart, requirement, 1, logContext .. " → LOCKED (melt previous gates first)")
		gatePart.LocalTransparencyModifier = 0
	end
end

-- Deprecated: session gates use applyGateVisualState with broken/active/future.
function StageCheckpointWorld.applyGateVisualForProgress(
	gatePart: BasePart,
	_stageNum: number,
	_currentStage: number,
	requirement: number,
	hp01Override: number?,
	logContext: string
)
	StageCheckpointWorld.applyGateVisualState(gatePart, requirement, "active", hp01Override, logContext)
end

function StageCheckpointWorld.getCachedRequirement(stageNum: number): number?
	return requirementCache[stageNum]
end

function StageCheckpointWorld.getGateCollisionGroupName(stageNum: number): string
	return StageCheckpointConfigs.CollisionGroup.GatePrefix .. tostring(stageNum)
end

function StageCheckpointWorld.prepareGateParts(): { [number]: BasePart }
	local prepared: { [number]: BasePart } = {}
	local folder = StageCheckpointWorld.getFolder()
	if not folder then
		warn("[StageCheckpointWorld] StageCheckpoints folder not found")
		return prepared
	end

	for _, child in folder:GetChildren() do
		local stageNum = tonumber(child.Name)
		if not stageNum or not StageCheckpointWorld.isMeltGateStage(stageNum) then
			continue
		end

		local gatePart: BasePart? = nil
		if child:IsA("BasePart") then
			gatePart = child :: BasePart
		else
			gatePart = child:FindFirstChildWhichIsA("BasePart", true)
		end
		if not gatePart then
			warn("[StageCheckpointWorld] No BasePart under stage", stageNum)
			continue
		end

		for _, desc in child:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanTouch = false
			end
		end
		gatePart.CanQuery = true
		gatePart.CanTouch = false
		gatePart.CollisionGroup = StageCheckpointWorld.getGateCollisionGroupName(stageNum)

		local requirement = StageCheckpointWorld.resolveRequirement(gatePart, stageNum)
		local usedDefault = StageCheckpointWorld.readRequirement(gatePart) == nil
		if requirement and requirement > 0 then
			requirementCache[stageNum] = requirement
			gatePart:SetAttribute(StageCheckpointConfigs.RequirementAttribute, requirement)
			if StageCheckpointWorld.hasGateUi(gatePart) then
				StageCheckpointWorld.ensureXpOverlayEnabled(gatePart)
				StageCheckpointWorld.applyGateUi(gatePart, requirement, 1, "ServerPrepare")
			else
				StageCheckpointDebug.logAlways(string.format(
					"Gate stage=%d MISSING XP UI — copy %s from gate 1 (needs Wrapper/Bar/Progress/Requirement)",
					stageNum,
					StageCheckpointConfigs.UiPaths.SurfaceGui
				))
			end
			if usedDefault then
				StageCheckpointDebug.logAlways(string.format(
					"Gate stage=%d using fallback requirement %d (add XP/Bar/Requirement label in Studio)",
					stageNum,
					requirement
				))
			end
		else
			warn("[StageCheckpointWorld] Missing Requirement on stage", stageNum)
		end

		gatePart.CanCollide = true
		prepared[stageNum] = gatePart
		StageCheckpointDebug.logAlways(string.format(
			"Prepared gate stage=%d req=%s CanQuery=%s CanCollide=%s group=%s label=%s progress=%s",
			stageNum,
			tostring(requirement),
			tostring(gatePart.CanQuery),
			tostring(gatePart.CanCollide),
			gatePart.CollisionGroup,
			tostring(StageCheckpointWorld.getRequirementLabel(gatePart) and StageCheckpointWorld.getRequirementLabel(gatePart).Text),
			tostring(StageCheckpointWorld.getBarProgressFrame(gatePart) and StageCheckpointWorld.getBarProgressFrame(gatePart).Size)
		))
	end

	return prepared
end

function StageCheckpointWorld.getFolderGateStageNumbers(): { number }
	local stages: { number } = {}
	local folder = StageCheckpointWorld.getFolder()
	if not folder then
		return stages
	end
	for _, child in folder:GetChildren() do
		local stageNum = tonumber(child.Name)
		if stageNum and StageCheckpointWorld.isMeltGateStage(stageNum) then
			table.insert(stages, stageNum)
		end
	end
	table.sort(stages)
	return stages
end

function StageCheckpointWorld.hasGateUi(gatePart: BasePart): boolean
	return StageCheckpointWorld.getBarProgressFrame(gatePart) ~= nil
end

function StageCheckpointWorld.resolveRequirement(gatePart: BasePart, stageNum: number): number?
	local fromConfig = StageCheckpointConfigs.GetGateSpeedRequirement(stageNum)
	if fromConfig then
		return fromConfig
	end

	local requirement = StageCheckpointWorld.readRequirement(gatePart)
	if requirement and requirement > 0 then
		return requirement
	end
	if stageNum == StageCheckpointConfigs.FirstGateStage then
		local defaultReq = StageCheckpointConfigs.DefaultMinSpeedXp
		if type(defaultReq) == "number" and defaultReq > 0 then
			return defaultReq
		end
	end
	return nil
end

function StageCheckpointWorld.getAllStageNumbers(): { number }
	local stages: { number } = {}
	for stageNum in requirementCache do
		table.insert(stages, stageNum)
	end
	table.sort(stages)
	return stages
end

function StageCheckpointWorld.getAllGateStageNumbers(): { number }
	return StageCheckpointWorld.getFolderGateStageNumbers()
end

function StageCheckpointWorld.getLocalGateStageNumbers(): { number }
	return StageCheckpointWorld.getFolderGateStageNumbers()
end

function StageCheckpointWorld.describeLocalGate(stageNum: number): string
	local gatePart = StageCheckpointWorld.getGatePart(stageNum)
	if not gatePart then
		return string.format("stage=%d MISSING", stageNum)
	end
	local attr = gatePart:GetAttribute(StageCheckpointConfigs.RequirementAttribute)
	local label = StageCheckpointWorld.getRequirementLabel(gatePart)
	local labelText = if label then label.Text else "nil"
	local hasBar = StageCheckpointWorld.getBarProgressFrame(gatePart) ~= nil
	return string.format(
		"stage=%d attr=%s label=%s CanQuery=%s CanCollide=%s hasBar=%s",
		stageNum,
		tostring(attr),
		labelText,
		tostring(gatePart.CanQuery),
		tostring(gatePart.CanCollide),
		tostring(hasBar)
	)
end

return StageCheckpointWorld
