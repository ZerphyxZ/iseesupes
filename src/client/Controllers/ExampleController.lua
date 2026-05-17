--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ExampleController = Knit.CreateController({ Name = "ExampleController" })

function ExampleController:KnitStart()
	print("[iseesupes] ExampleController ready.")
end

return ExampleController
