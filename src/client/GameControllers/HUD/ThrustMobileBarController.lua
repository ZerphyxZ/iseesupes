--!strict

-- Fills the circular ImageButton inside SupesMobile with a dark mask that
-- shrinks from the top as thrust charges.
--
-- ONLY touches the ImageButton — SupesMobile and its other children
-- (Frame, UICorner, UIAspectRatioConstraint) are left completely alone.
--
-- What we add:
--   ImageButton
--     UICorner       ← added if missing (makes button itself circular for clip)
--     _EmptyMask     ← plain Frame, top-anchored, height = (1 - fill)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Knit          = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DataLib       = require(ReplicatedStorage.Shared.Utils.DataLib)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)
local SupesMobileUI = require(ReplicatedStorage.Shared.Utils.SupesMobileUI)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local ThrustMobileBarController = Knit.CreateController({ Name = "ThrustMobileBarController" })

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"

-- ── Colors ────────────────────────────────────────────────────────────────────

local C_FULL = Color3.fromRGB(0,   210, 255)
local C_GOOD = Color3.fromRGB(60,  220,  80)
local C_WARN = Color3.fromRGB(255, 150,   0)
local C_CRIT = Color3.fromRGB(220,  40,  40)

local function getTint(f: number): Color3
	if f >= 0.99 then return C_FULL end
	if f >= 0.50 then return C_GOOD:Lerp(C_FULL, (f - 0.50) / 0.49) end
	if f >= 0.25 then return C_WARN:Lerp(C_GOOD, (f - 0.25) / 0.25) end
	return C_CRIT:Lerp(C_WARN, f / 0.25)
end

-- ── Data ─────────────────────────────────────────────────────────────────────

local function getFillPct(): number
	local data = DataLib.GetData()
	if not data then return 1 end
	if type(data.ThrustCurrent) ~= "number" then return 1 end
	if type(data.ThrustMax) ~= "number" or data.ThrustMax <= 0 then return 1 end
	return math.clamp(data.ThrustCurrent / data.ThrustMax, 0, 1)
end

-- ── Flight state ──────────────────────────────────────────────────────────────

local flightActive = false
local flightStartedAt: number? = nil
local holdingLocal = false
local lastCancelTooSoonToastAt = -math.huge
local DoubleJumpService: any = nil

local function getCancelMinActiveTime(): number
	local minT = CharacterConfigs.DoubleJump.CancelMinActiveTime
	if type(minT) == "number" and minT >= 0 then
		return minT
	end
	return 1.25
end

local function notifyCancelTooSoon()
	local now = os.clock()
	if now - lastCancelTooSoonToastAt < 0.6 then
		return
	end
	lastCancelTooSoonToastAt = now
	local minActive = getCancelMinActiveTime()
	local remaining = minActive
	if flightStartedAt then
		remaining = math.max(0.1, minActive - (now - flightStartedAt))
	end
	if remaining >= 10 then
		NotificationManager.show(string.format("Hold thrust — cancel in %ds", math.ceil(remaining)), "Info")
	else
		NotificationManager.show(string.format("Hold thrust — cancel in %.1fs", remaining), "Info")
	end
end

local function isPhaseAttrFlying(): boolean
	local phase = player:GetAttribute(PHASE_ATTR)
	return phase ~= nil and phase ~= ""
end

local function syncFlightActiveFromAttribute()
	flightActive = isPhaseAttrFlying()
end

local function resetFlightInputState()
	flightActive = false
	flightStartedAt = nil
	holdingLocal = false
end

local function markFlightStarted()
	flightStartedAt = os.clock()
end

local function requestFlightStart()
	if not DoubleJumpService then
		return
	end
	holdingLocal = true
	DoubleJumpService:RequestStart():andThen(function(ok: boolean)
		if ok then
			flightActive = true
			markFlightStarted()
			DoubleJumpService:SetHolding(true)
			task.defer(syncFlightActiveFromAttribute)
		else
			holdingLocal = false
			syncFlightActiveFromAttribute()
		end
	end):catch(function(err)
		holdingLocal = false
		syncFlightActiveFromAttribute()
		warn(err)
	end)
end

local function onButtonTapped()
	if not DoubleJumpService then
		return
	end

	syncFlightActiveFromAttribute()

	if flightActive then
		if flightStartedAt and os.clock() - flightStartedAt < getCancelMinActiveTime() then
			notifyCancelTooSoon()
			return
		end
		holdingLocal = false
		DoubleJumpService:SetHolding(false)
		return
	end

	-- Stale local state: thought we were flying but server ended the ability.
	if holdingLocal and not isPhaseAttrFlying() then
		resetFlightInputState()
	end

	requestFlightStart()
end

-- ── Locator ───────────────────────────────────────────────────────────────────

-- ── Setup ─────────────────────────────────────────────────────────────────────

type Refs = {
	supesFrame : Frame,
	baseButton : ImageButton,
	emptyMask  : Frame,
}

local function setupFill(supesFrame: Frame): Refs?
	local baseButton = supesFrame:FindFirstChildOfClass("ImageButton") :: ImageButton?
	if not baseButton then
		warn("[iseesupes][ThrustBar] No ImageButton inside SupesMobile")
		return nil
	end

	-- SupesMobile is NOT touched at all.
	-- We only modify the ImageButton itself.

	-- Give the button its own UICorner so ClipsDescendants = true
	-- clips children to a circle (not a rectangle).
	if not baseButton:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)   -- perfect circle
		c.Parent = baseButton
	end
	baseButton.ClipsDescendants = true   -- clips _EmptyMask to the circle

	-- _EmptyMask: dark overlay inside the button only.
	-- AnchorPoint top-left, height = (1 - fill)  →  covers the unfilled top portion.
	-- Pure UDim2.fromScale — always ≤ 100% of the button, can't escape.
	local mask = baseButton:FindFirstChild("_EmptyMask") :: Frame?
	if not mask then
		mask = Instance.new("Frame")
		mask.Name                   = "_EmptyMask"
		mask.AnchorPoint            = Vector2.new(0, 0)
		mask.Position               = UDim2.fromScale(0, 0)
		mask.Size                   = UDim2.fromScale(1, 0)  -- 0 when full, 1 when empty
		mask.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
		mask.BackgroundTransparency = 0.42
		mask.BorderSizePixel        = 0
		mask.ZIndex                 = baseButton.ZIndex + 1
		mask.Active                 = false
		mask.Selectable             = false
		mask.Parent                 = baseButton
	end

	return { supesFrame = supesFrame, baseButton = baseButton, emptyMask = mask :: Frame }
end

-- ── Per-frame update ──────────────────────────────────────────────────────────

local lastFill   = -1
local lastFull   = false
local lastFlying = false
local currentRefs: Refs? = nil
local buttonTapConn: RBXScriptConnection? = nil

local T = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function ensureButtonClickable(baseButton: ImageButton)
	baseButton.Active = true
	baseButton.Selectable = true
	local mask = baseButton:FindFirstChild("_EmptyMask")
	if mask and mask:IsA("GuiObject") then
		mask.Active = false
		mask.Selectable = false
	end
end

local function refsAreAlive(refs: Refs?): boolean
	if not refs then
		return false
	end
	return refs.supesFrame.Parent ~= nil and refs.baseButton.Parent ~= nil
end

local function applyFill(r: Refs, fill: number)
	-- Dark mask covers unfilled top; shrinks as fuel fills
	r.emptyMask.Size         = UDim2.fromScale(1, 1 - fill)
	-- Button icon tint changes colour with fuel level
	r.baseButton.ImageColor3 = getTint(fill)

	local isFull   = fill >= 0.99
	local isFlying = flightActive

	if isFlying ~= lastFlying then
		lastFlying = isFlying
		TweenService:Create(r.emptyMask, T,
			{ BackgroundTransparency = if isFlying then 0.28 else 0.42 }):Play()
	end

	if isFull ~= lastFull then
		lastFull = isFull
		if isFull and not isFlying then
			r.baseButton.ImageColor3 = Color3.new(1, 1, 1)
			task.delay(0.15, function()
				r.baseButton.ImageColor3 = C_FULL
			end)
		end
	end
end

local function refreshBarFromData()
	local refs = currentRefs
	if not refsAreAlive(refs) then
		return
	end
	local fill = getFillPct()
	lastFill = fill
	applyFill(refs :: Refs, fill)
end

local function bindSupesButton(refs: Refs)
	if buttonTapConn then
		buttonTapConn:Disconnect()
		buttonTapConn = nil
	end

	ensureButtonClickable(refs.baseButton)
	currentRefs = refs

	buttonTapConn = refs.baseButton.MouseButton1Down:Connect(function()
		HudAnimations.buttonPress(refs.baseButton, onButtonTapped)
	end)

	syncFlightActiveFromAttribute()
	local seedFill = getFillPct()
	lastFill = seedFill
	lastFull = seedFill >= 0.99
	lastFlying = flightActive
	applyFill(refs, seedFill)
end

local function tryAttachSupesMobile(playerGui: PlayerGui): boolean
	local supesFrame = SupesMobileUI.findSupesMobile(playerGui)
	if not supesFrame then
		return false
	end

	local refs = setupFill(supesFrame)
	if not refs then
		return false
	end

	if currentRefs and currentRefs.baseButton == refs.baseButton then
		ensureButtonClickable(refs.baseButton)
		return true
	end

	bindSupesButton(refs)
	return true
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function ThrustMobileBarController:KnitStart()
	DoubleJumpService = Knit.GetService("DoubleJumpService")

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local supesFrame: Frame? = nil
	local deadline = os.clock() + 30
	while not supesFrame and os.clock() < deadline do
		if tryAttachSupesMobile(playerGui) then
			supesFrame = currentRefs and currentRefs.supesFrame
		else
			task.wait(0.25)
		end
	end
	if not supesFrame then
		warn("[iseesupes][ThrustBar] SupesMobile not found — skipping.")
		return
	end

	player:GetAttributeChangedSignal(PHASE_ATTR):Connect(function()
		local wasActive = flightActive
		syncFlightActiveFromAttribute()
		if flightActive and not wasActive then
			markFlightStarted()
		elseif not flightActive then
			flightStartedAt = nil
			holdingLocal = false
		end
	end)

	DoubleJumpService.AbilityEnded:Connect(function()
		resetFlightInputState()
	end)
	DoubleJumpService.Rejected:Connect(function(reason: string)
		resetFlightInputState()
		syncFlightActiveFromAttribute()
		local refs = currentRefs
		if not refsAreAlive(refs) then
			return
		end
		if reason == "no_thrust" then
			local r = refs :: Refs
			TweenService:Create(r.baseButton, TweenInfo.new(0.06), { ImageColor3 = C_CRIT }):Play()
			task.delay(0.30, function()
				local live = currentRefs
				if refsAreAlive(live) then
					local liveRefs = live :: Refs
					liveRefs.baseButton.ImageColor3 = getTint(getFillPct())
				end
			end)
		end
	end)

	local function onRespawn()
		resetFlightInputState()
		syncFlightActiveFromAttribute()
		task.defer(function()
			tryAttachSupesMobile(playerGui)
		end)
	end

	player.CharacterAdded:Connect(onRespawn)

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "SupesMobile" and descendant:IsA("Frame") then
			task.defer(function()
				tryAttachSupesMobile(playerGui)
			end)
		end
	end)

	DataLib.OnThrustChanged(function()
		refreshBarFromData()
	end)

	RunService.Heartbeat:Connect(function()
		if not refsAreAlive(currentRefs) then
			tryAttachSupesMobile(playerGui)
		end

		syncFlightActiveFromAttribute()
		local refs = currentRefs
		if not refsAreAlive(refs) then
			return
		end

		local fill = getFillPct()
		if not flightActive and math.abs(fill - lastFill) < 0.002 then
			return
		end
		lastFill = fill
		applyFill(refs :: Refs, fill)
	end)

	print("[iseesupes] ThrustMobileBarController ready.")
end

return ThrustMobileBarController
