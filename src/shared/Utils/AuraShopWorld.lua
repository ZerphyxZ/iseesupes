--!strict

local Workspace = game:GetService("Workspace")

local AuraShopConfigs = require(script.Parent.Parent.Configs.AuraShopConfigs)
local MapWorld = require(script.Parent.MapWorld)

export type TouchBinding = {
	touch: BasePart,
	host: Model,
	offer: AuraShopConfigs.AuraOffer,
}

export type CollectOptions = {
	warnIfMissing: boolean?,
}

local missingTouchWarned: { [string]: boolean } = {}
local missingModelWarned: { [string]: boolean } = {}

local AuraShopWorld = {}

function AuraShopWorld.getShowcaseFolder(): Instance?
	local underMap = MapWorld.findChildInMap(AuraShopConfigs.ShowcaseFolderName)
	if underMap then
		return underMap
	end
	return Workspace:FindFirstChild(AuraShopConfigs.ShowcaseFolderName)
end

function AuraShopWorld.getAuraFolder(): Instance?
	local showcase = AuraShopWorld.getShowcaseFolder()
	if not showcase then
		return nil
	end
	return showcase:FindFirstChild(AuraShopConfigs.AuraFolderName)
end

function AuraShopWorld.getScanRoots(): { Instance }
	local roots: { Instance } = {}
	local map = MapWorld.getMapFolder()
	if map then
		table.insert(roots, map)
	end
	local showcase = AuraShopWorld.getShowcaseFolder()
	if showcase then
		table.insert(roots, showcase)
	end
	if #roots == 0 then
		table.insert(roots, Workspace)
	end
	return roots
end

function AuraShopWorld.findOfferModel(offer: AuraShopConfigs.AuraOffer): Model?
	for _, root in AuraShopWorld.getScanRoots() do
		local found = root:FindFirstChild(offer.ModelName, true)
		if found and found:IsA("Model") then
			return found
		end
	end
	return nil
end

--- All purchase hitboxes under Decor (Touch + Part platform — players often step on Part).
function AuraShopWorld.findTouchPartsDeep(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}

	local function add(part: BasePart)
		if seen[part] then
			return
		end
		seen[part] = true
		table.insert(parts, part)
	end

	local decor = root:FindFirstChild(AuraShopConfigs.DecorModelName, true)
	if decor then
		for _, child in decor:GetChildren() do
			if child:IsA("BasePart") then
				add(child)
			end
		end
		local touch = decor:FindFirstChild(AuraShopConfigs.TouchPartName, true)
		if touch and touch:IsA("BasePart") then
			add(touch)
		end
	end

	for _, desc in root:GetDescendants() do
		if desc.Name == AuraShopConfigs.TouchPartName and desc:IsA("BasePart") then
			add(desc)
		end
	end

	return parts
end

function AuraShopWorld.findTouchPartDeep(root: Instance): BasePart?
	local parts = AuraShopWorld.findTouchPartsDeep(root)
	return parts[1]
end

function AuraShopWorld.resolveProductId(host: Instance, offer: AuraShopConfigs.AuraOffer): number
	local attrName = AuraShopConfigs.ProductIdAttribute
	local keyAttr = AuraShopConfigs.AuraKeyAttribute

	for _, desc in host:GetDescendants() do
		local v = desc:GetAttribute(attrName)
		if typeof(v) == "number" and v > 0 then
			return v
		end
	end

	local rootPid = host:GetAttribute(attrName)
	if typeof(rootPid) == "number" and rootPid > 0 then
		return rootPid
	end

	return offer.ProductId
end

local function hostModelForTouch(touch: BasePart): Model?
	local current: Instance? = touch
	while current do
		if current:IsA("Model") and AuraShopConfigs.GetOfferByModelName(current.Name) then
			return current
		end
		current = current.Parent
	end
	return touch:FindFirstAncestorOfClass("Model")
end

function AuraShopWorld.resolveOfferFromTouch(touch: BasePart): (AuraShopConfigs.AuraOffer?, Model?)
	local attrName = AuraShopConfigs.ProductIdAttribute
	local keyAttr = AuraShopConfigs.AuraKeyAttribute

	local node: Instance? = touch
	while node do
		local pid = node:GetAttribute(attrName)
		if typeof(pid) == "number" and pid > 0 then
			local offer = AuraShopConfigs.GetOfferByProductId(pid)
			if offer then
				return offer, hostModelForTouch(touch)
			end
		end
		local key = node:GetAttribute(keyAttr)
		if typeof(key) == "string" then
			local offer = AuraShopConfigs.GetOfferByKey(key)
			if offer then
				return offer, hostModelForTouch(touch)
			end
		end
		node = node.Parent
	end

	local host = hostModelForTouch(touch)
	if host then
		local offer = AuraShopConfigs.GetOfferByModelName(host.Name)
		if offer then
			return offer, host
		end
	end

	return nil, host
end

function AuraShopWorld.collectTouchBindings(options: CollectOptions?): { TouchBinding }
	local bindings: { TouchBinding } = {}
	local seen: { [BasePart]: boolean } = {}
	local warnIfMissing = options and options.warnIfMissing == true

	local function addBinding(touch: BasePart, host: Model, offer: AuraShopConfigs.AuraOffer)
		if seen[touch] then
			return
		end
		seen[touch] = true
		table.insert(bindings, {
			touch = touch,
			host = host,
			offer = offer,
		})
	end

	for _, offer in AuraShopConfigs.Offers do
		local model = AuraShopWorld.findOfferModel(offer)
		if model then
			local touches = AuraShopWorld.findTouchPartsDeep(model)
			if #touches == 0 then
				local key = model:GetFullName()
				if warnIfMissing and not missingTouchWarned[key] then
					missingTouchWarned[key] = true
					warn("[iseesupes][AuraShop] no Decor/Touch on", model:GetFullName())
				end
			end
			for _, touch in touches do
				addBinding(touch, model, offer)
			end
		else
			local key = offer.ModelName
			if warnIfMissing and not missingModelWarned[key] then
				missingModelWarned[key] = true
				warn("[iseesupes][AuraShop] model not found:", offer.ModelName, offer.DisplayName)
			end
		end
	end

	for _, root in AuraShopWorld.getScanRoots() do
		for _, desc in root:GetDescendants() do
			if desc.Name == AuraShopConfigs.TouchPartName and desc:IsA("BasePart") then
				local offer, host = AuraShopWorld.resolveOfferFromTouch(desc)
				if offer and host then
					addBinding(desc, host, offer)
				end
			end
		end
	end

	return bindings
end

function AuraShopWorld.stampConfiguredTouches()
	for _, offer in AuraShopConfigs.Offers do
		local model = AuraShopWorld.findOfferModel(offer)
		if not model then
			continue
		end
		for _, touch in AuraShopWorld.findTouchPartsDeep(model) do
			touch:SetAttribute(AuraShopConfigs.ProductIdAttribute, offer.ProductId)
			touch:SetAttribute(AuraShopConfigs.AuraKeyAttribute, offer.Key)
			touch.CanTouch = true
		end
	end
end

return AuraShopWorld
