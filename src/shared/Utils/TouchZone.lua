--!strict

-- HRP-based zone checks for shop pads (works when .Touched misses tall / morph suits).

local Players = game:GetService("Players")

export type ZoneOptions = {
	horizontalPadding: number?,
	maxHeightAbove: number?,
	minHeightBelow: number?,
}

local TouchZone = {}

local DEFAULTS = {
	horizontalPadding = 6,
	maxHeightAbove = 18,
	minHeightBelow = -8,
}

function TouchZone.isRootInPartZone(root: BasePart, zonePart: BasePart, options: ZoneOptions?): boolean
	local opts = options or {}
	local pad = opts.horizontalPadding
	if type(pad) ~= "number" then
		pad = DEFAULTS.horizontalPadding
	end
	local maxAbove = opts.maxHeightAbove
	if type(maxAbove) ~= "number" then
		maxAbove = DEFAULTS.maxHeightAbove
	end
	local minBelow = opts.minHeightBelow
	if type(minBelow) ~= "number" then
		minBelow = DEFAULTS.minHeightBelow
	end

	local half = zonePart.Size * 0.5
	local radius = math.max(half.X, half.Z) + pad
	local delta = root.Position - zonePart.Position
	if Vector3.new(delta.X, 0, delta.Z).Magnitude > radius then
		return false
	end

	local topY = zonePart.Position.Y + half.Y
	local bottomY = zonePart.Position.Y - half.Y
	local rootY = root.Position.Y
	if rootY > topY + maxAbove then
		return false
	end
	if rootY < bottomY + minBelow then
		return false
	end
	return true
end

function TouchZone.getPlayerFromCharacterPart(hit: BasePart): Player?
	if not hit or not hit.Parent then
		return nil
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

return TouchZone
