--!strict
-- ReplicatedFirst > LoadingScreen
--
-- Masks the join until the world has actually streamed in around the player.
-- With StreamingEnabled ON and the map ~220k studs from origin, players can join
-- and the spawn area never finishes streaming (especially on high latency), leaving
-- them stuck staring at sky/ocean with no ground. This overlay holds until real,
-- solid ground exists beneath the spawn — and if streaming stalls, it rejoins the
-- player ONCE automatically instead of leaving them stranded (the manual "leave and
-- rejoin" fix, automated).

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Tunables
local GROUND_TIMEOUT = 18 -- seconds to wait for ground before the self-heal rejoin
local RAY_LENGTH = 1000 -- how far down to look for solid ground (studs)
local STREAM_TIMEOUT = 5 -- per-request streaming timeout (seconds)
local DATA_GRACE = 4 -- extra time to let data arrive once ground is ready
local POLL = 0.15

-- Suppress the default Roblox loading screen as early as possible.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- Build the overlay. No external assets — they may not be downloaded yet.
local gui = Instance.new("ScreenGui")
gui.Name = "StreamLoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000000
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local bg = Instance.new("Frame")
bg.Name = "BG"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(8, 11, 22)
bg.BorderSizePixel = 0
bg.Parent = gui

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.42, 0)
title.Size = UDim2.new(0.8, 0, 0, 56)
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "Loading…"
title.Parent = bg

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.new(0.5, 0, 0.52, 0)
status.Size = UDim2.new(0.7, 0, 0, 24)
status.Font = Enum.Font.Gotham
status.TextScaled = true
status.TextColor3 = Color3.fromRGB(170, 185, 210)
status.Text = "Preparing"
status.Parent = bg

-- Thin indeterminate progress bar.
local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0.5, 0.5)
barBg.Position = UDim2.new(0.5, 0, 0.6, 0)
barBg.Size = UDim2.new(0.32, 0, 0, 8)
barBg.BackgroundColor3 = Color3.fromRGB(30, 38, 58)
barBg.BorderSizePixel = 0
barBg.Parent = bg
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBg

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0, 0.5)
bar.Position = UDim2.new(0, 0, 0.5, 0)
bar.Size = UDim2.new(0.12, 0, 1, 0)
bar.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
bar.BorderSizePixel = 0
bar.Parent = barBg
barCorner:Clone().Parent = bar

gui.Parent = player:WaitForChild("PlayerGui")

local revealed = false

-- Indeterminate bar sweep.
local barTween = TweenService:Create(
	bar,
	TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
	{ Position = UDim2.new(0.88, 0, 0.5, 0) }
)
barTween:Play()

-- Animated status dots.
local baseStatus = "Preparing"
local function setStatus(text: string)
	baseStatus = text
end
task.spawn(function()
	local n = 0
	while not revealed and gui.Parent do
		n = (n % 3) + 1
		status.Text = baseStatus .. string.rep(".", n)
		task.wait(0.4)
	end
end)

local function getRoot(): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Returns true if there is solid, collidable ground below the player. Skips
-- invisible non-collidable pads (e.g. the SpawnLocation) and ignores water so the
-- ocean can never be mistaken for ground.
local function findGroundBelow(root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local origin = root.Position + Vector3.new(0, 6, 0)
	local dir = Vector3.new(0, -RAY_LENGTH, 0)
	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignore
		local result = Workspace:Raycast(origin, dir, params)
		if not result then
			return false
		end
		local hit = result.Instance
		if hit and hit.CanCollide then
			return true
		end
		if hit then
			table.insert(ignore, hit) -- skip this non-solid hit and look further down
		else
			return false
		end
	end
	return false
end

local function fadeOutAndDestroy()
	revealed = true
	pcall(function()
		barTween:Cancel()
	end)
	local ti = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, obj in gui:GetDescendants() do
		if obj:IsA("GuiObject") then
			TweenService:Create(obj, ti, { BackgroundTransparency = 1 }):Play()
		end
		if obj:IsA("TextLabel") then
			TweenService:Create(obj, ti, { TextTransparency = 1 }):Play()
		end
	end
	TweenService:Create(bg, ti, { BackgroundTransparency = 1 }):Play()
	task.delay(0.6, function()
		gui:Destroy()
	end)
end

-- One-shot self-heal: rejoin the same place to recover from a stuck stream.
-- Guarded with teleport data so it can never loop.
local function tryWatchdogRejoin(): boolean
	local data = TeleportService:GetLocalPlayerTeleportData()
	if typeof(data) == "table" and data.streamRetry == true then
		return false -- already retried once; don't loop
	end
	setStatus("Reconnecting")
	local ok = pcall(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ streamRetry = true })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	return ok
end

-- Wait for the game to finish its initial load.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Best-effort data-ready check (safe to require now that the game has loaded).
local dataReady: () -> boolean = function()
	return true
end
pcall(function()
	local DataLib = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("DataLib"))
	dataReady = function()
		return DataLib.IsLoaded()
	end
end)

-- Warm the cache for UI art/sounds in the background so they don't pop in on reveal.
-- Non-blocking: never delays the reveal, which is gated on ground instead.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		pcall(function()
			ContentProvider:PreloadAsync({ pg })
		end)
	end
end)

setStatus("Loading world")

-- Hold until solid ground exists under the player, requesting streaming each pass.
local deadline = os.clock() + GROUND_TIMEOUT
while os.clock() < deadline do
	local root = getRoot()
	if root then
		pcall(function()
			player:RequestStreamAroundAsync(root.Position, STREAM_TIMEOUT)
		end)
		if findGroundBelow(root) then
			break
		end
	end
	task.wait(POLL)
end

local root = getRoot()
local groundOk = root ~= nil and findGroundBelow(root)

if groundOk then
	-- Give data a brief grace period so the HUD shows real numbers on reveal.
	local dataDeadline = os.clock() + DATA_GRACE
	while not dataReady() and os.clock() < dataDeadline do
		task.wait(0.1)
	end
	fadeOutAndDestroy()
elseif not tryWatchdogRejoin() then
	-- Couldn't rejoin (already retried once, or running in Studio): reveal anyway
	-- so the player is never trapped behind the overlay.
	setStatus("Still loading — rejoin if the world doesn't appear")
	task.wait(1.5)
	fadeOutAndDestroy()
end
