--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local DataController = Knit.CreateController({ Name = "DataController" })

local function applySnapshot(data: any)
	if not data then
		return
	end
	DataLib.SetData(data)
end

function DataController:KnitStart()
	local DataService = Knit.GetService("DataService")
	local MonetizationService = Knit.GetService("MonetizationService")

	DataService.DataReplicated:Connect(applySnapshot)
	DataService.ThrustChanged:Connect(function(current: number, max: number)
		DataLib.SetThrust(current, max)
	end)
	DataService.SolarChanged:Connect(function(current: number, max: number)
		DataLib.SetSolar(current, max)
	end)
	DataService:RequestData():andThen(applySnapshot):catch(warn)

	MonetizationService.GamepassUpdated:Connect(function(key: string, owned: boolean)
		DataLib.SetGamepass(key, owned)
	end)

	MonetizationService:GetGamepassSnapshot():andThen(function(snapshot)
		DataLib.SetGamepasses(snapshot)
	end):catch(warn)
end

return DataController
