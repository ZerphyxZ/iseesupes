--!strict
-- Thrust bar UI lives in SpeedController (synced). Optional stub if this folder is synced via Rojo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ThrustController = Knit.CreateController({ Name = "ThrustController" })

function ThrustController:KnitStart() end

return ThrustController
