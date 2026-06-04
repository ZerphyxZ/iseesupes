--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NotificationManager = require(script.Parent.Parent.Modules.NotificationManager)

local LikeGameController = Knit.CreateController({
	Name = "LikeGameController",
})

function LikeGameController:KnitStart()
	local LikeGameService = Knit.GetService("LikeGameService")

	-- Listen for notifications from server
	LikeGameService.ShowNotification:Connect(function(message: string, kind: string?)
		NotificationManager.show(message, kind or "Info")
	end)

	print("[LikeGameController] initialized successfully")
end

return LikeGameController
