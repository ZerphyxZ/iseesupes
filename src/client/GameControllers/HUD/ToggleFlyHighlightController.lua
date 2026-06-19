--!strict

-- AutoFly pad highlight — TWO-STEP arm->launch mechanic.
--
-- A ToggleFly pad is two adjacent invisible parts: the `Toggle` child (the ARMING pad) and the
-- tagged PARENT (the LAUNCH pad, ahead of the Toggle). When AutoFly is ON and the player steps
-- on the Toggle, this controller glows the PARENT (color from the parent's `Color` attribute)
-- and plays a one-shot chime — telling the player "walk forward onto that glowing pad to fly."
-- AutoFly itself (ToggleFlyZone.getActiveZoneRoot, used by AutoFlyController) only launches once
-- the player is actually ON the glowing parent, NOT on the Toggle. The glow stays armed while the
-- player is on the Toggle OR the parent, so it's lit the whole way from arming to lift-off, then
-- clears on leave/fly. Entirely local — the Highlight + Sound are created on this client only.
-- DO NOT collapse this to glow+launch on a single part: the arm pad and launch pad are distinct.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoFlyConfigs = require(ReplicatedStorage.Shared.Configs.AutoFlyConfigs)
local ToggleFlyConfigs = require(ReplicatedStorage.Shared.Configs.ToggleFlyConfigs)
local ToggleFlyZone = require(ReplicatedStorage.Shared.Utils.ToggleFlyZone)
local TouchZone = require(ReplicatedStorage.Shared.Utils.TouchZone)

local ToggleFlyHighlightController = Knit.CreateController({ Name = "ToggleFlyHighlightController" })

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"
local TAG = ToggleFlyConfigs.CollectionTag or "ToggleFly"

-- Map each pad's STEP part (what the player stands on) to its tagged parent (the part we glow
-- + read the Color attribute from). Triggering on the step part — not the tagged part's
-- broader zone — lights the glow up right where the player stands. The step part is normally
-- the `Toggle` child; some pads name it differently, so we fall back to the only non-
-- Destination BasePart child, and finally to the tagged part itself, so every pad works.
local triggerToTagged: { [BasePart]: Instance } = {}

local function indexTagged(tagged: Instance)
	if not tagged:IsDescendantOf(Workspace) then
		return
	end
	-- Same step part AutoFly now triggers on, so the glow lands exactly where you fly from.
	local trigger = ToggleFlyZone.getStepPart(tagged)
	if trigger then
		triggerToTagged[trigger] = tagged
	end
end

local function rebuildToggleRegistry()
	table.clear(triggerToTagged)
	for _, tagged in CollectionService:GetTagged(TAG) do
		indexTagged(tagged)
	end
end

local function unindexTagged(tagged: Instance)
	for trigger, owner in triggerToTagged do
		if owner == tagged then
			triggerToTagged[trigger] = nil
		end
	end
end

-- Tight footprint box test: is the player standing within `part`'s X/Z footprint (plus a small
-- horizontal pad) and inside the pad's vertical band? Same box shape AutoFly uses to launch.
local function isRootOnBox(root: BasePart, part: BasePart): boolean
	local launchPad = ToggleFlyConfigs.LaunchHorizontalPadding
	if typeof(launchPad) ~= "number" then
		launchPad = 3
	end
	local zone = ToggleFlyConfigs.Zone
	local maxAbove = if typeof(zone) == "table" and typeof(zone.maxHeightAbove) == "number" then zone.maxHeightAbove else 18
	local minBelow = if typeof(zone) == "table" and typeof(zone.minHeightBelow) == "number" then zone.minHeightBelow else -8
	local localPos = part.CFrame:PointToObjectSpace(root.Position)
	local half = part.Size * 0.5
	if math.abs(localPos.X) > half.X + launchPad or math.abs(localPos.Z) > half.Z + launchPad then
		return false
	end
	return localPos.Y <= half.Y + maxAbove and localPos.Y >= -half.Y + minBelow
end

-- Which pad to glow, by the TWO-STEP mechanic the player expects:
--   1. Step on the TOGGLE child (the arming pad)  ->  light up its tagged PARENT.
--   2. Walk FORWARD onto that glowing PARENT       ->  AutoFly launches (getActiveZoneRoot).
-- The glow stays armed while the player is on the Toggle OR already on the tagged parent, so the
-- highlight stays lit the whole way from arming to lift-off (the two parts sit adjacent/overlap).
-- Returns the TOGGLE key so glowOn can look up + render the glow on its tagged parent.
local function activeStepPart(root: BasePart): BasePart?
	for trigger, tagged in triggerToTagged do
		if not trigger.Parent or not tagged then
			continue
		end
		if isRootOnBox(root, trigger) then
			return trigger
		end
		if tagged:IsA("BasePart") and isRootOnBox(root, tagged :: BasePart) then
			return trigger
		end
	end
	return nil
end

local glowPart: BasePart? = nil
local glowOutline: SelectionBox? = nil
local flyBeacon: BillboardGui? = nil
local beaconBaseHeight = 0
local chime: Sound? = nil
local currentPad: BasePart? = nil
local lastChimePad: BasePart? = nil
local lastChimeAt = 0
local scanAccum = 0

local function autoFlyOn(): boolean
	if AutoFlyConfigs.Enabled == false then
		return false
	end
	local attr = AutoFlyConfigs.PlayerAttribute
	if typeof(attr) ~= "string" or attr == "" then
		attr = "AutoFlyEnabled"
	end
	return player:GetAttribute(attr) == true
end

local function isFlying(): boolean
	local phase = player:GetAttribute(PHASE_ATTR)
	return phase ~= nil and phase ~= ""
end

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function ensureGlowPart(): BasePart
	if glowPart and glowPart.Parent then
		return glowPart
	end
	local p = Instance.new("Part")
	p.Name = "ToggleFlyHighlight"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1 -- hidden until glowOn (a Neon part at Transparency 1 is invisible)
	p.Size = Vector3.one
	p.Parent = Workspace
	glowPart = p

	-- High-contrast outline so the pad reads even when its colour matches the floor.
	local box = Instance.new("SelectionBox")
	box.Name = "Outline"
	box.Adornee = p
	box.Color3 = ToggleFlyConfigs.HighlightOutlineColor or Color3.fromRGB(255, 255, 255)
	box.LineThickness = ToggleFlyConfigs.HighlightOutlineThickness or 0.2
	box.SurfaceTransparency = 1 -- the Neon part is the fill; the box only draws edges
	box.Transparency = 0
	box.Visible = false
	box.Parent = p
	glowOutline = box

	-- "FLY! ▼" beacon floated over the launch runway: marks the separate "step here to fly"
	-- strip so the two-step pad can't be misread as "standing on the arming pad does nothing".
	local bb = Instance.new("BillboardGui")
	bb.Name = "FlyBeacon"
	bb.Adornee = p
	bb.Size = UDim2.fromOffset(230, 120)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Enabled = false
	bb.Parent = p

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = ToggleFlyConfigs.LaunchBeaconText or "FLY!"
	title.Parent = bb
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Font = Enum.Font.GothamBlack
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.Text = ToggleFlyConfigs.LaunchBeaconSubtext or "▼ step on the glow ▼"
	sub.Parent = bb
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Color = Color3.fromRGB(0, 0, 0)
	subStroke.Parent = sub

	flyBeacon = bb

	return p
end

local function ensureChime(): Sound?
	if chime and chime.Parent then
		return chime
	end
	local id = ToggleFlyConfigs.HighlightSoundId
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "ToggleFlyHighlightChime"
	s.SoundId = id
	s.Volume = ToggleFlyConfigs.HighlightSoundVolume or 0.6
	s.Parent = SoundService
	chime = s
	return s
end

local function clearGlow()
	currentPad = nil
	if glowPart then
		glowPart.Transparency = 1 -- hide (Neon at full transparency renders nothing)
	end
	if glowOutline then
		glowOutline.Visible = false
	end
	if flyBeacon then
		flyBeacon.Enabled = false
	end
end

local function glowOn(trigger: BasePart)
	currentPad = trigger
	local tagged = triggerToTagged[trigger]
	if not tagged then
		return
	end
	local p = ensureGlowPart()

	-- Glow renders ON THE TAGGED PARENT — the launch pad the player flies from. Standing on the
	-- Toggle child ARMS this glow; the player then walks FORWARD onto this glowing parent and
	-- AutoFly fires (getActiveZoneRoot also keys off the tagged parent, so glow + launch match).
	-- TWO-STEP MECHANIC: Toggle = arm the highlight, Parent = the highlight you step onto to fly.
	-- DO NOT move this to the Toggle/step part — that collapses the arm->launch mechanic the
	-- player wants (glow must be on the Parent ahead, not on the Toggle they're standing on).
	local cf: CFrame, size: Vector3
	if tagged:IsA("BasePart") then
		cf, size = (tagged :: BasePart).CFrame, (tagged :: BasePart).Size
	elseif tagged:IsA("Model") then
		cf, size = (tagged :: Model):GetBoundingBox()
	else
		return
	end
	local pad2 = ToggleFlyConfigs.HighlightSizePadding or 0.6
	p.Size = size + Vector3.new(pad2, pad2, pad2)
	p.CFrame = cf

	-- Colour from the TAGGED PARENT's attribute (the Toggle/step part has no Color of its own).
	local attrName = ToggleFlyConfigs.HighlightColorAttribute
	if typeof(attrName) ~= "string" or attrName == "" then
		attrName = "Color"
	end
	local col = tagged:GetAttribute(attrName)
	if typeof(col) ~= "Color3" then
		col = ToggleFlyConfigs.HighlightFallbackColor or Color3.fromRGB(255, 200, 30)
	end
	p.Color = col
	p.Transparency = ToggleFlyConfigs.HighlightFillTransparencyMin or 0.2
	if glowOutline then
		glowOutline.Visible = true
	end

	-- Float the "FLY!" beacon above the runway's top surface; pulse() bobs it from this height.
	if ToggleFlyConfigs.LaunchBeaconEnabled ~= false and flyBeacon then
		local height = ToggleFlyConfigs.LaunchBeaconHeightStuds
		if typeof(height) ~= "number" then
			height = 6
		end
		beaconBaseHeight = (p.Size.Y * 0.5) + height
		flyBeacon.StudsOffsetWorldSpace = Vector3.new(0, beaconBaseHeight, 0)
		flyBeacon.Enabled = true
	elseif flyBeacon then
		flyBeacon.Enabled = false
	end

	-- One-shot arcade chime on entry (guarded so hovering the pad edge can't machine-gun it).
	local now = os.clock()
	if trigger ~= lastChimePad or now - lastChimeAt > 1 then
		local s = ensureChime()
		if s then
			s:Play()
		end
		lastChimePad = trigger
		lastChimeAt = now
	end
end

local function pulse()
	local p = glowPart
	if not p or not currentPad then
		return
	end
	local minT = ToggleFlyConfigs.HighlightFillTransparencyMin or 0.2
	local maxT = ToggleFlyConfigs.HighlightFillTransparencyMax or 0.55
	local speed = ToggleFlyConfigs.HighlightPulseSpeed or 6
	local s = 0.5 + 0.5 * math.sin(os.clock() * speed)
	p.Transparency = minT + (maxT - minT) * s

	if flyBeacon and flyBeacon.Enabled then
		local amp = ToggleFlyConfigs.LaunchBeaconBounceStuds
		if typeof(amp) ~= "number" then
			amp = 1.4
		end
		local bspeed = ToggleFlyConfigs.LaunchBeaconBounceSpeed
		if typeof(bspeed) ~= "number" then
			bspeed = 5
		end
		local bob = amp * (0.5 + 0.5 * math.sin(os.clock() * bspeed))
		flyBeacon.StudsOffsetWorldSpace = Vector3.new(0, beaconBaseHeight + bob, 0)
	end
end

local function tick(dt: number)
	if ToggleFlyConfigs.Enabled == false or ToggleFlyConfigs.HighlightEnabled == false then
		if currentPad then
			clearGlow()
		end
		return
	end

	-- Only while AutoFly is armed AND the player is still grounded (not already flying off).
	if not autoFlyOn() or isFlying() then
		if currentPad then
			clearGlow()
		end
		return
	end

	scanAccum += dt
	local interval = ToggleFlyConfigs.HighlightScanInterval or 0.1
	if scanAccum >= interval then
		scanAccum = 0
		local root = getRoot()
		local trig = if root then activeStepPart(root) else nil
		if trig then
			if trig ~= currentPad then
				glowOn(trig)
			end
		elseif currentPad then
			clearGlow()
		end
	end

	pulse()
end

function ToggleFlyHighlightController:KnitStart()
	if ToggleFlyConfigs.Enabled == false or ToggleFlyConfigs.HighlightEnabled == false then
		return
	end

	ToggleFlyZone.ensureInitialized()

	-- Build + maintain the Toggle→tagged map.
	rebuildToggleRegistry()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		task.defer(indexTagged, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(unindexTagged)
	-- Stages stream/clone in after boot; catch late arrivals, then flag any pad missing a Toggle.
	for _, delay in { 1, 3, 6 } do
		task.delay(delay, rebuildToggleRegistry)
	end
	task.delay(7, function()
		if not RunService:IsStudio() then
			return
		end
		local attrName = ToggleFlyConfigs.HighlightColorAttribute or "Color"
		local total, withColor = 0, 0
		for _, tagged in CollectionService:GetTagged(TAG) do
			total += 1
			if typeof(tagged:GetAttribute(attrName)) == "Color3" then
				withColor += 1
			end
		end
		if withColor < total then
			warn(("[iseesupes] ToggleFlyHighlight: %d/%d pads have a '%s' attribute; the rest glow the fallback color"):format(withColor, total, attrName))
		end
	end)

	-- New character = drop any stale glow.
	player.CharacterAdded:Connect(clearGlow)
	-- The instant flight starts, hide the glow (don't wait for the throttled scan).
	player:GetAttributeChangedSignal(PHASE_ATTR):Connect(function()
		if isFlying() and currentPad then
			clearGlow()
		end
	end)

	RunService.Heartbeat:Connect(tick)

	StudioLog.ready("ToggleFlyHighlightController")
end

return ToggleFlyHighlightController
