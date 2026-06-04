--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationManager = require(script.Parent.Parent.Modules.NotificationManager)

local BoostController = Knit.CreateController({
	Name = "BoostController",
})

function BoostController:KnitStart()
	local BoostService = Knit.GetService("BoostService")

	-- Listen for boost activation
	BoostService.BoostActivated:Connect(function()
		NotificationManager.show("⚡ +1 Boost Activated! Double Thrust for 1 Run!", "Success")
	end)

	-- Listen for boost cleared
	BoostService.BoostCleared:Connect(function()
		NotificationManager.show("Boost Used!", "Info")
	end)

	print("[BoostController] initialized successfully")
end

return BoostController
