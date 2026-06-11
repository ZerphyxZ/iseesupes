--!strict

-- Client-side treadmill feedback: running-loop sound while on a treadmill
-- (Workspace/Sounds/TreadmillRun, quiet by design) + lock notifications.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationManager = require(script.Parent.Parent.Modules.NotificationManager)

local TreadmillController = Knit.CreateController({ Name = "TreadmillController" })

local activeTierKey: string? = nil
local activeMultiplier = 1

function TreadmillController:GetActiveTierKey(): string?
	return activeTierKey
end

function TreadmillController:IsOnTreadmill(): boolean
	return activeTierKey ~= nil
end

function TreadmillController:GetMultiplier(): number
	return activeMultiplier
end

function TreadmillController:KnitStart()
	local TreadmillService = Knit.GetService("TreadmillService")

	-- Footstep loop while running on a treadmill. Volume/cadence are authored on
	-- the Sound instance; higher tiers pitch the cadence up slightly (capped).
	local runSound: Sound? = nil
	local runSoundBaseSpeed = 1
	do
		local soundsFolder = Workspace:FindFirstChild("Sounds")
		local snd = soundsFolder and soundsFolder:FindFirstChild("TreadmillRun")
		if snd and snd:IsA("Sound") then
			runSound = snd
			runSoundBaseSpeed = snd.PlaybackSpeed
		end
	end

	local function updateRunSound()
		if not runSound then
			return
		end
		if activeTierKey ~= nil then
			local cadence = 1 + math.min(0.3, math.max(0, activeMultiplier - 1) * 0.01)
			runSound.PlaybackSpeed = runSoundBaseSpeed * cadence
			if not runSound.Playing then
				runSound:Play()
			end
		elseif runSound.Playing then
			runSound:Stop()
		end
	end

	TreadmillService.ActiveTreadmillChanged:Connect(function(tierKey: string?, multiplier: number)
		activeTierKey = tierKey
		activeMultiplier = multiplier
		updateRunSound()
	end)

	TreadmillService.AccessDenied:Connect(function(tierKey: string, displayName: string)
		NotificationManager.show(displayName .. " is locked — purchase to unlock!", "Info")
	end)
end

return TreadmillController
