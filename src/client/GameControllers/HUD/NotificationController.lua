--!strict

-- Top HUD toasts under Skip Stage (GUI.Frames.Notifications).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationConfigs = require(ReplicatedStorage.Shared.Configs.NotificationConfigs)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local NotificationController = Knit.CreateController({ Name = "NotificationController" })

local TOAST_LIFETIME = 2.8
local MAX_TOASTS = 5
local DEBOUNCE_SEC = 0.35
-- Fallback gap below Skip Stage (scale) — used only before the JumpCounter pill is built.
local SKIP_GAP_SCALE = 0.072
-- Pixel gap below the JumpCounter pill. The pill's height is in PIXELS and doesn't scale with
-- the screen, so we anchor to its real bottom in pixels too; a scale-only gap rides up into it
-- on short mobile screens (the overlap this fixes).
local NOTIF_GAP_PX = 12

local toastContainer: Frame? = nil
local hudRef: Instance? = nil
local listLayout: UIListLayout? = nil
local activeToasts: { Frame } = {}

local lastMessage = ""
local lastShownAt = -math.huge
local lastCooldownRejectAt = -math.huge

local COLORS = {
	Success = {
		bg = Color3.fromRGB(28, 72, 48),
		stroke = Color3.fromRGB(90, 255, 150),
		text = Color3.fromRGB(210, 255, 220),
	},
	Error = {
		bg = Color3.fromRGB(72, 28, 28),
		stroke = Color3.fromRGB(255, 120, 90),
		text = Color3.fromRGB(255, 220, 200),
	},
	Info = {
		bg = Color3.fromRGB(28, 48, 72),
		stroke = Color3.fromRGB(120, 180, 255),
		text = Color3.fromRGB(210, 230, 255),
	},
}

-- Anchor the toast container just below the JumpCounter pill when it exists (top anchor, so
-- toasts grow downward from there). Anchored to the pill's REAL rendered bottom in pixels,
-- because the pill is pixel-sized; a scale-only gap below Skip Stage rides up into it on short
-- mobile screens. Falls back to the skip-relative scale gap before the pill is built, so this
-- is re-run on each toast (by then the pill exists).
local function repositionNotifications(hud: Instance, notifications: Frame)
	notifications.AnchorPoint = Vector2.new(0.5, 0)
	notifications.BackgroundTransparency = 1
	notifications.Size = UDim2.new(0.9, 0, 0, 0)
	notifications.AutomaticSize = Enum.AutomaticSize.Y

	local frames = notifications.Parent
	local jumpCounter = if frames then frames:FindFirstChild("JumpCounter") else nil
	if
		frames
		and frames:IsA("GuiObject")
		and jumpCounter
		and jumpCounter:IsA("GuiObject")
		and frames.AbsoluteSize.Y > 0
	then
		local jc = jumpCounter :: GuiObject
		local bottom = jc.AbsolutePosition.Y + jc.AbsoluteSize.Y
		local y = (bottom + NOTIF_GAP_PX - (frames :: GuiObject).AbsolutePosition.Y) / (frames :: GuiObject).AbsoluteSize.Y
		notifications.Position = UDim2.new(0.5, 0, y, 0)
		return
	end

	local skip = hud:FindFirstChild("Skipstage")
	if skip and skip:IsA("GuiObject") then
		local y = skip.Position.Y.Scale + skip.Size.Y.Scale + SKIP_GAP_SCALE
		notifications.Position = UDim2.new(0.5, 0, y, 0)
	end
end

local function pruneToasts()
	while #activeToasts > MAX_TOASTS do
		local oldest = table.remove(activeToasts, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
end

local function showToast(message: string, kind: string?)
	local now = os.clock()
	if message == lastMessage and now - lastShownAt < DEBOUNCE_SEC then
		return
	end
	lastMessage = message
	lastShownAt = now

	local parent = toastContainer
	if not parent then
		return
	end

	-- Re-anchor below the JumpCounter (built after us) right before the toast appears.
	if hudRef then
		repositionNotifications(hudRef, parent)
	end

	local palette = COLORS[kind :: string] or COLORS.Info

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = palette.bg
	toast.BackgroundTransparency = 0.15
	toast.BorderSizePixel = 0
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Size = UDim2.new(1, -24, 0, 0)
	toast.ZIndex = 20

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.stroke
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = toast

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = toast

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextWrapped = true
	label.TextColor3 = palette.text
	label.TextStrokeTransparency = 0.6
	label.Text = message
	label.ZIndex = 21
	label.Parent = toast

	toast.Parent = parent
	table.insert(activeToasts, toast)
	pruneToasts()

	task.delay(TOAST_LIFETIME * 0.65, function()
		if not toast.Parent then
			return
		end
		local fade = TweenInfo.new(TOAST_LIFETIME * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)

	task.delay(TOAST_LIFETIME, function()
		local idx = table.find(activeToasts, toast)
		if idx then
			table.remove(activeToasts, idx)
		end
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

local function showReject(reason: string, detail: number?)
	if reason == "cooldown" then
		local now = os.clock()
		local debounce = NotificationConfigs.CooldownToastDebounceSeconds or 10
		if now - lastCooldownRejectAt < debounce then
			return
		end
		lastCooldownRejectAt = now
	end
	local message = NotificationConfigs.GetMessage(reason, detail)
	local kind = NotificationConfigs.GetKind(reason)
	NotificationManager.show(message, kind)
end

function NotificationController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] NotificationController: GUI not found.")
		return
	end

	local frames = gui:WaitForChild("Frames", 30)
	local notifications = frames and frames:WaitForChild("Notifications", 30)
	if not notifications or not notifications:IsA("Frame") then
		warn("[iseesupes] NotificationController: GUI.Frames.Notifications missing.")
		return
	end

	local hud = gui:WaitForChild("HUD", 30)
	if hud then
		hudRef = hud
		repositionNotifications(hud, notifications)
	end

	listLayout = notifications:FindFirstChild("List") :: UIListLayout?
	if listLayout then
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 6)
	end

	toastContainer = notifications
	notifications.Visible = true

	NotificationManager.OnShow:Connect(showToast)

	local DoubleJumpService = Knit.GetService("DoubleJumpService")
	DoubleJumpService.Rejected:Connect(function(reason: string, detail: number?)
		showReject(reason, detail)
	end)

	StudioLog.ready("NotificationController", "(below Skip Stage)")
end

return NotificationController
