--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local AuraShopConfigs = require(ReplicatedStorage.Shared.Configs.AuraShopConfigs)
local AuraShopWorld = require(ReplicatedStorage.Shared.Utils.AuraShopWorld)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)

local DataService: any = nil
local DoubleJumpService: any = nil
local SuperJumpService: any = nil
local HeatVisionService: any = nil
local equipMutex: { [Player]: boolean } = {}

local function endActiveAbilitiesBeforeMorph(player: Player)
	if DoubleJumpService and DoubleJumpService.ForceEndForLobby then
		DoubleJumpService:ForceEndForLobby(player)
	end
	if SuperJumpService and SuperJumpService._endAbility then
		SuperJumpService:_endAbility(player)
	end
	if HeatVisionService and HeatVisionService.ForceEndForLobby then
		HeatVisionService:ForceEndForLobby(player)
	end
end

local AuraShopService = Knit.CreateService({
	Name = "AuraShopService",
	Client = {
		RequestProductPrompt = Knit.CreateSignal(),
		EquipAura = Knit.CreateSignal(),
	},
})

local touchConns: { RBXScriptConnection } = {}
local boundTouches: { [BasePart]: boolean } = {}
local lastTouchAt: { [Player]: number } = {}

local function disconnectAll()
	for _, conn in touchConns do
		conn:Disconnect()
	end
	table.clear(touchConns)
	table.clear(boundTouches)
end

local function bindTouch(touch: BasePart, offer: AuraShopConfigs.AuraOffer)
	if boundTouches[touch] then
		return
	end
	boundTouches[touch] = true
	touch.CanTouch = true

	table.insert(
		touchConns,
		touch.Touched:Connect(function(hit: BasePart)
			if not hit or not hit.Parent then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end

			local now = os.clock()
			local last = lastTouchAt[player] or 0
			if now - last < AuraShopConfigs.TouchDebounce then
				return
			end
			lastTouchAt[player] = now

			-- If player already owns this aura → equip it instead of prompting purchase.
			local profile = DataService and DataService:GetProfile(player)
			if profile and typeof(profile.Data.OwnedAuras) == "table" and profile.Data.OwnedAuras[offer.Key] == true then
				StudioLog.print("AuraShop", "[iseesupes][AuraShop][Server] touch (owned) → equipping", offer.Key, "for", player.Name)
				AuraShopService:EquipAura(player, offer.Key)
				return
			end

			local host = touch:FindFirstAncestorOfClass("Model")
			local productId = AuraShopWorld.resolveProductId(host or touch, offer)
			StudioLog.print("AuraShop", "[iseesupes][AuraShop][Server] touch", offer.Key, "productId=", productId, "→", player.Name)
			AuraShopService.Client.RequestProductPrompt:Fire(player, productId, offer.DisplayName)
		end)
	)

	StudioLog.print("AuraShop", "[iseesupes][AuraShop][Server] bound", offer.DisplayName, "→", touch:GetFullName())
end

function AuraShopService:ScanAndBindAll(): number
	disconnectAll()
	AuraShopWorld.stampConfiguredTouches()

	local bindings = AuraShopWorld.collectTouchBindings()
	for _, binding in bindings do
		bindTouch(binding.touch, binding.offer)
	end

	if #bindings == 0 then
		warn(
			"[iseesupes][AuraShop][Server] no Touch parts found — add StarterCharacterAura / StarterCharacterAura2 with Decor/Touch under AvatarsShowcase (or set ProductId on Touch)"
		)
	else
		StudioLog.print("AuraShop", "[iseesupes][AuraShop][Server] scan complete,", #bindings, "touch binding(s)")
	end
	return #bindings
end

--- Strip showcase-only children (Decor stand + any loose base Part) and rescale
--- oversized showcase models down to standard player size.
local function makeCleanTemplate(template: Model): Model
	local clone = template:Clone()
	-- Remove the showcase pedestal / stand model
	local decor = clone:FindFirstChild(AuraShopConfigs.DecorModelName)
	if decor then
		decor:Destroy()
	end
	-- Remove any top-level Part that isn't a known body part (e.g. the aura-base platform)
	for _, child in clone:GetChildren() do
		if child.Name == "Part" and child:IsA("BasePart") then
			child:Destroy()
		end
	end
	-- Note: showcase models were pre-scaled to GetScale=1 (standard player size) in Studio.
	-- No runtime ScaleTo needed — avoids lag spikes from scaling large models at runtime.
	return clone
end

function AuraShopService:GrantAura(player: Player, key: string): boolean
	local offer = AuraShopConfigs.GetOfferByKey(key)
	if not offer then
		return false
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local data = profile.Data
	if typeof(data.OwnedAuras) ~= "table" then
		data.OwnedAuras = {}
	end

	data.OwnedAuras[key] = true
	-- An aura purchase ALWAYS sets the equipped aura (player just spent Robux — they want it equipped).
	data.EquippedAura = key
	-- NOTE: we DON'T clear EquippedAvatar. UpgradeWinsService.TryEquipFromProfile now
	-- checks EquippedAura first and skips if set, so the user's avatar choice is preserved
	-- in case they unequip the aura later.

	DataService:Replicate(player)
	-- Force-save immediately — Robux purchases must be durable even if Studio test stops.
	if DataService.ForceSave then
		DataService:ForceSave(player)
	end

	-- Apply the aura character immediately (morph player into the showcase model).
	-- Guard against concurrent equip calls for the same player.
	if not equipMutex[player] then
		equipMutex[player] = true
		task.defer(function()
			endActiveAbilitiesBeforeMorph(player)
			local showcaseFolder = AuraShopWorld.getShowcaseFolder()
			if showcaseFolder then
				local template = showcaseFolder:FindFirstChild(offer.ModelName)
				if template and template:IsA("Model") then
					local cleanTemplate = makeCleanTemplate(template)
					-- Full character swap: the Aura skins use entirely different MeshPart
					-- meshes that cannot be changed via visual-only morph (MeshId is read-only).
					AvatarReplace.replacePlayerCharacter(player, cleanTemplate, offer.ModelName)
					cleanTemplate:Destroy()
				else
					warn("[iseesupes][AuraShop] Template not found:", offer.ModelName)
				end
			end
			equipMutex[player] = nil
		end)
	end

	StudioLog.print("Gameplay", "[iseesupes][AuraShop] granted", key, "to", player.Name)
	return true
end

--- Re-apply a player's saved aura when they join/respawn (so the equip persists).
function AuraShopService:ReapplyFromProfile(player: Player)
	if equipMutex[player] then
		return
	end
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return
	end
	local key = profile.Data.EquippedAura
	if type(key) ~= "string" or key == "" then
		return
	end
	local offer = AuraShopConfigs.GetOfferByKey(key)
	if not offer then
		return
	end
	-- Skip if character already has this aura applied
	local character = player.Character
	if character and character:GetAttribute(AvatarReplace.EQUIPPED_SHOWCASE_ATTR) == offer.ModelName then
		return
	end

	equipMutex[player] = true
	task.defer(function()
		endActiveAbilitiesBeforeMorph(player)
		local showcaseFolder = AuraShopWorld.getShowcaseFolder()
		if showcaseFolder then
			local template = showcaseFolder:FindFirstChild(offer.ModelName)
			if template and template:IsA("Model") then
				local cleanTemplate = makeCleanTemplate(template)
				AvatarReplace.replacePlayerCharacter(player, cleanTemplate, offer.ModelName)
				cleanTemplate:Destroy()
			end
		end
		equipMutex[player] = nil
	end)
end

--- Client-callable wrapper for EquipAura (so client touch handler can request equip).
function AuraShopService.Client:EquipAura(player: Player, key: string): boolean
	if typeof(key) ~= "string" or key == "" then
		return false
	end
	return AuraShopService:EquipAura(player, key)
end

--- Equip an aura that the player already owns.
function AuraShopService:EquipAura(player: Player, key: string): boolean
	local offer = AuraShopConfigs.GetOfferByKey(key)
	if not offer then
		return false
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local data = profile.Data
	-- Check that player owns this aura
	if typeof(data.OwnedAuras) ~= "table" or data.OwnedAuras[key] ~= true then
		warn("[iseesupes][AuraShop] EquipAura: player", player.Name, "does not own", key)
		return false
	end

	-- Set as equipped aura and replicate
	data.EquippedAura = key
	DataService:Replicate(player)

	-- Apply the aura character immediately (morph player into the showcase model).
	-- Guard against concurrent equip calls for the same player.
	if not equipMutex[player] then
		equipMutex[player] = true
		task.defer(function()
			endActiveAbilitiesBeforeMorph(player)
			local showcaseFolder = AuraShopWorld.getShowcaseFolder()
			if showcaseFolder then
				local template = showcaseFolder:FindFirstChild(offer.ModelName)
				if template and template:IsA("Model") then
					local cleanTemplate = makeCleanTemplate(template)
					AvatarReplace.replacePlayerCharacter(player, cleanTemplate, offer.ModelName)
					cleanTemplate:Destroy()
				else
					warn("[iseesupes][AuraShop] Template not found:", offer.ModelName)
				end
			end
			equipMutex[player] = nil
		end)
	end

	StudioLog.print("Gameplay", "[iseesupes][AuraShop] equipped", key, "for", player.Name)
	return true
end

function AuraShopService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function()
		DoubleJumpService = Knit.GetService("DoubleJumpService")
	end)
	pcall(function()
		SuperJumpService = Knit.GetService("SuperJumpService")
	end)
	pcall(function()
		HeatVisionService = Knit.GetService("HeatVisionService")
	end)

	task.defer(function()
		for attempt = 1, 30 do
			local count = AuraShopService:ScanAndBindAll()
			if count > 0 then
				break
			end
			task.wait(2)
		end
	end)

	local showcase = AuraShopWorld.getShowcaseFolder()
	if showcase then
		showcase.DescendantAdded:Connect(function(desc)
			if desc.Name == AuraShopConfigs.TouchPartName and desc:IsA("BasePart") then
				task.defer(AuraShopService.ScanAndBindAll)
			end
		end)
	end

	-- Re-apply saved aura on every character spawn (persists across rebirths/respawns).
	-- Retry up to 5 seconds for profile data to load (race on first rejoin).
	local function reapplyWithRetry(player: Player)
		task.spawn(function()
			for _ = 1, 10 do
				if not player.Parent then return end
				local profile = DataService and DataService:GetProfile(player)
				if profile then
					AuraShopService:ReapplyFromProfile(player)
					return
				end
				task.wait(0.5)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			reapplyWithRetry(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			reapplyWithRetry(player)
		end
		player.CharacterAdded:Connect(function()
			reapplyWithRetry(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTouchAt[player] = nil
		equipMutex[player] = nil
	end)

	StudioLog.ready("AuraShopService")
end

return AuraShopService
