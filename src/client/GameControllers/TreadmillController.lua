--!strict

-- Client-side treadmill feedback (highlights are server-owned; this handles signals / future UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local TreadmillController = Knit.CreateController({ Name = "TreadmillController" })

local activeTierKey: string? = nil
local activeMultiplier = 1

function TreadmillController:GetActiveTierKey(): string?
	return activeTierKey
end

function TreadmillController:GetMultiplier(): number
	return activeMultiplier
end

function TreadmillController:KnitStart()
	local TreadmillService = Knit.GetService("TreadmillService")

	TreadmillService.ActiveTreadmillChanged:Connect(function(tierKey: string?, multiplier: number)
		activeTierKey = tierKey
		activeMultiplier = multiplier
	end)

	TreadmillService.AccessDenied:Connect(function(tierKey: string, displayName: string, _gamepassKey: string?)
		warn("[iseesupes] Treadmill locked:", tierKey, displayName)
	end)
end

return TreadmillController
