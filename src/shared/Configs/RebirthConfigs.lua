--!strict

-- Rebirth: reset Speed XP (re-locks stage gates) in exchange for permanent,
-- compounding power. Each rebirth grants:
--   * +WinsMultAdd Wins multiplier on stage-end button claims (the core grind)
--   * +MultAdd Speed XP gain multiplier (movement AND treadmill XP)
--   * +ThrustBonusPerRebirth permanent Max Thrust (stacks with Thrust Packs)
-- Wins, thrust upgrades, avatars, trails are all kept.
--
-- The Wins multiplier is the headline perk since wins drive the whole loop now
-- (every stage is reachable regardless of speed → the grind IS the win economy).
-- It only scales the player's GRINDING (button claims), not gift wins (login /
-- playtime / starter pack). Self-limited: each rebirth costs a full level reset,
-- so +100% at 10 rebirths is a real investment, no artificial cap needed.

local RebirthConfigs = {
	LevelStep = 5,
	MultAdd = 0.5,
	--- Permanent Wins multiplier added per rebirth (applied to button claims).
	WinsMultAdd = 0.10,
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

--- Wins multiplier from rebirths (1 = no bonus). Applied to stage-end button claims.
function RebirthConfigs.GetWinsMultiplier(rebirths: number): number
	if type(rebirths) ~= "number" or rebirths <= 0 then
		return 1
	end
	return 1 + (math.floor(rebirths) * RebirthConfigs.WinsMultAdd)
end

--- Wins actually granted for a base stage-end amount at a rebirth count: the Wins multiplier with
--- round-half-up, never below the base. SINGLE SOURCE OF TRUTH so display == payout everywhere —
--- used by GiveWinsService, GiveDoubleWinsService (Robux 2x buttons), and the client label
--- controller. Each button's authored WinAmount is the `base` (the free buttons' base, and the 2x
--- buttons' already-doubled authored value — so the 2x stays a real multiple instead of eroding).
function RebirthConfigs.ApplyWinsBoost(base: number, rebirths: number): number
	if type(rebirths) ~= "number" or rebirths <= 0 then
		return base
	end
	return math.max(base, math.floor(base * RebirthConfigs.GetWinsMultiplier(rebirths) + 0.5))
end

function RebirthConfigs.GetThrustBonus(rebirths: number): number
	if type(rebirths) ~= "number" or rebirths <= 0 then
		return 0
	end
	return math.floor(rebirths) * RebirthConfigs.ThrustBonusPerRebirth
end

return RebirthConfigs
