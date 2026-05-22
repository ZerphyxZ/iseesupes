--!strict

export type PlayerData = {
	Coins: number,
	Level: number,
	Speed: number,
	Wins: number,
	SpeedPoints: number,
	Rebirths: number,
	OwnedTrails: { [string]: boolean },
	EquippedTrail: string,
	ClaimedRewards: { [string]: number }, -- rewardIndex (string) → os.time() of last claim
}

local ProfileTemplate: PlayerData = {
	Coins = 0,
	Level = 1,
	Speed = 0,
	Wins = 0,
	SpeedPoints = 0,
	Rebirths = 0,
	OwnedTrails = {},
	EquippedTrail = "",
	ClaimedRewards = {},
}

return ProfileTemplate
