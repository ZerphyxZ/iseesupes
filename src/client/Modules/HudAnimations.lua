--!strict

local TweenService = game:GetService("TweenService")

local HudAnimations = {}

local SCALE_KEY = "_HudBaseScale"
local SIZE_KEY = "_HudBaseSize"

local baseSizes: { [GuiObject]: UDim2 } = {}
local activeFrameTweens: { [GuiObject]: Tween } = {}

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

function HudAnimations.buttonPress(button: GuiButton, onComplete: (() -> ())?)
	HudAnimations.rememberBaseScale(button)
	local uiScale = getOrCreateUIScale(button)
	local base = button:GetAttribute(SCALE_KEY) :: number? or 1

	local press = TweenService:Create(uiScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = base * 0.92,
	})
	local release = TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = base,
	})

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
		end
	end)
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
