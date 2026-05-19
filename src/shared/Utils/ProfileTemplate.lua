--!strict

export type PlayerData = {
	Coins: number,
	Level: number,
	Wins: number,
	SpeedPoints: number,
}

local ProfileTemplate: PlayerData = {
	Coins = 0,
	Level = 1,
	Wins = 0,
	SpeedPoints = 0,
}

return ProfileTemplate
