--!strict

local TweenService = game:GetService("TweenService")

local HudAnimations = {}

local SCALE_KEY = "_HudBaseScale"

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
