--!strict

-- Spidey-style +Speed / +Thrust bursts from screen centre (spread upward/sideways, no overlap pile-up).
-- Win gains: thin icons fly from centre to HUD Wins frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HudAnimations = require(script.Parent.HudAnimations)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local EffectsSystem = {}

local POPUP_LIFETIME = 1.1
local POPUP_TRAVEL_PX = 280
local START_OFFSET_PX = 72
local LANE_SPREAD_PX = 38
local DIRECTION_SLOTS = 5
local COMBINE_WINDOW = 0.2

type BurstPopupLayout = {
	iconPx: number,
	textSize: number,
	textWidth: number,
	popupHeight: number,
}

local function getBurstPopupLayout(hasGainIcon: boolean): BurstPopupLayout
	local cfg = SpeedConfigs
	local iconPx: number
	local textSize: number
	local textWidth: number

	if ClientPerformance.isLowEnd() then
		iconPx = if hasGainIcon then cfg.GainPopupIconPxLowEnd else 0
		textSize = if hasGainIcon then cfg.GainPopupTextSizeLowEnd else cfg.GainPopupTextSizeMobile
		textWidth = cfg.GainPopupTextWidthLowEnd
	elseif ClientPerformance.isMobile() then
		iconPx = if hasGainIcon then cfg.GainPopupIconPxMobile else 0
		textSize = cfg.GainPopupTextSizeMobile
		textWidth = cfg.GainPopupTextWidthMobile
	else
		iconPx = if hasGainIcon then cfg.GainPopupIconPx else 0
		textSize = cfg.GainPopupTextSize
		textWidth = cfg.GainPopupTextWidth
	end

	local popupHeight = iconPx + 12
	return {
		iconPx = iconPx,
		textSize = textSize,
		textWidth = textWidth,
		popupHeight = popupHeight,
	}
end

local speedDirectionSlot = 0
local thrustDirectionSlot = 0

local effectsGui: ScreenGui? = nil

type BurstKind = "Speed" | "Thrust" | "Wins"

type PendingBurst = {
	total: number,
	flushThread: thread?,
}

local pendingByKind: { [BurstKind]: PendingBurst } = {
	Speed = { total = 0 },
	Thrust = { total = 0 },
	Wins = { total = 0 },
}

local function getEffectsLayer(): ScreenGui?
	if effectsGui and effectsGui.Parent then
		return effectsGui
	end

	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local existing = playerGui:FindFirstChild("EffectPopups")
	if existing and existing:IsA("ScreenGui") then
		effectsGui = existing
		return effectsGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "EffectPopups"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	effectsGui = gui
	return gui
end

local function formatGain(amount: number): string
	return "+" .. NumberFormatter.Format(math.floor(amount + 0.5))
end

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, seg in segments do
		local child = current:FindFirstChild(seg)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function resolvePathWithWait(root: Instance, segments: { string }, timeoutPerSegment: number): Instance?
	local current: Instance = root
	for _, seg in segments do
		local child = current:FindFirstChild(seg)
		if not child then
			child = current:WaitForChild(seg, timeoutPerSegment)
		end
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function getWinCollectCfg()
	return HudConfigs.WinCollectEffect
end

local WIN_FRAME_WAIT_SEC = 2

local function resolveWinsFrame(): GuiObject?
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	local cfg = getWinCollectCfg()
	local path = cfg.WinsFramePath or { "GUI", "HUD", "Left", "Wins" }
	local inst = resolvePathWithWait(playerGui, path, WIN_FRAME_WAIT_SEC)
	if inst and inst:IsA("GuiObject") then
		return inst
	end
	return nil
end

local function getScreenCenter(): Vector2
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize * 0.5
	end
	return Vector2.new(960, 540)
end

local function getFrameScreenCenter(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize * 0.5
end

type WinCollectIconLayout = {
	width: number,
	height: number,
	scaleType: Enum.ScaleType,
	image: string,
}

local function resolveWinsHudIcon(winsFrame: GuiObject): ImageLabel?
	local cfg = getWinCollectCfg()
	local iconName = cfg.HudIconName or "Icon"
	local named = winsFrame:FindFirstChild(iconName)
	if named and named:IsA("ImageLabel") then
		return named
	end
	local targetImage = cfg.IconImage
	if typeof(targetImage) == "string" and targetImage ~= "" then
		for _, desc in winsFrame:GetDescendants() do
			if desc:IsA("ImageLabel") and desc.Image == targetImage then
				return desc
			end
		end
	end
	return nil
end

local function getFallbackWinIconPx(cfg: typeof(HudConfigs.WinCollectEffect)): number
	if ClientPerformance.isLowEnd() then
		return cfg.IconPxLowEnd or 40
	end
	if ClientPerformance.isMobile() then
		return cfg.IconPxMobile or 48
	end
	return cfg.IconPx or 56
end

local function ensureHudLayoutReady(_winsFrame: GuiObject)
	RunService.RenderStepped:Wait()
end

local function getWinCollectIconLayout(winsFrame: GuiObject): WinCollectIconLayout
	local cfg = getWinCollectCfg()
	local fallbackPx = getFallbackWinIconPx(cfg)
	local fallback: WinCollectIconLayout = {
		width = fallbackPx,
		height = fallbackPx,
		scaleType = cfg.ScaleType or Enum.ScaleType.Fit,
		image = cfg.IconImage or "",
	}

	if cfg.MatchHudIconSize == false then
		return fallback
	end

	ensureHudLayoutReady(winsFrame)

	local hudIcon = resolveWinsHudIcon(winsFrame)
	if not hudIcon then
		return fallback
	end

	local sz = hudIcon.AbsoluteSize
	if sz.X <= 4 or sz.Y <= 4 then
		return fallback
	end

	return {
		width = sz.X,
		height = sz.Y,
		scaleType = hudIcon.ScaleType,
		image = if hudIcon.Image ~= "" then hudIcon.Image else (cfg.IconImage or ""),
	}
end

local function getWinCollectTargetCenter(winsFrame: GuiObject): Vector2
	ensureHudLayoutReady(winsFrame)
	local hudIcon = resolveWinsHudIcon(winsFrame)
	if hudIcon and hudIcon.AbsoluteSize.X > 4 and hudIcon.AbsoluteSize.Y > 4 then
		return getFrameScreenCenter(hudIcon)
	end
	return getFrameScreenCenter(winsFrame)
end

local function pixelPosition(pos: Vector2): UDim2
	return UDim2.fromOffset(pos.X, pos.Y)
end

local function randomSpawnOffset(spreadPx: number): Vector2
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random()) * spreadPx
	local x = math.cos(angle) * dist
	local y = math.sin(angle) * dist * 0.65 - spreadPx * 0.12
	return Vector2.new(x, y)
end

local function spawnWinRemainderLabel(parent: ScreenGui, winsFrame: GuiObject, totalGain: number, cfg: typeof(HudConfigs.WinCollectEffect))
	local remainder = totalGain - (cfg.MaxVisibleIcons or 12)
	if remainder <= 0 then
		return
	end

	local target = getFrameScreenCenter(winsFrame) + Vector2.new(0, -28)
	local label = Instance.new("TextLabel")
	label.Name = "WinRemainder"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = pixelPosition(target)
	label.Size = UDim2.fromOffset(120, 32)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 220, 80)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.15
	label.Text = formatGain(remainder)
	label.ZIndex = 80
	label.Parent = parent

	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, fade, {
		Position = pixelPosition(target + Vector2.new(0, -18)),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.4, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local function spawnWinCollectIcon(
	parent: ScreenGui,
	index: number,
	totalVisible: number,
	totalGain: number,
	winsFrame: GuiObject,
	cfg: typeof(HudConfigs.WinCollectEffect)
)
	if not winsFrame.Parent then
		return
	end

	local layout = getWinCollectIconLayout(winsFrame)
	local targetCenter = getWinCollectTargetCenter(winsFrame)

	local spread = cfg.SpawnSpreadPx or 140
	local flyDuration = cfg.FlyDuration or 0.42
	local popInDuration = cfg.PopInDuration or 0.16
	local arrivalDuration = cfg.ArrivalPopDuration or 0.12
	local isLast = index == totalVisible

	local startCenter = getScreenCenter() + randomSpawnOffset(spread)

	local icon = Instance.new("ImageLabel")
	icon.Name = "WinCollectIcon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = pixelPosition(startCenter)
	icon.Size = UDim2.fromOffset(layout.width, layout.height)
	icon.Image = layout.image
	icon.ScaleType = layout.scaleType
	icon.ZIndex = 60 + index
	icon.Parent = parent

	local popScale = Instance.new("UIScale")
	popScale.Scale = 0
	popScale.Parent = icon

	local popIn = TweenInfo.new(popInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(popScale, popIn, { Scale = 1.15 }):Play()
	task.delay(popInDuration, function()
		if popScale.Parent then
			TweenService:Create(
				popScale,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end)

	task.delay(popInDuration * 0.85, function()
		if not icon.Parent then
			return
		end

		local flyInfo = TweenInfo.new(flyDuration, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local flyTween = TweenService:Create(icon, flyInfo, { Position = pixelPosition(targetCenter) })
		flyTween:Play()
		flyTween.Completed:Connect(function(state)
			if state ~= Enum.PlaybackState.Completed or not icon.Parent then
				return
			end

			local arrivalPop = TweenInfo.new(arrivalDuration * 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local shrink = TweenInfo.new(arrivalDuration * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(popScale, arrivalPop, { Scale = 1.28 }):Play()
			TweenService:Create(icon, shrink, { ImageTransparency = 1 }):Play()
			task.delay(arrivalDuration * 0.45, function()
				if popScale.Parent then
					TweenService:Create(popScale, shrink, { Scale = 0 }):Play()
				end
			end)

			if isLast then
				local pulseScale = cfg.FinalPulseScale or 1.18
				HudAnimations.pulse(winsFrame, pulseScale, 0.32)
				if totalGain > totalVisible then
					spawnWinRemainderLabel(parent, winsFrame, totalGain, cfg)
				end
			end

			task.delay(arrivalDuration + 0.02, function()
				if icon.Parent then
					icon:Destroy()
				end
			end)
		end)
	end)
end

local function spawnWinCollectEffect(gain: number)
	if gain <= 0 then
		return
	end

	local parent = getEffectsLayer()
	if not parent then
		return
	end

	local winsFrame = resolveWinsFrame()
	if not winsFrame then
		return
	end

	local cfg = getWinCollectCfg()
	local maxVisible = cfg.MaxVisibleIcons or 12
	local totalGain = math.floor(gain + 0.5)
	local visible = math.min(totalGain, maxVisible)
	if visible <= 0 then
		return
	end

	local stagger = cfg.StaggerDelay or 0.055
	for i = 1, visible do
		local delay = (i - 1) * stagger
		task.delay(delay, function()
			if parent.Parent and winsFrame.Parent then
				spawnWinCollectIcon(parent, i, visible, totalGain, winsFrame, cfg)
			end
		end)
	end
end

--- Upper arc only (left → up → right). Screen Y+ is down.
local ARC_START = math.pi + 0.15
local ARC_END = math.pi * 2 - 0.15

local function nextDirection(slotCounter: number): (Vector2, number)
	local slot = (slotCounter % DIRECTION_SLOTS) + 1
	local t = if DIRECTION_SLOTS > 1 then (slot - 1) / (DIRECTION_SLOTS - 1) else 0.5
	local angle = ARC_START + (ARC_END - ARC_START) * t
	local dir = Vector2.new(math.cos(angle), math.sin(angle))
	if dir.Y > 0 then
		dir = Vector2.new(dir.X, -math.abs(dir.Y))
	end
	if dir.Magnitude < 0.001 then
		dir = Vector2.new(0, -1)
	else
		dir = dir.Unit
	end
	return dir, slot
end

local function spawnBurstPopup(kind: BurstKind, gain: number)
	if gain <= 0 then
		return
	end

	local parent = getEffectsLayer()
	if not parent then
		return
	end

	local dir: Vector2
	local slot: number
	if kind == "Thrust" then
		dir, thrustDirectionSlot = nextDirection(thrustDirectionSlot)
		slot = thrustDirectionSlot
	else
		dir, speedDirectionSlot = nextDirection(speedDirectionSlot)
		slot = speedDirectionSlot
	end

	local perp = Vector2.new(-dir.Y, dir.X)
	local laneIndex = slot - (DIRECTION_SLOTS + 1) * 0.5
	local startOffset = dir * START_OFFSET_PX + perp * (laneIndex * LANE_SPREAD_PX)

	local textColor: Color3
	local iconImage: string?
	local iconScaleType = Enum.ScaleType.Fit
	if kind == "Thrust" then
		textColor = Color3.fromRGB(255, 140, 100)
		iconImage = SpeedConfigs.ThrustGainPopupImage
		iconScaleType = Enum.ScaleType.Crop
	elseif kind == "Speed" then
		textColor = Color3.fromRGB(90, 255, 140)
		iconImage = SpeedConfigs.SpeedGainPopupImage
	else
		return
	end

	local hasGainIcon = iconImage ~= nil
	local layout = getBurstPopupLayout(hasGainIcon)
	local iconPx = layout.iconPx
	local popupHeight = layout.popupHeight
	local popupWidth = iconPx + 10 + layout.textWidth

	local container = Instance.new("Frame")
	container.Name = "BurstPopup"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.new(0.5, startOffset.X, 0.5, startOffset.Y)
	container.Size = UDim2.fromOffset(popupWidth, popupHeight)
	container.ZIndex = 50 + slot
	container.Parent = parent

	local popScale = Instance.new("UIScale")
	popScale.Scale = 0.6
	popScale.Parent = container

	local textOffsetX = 0
	if iconImage then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
		icon.Position = UDim2.fromOffset(0, math.floor(popupHeight * 0.5))
		icon.Image = iconImage
		icon.ScaleType = iconScaleType
		icon.ZIndex = 51
		icon.Parent = container
		textOffsetX = iconPx + 10
	end

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(textOffsetX, 0)
	label.Size = UDim2.new(1, -textOffsetX, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = layout.textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = textColor
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.15
	label.Text = formatGain(gain)
	label.ZIndex = 52
	label.Parent = container

	local travel = dir * POPUP_TRAVEL_PX
	local endPos = UDim2.new(0.5, startOffset.X + travel.X, 0.5, startOffset.Y + travel.Y)

	local popIn = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(popScale, popIn, { Scale = 1.08 }):Play()
	task.delay(0.18, function()
		if popScale.Parent then
			TweenService
				:Create(popScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end)

	local moveInfo = TweenInfo.new(POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(POPUP_LIFETIME * 0.82, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	TweenService:Create(container, moveInfo, { Position = endPos }):Play()

	for _, inst in container:GetChildren() do
		if inst:IsA("TextLabel") then
			TweenService:Create(inst, fadeInfo, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		elseif inst:IsA("ImageLabel") then
			TweenService:Create(inst, fadeInfo, { ImageTransparency = 1 }):Play()
		end
	end

	task.delay(POPUP_LIFETIME, function()
		if container.Parent then
			container:Destroy()
		end
	end)
end

local function queueBurstPopup(kind: BurstKind, gain: number)
	if gain <= 0 then
		return
	end

	local pending = pendingByKind[kind]
	pending.total += gain

	if pending.flushThread then
		return
	end

	pending.flushThread = task.delay(COMBINE_WINDOW, function()
		pending.flushThread = nil
		local amount = pending.total
		pending.total = 0
		if amount > 0 then
			if kind == "Wins" then
				spawnWinCollectEffect(amount)
			else
				spawnBurstPopup(kind, amount)
			end
		end
	end)
end

function EffectsSystem.ShowSpeedPopUp(gain: number)
	queueBurstPopup("Speed", gain)
end

function EffectsSystem.ShowWinPopUp(gain: number)
	queueBurstPopup("Wins", gain)
end

function EffectsSystem.ShowThrustPopUp(gain: number)
	queueBurstPopup("Thrust", gain)
end

return EffectsSystem
