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

	local localPos = zonePart.CFrame:PointToObjectSpace(root.Position)
	local half = zonePart.Size * 0.5
	local radius = math.max(half.X, half.Z) + pad
	if Vector3.new(localPos.X, 0, localPos.Z).Magnitude > radius then
		return false
	end

	if localPos.Y > half.Y + maxAbove then
		return false
	end
	if localPos.Y < -half.Y + minBelow then
		return false
	end
	return true
end

function TouchZone.isRootInAnyPartZone(root: BasePart, zoneParts: { BasePart }, options: ZoneOptions?): boolean
	for _, zonePart in zoneParts do
		if TouchZone.isRootInPartZone(root, zonePart, options) then
			return true
		end
	end
	return false
end

function TouchZone.collectNamedParts(container: Instance, partNames: { string }): { BasePart }
	local seen: { [BasePart]: boolean } = {}
	local parts: { BasePart } = {}
	for _, name in partNames do
		local inst = container:FindFirstChild(name, true)
		if inst and inst:IsA("BasePart") and not seen[inst] then
			seen[inst] = true
			table.insert(parts, inst)
		end
	end
	return parts
end

function TouchZone.pickLargestBasePart(container: Instance): BasePart?
	local largest: BasePart? = nil
	local largestVol = 0
	for _, desc in container:GetDescendants() do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > largestVol then
				largestVol = vol
				largest = part
			end
		end
	end
	return largest
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
