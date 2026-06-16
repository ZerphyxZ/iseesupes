--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local Knit = require(ReplicatedStorage.Packages.Knit)

local ExampleController = Knit.CreateController({ Name = "ExampleController" })

function ExampleController:KnitStart()
	StudioLog.ready("ExampleController")
end

return ExampleController
