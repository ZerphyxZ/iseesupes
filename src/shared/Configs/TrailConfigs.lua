--!strict

-- Trail shop definitions. Set ProductId from Creator Dashboard (Developer Products).
-- Id = 0 disables Robux purchase until configured.
--
-- Example entry:
--   { ID = "FireTrail", Name = "Fire", WinCost = 500, ProductId = 1234567890, SpeedBoost = 1.5, Image = "rbxassetid://0" }

export type TrailInfo = {
	ID: string,
	Name: string,
	WinCost: number,
	ProductId: number,
	SpeedBoost: number,
	Image: string?,
	Color: ColorSequence?,
}

local TrailConfigs = {}

--- Shop list row: ReplicatedStorage → Templates → TrailTemplate (Studio).
TrailConfigs.ShopTemplatePath = { "Templates", "TrailTemplate" }

--- Legacy path if an older place still uses Particles/Trail/Template.
TrailConfigs.ShopTemplatePathLegacy = { "Particles", "Trail", "Template", "TrailTemplate" }

TrailConfigs.Trails = {} :: { TrailInfo }

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

return TrailConfigs
