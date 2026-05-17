--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ExampleService = Knit.CreateService({
	Name = "ExampleService",
	Client = {},
})

function ExampleService:KnitStart()
	print("[iseesupes] ExampleService ready.")
end

return ExampleService
