--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)

local HudAnimations = {}

local SCALE_KEY = "_HudBaseScale"
local SIZE_KEY = "_HudBaseSize"

local baseSizes: { [GuiObject]: UDim2 } = {}
local activeFrameTweens: { [GuiObject]: Tween } = {}
local activeScaleTweens: { [GuiObject]: Tween } = {}
local heartbeatGeneration: { [GuiObject]: number } = {}
local activeCountUpConns: { [TextLabel]: RBXScriptConnection } = {}
local buttonHovered: { [GuiButton]: boolean } = {}
local buttonPressed: { [GuiButton]: boolean } = {}
local lastHoverSoundAt = -math.huge

local function getButtonFxCfg()
	return HudConfigs.ButtonEffects
end

local function resolveScaleTarget(gui: GuiObject): GuiObject
	local parentNames = getButtonFxCfg().ScaleTweenParentFrameNames
	if gui:IsA("GuiButton") and typeof(parentNames) == "table" then
		local parent = gui.Parent
		if parent and parent:IsA("GuiObject") and parentNames[parent.Name] == true then
			return parent
		end
	end
	return gui
end

local function getButtonSoundCfg()
	return HudConfigs.ButtonSounds
end

local function playConfiguredButtonSound(kind: "Hover" | "Click")
	local cfg = getButtonSoundCfg()
	local soundId = cfg.SoundId
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end

	if kind == "Hover" then
		local now = os.clock()
		if now - lastHoverSoundAt < (cfg.HoverDebounce or 0.04) then
			return
		end
		lastHoverSoundAt = now
	end

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	if kind == "Hover" then
		sound.Volume = cfg.HoverVolume or 0.42
		sound.PlaybackSpeed = cfg.HoverPlaybackSpeed or 1.06
	else
		sound.Volume = cfg.ClickVolume or 0.58
		sound.PlaybackSpeed = cfg.ClickPlaybackSpeed or 0.94
	end
	sound.Parent = playerGui
	sound:Play()
	Debris:AddItem(sound, 2)
end

function HudAnimations.playButtonHoverSound()
	playConfiguredButtonSound("Hover")
end

function HudAnimations.playButtonClickSound()
	playConfiguredButtonSound("Click")
end

local function getOrCreateUIScale(gui: GuiObject): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = gui
	return scale
end

function HudAnimations.rememberBaseScale(gui: GuiObject)
	local scale = getOrCreateUIScale(gui)
	if gui:GetAttribute(SCALE_KEY) == nil then
		gui:SetAttribute(SCALE_KEY, scale.Scale)
	end
end

local function cancelScaleTween(gui: GuiObject)
	local tween = activeScaleTweens[gui]
	if tween then
		tween:Cancel()
		activeScaleTweens[gui] = nil
	end
end

function HudAnimations.pulse(gui: GuiObject, peakScale: number?, duration: number?)
	HudAnimations.rememberBaseScale(gui)
	local uiScale = getOrCreateUIScale(gui)
	local base = gui:GetAttribute(SCALE_KEY) :: number? or 1
	local peak = peakScale or (base * 1.12)
	local dur = duration or 0.22

	local up = TweenService:Create(uiScale, TweenInfo.new(dur * 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = peak,
	})
	local down = TweenService:Create(uiScale, TweenInfo.new(dur * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = base,
	})
	up:Play()
	up.Completed:Connect(function()
		if gui.Parent then
			down:Play()
		end
	end)
end

function HudAnimations.stopHeartbeat(gui: GuiObject)
	heartbeatGeneration[gui] = (heartbeatGeneration[gui] or 0) + 1
	cancelScaleTween(gui)
	HudAnimations.rememberBaseScale(gui)
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	local base = gui:GetAttribute(SCALE_KEY) :: number? or 1
	if uiScale then
		uiScale.Scale = base
	end
end

function HudAnimations.startHeartbeat(gui: GuiObject, peakScale: number?, periodSeconds: number?)
	HudAnimations.stopHeartbeat(gui)
	HudAnimations.rememberBaseScale(gui)
	local uiScale = getOrCreateUIScale(gui)
	local base = gui:GetAttribute(SCALE_KEY) :: number? or 1
	local peak = peakScale or (base * 1.14)
	local period = periodSeconds or 0.9
	local beatDur = period * 0.22

	local gen = (heartbeatGeneration[gui] or 0) + 1
	heartbeatGeneration[gui] = gen
	task.spawn(function()
		while gui.Parent and heartbeatGeneration[gui] == gen do
			for _ = 1, 2 do
				if not gui.Parent then
					return
				end
				local up = TweenService:Create(
					uiScale,
					TweenInfo.new(beatDur * 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = peak }
				)
				local down = TweenService:Create(
					uiScale,
					TweenInfo.new(beatDur * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = base }
				)
				up:Play()
				up.Completed:Wait()
				if not gui.Parent then
					return
				end
				down:Play()
				down.Completed:Wait()
				task.wait(beatDur * 0.35)
			end
			task.wait(period * 0.35)
		end
	end)
end

function HudAnimations.setButtonScale(button: GuiButton, targetScale: number, duration: number?, easingStyle: Enum.EasingStyle?)
	local target = resolveScaleTarget(button)
	if not target.Parent then
		return
	end
	HudAnimations.rememberBaseScale(target)
	local uiScale = getOrCreateUIScale(target)
	cancelScaleTween(target)
	local dur = duration or 0.12
	local tween = TweenService:Create(
		uiScale,
		TweenInfo.new(dur, easingStyle or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = targetScale }
	)
	activeScaleTweens[target] = tween
	tween:Play()
	tween.Completed:Connect(function()
		if activeScaleTweens[target] == tween then
			activeScaleTweens[target] = nil
		end
	end)
end

local function getBaseScale(button: GuiButton): number
	local target = resolveScaleTarget(button)
	return target:GetAttribute(SCALE_KEY) :: number? or 1
end

function HudAnimations.buttonHoverIn(button: GuiButton)
	local cfg = getButtonFxCfg()
	HudAnimations.setButtonScale(button, getBaseScale(button) * cfg.HoverScale, cfg.HoverDuration)
end

function HudAnimations.buttonHoverOut(button: GuiButton)
	local cfg = getButtonFxCfg()
	if buttonPressed[button] then
		return
	end
	HudAnimations.setButtonScale(button, getBaseScale(button), cfg.HoverDuration)
end

function HudAnimations.buttonPressDown(button: GuiButton)
	local cfg = getButtonFxCfg()
	buttonPressed[button] = true
	HudAnimations.setButtonScale(button, getBaseScale(button) * cfg.PressScale, cfg.PressDuration)
end

function HudAnimations.buttonPressUp(button: GuiButton)
	local cfg = getButtonFxCfg()
	buttonPressed[button] = nil
	if buttonHovered[button] then
		HudAnimations.setButtonScale(
			button,
			getBaseScale(button) * cfg.HoverScale,
			cfg.ReleaseDuration,
			Enum.EasingStyle.Back
		)
	else
		HudAnimations.setButtonScale(button, getBaseScale(button), cfg.ReleaseDuration, Enum.EasingStyle.Back)
	end
end

function HudAnimations.bindButtonSounds(button: GuiButton)
	local cfg = getButtonSoundCfg()
	if button:GetAttribute(cfg.BoundAttribute) == true then
		return
	end
	if not button.Active then
		return
	end

	button:SetAttribute(cfg.BoundAttribute, true)

	button.MouseEnter:Connect(function()
		if button.Active then
			HudAnimations.playButtonHoverSound()
		end
	end)

	button.MouseButton1Down:Connect(function()
		if button.Active then
			HudAnimations.playButtonClickSound()
		end
	end)
end

function HudAnimations.bindButtonEffects(button: GuiButton)
	local cfg = getButtonFxCfg()
	if button:GetAttribute(cfg.BoundAttribute) == true then
		return
	end
	if not button.Active then
		return
	end

	button:SetAttribute(cfg.BoundAttribute, true)
	HudAnimations.rememberBaseScale(resolveScaleTarget(button))

	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		buttonHovered[button] = true
		if not buttonPressed[button] then
			HudAnimations.buttonHoverIn(button)
		end
	end)

	button.MouseLeave:Connect(function()
		buttonHovered[button] = nil
		buttonPressed[button] = nil
		HudAnimations.buttonHoverOut(button)
	end)

	button.MouseButton1Down:Connect(function()
		if not button.Active then
			return
		end
		HudAnimations.buttonPressDown(button)
	end)

	button.MouseButton1Up:Connect(function()
		HudAnimations.buttonPressUp(button)
	end)
end

function HudAnimations.buttonPress(button: GuiButton, onComplete: (() -> ())?)
	local cfg = getButtonFxCfg()
	local target = resolveScaleTarget(button)
	HudAnimations.rememberBaseScale(target)
	local uiScale = getOrCreateUIScale(target)
	local base = getBaseScale(button)

	cancelScaleTween(target)
	local press = TweenService:Create(
		uiScale,
		TweenInfo.new(cfg.PressDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = base * cfg.PressScale }
	)
	local release = TweenService:Create(
		uiScale,
		TweenInfo.new(cfg.ReleaseDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = base }
	)

	press:Play()
	press.Completed:Connect(function()
		release:Play()
		if onComplete then
			onComplete()
		end
	end)
end

function HudAnimations.fadeIn(gui: GuiObject, duration: number?)
	if not gui:IsA("GuiObject") then
		return
	end
	local startTransparency = gui.BackgroundTransparency
	gui.BackgroundTransparency = 1
	gui.Visible = true
	TweenService:Create(gui, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = startTransparency,
	}):Play()
end

function HudAnimations.slideIn(gui: GuiObject, offsetY: number?, duration: number?)
	if not gui:IsA("GuiObject") then
		return
	end
	local basePos = gui.Position
	gui.Position = basePos + UDim2.new(0, 0, 0, offsetY or 12)
	gui.Visible = true
	TweenService:Create(gui, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = basePos,
	}):Play()
end

function HudAnimations.countUpText(
	label: TextLabel,
	fromValue: number,
	toValue: number,
	formatter: (number) -> string,
	duration: number?
)
	local prior = activeCountUpConns[label]
	if prior then
		prior:Disconnect()
		activeCountUpConns[label] = nil
	end

	if fromValue == toValue then
		label.Text = formatter(toValue)
		return
	end

	local dur = duration or 0.35
	local start = os.clock()
	local conn: RBXScriptConnection?
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - start) / dur, 0, 1)
		local eased = 1 - (1 - t) ^ 3
		local current = math.floor(fromValue + (toValue - fromValue) * eased + 0.5)
		label.Text = formatter(current)
		if t >= 1 then
			label.Text = formatter(toValue)
			if conn then
				conn:Disconnect()
			end
			if activeCountUpConns[label] == conn then
				activeCountUpConns[label] = nil
			end
		end
	end)
	activeCountUpConns[label] = conn
end

function HudAnimations.rememberBaseSize(gui: GuiObject)
	if not baseSizes[gui] then
		baseSizes[gui] = gui.Size
	end
end

local function cancelFrameTween(gui: GuiObject)
	local tween = activeFrameTweens[gui]
	if tween then
		tween:Cancel()
		activeFrameTweens[gui] = nil
	end
end

local function collapsedSizeY(target: UDim2): UDim2
	return UDim2.new(target.X.Scale, target.X.Offset, 0, 0)
end

function HudAnimations.openFrameY(gui: GuiObject, duration: number?, onComplete: (() -> ())?)
	if not gui:IsA("GuiObject") then
		return
	end

	HudAnimations.rememberBaseSize(gui)
	cancelFrameTween(gui)

	local target = baseSizes[gui] :: UDim2
	local dur = duration or 0.35
	gui.Size = collapsedSizeY(target)
	gui.Visible = true

	local tween = TweenService:Create(
		gui,
		TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = target }
	)
	activeFrameTweens[gui] = tween
	tween:Play()
	tween.Completed:Connect(function(state)
		if activeFrameTweens[gui] == tween then
			activeFrameTweens[gui] = nil
		end
		if state == Enum.PlaybackState.Completed and gui.Parent then
			gui.Size = target
			if onComplete then
				onComplete()
			end
		end
	end)
end

function HudAnimations.closeFrameY(gui: GuiObject, duration: number?, onComplete: (() -> ())?)
	if not gui:IsA("GuiObject") then
		return
	end

	HudAnimations.rememberBaseSize(gui)
	cancelFrameTween(gui)

	local target = baseSizes[gui] :: UDim2
	local dur = duration or 0.28
	local collapsed = collapsedSizeY(target)

	local tween = TweenService:Create(
		gui,
		TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = collapsed }
	)
	activeFrameTweens[gui] = tween
	tween:Play()
	tween.Completed:Connect(function(state)
		if activeFrameTweens[gui] == tween then
			activeFrameTweens[gui] = nil
		end
		if state == Enum.PlaybackState.Completed then
			gui.Visible = false
			gui.Size = target
			if onComplete then
				onComplete()
			end
		end
	end)
end

function HudAnimations.highlightTextBox(textBox: TextBox, active: boolean)
	local stroke = textBox:FindFirstChild("_HudStroke") :: UIStroke?
	if active then
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Name = "_HudStroke"
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(255, 200, 80)
			stroke.Parent = textBox
		end
		stroke.Enabled = true
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0 }):Play()
	else
		if stroke then
			local tween = TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 1 })
			tween:Play()
			tween.Completed:Connect(function()
				if stroke and stroke.Transparency >= 0.99 then
					stroke.Enabled = false
				end
			end)
		end
	end
end

return HudAnimations
