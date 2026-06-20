--!strict

-- Bold, rounded "Double Jump" pill under Skip Stage. Teaches casual players they
-- have air jumps to recover from a fall, and shows a recharge countdown after both
-- are spent. Reads the LongJumpUsed / LongJumpMax / LongJumpReadyAt player attrs
-- set by LongJumpController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local JumpCounterController = Knit.CreateController({ Name = "JumpCounterController" })

-- Mobile gets a smaller pill (touch screens are smaller). The pill now takes the Skip Stage spot at
-- the top (the player turned Skip Stage off), so it aligns to that frame instead of sitting below it.
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local PILL_HEIGHT = if IS_MOBILE then 26 else 34
local TEXT_SIZE = if IS_MOBILE then 14 else 19
local PAD_X = if IS_MOBILE then 10 else 16
local PAD_Y = if IS_MOBILE then 4 else 6
local STROKE_W = if IS_MOBILE then 1.6 else 2.4

local READY_FILL = Color3.fromRGB(40, 44, 66)
local READY_STROKE = Color3.fromRGB(120, 230, 170)
local READY_TEXT = Color3.fromRGB(235, 255, 245)
local CHARGING_FILL = Color3.fromRGB(58, 40, 40)
local CHARGING_STROKE = Color3.fromRGB(255, 180, 90)
local CHARGING_TEXT = Color3.fromRGB(255, 232, 205)

local label: TextLabel? = nil
local container: Frame? = nil
local stroke: UIStroke? = nil
local tickConn: RBXScriptConnection? = nil

local function maxJumps(): number
	local lj = CharacterConfigs.LongJump
	local air = lj and lj.MaxAirLongJumps
	if typeof(air) == "number" and air > 0 then
		return 1 + math.floor(air)
	end
	return 2
end

local function render()
	local lbl, frame, str = label, container, stroke
	if not lbl or not frame or not str then
		return
	end
	local player = Players.LocalPlayer

	local readyAtAttr = player:GetAttribute("LongJumpReadyAt")
	local readyAt = if typeof(readyAtAttr) == "number" then readyAtAttr else 0
	local now = os.clock()

	if readyAt > now then
		-- Recharging: show the countdown, amber styling.
		lbl.Text = string.format("\u{2193} Long Jump  %.1fs", readyAt - now)
		lbl.TextColor3 = CHARGING_TEXT
		frame.BackgroundColor3 = CHARGING_FILL
		str.Color = CHARGING_STROKE
		return
	end

	local usedAttr = player:GetAttribute("LongJumpUsed")
	local maxAttr = player:GetAttribute("LongJumpMax")
	local used = if typeof(usedAttr) == "number" then usedAttr else 0
	local max = if typeof(maxAttr) == "number" and maxAttr > 0 then maxAttr else maxJumps()

		lbl.Text = string.format("\u{2191}\u{2191} Long Jump  %d/%d", used, max)
	lbl.TextColor3 = READY_TEXT
	frame.BackgroundColor3 = READY_FILL
	str.Color = READY_STROKE
end

function JumpCounterController:KnitStart()
	if CharacterConfigs.Features and CharacterConfigs.Features.UseLongJump == false then
		return
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] JumpCounterController: GUI not found.")
		return
	end
	local hud = gui:WaitForChild("HUD", 30)
	if not hud then
		return
	end
	local skip = hud:WaitForChild("Skipstage", 30)

	-- Parent alongside the other code-built HUD frames (GUI.Frames), positioned
	-- with the same skip-relative formula NotificationController uses.
	local parent = gui:FindFirstChild("Frames") or gui

	local frame = Instance.new("Frame")
	frame.Name = "JumpCounter"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Size = UDim2.new(0, 0, 0, PILL_HEIGHT)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = READY_FILL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Position = UDim2.new(0.5, 0, 0.2, 0) -- fallback; refined below via real geometry
	frame.ZIndex = 20
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local str = Instance.new("UIStroke")
	str.Color = READY_STROKE
	str.Thickness = STROKE_W
	str.Transparency = 0.1
	str.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD_Y)
	padding.PaddingBottom = UDim.new(0, PAD_Y)
	padding.PaddingLeft = UDim.new(0, PAD_X)
	padding.PaddingRight = UDim.new(0, PAD_X)
	padding.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = TEXT_SIZE
	lbl.TextColor3 = READY_TEXT
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = ""
	lbl.ZIndex = 21
	lbl.Parent = frame

	container = frame
	label = lbl
	stroke = str

	-- Skip Stage is hidden by design now, so the pill TAKES its spot: align the pill's top with the
	-- Skip Stage frame's top (instead of sitting below the now-empty +/- cluster). The frame's real
	-- geometry is still valid while Visible = false, so this lands exactly where Skip Stage was.
	local function reposition()
		if not skip or not skip:IsA("GuiObject") then
			return
		end
		local parentH = parent.AbsoluteSize.Y
		if parentH <= 0 then
			return
		end
		local top = skip.AbsolutePosition.Y - parent.AbsolutePosition.Y
		frame.Position = UDim2.new(0.5, 0, top / parentH, 0)
	end
	reposition()
	task.defer(reposition)

	render()
	player:GetAttributeChangedSignal("LongJumpUsed"):Connect(render)
	player:GetAttributeChangedSignal("LongJumpMax"):Connect(render)
	player:GetAttributeChangedSignal("LongJumpReadyAt"):Connect(render)

	-- Tick the countdown only while a recharge is pending (cheap otherwise).
	tickConn = RunService.Heartbeat:Connect(function()
		local readyAtAttr = player:GetAttribute("LongJumpReadyAt")
		local readyAt = if typeof(readyAtAttr) == "number" then readyAtAttr else 0
		if readyAt > os.clock() then
			render()
		end
	end)

	StudioLog.ready("JumpCounterController", "(at Skip Stage spot)")
end

return JumpCounterController
