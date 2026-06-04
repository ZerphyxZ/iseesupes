--!strict

-- Spidey-style +Speed / +Thrust bursts from screen centre (spread upward/sideways, no overlap pile-up).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)

local EffectsSystem = {}

local SPEED_ICON = "rbxassetid://122922293878122"
local THRUST_ICON = "rbxassetid://118156105091587"

local POPUP_LIFETIME = 1.1
local POPUP_TRAVEL_PX = 280
local START_OFFSET_PX = 72
local LANE_SPREAD_PX = 38
local DIRECTION_SLOTS = 5
local COMBINE_WINDOW = 0.2

local ICON_PX = 108
local TEXT_SIZE = 62
local POPUP_HEIGHT = 118
local POPUP_WIDTH_WITH_ICON = 300
local POPUP_WIDTH_TEXT_ONLY = 200

local speedDirectionSlot = 0
local thrustDirectionSlot = 0
local winDirectionSlot = 0

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
	elseif kind == "Speed" then
		dir, speedDirectionSlot = nextDirection(speedDirectionSlot)
		slot = speedDirectionSlot
	else
		dir, winDirectionSlot = nextDirection(winDirectionSlot)
		slot = winDirectionSlot
	end

	local perp = Vector2.new(-dir.Y, dir.X)
	local laneIndex = slot - (DIRECTION_SLOTS + 1) * 0.5
	local startOffset = dir * START_OFFSET_PX + perp * (laneIndex * LANE_SPREAD_PX)

	local textColor: Color3
	local iconImage: string?
	if kind == "Thrust" then
		textColor = Color3.fromRGB(255, 140, 100)
		iconImage = THRUST_ICON
	elseif kind == "Speed" then
		textColor = Color3.fromRGB(90, 255, 140)
		iconImage = SPEED_ICON
	else
		textColor = Color3.fromRGB(255, 220, 80)
		iconImage = nil
	end

	local container = Instance.new("Frame")
	container.Name = "BurstPopup"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.new(0.5, startOffset.X, 0.5, startOffset.Y)
	container.Size = UDim2.fromOffset(if iconImage then POPUP_WIDTH_WITH_ICON else POPUP_WIDTH_TEXT_ONLY, POPUP_HEIGHT)
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
		icon.Size = UDim2.fromOffset(ICON_PX, ICON_PX)
		icon.Position = UDim2.fromOffset(0, math.floor((POPUP_HEIGHT - ICON_PX) * 0.5))
		icon.Image = iconImage
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 51
		icon.Parent = container
		textOffsetX = ICON_PX + 10
	end

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(textOffsetX, 0)
	label.Size = UDim2.new(1, -textOffsetX, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = TEXT_SIZE
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
			TweenService:Create(popScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
			spawnBurstPopup(kind, amount)
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
