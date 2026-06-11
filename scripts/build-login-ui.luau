-- Builds GUI.Frames.DailyStreak + GUI.Frames.OfflineReward in StarterGui.
-- Style copied from the existing Rewards frame (white panel + gradient +
-- black stroke 3, FredokaOne close X, GothamSSm labels, card grid).
-- Run from Roblox Studio (command bar / MCP execute_luau) in EDIT mode.
-- Idempotent: destroys and rebuilds both frames.

local StarterGui = game:GetService("StarterGui")

local gui = StarterGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")

local GOTHAM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local GOTHAM_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")

local ICON_SPEED = "rbxassetid://111493420189104"
local ICON_WINS = "rbxassetid://126127674350677"
local ICON_GIFT = "rbxassetid://80861029762439"
local ICON_TITLE = "rbxassetid://105401885776857"
local ICON_BOLT = "rbxassetid://118867680307140"
local ICON_CHECK = "rbxassetid://6927295847"

local CARD_GRADIENT = ColorSequence.new(Color3.new(0, 0, 0.498), Color3.new(0.345, 0.824, 1))
local CARD_GRADIENT_GOLD = ColorSequence.new(Color3.new(0.957, 0.353, 1), Color3.new(1, 0.792, 0.161))

local function mk(class: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function addPanelChrome(panel: Frame, gradient: ColorSequence, ratio: number)
	mk("UICorner", { Name = "Corner", CornerRadius = UDim.new(0, 4) }, panel)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0, 0), Thickness = 3 }, panel)
	mk("UIGradient", { Name = "Gradient", Color = gradient, Rotation = 90 }, panel)
	mk("UIAspectRatioConstraint", { Name = "Ratio", AspectRatio = ratio }, panel)
end

local function addCloseButton(panel: Frame)
	local close = mk("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.13, 0, 0.13, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
	}, panel) :: TextButton
	mk("UIAspectRatioConstraint", { Name = "Ratio", AspectRatio = 1 }, close)
	local design = mk("Frame", {
		Name = "Design",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
	}, close)
	mk("UICorner", { Name = "Corner", CornerRadius = UDim.new(0, 8) }, design)
	mk("UIGradient", {
		Name = "Gradient",
		Color = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(1, 0.333, 0.498)),
		Rotation = 90,
	}, design)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0.392, 0, 0), Thickness = 3 }, design)
	local text = mk("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0.9, 0),
		BackgroundTransparency = 1,
		Text = "X",
		FontFace = FREDOKA,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 6,
	}, close)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0.392, 0, 0), Thickness = 3 }, text)
end

local function addTitle(panel: Frame, icon: string, titleText: string)
	local title = mk("Frame", {
		Name = "Title",
		Position = UDim2.new(0.225, 0, 0, 0),
		Size = UDim2.new(0.55, 0, 0.14, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, panel)
	mk("UIListLayout", {
		Name = "List",
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.025, 0),
	}, title)
	local image = mk("ImageLabel", {
		Name = "Image",
		Size = UDim2.new(0.2, 0, 1.14, 0),
		BackgroundTransparency = 1,
		Image = icon,
		ZIndex = 4,
	}, title)
	mk("UIAspectRatioConstraint", { Name = "Ratio", AspectRatio = 1 }, image)
	local text = mk("TextLabel", {
		Name = "Text",
		Size = UDim2.new(0.78, 0, 0.75, 0),
		BackgroundTransparency = 1,
		Text = titleText,
		FontFace = GOTHAM_BOLD,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 4,
	}, title)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0, 0), Thickness = 3 }, text)
end

local function addClaimButton(panel: Frame, label: string)
	local btn = mk("TextButton", {
		Name = "ClaimButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.915, 0),
		Size = UDim2.new(0.32, 0, 0.115, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		ZIndex = 4,
	}, panel) :: TextButton
	mk("UICorner", { Name = "Corner", CornerRadius = UDim.new(0, 8) }, btn)
	mk("UIGradient", {
		Name = "Gradient",
		Color = ColorSequence.new(Color3.new(0.25, 0.9, 0.3), Color3.new(0.05, 0.6, 0.12)),
		Rotation = 90,
	}, btn)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0.3, 0), Thickness = 3 }, btn)
	local text = mk("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0.72, 0),
		BackgroundTransparency = 1,
		Text = label,
		FontFace = FREDOKA,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 5,
	}, btn)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0.3, 0), Thickness = 2 }, text)
end

-- ── DailyStreak ─────────────────────────────────────────────────────
local old = frames:FindFirstChild("DailyStreak")
if old then
	old:Destroy()
end

local streak = mk("Frame", {
	Name = "DailyStreak",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0.5, 0, 0.58, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
}, frames) :: Frame
addPanelChrome(streak, ColorSequence.new(Color3.new(1, 0.78, 0.15), Color3.new(0.95, 0.45, 0.05)), 1.5)
addCloseButton(streak)
addTitle(streak, ICON_TITLE, "Daily Streak")
addClaimButton(streak, "CLAIM")

local bg = mk("Frame", {
	Name = "Background",
	Position = UDim2.new(0.017, 0, 0.104, 0),
	Size = UDim2.new(0.967, 0, 0.68, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.9,
}, streak) :: Frame
mk("UICorner", { Name = "Corner", CornerRadius = UDim.new(0.03, 0) }, bg)
mk("UIGridLayout", {
	Name = "Grid",
	CellSize = UDim2.new(0.23, 0, 0.42, 0),
	CellPadding = UDim2.new(0.0225, 0, 0.06, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, bg)

local dayIcons = { ICON_SPEED, ICON_SPEED, ICON_WINS, ICON_SPEED, ICON_WINS, ICON_SPEED, ICON_GIFT }
for day = 1, 7 do
	local card = mk("ImageButton", {
		Name = "Day" .. day,
		LayoutOrder = day,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Image = "",
		AutoButtonColor = false,
	}, bg) :: ImageButton
	mk("UICorner", { Name = "UICorner", CornerRadius = UDim.new(0.1, 0) }, card)
	mk("UIStroke", { Name = "UIStroke", Color = Color3.fromRGB(255, 200, 40), Thickness = 0 }, card)
	mk("UIGradient", {
		Name = "UIGradient",
		Color = if day == 7 then CARD_GRADIENT_GOLD else CARD_GRADIENT,
		Rotation = 90,
	}, card)
	local dayLabel = mk("TextLabel", {
		Name = "DayLabel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		Size = UDim2.new(0.9, 0, 0.22, 0),
		BackgroundTransparency = 1,
		Text = "Day " .. day,
		FontFace = GOTHAM_BOLD,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 2,
	}, card)
	mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0, 0), Thickness = 2 }, dayLabel)
	local icon = mk("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.44, 0),
		Size = UDim2.new(0.36, 0, 0.36, 0),
		BackgroundTransparency = 1,
		Image = dayIcons[day],
		ZIndex = 2,
	}, card)
	mk("UIAspectRatioConstraint", { Name = "Ratio", AspectRatio = 1 }, icon)
	mk("TextLabel", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.71, 0),
		Size = UDim2.new(0.96, 0, 0.18, 0),
		BackgroundTransparency = 1,
		Text = "+Speed",
		FontFace = GOTHAM,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 2,
	}, card)
	mk("TextLabel", {
		Name = "Wins",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.88, 0),
		Size = UDim2.new(0.96, 0, 0.16, 0),
		BackgroundTransparency = 1,
		Text = "+Wins",
		FontFace = GOTHAM,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		TextScaled = true,
		Visible = false,
		ZIndex = 2,
	}, card)
	mk("ImageLabel", {
		Name = "Claimed",
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		Image = ICON_CHECK,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 3,
	}, card)
end

mk("TextLabel", {
	Name = "Footer",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.82, 0),
	Size = UDim2.new(0.85, 0, 0.05, 0),
	BackgroundTransparency = 1,
	Text = "Streak: 0 days",
	FontFace = GOTHAM,
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	ZIndex = 4,
}, streak)

-- ── OfflineReward ───────────────────────────────────────────────────
local oldOffline = frames:FindFirstChild("OfflineReward")
if oldOffline then
	oldOffline:Destroy()
end

local offline = mk("Frame", {
	Name = "OfflineReward",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0.36, 0, 0.44, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
}, frames) :: Frame
addPanelChrome(offline, ColorSequence.new(Color3.new(0.3, 0.45, 1), Color3.new(0.12, 0.18, 0.65)), 1.35)
addCloseButton(offline)
addTitle(offline, ICON_BOLT, "Welcome Back!")
addClaimButton(offline, "CLAIM")

local obg = mk("Frame", {
	Name = "Background",
	Position = UDim2.new(0.04, 0, 0.16, 0),
	Size = UDim2.new(0.92, 0, 0.64, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.9,
}, offline) :: Frame
mk("UICorner", { Name = "Corner", CornerRadius = UDim.new(0.03, 0) }, obg)
mk("TextLabel", {
	Name = "AwayTime",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.new(0.9, 0, 0.16, 0),
	BackgroundTransparency = 1,
	Text = "You were away",
	FontFace = GOTHAM,
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	ZIndex = 2,
}, obg)
local offlineIcon = mk("ImageLabel", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.47, 0),
	Size = UDim2.new(0.3, 0, 0.42, 0),
	BackgroundTransparency = 1,
	Image = ICON_SPEED,
	ZIndex = 2,
}, obg)
mk("UIAspectRatioConstraint", { Name = "Ratio", AspectRatio = 1 }, offlineIcon)
local amount = mk("TextLabel", {
	Name = "Amount",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.81, 0),
	Size = UDim2.new(0.95, 0, 0.24, 0),
	BackgroundTransparency = 1,
	Text = "+0 Speed",
	FontFace = FREDOKA,
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	ZIndex = 2,
}, obg)
mk("UIStroke", { Name = "Stroke", Color = Color3.new(0, 0, 0), Thickness = 3 }, amount)

-- Render above the bottom HUD (level/thrust bars draw at higher ZIndex than default panels).
for _, panel in { streak, offline } do
	panel.ZIndex += 20
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 20
		end
	end
end

print("[build-login-ui] Built GUI.Frames.DailyStreak and GUI.Frames.OfflineReward")
