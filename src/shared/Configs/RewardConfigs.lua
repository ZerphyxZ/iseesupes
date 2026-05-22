--!strict

-- Timed reward slot definitions. Each of the 12 slots is independent.
-- CooldownHours: how long (real hours) before this slot can be claimed again.
-- Grant.Type: "Speed" adds to data.Speed (XP); "SpeedPoints" adds to data.SpeedPoints.
-- Grant.Amount: how much to add.
-- Label: shown on the Reward TextLabel inside the button.

export type RewardGrant = {
	Type: "Speed" | "SpeedPoints",
	Amount: number,
}

export type RewardInfo = {
	Label: string,
	CooldownHours: number,
	Grant: RewardGrant,
}

local RewardConfigs = {}

RewardConfigs.Rewards = {
	{ Label = "+50 Speed XP",    CooldownHours = 1,  Grant = { Type = "Speed",       Amount = 50  } },
	{ Label = "+5 SP",           CooldownHours = 2,  Grant = { Type = "SpeedPoints", Amount = 5   } },
	{ Label = "+120 Speed XP",   CooldownHours = 3,  Grant = { Type = "Speed",       Amount = 120 } },
	{ Label = "+10 SP",          CooldownHours = 4,  Grant = { Type = "SpeedPoints", Amount = 10  } },
	{ Label = "+200 Speed XP",   CooldownHours = 6,  Grant = { Type = "Speed",       Amount = 200 } },
	{ Label = "+15 SP",          CooldownHours = 8,  Grant = { Type = "SpeedPoints", Amount = 15  } },
	{ Label = "+350 Speed XP",   CooldownHours = 10, Grant = { Type = "Speed",       Amount = 350 } },
	{ Label = "+20 SP",          CooldownHours = 12, Grant = { Type = "SpeedPoints", Amount = 20  } },
	{ Label = "+500 Speed XP",   CooldownHours = 16, Grant = { Type = "Speed",       Amount = 500 } },
	{ Label = "+30 SP",          CooldownHours = 18, Grant = { Type = "SpeedPoints", Amount = 30  } },
	{ Label = "+750 Speed XP",   CooldownHours = 20, Grant = { Type = "Speed",       Amount = 750 } },
	{ Label = "+50 SP",          CooldownHours = 24, Grant = { Type = "SpeedPoints", Amount = 50  } },
} :: { RewardInfo }

return RewardConfigs
