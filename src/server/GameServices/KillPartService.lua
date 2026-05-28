--!strict
-- Deprecated: KillPart handling lives in TreadmillService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local TreadmillService: any = nil

local KillPartService = Knit.CreateService({
	Name = "KillPartService",
})

function KillPartService:RespawnPlayer(player: Player)
	if TreadmillService then
		TreadmillService:RespawnFromKillPart(player)
	end
end

function KillPartService:KnitStart()
	TreadmillService = Knit.GetService("TreadmillService")
	warn("[iseesupes] KillPartService is deprecated; tag handling is in TreadmillService.")
end

return KillPartService
