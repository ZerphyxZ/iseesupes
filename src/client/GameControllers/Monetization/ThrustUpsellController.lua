--!strict

-- Surfaces Thrust Packs at the exact frustration moment: running out of thrust.
-- 3rd depletion in a session → helpful toast pointing at the Upgrade Shop.
-- 6th and 12th depletion → direct Thrust Pack 1 purchase prompt.
-- Never fires during the tutorial; min 3 minutes between nudges.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local ThrustUpsellController = Knit.CreateController({ Name = "ThrustUpsellController" })

local TOAST_AT = 3
local PROMPT_AT = { [6] = true, [12] = true }
local MIN_SECONDS_BETWEEN_NUDGES = 180

function ThrustUpsellController:KnitStart()
	local player = Players.LocalPlayer
	local DataService = Knit.GetService("DataService")

	local depletions = 0
	local lastNudgeAt = 0

	local function tutorialDone(): boolean
		local data = DataLib.GetData()
		local step = if data and type(data.TutorialStep) == "number" then data.TutorialStep else 1
		return step >= TutorialConfigs.Step.Complete
	end

	DataService.ThrustDepleted:Connect(function()
		if not tutorialDone() then
			return
		end
		depletions += 1

		local now = os.clock()
		if now - lastNudgeAt < MIN_SECONDS_BETWEEN_NUDGES then
			return
		end

		if depletions == TOAST_AT then
			lastNudgeAt = now
			NotificationManager.show("Out of Thrust? Thrust Packs in the Upgrade Shop grow your tank!", "info")
		elseif PROMPT_AT[depletions] then
			local tier = ThrustUpgradeConfigs.Tiers[1]
			if tier and tier.ProductId ~= 0 then
				lastNudgeAt = now
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, tier.ProductId)
				end)
			end
		end
	end)

	StudioLog.ready("ThrustUpsellController")
end

return ThrustUpsellController
