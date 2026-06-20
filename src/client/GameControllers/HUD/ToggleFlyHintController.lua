--!strict

-- When the local player stands on a CollectionService ToggleFly zone, pulse SupesMobile
-- (heartbeat) so mobile players know to tap and fly forward.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local ToggleFlyConfigs = require(ReplicatedStorage.Shared.Configs.ToggleFlyConfigs)
local ToggleFlyZone = require(ReplicatedStorage.Shared.Utils.ToggleFlyZone)
local SupesMobileUI = require(ReplicatedStorage.Shared.Utils.SupesMobileUI)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)
local TutorialFlyHint = require(script.Parent.Parent.Parent.Modules.TutorialFlyHint)

local ToggleFlyHintController = Knit.CreateController({ Name = "ToggleFlyHintController" })

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"

local supesFrame: Frame? = nil
local popActive = false
local heartbeatConn: RBXScriptConnection? = nil

local function resolveSupesFrame(): Frame?
	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return nil
	end
	return SupesMobileUI.findSupesMobile(playerGui)
end

local function isFlying(): boolean
	if ToggleFlyConfigs.HideWhenFlying == false then
		return false
	end
	return player:GetAttribute(PHASE_ATTR) ~= nil and player:GetAttribute(PHASE_ATTR) ~= ""
end

local function shouldSkipForTutorialHint(): boolean
	if ToggleFlyConfigs.SkipWhenTutorialFlyHintActive == false then
		return false
	end
	return TutorialFlyHint.isActive()
end

local function stopPop()
	if not popActive then
		return
	end
	popActive = false
	local frame = supesFrame
	if frame and frame.Parent then
		HudAnimations.stopHeartbeat(frame)
	end
end

local function startPop()
	local frame = supesFrame
	if not frame or not frame.Parent then
		return
	end
	if popActive then
		return
	end
	popActive = true
	HudAnimations.startHeartbeat(
		frame,
		ToggleFlyConfigs.HeartbeatPeakScale,
		ToggleFlyConfigs.HeartbeatPeriodSeconds
	)
end

local function isPlayerInToggleFlyZone(): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return ToggleFlyZone.isRootInAnyZone(root)
end

local function tickHint()
	if ToggleFlyConfigs.Enabled == false then
		stopPop()
		return
	end

	if not supesFrame or not supesFrame.Parent then
		supesFrame = resolveSupesFrame()
	end

	if shouldSkipForTutorialHint() or isFlying() or not isPlayerInToggleFlyZone() then
		stopPop()
		return
	end

	if supesFrame then
		startPop()
	else
		stopPop()
	end
end

function ToggleFlyHintController:KnitStart()
	if ToggleFlyConfigs.Enabled == false then
		return
	end

	ToggleFlyZone.ensureInitialized()

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	supesFrame = resolveSupesFrame()
	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "SupesMobile" and descendant:IsA("Frame") then
			task.defer(function()
				supesFrame = resolveSupesFrame()
			end)
		end
	end)

	player.CharacterAdded:Connect(function()
		stopPop()
	end)

	player:GetAttributeChangedSignal(PHASE_ATTR):Connect(tickHint)

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	-- Throttle the per-frame pad-zone scan (isPlayerInToggleFlyZone loops every ToggleFly pad) to
	-- ~8 Hz — it was running every frame. The flight-phase attribute handler above still fires
	-- tickHint instantly when you start/stop flying, so the hint hides with no perceptible lag.
	local hintScanAccum = 0
	local HINT_SCAN_INTERVAL = 0.12
	heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		hintScanAccum += dt
		if hintScanAccum < HINT_SCAN_INTERVAL then
			return
		end
		hintScanAccum = 0
		tickHint()
	end)

	StudioLog.ready("ToggleFlyHintController")
end

return ToggleFlyHintController
