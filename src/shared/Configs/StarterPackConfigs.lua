--!strict

-- Limited-time Starter Pack — drives the (already designed) GUI.HUD.StarterPack
-- button. ProductId = 0 keeps the offer hidden: create a "Starter Pack"
-- developer product in Creator Hub (suggested 9 R$ — the button art says 9),
-- paste the id here, done.
-- Countdown loops every OfferHours until purchase (RestartOfferOnExpiry).
-- One purchase per player (OwnedStarterPack flag).

local StarterPackConfigs = {
	ProductId = 3603845869,
	--- Offer window per cycle; the button art was designed around 18h.
	OfferHours = 18,
	--- When true, timer restarts at full OfferHours each cycle instead of hiding the offer.
	RestartOfferOnExpiry = true,
	AnchorField = "StarterPackAnchorTime",
	OwnedFlag = "OwnedStarterPack",
	HudButtonName = "StarterPack",

	StandModelName = "StarterPackStand",
	GiftBoxPartName = "GiftBox",
	TouchPartName = "Touch",
	BillboardName = "Billboard",
	BillboardTimerName = "Timer",
	ResolveTimeoutSeconds = 60,
	ResolveRetrySeconds = 2,
	MaxResolveAttempts = 30,

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

function StarterPackConfigs.GetOfferCycleSeconds(): number
	return StarterPackConfigs.OfferHours * 3600
end

function StarterPackConfigs.GetOfferAnchor(data: any, now: number): number
	local field = StarterPackConfigs.AnchorField
	if type(field) == "string" and field ~= "" then
		local anchor = data[field]
		if type(anchor) == "number" then
			return anchor
		end
	end
	if type(data.RewardsAnchorTime) == "number" then
		return data.RewardsAnchorTime
	end
	return now
end

function StarterPackConfigs.GetDeadline(data: any): number
	local now = os.time()
	return StarterPackConfigs.GetOfferAnchor(data, now) + StarterPackConfigs.GetOfferCycleSeconds()
end

function StarterPackConfigs.IsOfferActive(data: any, now: number): boolean
	if StarterPackConfigs.ProductId == 0 then
		return false
	end
	if data == nil or data[StarterPackConfigs.OwnedFlag] == true then
		return false
	end
	if StarterPackConfigs.RestartOfferOnExpiry == true then
		return true
	end
	return now < StarterPackConfigs.GetDeadline(data)
end

function StarterPackConfigs.GetRemainingSeconds(data: any, now: number?): number
	if data == nil then
		return 0
	end
	local t = if type(now) == "number" then now else os.time()
	local cycle = StarterPackConfigs.GetOfferCycleSeconds()
	local anchor = StarterPackConfigs.GetOfferAnchor(data, t)

	if StarterPackConfigs.RestartOfferOnExpiry == true then
		local elapsed = math.max(0, t - anchor)
		local intoCycle = elapsed % cycle
		if intoCycle == 0 and elapsed > 0 then
			return cycle
		end
		return cycle - intoCycle
	end

	return math.max(0, anchor + cycle - t)
end

function StarterPackConfigs.FormatRemaining(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	return string.format("%d:%02d:%02d", h, m, sec)
end

return StarterPackConfigs
