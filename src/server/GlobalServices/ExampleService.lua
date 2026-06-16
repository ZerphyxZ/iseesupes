--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local Knit = require(ReplicatedStorage.Packages.Knit)

local ExampleService = Knit.CreateService({
	Name = "ExampleService",
	Client = {},
})

function ExampleService:KnitStart()
	StudioLog.ready("ExampleService")
end

return ExampleService
