--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RewardConfigs = require(ReplicatedStorage.Shared.Configs.RewardConfigs)

local DataService: any = nil

local RewardService = Knit.CreateService({
	Name = "RewardService",
	Client = {
		ClaimReward = Knit.CreateSignal(), -- fired back to client on success: (index, grantType, amount)
	},
})

local function getClaimedRewards(data: any): { [string]: number }
	if type(data.ClaimedRewards) == "table" then
		return data.ClaimedRewards
	end
	data.ClaimedRewards = {}
	return data.ClaimedRewards
end

local function isClaimable(data: any, index: number): boolean
	local info = RewardConfigs.Rewards[index]
	if not info then
		return false
	end
	local claimed = getClaimedRewards(data)
	local lastClaimed = claimed[tostring(index)]
	if type(lastClaimed) ~= "number" then
		return true
	end
	local cooldownSecs = info.CooldownHours * 3600
	return os.time() - lastClaimed >= cooldownSecs
end

function RewardService:PerformClaim(player: Player, index: number): boolean
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local info = RewardConfigs.Rewards[index]
	if not info then
		warn("[iseesupes] RewardService: invalid reward index", index)
		return false
	end

	local data = profile.Data
	if not isClaimable(data, index) then
		return false
	end

	local claimed = getClaimedRewards(data)
	claimed[tostring(index)] = os.time()

	local grant = info.Grant
	if grant.Type == "Speed" then
		if type(data.Speed) ~= "number" then
			data.Speed = 0
		end
		data.Speed += grant.Amount
	elseif grant.Type == "SpeedPoints" then
		if type(data.SpeedPoints) ~= "number" then
			data.SpeedPoints = 0
		end
		data.SpeedPoints += grant.Amount
	end

	DataService:Replicate(player)
	RewardService.Client.ClaimReward:Fire(player, index, grant.Type, grant.Amount)

	print("[iseesupes] RewardService: claimed reward", index, "for", player.Name, "→", grant.Type, grant.Amount)
	return true
end

function RewardService.Client:RequestClaimReward(player: Player, index: number): boolean
	return RewardService:PerformClaim(player, index)
end

function RewardService:KnitStart()
	DataService = Knit.GetService("DataService")
	print("[iseesupes] RewardService ready.")
end

return RewardService
