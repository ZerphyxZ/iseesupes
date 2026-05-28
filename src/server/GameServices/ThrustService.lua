--!strict
-- Deprecated: thrust API lives on DataService. Kept for Rojo layout; forwards if this module loads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local DataService: any = nil

local ThrustService = Knit.CreateService({
	Name = "ThrustService",
	Client = {
		ThrustDepleted = Knit.CreateSignal(),
	},
})

function ThrustService:KnitStart()
	DataService = Knit.GetService("DataService")
	DataService.Client.ThrustDepleted:Connect(function(player)
		ThrustService.Client.ThrustDepleted:Fire(player)
	end)
	warn("[iseesupes] ThrustService is deprecated; use DataService for thrust APIs.")
end

function ThrustService:GetFuel(player: Player): (number, number)
	return DataService:GetFuel(player)
end

function ThrustService:AddFuel(player: Player, amount: number): boolean
	return DataService:AddFuel(player, amount)
end

function ThrustService:TryConsume(player: Player, amount: number): boolean
	return DataService:TryConsumeThrust(player, amount)
end

function ThrustService:CanStartFlight(player: Player): boolean
	return DataService:CanStartFlight(player)
end

function ThrustService:TeleportToLobby(player: Player)
	DataService:TeleportToLobby(player)
end

function ThrustService:OnFlightDrained(player: Player)
	DataService:OnFlightDrained(player)
end

function ThrustService:RefillToMax(player: Player): boolean
	return DataService:RefillThrustToMax(player)
end

return ThrustService
