--!strict

local RewardConfigs = require(script.Parent.Parent.Configs.RewardConfigs)

local RewardTiming = {}

-- Server-only: persist when reward timers start (first join / profile migration).
function RewardTiming.ensureAnchor(data: any): number
	local anchor = data.RewardsAnchorTime
	if typeof(anchor) == "number" then
		return anchor
	end
	anchor = os.time()
	data.RewardsAnchorTime = anchor
	return anchor
end

function RewardTiming.getSecondsUntilClaimable(data: any, index: number): number
	local info = RewardConfigs.Rewards[index]
	if not info then
		return 0
	end

	local cooldownSecs = info.CooldownHours * 3600
	local claimed = data.ClaimedRewards
	if type(claimed) == "table" then
		local lastClaimed = claimed[tostring(index)]
		if typeof(lastClaimed) == "number" then
			local remaining = cooldownSecs - (os.time() - lastClaimed)
			return math.max(0, remaining)
		end
	end

	-- Never claimed: unlock after CooldownHours from server anchor (not instant on join).
	local anchor = data.RewardsAnchorTime
	if typeof(anchor) ~= "number" then
		return cooldownSecs
	end

	local unlockAt = anchor + cooldownSecs
	return math.max(0, unlockAt - os.time())
end

function RewardTiming.isClaimable(data: any, index: number): boolean
	return RewardTiming.getSecondsUntilClaimable(data, index) == 0
end

return RewardTiming
