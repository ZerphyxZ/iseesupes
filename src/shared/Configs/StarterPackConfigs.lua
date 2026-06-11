--!strict

-- Limited-time Starter Pack — drives the (already designed) GUI.HUD.StarterPack
-- button. ProductId = 0 keeps the offer hidden: create a "Starter Pack"
-- developer product in Creator Hub (suggested 9 R$ — the button art says 9),
-- paste the id here, done.
-- Countdown anchors to first join (RewardsAnchorTime); offer hides on expiry
-- or after purchase. One purchase per player (OwnedStarterPack flag).

local StarterPackConfigs = {
	ProductId = 3603845869,
	--- Offer window from first join; the button art was designed around 18h.
	OfferHours = 18,
	OwnedFlag = "OwnedStarterPack",
	HudButtonName = "StarterPack",

	--- What the pack grants (bundle ≈ 60+ R$ of value for 9 R$ — that gap is the pitch).
	Grants = {
		--- Free Thrust Pack tier 1 (+40 Max Thrust, permanent; recorded like a purchase).
		ThrustPackTier = 1,
		--- Instant Speed XP (≈ level 5-6 for a fresh player; trivial for veterans by design).
		SpeedXp = 2000,
		--- Enough Wins to taste the Upgrade Shop without trivializing it.
		Wins = 25,
		--- One GodSpeed run (infinite thrust + boosted gain until the next win claim).
		GodSpeedRun = true,
	},
}

function StarterPackConfigs.GetDeadline(data: any): number
	local anchor = if type(data.RewardsAnchorTime) == "number" then data.RewardsAnchorTime else os.time()
	return anchor + StarterPackConfigs.OfferHours * 3600
end

function StarterPackConfigs.IsOfferActive(data: any, now: number): boolean
	if StarterPackConfigs.ProductId == 0 then
		return false
	end
	if data == nil or data[StarterPackConfigs.OwnedFlag] == true then
		return false
	end
	return now < StarterPackConfigs.GetDeadline(data)
end

function StarterPackConfigs.FormatRemaining(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	return string.format("%d:%02d:%02d", h, m, sec)
end

return StarterPackConfigs
