--!strict

-- CollectionService ToggleFly pad registry + HRP zone checks.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToggleFlyConfigs = require(ReplicatedStorage.Shared.Configs.ToggleFlyConfigs)
local TouchZone = require(ReplicatedStorage.Shared.Utils.TouchZone)

local ToggleFlyZone = {}

local zoneParts: { BasePart } = {}
local partToTaggedRoot: { [BasePart]: Instance } = {}
local initialized = false

local function getCollectionTag(): string
	local tag = ToggleFlyConfigs.CollectionTag
	if typeof(tag) == "string" and tag ~= "" then
		return tag
	end
	return "ToggleFly"
end

function ToggleFlyZone.getZoneOptions(): TouchZone.ZoneOptions
	local zone = ToggleFlyConfigs.Zone
	if typeof(zone) ~= "table" then
		return {}
	end
	return {
		horizontalPadding = zone.horizontalPadding,
		maxHeightAbove = zone.maxHeightAbove,
		minHeightBelow = zone.minHeightBelow,
	}
end

--- The part the player physically steps on to fly: the `Toggle` child (the intended
--- trigger), else the only non-Destination BasePart child (some pads name it differently),
--- else the tagged part itself / its largest part. Using THIS as the zone — instead of the
--- tagged part, which can sit offset from where the player actually stands — makes AutoFly
--- (and the pad glow, which reuses this) trigger ON the pad, not before/after it.
function ToggleFlyZone.getStepPart(instance: Instance): BasePart?
	local toggle = instance:FindFirstChild("Toggle")
	if toggle and toggle:IsA("BasePart") then
		return toggle
	end
	for _, child in instance:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Destination" then
			return child
		end
	end
	if instance:IsA("BasePart") then
		return instance
	end
	return TouchZone.pickLargestBasePart(instance)
end

local function collectZonePartsFromTagged(instance: Instance): { BasePart }
	local parts: { BasePart } = {}
	local step = ToggleFlyZone.getStepPart(instance)
	if step then
		table.insert(parts, step)
	end
	return parts
end

local function registerTaggedInstance(instance: Instance)
	for _, part in collectZonePartsFromTagged(instance) do
		if not partToTaggedRoot[part] then
			partToTaggedRoot[part] = instance
			table.insert(zoneParts, part)
		end
	end
end

local function unregisterTaggedInstance(instance: Instance)
	for i = #zoneParts, 1, -1 do
		local part = zoneParts[i]
		if partToTaggedRoot[part] == instance then
			partToTaggedRoot[part] = nil
			table.remove(zoneParts, i)
		end
	end
end

local function rebuildZoneRegistry()
	table.clear(zoneParts)
	table.clear(partToTaggedRoot)
	for _, instance in CollectionService:GetTagged(getCollectionTag()) do
		registerTaggedInstance(instance)
	end
end

function ToggleFlyZone.ensureInitialized()
	if initialized then
		return
	end
	initialized = true

	rebuildZoneRegistry()

	local tag = getCollectionTag()
	CollectionService:GetInstanceAddedSignal(tag):Connect(registerTaggedInstance)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unregisterTaggedInstance)
end

function ToggleFlyZone.isRootInAnyZone(root: BasePart): boolean
	ToggleFlyZone.ensureInitialized()
	if #zoneParts == 0 then
		return false
	end
	return TouchZone.isRootInAnyPartZone(root, zoneParts, ToggleFlyZone.getZoneOptions())
end

--- Tight BOX check on the TAGGED PART (the glowing pad you see): used for LAUNCHING AutoFly.
local function isRootOnTaggedPart(root: BasePart, tagged: Instance): boolean
	local taggedPart: BasePart? = nil
	if tagged:IsA("BasePart") then
		taggedPart = tagged
	else
		taggedPart = TouchZone.pickLargestBasePart(tagged)
	end
	if not taggedPart then
		return false
	end
	local localPos = taggedPart.CFrame:PointToObjectSpace(root.Position)
	local half = taggedPart.Size * 0.5
	local pad = ToggleFlyConfigs.LaunchHorizontalPadding
	if typeof(pad) ~= "number" then
		pad = 3
	end
	if math.abs(localPos.X) > half.X + pad or math.abs(localPos.Z) > half.Z + pad then
		return false
	end
	local zone = ToggleFlyConfigs.Zone
	local maxAbove = if typeof(zone) == "table" and typeof(zone.maxHeightAbove) == "number" then zone.maxHeightAbove else 18
	local minBelow = if typeof(zone) == "table" and typeof(zone.minHeightBelow) == "number" then zone.minHeightBelow else -8
	return localPos.Y <= half.Y + maxAbove and localPos.Y >= -half.Y + minBelow
end

--- The tagged root whose pad the player is standing ON (tight footprint check on the TAGGED
--- PART — the visible glowing pad — used to LAUNCH AutoFly). The glow appears when the
--- player touches the Toggle, but flight fires when they touch the glowing part (tagged).
function ToggleFlyZone.getActiveZoneRoot(root: BasePart): Instance?
	ToggleFlyZone.ensureInitialized()
	for _, tagged in CollectionService:GetTagged(getCollectionTag()) do
		if tagged then
			if isRootOnTaggedPart(root, tagged) then
				return tagged
			end
		end
	end
	return nil
end

function ToggleFlyZone.getDestinationPart(taggedRoot: Instance, childName: string?): BasePart?
	local name = childName
	if typeof(name) ~= "string" or name == "" then
		name = "Destination"
	end
	local child = taggedRoot:FindFirstChild(name)
	if child and child:IsA("BasePart") then
		return child
	end
	return nil
end

return ToggleFlyZone
