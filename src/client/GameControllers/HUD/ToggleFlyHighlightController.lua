--!strict

-- AutoFly pad highlight.
--
-- When AutoFly is ON and the local player stands on a ToggleFly pad, glow the tagged pad
-- part (color from its `Color` attribute) and play a one-shot arcade chime, so the player
-- knows stepping there auto-flies them. The pad parts are invisible, so the Highlight traces
-- the pad's footprint; it breathes for an arcade feel and clears the moment the player leaves
-- the pad or flies off. Entirely local — the Highlight and Sound are created on this client,
-- so no other player sees them. Detection reuses ToggleFlyZone.getActiveZoneRoot, the SAME
-- check AutoFly uses to trigger, so the glow appears exactly where stepping launches you.

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

-- Distance from a world point to the NEAREST point of a part (not its center) — so a long
-- runway pad still counts as "near" when you're beside its edge.
local function distToPart(pos: Vector3, part: BasePart): number
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size * 0.5
	local closest = part.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z))
	)
	return (closest - pos).Magnitude
end

-- The trigger (Toggle/step part) to glow: ONLY when the player is standing ON the STEP PART's
-- tight box, using the same tight footprint check as AutoFly launch. We glow the TAGGED PARENT
-- (the part with the Color attribute), but the trigger fires only when on the Toggle.
local function activeStepPart(root: BasePart): BasePart?
	local launchPad = ToggleFlyConfigs.LaunchHorizontalPadding
	if typeof(launchPad) ~= "number" then
		launchPad = 3
	end
	local zone = ToggleFlyConfigs.Zone
	local maxAbove = if typeof(zone) == "table" and typeof(zone.maxHeightAbove) == "number" then zone.maxHeightAbove else 18
	local minBelow = if typeof(zone) == "table" and typeof(zone.minHeightBelow) == "number" then zone.minHeightBelow else -8

	for trigger, tagged in triggerToTagged do
		if not trigger.Parent or not tagged then
			continue
		end
		-- Check if player is on the STEP PART (Toggle) tight footprint.
		local localPos = trigger.CFrame:PointToObjectSpace(root.Position)
		local half = trigger.Size * 0.5
		if math.abs(localPos.X) > half.X + launchPad or math.abs(localPos.Z) > half.Z + launchPad then
			continue
		end
		if localPos.Y > half.Y + maxAbove or localPos.Y < -half.Y + minBelow then
			continue
		end
		-- Player is on the step part — return trigger so we glow its tagged parent.
		return trigger
	end
	return nil
end

local glowPart: BasePart? = nil
local glowOutline: SelectionBox? = nil
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
end

local function glowOn(trigger: BasePart)
	currentPad = trigger
	local tagged = triggerToTagged[trigger]
	if not tagged then
		return
	end
	local p = ensureGlowPart()

	-- Glow renders on the TAGGED PARENT (the visible glowing pad where the player flies from).
	local cf: CFrame, size: Vector3
	if tagged:IsA("BasePart") then
		cf, size = tagged.CFrame, tagged.Size
	elseif tagged:IsA("Model") then
		cf, size = tagged:GetBoundingBox()
	else
		return
	end
	local pad2 = ToggleFlyConfigs.HighlightSizePadding or 0.6
	p.Size = size + Vector3.new(pad2, pad2, pad2)
	p.CFrame = cf

	-- Colour from the TAGGED PART's attribute.
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
