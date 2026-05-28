--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local DJ_PHASE_ATTR = "DjAbilityPhase"

local UpgradeWinsController = Knit.CreateController({ Name = "UpgradeWinsController" })

local function resetSteerAfterMorph()
	local ok, doubleJump = pcall(function()
		return Knit.GetController("DoubleJumpController")
	end)
	if ok and doubleJump and doubleJump.resetSteerTrackingAfterMorph then
		doubleJump:resetSteerTrackingAfterMorph()
	end
end

local function snapCameraAfterMorph()
	local player = Players.LocalPlayer
	if player and player:GetAttribute(DJ_PHASE_ATTR) then
		return
	end
	task.spawn(AvatarReplace.waitAndSnapLocalCamera, 4)
end

function UpgradeWinsController:KnitStart()
	local UpgradeWinsService = Knit.GetService("UpgradeWinsService")
	local player = Players.LocalPlayer

	player.CharacterAdded:Connect(function(_character)
		resetSteerAfterMorph()
		snapCameraAfterMorph()
	end)

	UpgradeWinsService.UpgradeResult:Connect(function(kind: string, avatarId: string)
		if kind == "Unlocked" or kind == "Equipped" then
			resetSteerAfterMorph()
			-- Full character swap snaps via CharacterAdded; palette-only equip keeps the same instance.
		end

		if kind == "Unlocked" then
			NotificationManager.show("Avatar " .. avatarId .. " unlocked!", "Success")
		elseif kind == "Equipped" then
			NotificationManager.show("Equipped avatar " .. avatarId, "Success")
		elseif kind == "NotEnoughWins" then
			NotificationManager.show("Not enough wins!", "Error")
		elseif kind == "AvatarMissing" then
			NotificationManager.show("Avatar model not found in showcase.", "Error")
		elseif kind == "InvalidButton" then
			NotificationManager.show("Upgrade button is not configured.", "Error")
		end
	end)

	print("[iseesupes] UpgradeWinsController ready.")
end

return UpgradeWinsController
