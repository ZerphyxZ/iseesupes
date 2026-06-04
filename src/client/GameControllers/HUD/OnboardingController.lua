--!strict

-- Lightweight onboarding hints for brand-new players only.
--
-- Hint 1 — "Press E to Fly!"
--   Appears ~3s after the spawn-intro landing. Dismisses on E press or after 8s.
--
-- Hint 2 — Win Button Glow
--   Gold Highlight + "Claim Win!" BillboardGui on the first GiveWins button.
--   Dismisses when player earns their first win.
--
-- Guard: only shown when Level == 1, Wins == 0, and TotalPlayTime < 120s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local GiveWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveWinsConfigs)

local OnboardingController = Knit.CreateController({ Name = "OnboardingController" })

local player = Players.LocalPlayer
local hintsShown = false -- once per session; reset when data is detected as fresh

-- ─────────────────────────────────────────────────────────────────────────────
-- Guard
-- ─────────────────────────────────────────────────────────────────────────────

local function isNewPlayer(): boolean
	local data = DataLib.GetData()
	if not data then
		return false
	end
	local level = type(data.Level) == "number" and data.Level or 1
	local wins = type(data.Wins) == "number" and data.Wins or 0
	local playTime = type(data.TotalPlayTime) == "number" and data.TotalPlayTime or 0
	return level <= 1 and wins == 0 and playTime < 120
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hint 1: Press E to Fly
-- ─────────────────────────────────────────────────────────────────────────────

local function fadeAndDestroy(frame: Frame, duration: number)
	local descendants = frame:GetDescendants()
	local tweens: { Tween } = {}
	table.insert(tweens, TweenService:Create(frame, TweenInfo.new(duration), { BackgroundTransparency = 1 }))
	for _, desc in descendants do
		if desc:IsA("TextLabel") then
			table.insert(
				tweens,
				TweenService:Create(desc :: TextLabel, TweenInfo.new(duration), { TextTransparency = 1 })
			)
		elseif desc:IsA("UIStroke") then
			table.insert(
				tweens,
				TweenService:Create(desc :: UIStroke, TweenInfo.new(duration), { Transparency = 1 })
			)
		end
	end
	for _, t in tweens do
		t:Play()
	end
	task.delay(duration, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

local function showFlyHint(gui: ScreenGui)
	-- Outer frame ─ semi-transparent pill centered near the bottom third
	local frame = Instance.new("Frame")
	frame.Name = "FlyHint"
	frame.Size = UDim2.new(0, 280, 0, 52)
	frame.Position = UDim2.new(0.5, 0, 0.72, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.ZIndex = 10
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.Text = "Press  E  to Fly!"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.BackgroundTransparency = 1
	label.ZIndex = 11
	label.Parent = frame

	-- Auto-dismiss after 8 seconds
	task.delay(8, function()
		if frame.Parent then
			fadeAndDestroy(frame, 0.5)
		end
	end)

	-- Dismiss on first E press
	local conn: RBXScriptConnection
	conn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			conn:Disconnect()
			if frame.Parent then
				fadeAndDestroy(frame, 0.3)
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hint 1b: "Earn a Win to unlock your Superman suit!"  (shown alongside Hint 1)
-- ─────────────────────────────────────────────────────────────────────────────

local function showSupermanHint(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "SupermanHint"
	frame.Size = UDim2.new(0, 300, 0, 46)
	frame.Position = UDim2.new(0.5, 0, 0.79, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.ZIndex = 10
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0) -- gold border
	stroke.Transparency = 0.3
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.Text = "🏆 Earn 1 Win to unlock Superman!"
	label.TextColor3 = Color3.fromRGB(255, 230, 100)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.BackgroundTransparency = 1
	label.ZIndex = 11
	label.Parent = frame

	-- Dismiss when player earns their first win
	local winConn: RBXScriptConnection? = nil
	winConn = DataLib.OnChanged(function(data: any)
		if data and type(data.Wins) == "number" and data.Wins > 0 then
			if winConn then
				winConn:Disconnect()
				winConn = nil
			end
			fadeAndDestroy(frame, 0.5)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hint 2: Win Button Glow
-- ─────────────────────────────────────────────────────────────────────────────

local function showWinHint()
	local folder = MapWorld.findChildInMap(GiveWinsConfigs.FolderName)
	if not folder then
		return
	end

	-- Pick the first Model (Button1)
	local button: Model? = nil
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			button = child :: Model
			break
		end
	end
	if not button then
		return
	end

	local touchPart = button:FindFirstChild(GiveWinsConfigs.TouchPartName)
	if not touchPart or not touchPart:IsA("BasePart") then
		return
	end

	-- Gold highlight on the whole button model
	local highlight = Instance.new("Highlight")
	highlight.Name = "OnboardingHighlight"
	highlight.FillColor = Color3.fromRGB(255, 210, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0
	highlight.Adornee = button
	highlight.Parent = player.PlayerGui

	-- "Claim Win!" billboard floating above the touch part
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OnboardingBillboard"
	billboard.Size = UDim2.new(0, 200, 0, 48)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = false
	billboard.Adornee = touchPart :: BasePart
	billboard.Parent = player.PlayerGui

	local billboardLabel = Instance.new("TextLabel")
	billboardLabel.Size = UDim2.new(1, 0, 1, 0)
	billboardLabel.Text = "Claim Your Win!"
	billboardLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	billboardLabel.Font = Enum.Font.GothamBold
	billboardLabel.TextScaled = true
	billboardLabel.BackgroundTransparency = 1
	billboardLabel.Parent = billboard

	local billboardStroke = Instance.new("UIStroke")
	billboardStroke.Color = Color3.fromRGB(0, 0, 0)
	billboardStroke.Thickness = 2
	billboardStroke.Parent = billboardLabel

	-- Pulse the outline thickness to draw attention
	task.spawn(function()
		while highlight.Parent do
			TweenService
				:Create(highlight, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					FillTransparency = 0.65,
				})
				:Play()
			task.wait(0.75)
			if not highlight.Parent then
				break
			end
			TweenService
				:Create(highlight, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					FillTransparency = 0.25,
				})
				:Play()
			task.wait(0.75)
		end
	end)

	-- Dismiss when player earns their first win
	local winConn: RBXScriptConnection? = nil
	winConn = DataLib.OnChanged(function(data: any)
		if data and type(data.Wins) == "number" and data.Wins > 0 then
			if winConn then
				winConn:Disconnect()
				winConn = nil
			end
			if highlight.Parent then
				highlight:Destroy()
			end
			if billboard.Parent then
				billboard:Destroy()
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Knit Start
-- ─────────────────────────────────────────────────────────────────────────────

function OnboardingController:KnitStart()
	local SpawnIntroService = Knit.GetService("SpawnIntroService")

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120) :: ScreenGui?

	-- If data arrives and the player is brand-new (e.g. after /devresetdata or first ever join),
	-- reset the hintsShown flag so onboarding can fire when SpawnIntroLifted arrives.
	DataLib.OnChanged(function(data: any)
		if not data then return end
		local playTime = type(data.TotalPlayTime) == "number" and data.TotalPlayTime or 0
		local wins    = type(data.Wins)          == "number" and data.Wins          or 0
		local level   = type(data.Level)         == "number" and data.Level         or 1
		-- Fresh / reset profile: allow hints to show
		if playTime < 30 and wins == 0 and level <= 1 then
			hintsShown = false
		end
	end)

	local function triggerHints()
		if hintsShown then return end
		-- Retry loop: wait up to 3s for data to replicate before giving up
		task.spawn(function()
			for _ = 1, 6 do
				if isNewPlayer() then
					break
				end
				task.wait(0.5)
			end
			if not isNewPlayer() then return end
			hintsShown = true

			-- Hint 1: fly hint after landing (~3s)
			task.delay(3, function()
				if gui and isNewPlayer() then showFlyHint(gui) end
			end)

			-- Hint 1b: Superman unlock hint (~4s)
			task.delay(4, function()
				if gui and isNewPlayer() then showSupermanHint(gui) end
			end)

			-- Hint 2: win button glow after landing (~5s)
			task.delay(5, function()
				if isNewPlayer() then showWinHint() end
			end)
		end)
	end

	SpawnIntroService.SpawnIntroLifted:Connect(triggerHints)

	print("[iseesupes] OnboardingController ready.")
end

return OnboardingController
