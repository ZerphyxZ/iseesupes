--!strict

-- Rebirth: reset Speed XP (re-locks stage gates) in exchange for permanent,
-- compounding power. Each rebirth grants:
--   * +MultAdd Speed XP gain multiplier (movement AND treadmill XP)
--   * +ThrustBonusPerRebirth permanent Max Thrust (stacks with Thrust Packs)
-- Wins, thrust upgrades, avatars, trails are all kept.

local RebirthConfigs = {
	LevelStep = 5,
	MultAdd = 0.5,
	ResetLevelOnRebirth = true,
	--- Permanent Max Thrust granted per rebirth ("always more thrust" loop).
	ThrustBonusPerRebirth = 10,
}

function RebirthConfigs.GetRequiredLevel(rebirths: number): number
	return (rebirths + 1) * RebirthConfigs.LevelStep
end

function RebirthConfigs.GetNextRequiredLevel(rebirths: number): number
	return (rebirths + 2) * RebirthConfigs.LevelStep
end

function RebirthConfigs.GetSpeedMultiplier(rebirths: number): number
	return 1 + (rebirths * RebirthConfigs.MultAdd)
end

function RebirthConfigs.GetThrustBonus(rebirths: number): number
	if type(rebirths) ~= "number" or rebirths <= 0 then
		return 0
	end
	return math.floor(rebirths) * RebirthConfigs.ThrustBonusPerRebirth
end

return RebirthConfigs
