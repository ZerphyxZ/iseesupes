--!strict

export type PlayerData = {
	Coins: number,
	Level: number,
	Speed: number,
	Wins: number,
	SpeedPoints: number,
	ThrustCurrent: number,
	ThrustMax: number,
	Rebirths: number,
	OwnedTrails: { [string]: boolean },
	EquippedTrail: string,
	ClaimedRewards: { [string]: number }, -- rewardIndex (string) → os.time() of last claim
	RewardsAnchorTime: number?, -- os.time() when reward timers started (first join / migration)
	UnlockedAvatars: { [string]: boolean },
	EquippedAvatar: string,
	StepSpeedBonus: number,
}

local ProfileTemplate: PlayerData = {
	Coins = 0,
	Level = 1,
	Speed = 0,
	Wins = 0,
	SpeedPoints = 0,
	ThrustCurrent = 75,
	ThrustMax = 75,
	Rebirths = 0,
	OwnedTrails = {},
	EquippedTrail = "",
	ClaimedRewards = {},
	UnlockedAvatars = {},
	EquippedAvatar = "",
	StepSpeedBonus = 0,
}

return ProfileTemplate
