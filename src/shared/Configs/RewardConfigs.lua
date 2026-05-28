--!strict

-- Timed reward slot definitions. Each of the 12 slots is independent.
-- CooldownHours: real hours after RewardsAnchorTime before first claim; same delay after each claim.
-- Grant.Type: "Speed" adds to data.Speed (XP); "Thrust" refills fuel; "SpeedPoints" legacy → Thrust fuel.
-- Grant.Amount: how much to add.
-- Label: shown on the Reward TextLabel inside the button.

export type RewardGrant = {
	Type: "Speed" | "SpeedPoints" | "Thrust",
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
	{ Label = "+15 Thrust",      CooldownHours = 2,  Grant = { Type = "Thrust",       Amount = 15  } },
	{ Label = "+120 Speed XP",   CooldownHours = 3,  Grant = { Type = "Speed",       Amount = 120 } },
	{ Label = "+25 Thrust",      CooldownHours = 4,  Grant = { Type = "Thrust",       Amount = 25  } },
	{ Label = "+200 Speed XP",   CooldownHours = 6,  Grant = { Type = "Speed",       Amount = 200 } },
	{ Label = "+35 Thrust",      CooldownHours = 8,  Grant = { Type = "Thrust",       Amount = 35  } },
	{ Label = "+350 Speed XP",   CooldownHours = 10, Grant = { Type = "Speed",       Amount = 350 } },
	{ Label = "+50 Thrust",      CooldownHours = 12, Grant = { Type = "Thrust",       Amount = 50  } },
	{ Label = "+500 Speed XP",   CooldownHours = 16, Grant = { Type = "Speed",       Amount = 500 } },
	{ Label = "+60 Thrust",      CooldownHours = 18, Grant = { Type = "Thrust",       Amount = 60  } },
	{ Label = "+750 Speed XP",   CooldownHours = 20, Grant = { Type = "Speed",       Amount = 750 } },
	{ Label = "+75 Thrust",      CooldownHours = 24, Grant = { Type = "Thrust",       Amount = 75  } },
} :: { RewardInfo }

return RewardConfigs
