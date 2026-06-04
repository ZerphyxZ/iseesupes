--!strict

-- World showcase auras (Workspace.Map.AvatarsShowcase.R-AURA or Workspace.AvatarsShowcase.R-AURA).
-- Each offer model contains Decor → Touch (developer product purchase on touch).

export type AuraOffer = {
	Key: string,
	DisplayName: string,
	--- Model name under the aura folder (e.g. StarterCharacterAura).
	ModelName: string,
	ProductId: number,
}

local AuraShopConfigs = {
	ShowcaseFolderName = "AvatarsShowcase",
	AuraFolderName = "R-AURA",
	DecorModelName = "Decor",
	TouchPartName = "Touch",
	TouchDebounce = 1.5,
	ProductIdAttribute = "ProductId",
	AuraKeyAttribute = "AuraKey",

	Offers = {
		{
			Key = "KryptonianWarrior",
			DisplayName = "Kryptonian Warrior",
			ModelName = "StarterCharacterAura",
			ProductId = 3602183647,
		},
		{
			Key = "DarkSuperman",
			DisplayName = "Dark Superman",
			ModelName = "StarterCharacterAura2",
			ProductId = 3602183718,
		},
	} :: { AuraOffer },
}

local byKey: { [string]: AuraOffer } = {}
local byProductId: { [number]: AuraOffer } = {}
local byModelName: { [string]: AuraOffer } = {}

local function rebuildIndexes()
	table.clear(byKey)
	table.clear(byProductId)
	table.clear(byModelName)
	for _, offer in AuraShopConfigs.Offers do
		byKey[offer.Key] = offer
		byModelName[offer.ModelName] = offer
		if offer.ProductId ~= 0 then
			byProductId[offer.ProductId] = offer
		end
	end
end

rebuildIndexes()

function AuraShopConfigs.GetOfferByKey(key: string): AuraOffer?
	return byKey[key]
end

function AuraShopConfigs.GetOfferByProductId(productId: number): AuraOffer?
	return byProductId[productId]
end

function AuraShopConfigs.GetOfferByModelName(modelName: string): AuraOffer?
	return byModelName[modelName]
end

return AuraShopConfigs
