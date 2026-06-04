--!strict

-- Top HUD toasts under Skip Stage (GUI.Frames.Notifications).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationConfigs = require(ReplicatedStorage.Shared.Configs.NotificationConfigs)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local NotificationController = Knit.CreateController({ Name = "NotificationController" })

local TOAST_LIFETIME = 2.8
local MAX_TOASTS = 5
local DEBOUNCE_SEC = 0.35
local SKIP_GAP_SCALE = 0.035

local toastContainer: Frame? = nil
local listLayout: UIListLayout? = nil
local activeToasts: { Frame } = {}

local lastMessage = ""
local lastShownAt = -math.huge

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

local function anchorBelowSkipStage(hud: Instance, notifications: Frame)
	local skip = hud:FindFirstChild("Skipstage")
	if skip and skip:IsA("GuiObject") then
		local y = skip.Position.Y.Scale + skip.Size.Y.Scale + SKIP_GAP_SCALE
		notifications.AnchorPoint = Vector2.new(0.5, 0)
		notifications.Position = UDim2.new(0.5, 0, y, 0)
	end
	notifications.BackgroundTransparency = 1
	notifications.Size = UDim2.new(0.9, 0, 0, 0)
	notifications.AutomaticSize = Enum.AutomaticSize.Y
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
		anchorBelowSkipStage(hud, notifications)
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

	print("[iseesupes] NotificationController ready (below Skip Stage).")
end

return NotificationController
