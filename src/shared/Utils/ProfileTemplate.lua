--!strict

export type PlayerData = {
	Coins: number,
	Level: number,
	Speed: number,
	Wins: number,
	SpeedPoints: number,
	ThrustCurrent: number,
	ThrustMax: number,
	SolarCurrent: number,
	SolarMax: number,
	ThrustUpgradeTier: number,
	Rebirths: number,
	Stage: number,
	MaxStage: number,
	--- Highest stage index sent to Analytics funnel (LogFunnelStepEvent dedupe).
	AnalyticsMaxStageLogged: number,
	OwnedTrails: { [string]: boolean },
	EquippedTrail: string,
	OwnedAuras: { [string]: boolean },
	EquippedAura: string,
	ClaimedRewards: { [string]: number }, -- rewardIndex (string) → os.time() of last claim
	RewardsAnchorTime: number?, -- os.time() when reward timers started (first join / migration)
	UnlockedAvatars: { [string]: boolean },
	EquippedAvatar: string,
	FriendInviteRewards: { [string]: boolean },
	OwnedSpeedPeaks: { [string]: boolean },
	OwnedTreadmills: { [string]: boolean },
	OwnedDoubleWins: boolean,
	StepSpeedBonus: number,
	TotalPlayTime: number,
	LeaderboardOdsVersion: string?, -- set after ODS reconcile; never put nil in the store template
	BoostActive: boolean?, -- temporary boost flag (cleared when player wins)
	--- 1=treadmill, 2=give wins, 3=upgrade avatar, 4=core done, 5=go stage 1, 6=complete
	TutorialStep: number,
	TutorialThrustHintShown: boolean,
	TutorialThrustShopIntroShown: boolean,
	TutorialFlyIntroShown: boolean,
	TutorialLowThrustFlyHintShown: boolean,
}

-- Pure data only — passed to ProfileService (no functions, no nil values).
local Data: PlayerData = {
	Coins = 0,
	Level = 1,
	Speed = 0,
	Wins = 0,
	SpeedPoints = 0,
	ThrustCurrent = 60,
	ThrustMax = 60,
	SolarCurrent = 60,
	SolarMax = 60,
	ThrustUpgradeTier = 0,
	Rebirths = 0,
	Stage = 0,
	MaxStage = 0,
	AnalyticsMaxStageLogged = 0,
	OwnedTrails = {},
	EquippedTrail = "",
	OwnedAuras = {},
	EquippedAura = "",
	ClaimedRewards = {},
	UnlockedAvatars = {},
	EquippedAvatar = "",
	FriendInviteRewards = {},
	OwnedSpeedPeaks = {},
	OwnedTreadmills = {},
	OwnedDoubleWins = false,
	StepSpeedBonus = 0,
	TotalPlayTime = 0,
	TutorialStep = 1,
	TutorialThrustHintShown = false,
	TutorialThrustShopIntroShown = false,
	TutorialFlyIntroShown = false,
	TutorialLowThrustFlyHintShown = false,
}

local ProfileTemplate = {}

ProfileTemplate.Data = Data

function ProfileTemplate.applyTo(target: any)
	for key, value in Data do
		if typeof(value) == "table" then
			local copy = {}
			for k, v in value :: { [any]: any } do
				copy[k] = v
			end
			target[key] = copy
		else
			target[key] = value
		end
	end
end

function ProfileTemplate.sanitizeForStore(root: any)
	if typeof(root) ~= "table" then
		return
	end

	local removeKeys: { any } = {}
	for key, value in root do
		local valueType = typeof(value)
		if value == nil or valueType == "function" or valueType == "Instance" or valueType == "userdata" then
			table.insert(removeKeys, key)
		elseif valueType == "string" then
			if utf8.len(value :: string) == nil then
				root[key] = ""
			end
		elseif valueType == "number" then
			local n = value :: number
			if n ~= n or n == math.huge or n == -math.huge then
				root[key] = 0
			end
		elseif valueType == "boolean" then
			-- Booleans are valid DataStore types — keep as-is.
			-- (Without this branch, OwnedAuras / UnlockedAvatars / OwnedDoubleWins / etc.
			-- which store true/false values would be silently wiped on every save.)
		elseif valueType == "table" then
			ProfileTemplate.sanitizeForStore(value)
		else
			table.insert(removeKeys, key)
		end
	end

	for _, key in removeKeys do
		root[key] = nil
	end
end

function ProfileTemplate.describeStats(data: any): string
	local speed = if type(data.Speed) == "number" then math.floor(data.Speed) else 0
	local level = if type(data.Level) == "number" then math.floor(data.Level) else 1
	local wins = if type(data.Wins) == "number" then math.floor(data.Wins) else 0
	local rebirths = if type(data.Rebirths) == "number" then math.floor(data.Rebirths) else 0
	local playTime = if type(data.TotalPlayTime) == "number" then math.floor(data.TotalPlayTime) else 0
	return string.format(
		"Speed=%d Level=%d Wins=%d Rebirths=%d TotalPlayTime=%ds",
		speed,
		level,
		wins,
		rebirths,
		playTime
	)
end

return ProfileTemplate
