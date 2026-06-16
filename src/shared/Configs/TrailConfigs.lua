--!strict

-- Trail shop definitions. Set ProductId from Creator Dashboard (Developer Products).
-- ProductId = 0 disables Robux purchase until configured.
--
-- Balancing (tune WinCost here after playtest):
--   Superman 50 wins — target: a few stage clears after onboarding.
--   SpeedBoost applies to walk/swim cap when equipped (see CharacterMovementSpeed).
--   Compare wins/stage on Map GiveWins buttons vs these costs.

export type TrailInfo = {
	ID: string,
	Name: string,
	WinCost: number,
	ProductId: number,
	SpeedBoost: number,
	Image: string?,
	Color: ColorSequence?,
}

local TrailConfigs = {
	DefaultTrailId = "",

	--- Row template inside GUI.Frames.Trails.Scrolling (Studio layout).
	ShopTemplateScrollingPath = { "Scrolling", "TrailTemplate" },

	--- Fallback: ReplicatedStorage → Templates → TrailTemplate
	ShopTemplatePath = { "Templates", "TrailTemplate" },
	ShopTemplatePathLegacy = { "Particles", "Trail", "Template", "TrailTemplate" },

	ShopTemplateName = "TrailTemplate",

	-- Cheapest → most expensive (shop list order).
	Trails = {
		{
			ID = "SupermanClassic",
			Name = "Superman",
			WinCost = 150,
			ProductId = 3602184828, -- Developer Product: Superman Trail
			SpeedBoost = 1.5,
			Image = "rbxassetid://120995773891656",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 30, 30)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 80, 220)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 50)),
			}),
		},
		{
			ID = "Kryptonite",
			Name = "Kryptonite",
			WinCost = 1500,
			ProductId = 3602184962, -- Developer Product: Kryptonite Trail
			SpeedBoost = 1.5,
			Image = "rbxassetid://75031648687157",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 200, 80)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 255, 120)),
			}),
		},
		{
			ID = "Ice",
			Name = "Arctic",
			WinCost = 2500,
			ProductId = 3602185251, -- Developer Product: Arctic Trail
			SpeedBoost = 1.5,
			Image = "rbxassetid://70542207066635",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 250, 255)),
			}),
		},
		{
			ID = "Solar",
			Name = "Solar",
			WinCost = 4000,
			ProductId = 3602185055, -- Developer Product: Solar Trail
			SpeedBoost = 2,
			Image = "rbxassetid://100582612862019",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 100)),
			}),
		},
	} :: { TrailInfo },
}

local byId: { [string]: TrailInfo } = {}
local byProductId: { [number]: TrailInfo } = {}

local function rebuildIndexes()
	table.clear(byId)
	table.clear(byProductId)
	for _, info in TrailConfigs.Trails do
		byId[info.ID] = info
		if info.ProductId ~= 0 then
			byProductId[info.ProductId] = info
		end
	end
end

rebuildIndexes()

function TrailConfigs.GetTrailById(id: string): TrailInfo?
	return byId[id]
end

function TrailConfigs.GetTrailByProductId(productId: number): TrailInfo?
	return byProductId[productId]
end

function TrailConfigs.GetDefaultTrail(): TrailInfo?
	if TrailConfigs.DefaultTrailId == "" then
		return nil
	end
	return TrailConfigs.GetTrailById(TrailConfigs.DefaultTrailId)
end

function TrailConfigs.IsTrailRowName(name: string): boolean
	return byId[name] ~= nil
end

--- Walk/swim speed multiplier when this trail is equipped and owned (1 = no boost).
function TrailConfigs.GetEquippedSpeedMultiplier(data: any): number
	if not data then
		return 1
	end
	local equipped = data.EquippedTrail
	if type(equipped) ~= "string" or equipped == "" then
		return 1
	end
	if typeof(data.OwnedTrails) ~= "table" or data.OwnedTrails[equipped] ~= true then
		return 1
	end
	local info = TrailConfigs.GetTrailById(equipped)
	if not info then
		return 1
	end
	local boost = info.SpeedBoost
	if typeof(boost) ~= "number" or boost <= 0 then
		return 1
	end
	return boost
end

--- Ensures OwnedTrails table exists. Does NOT auto-grant any trail.
function TrailConfigs.EnsureDefaultTrail(data: any)
	if not data then
		return
	end
	if not data.OwnedTrails or typeof(data.OwnedTrails) ~= "table" then
		data.OwnedTrails = {}
	end

	local defaultId = TrailConfigs.DefaultTrailId
	if defaultId ~= "" then
		data.OwnedTrails[defaultId] = true
		if type(data.EquippedTrail) ~= "string" or data.EquippedTrail == "" then
			data.EquippedTrail = defaultId
		end
	end
end

return TrailConfigs
