--!strict

-- Touch Decor/Touch on showcase aura models → developer product purchase prompt.
-- Server also detects touch and fires RequestProductPrompt (works if client scan misses models).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AuraShopConfigs = require(ReplicatedStorage.Shared.Configs.AuraShopConfigs)
local AuraShopWorld = require(ReplicatedStorage.Shared.Utils.AuraShopWorld)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local CapeVfx = require(script.Parent.Parent.Parent.Modules.CapeVfx)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local AuraShopController = Knit.CreateController({ Name = "AuraShopController" })

local player = Players.LocalPlayer
local touchConns: { RBXScriptConnection } = {}
local boundTouches: { [BasePart]: boolean } = {}
local lastTouchAt = 0
local pendingAuraMorphSnap = false
local currentData: any = nil

local DJ_PHASE_ATTR = "DjAbilityPhase"

local function disconnectAll()
	for _, conn in touchConns do
		conn:Disconnect()
	end
	table.clear(touchConns)
	table.clear(boundTouches)
end

local function promptPurchase(productId: number, displayName: string)
	print("[iseesupes][AuraShop][Client] PromptProductPurchase", displayName, "id=", productId)
	if productId == 0 then
		NotificationManager.show(displayName .. " is not configured yet.", "Error")
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		warn("[iseesupes][AuraShop][Client] PromptProductPurchase failed:", displayName, err)
		NotificationManager.show("Could not open purchase window.", "Error")
	else
		print("[iseesupes][AuraShop][Client] prompt opened OK")
	end
end

local function localPlayerOwnsAura(offerKey: string): boolean
	local data = DataLib.GetData()
	if not data or typeof(data.OwnedAuras) ~= "table" then
		return false
	end
	return data.OwnedAuras[offerKey] == true
end

local function bindTouchClient(touch: BasePart, host: Model, offer: AuraShopConfigs.AuraOffer)
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
			if not character or Players:GetPlayerFromCharacter(character) ~= player then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end

			local now = os.clock()
			if now - lastTouchAt < AuraShopConfigs.TouchDebounce then
				return
			end
			lastTouchAt = now

			-- If already owned → equip instead of prompting purchase.
			if localPlayerOwnsAura(offer.Key) then
				print("[iseesupes][AuraShop][Client] touch (owned) → equipping", offer.Key)
				local AuraShopService = Knit.GetService("AuraShopService")
				pendingAuraMorphSnap = true
				task.spawn(function()
					AuraShopService:EquipAura(offer.Key)
				end)
				NotificationManager.show(offer.DisplayName .. " equipped!", "Success")
				return
			end

			local productId = AuraShopWorld.resolveProductId(host, offer)
			print("[iseesupes][AuraShop][Client] touch", offer.Key, "productId=", productId)
			promptPurchase(productId, offer.DisplayName)
		end)
	)

	print("[iseesupes][AuraShop][Client] bound", offer.DisplayName, "→", touch:GetFullName())
end

local function scanAndBindClient(): number
	disconnectAll()
	AuraShopWorld.stampConfiguredTouches()

	local bindings = AuraShopWorld.collectTouchBindings()
	for _, binding in bindings do
		bindTouchClient(binding.touch, binding.host, binding.offer)
	end

	print("[iseesupes][AuraShop][Client] scan found", #bindings, "binding(s)")
	if #bindings == 0 then
		warn(
			"[iseesupes][AuraShop][Client] no bindings — ensure models exist:",
			"StarterCharacterAura, StarterCharacterAura2 with Decor/Touch under AvatarsShowcase"
		)
	end
	return #bindings
end

local function resetSteerAfterMorph()
	local ok, doubleJump = pcall(function()
		return Knit.GetController("DoubleJumpController")
	end)
	if ok and doubleJump and doubleJump.resetSteerTrackingAfterMorph then
		doubleJump:resetSteerTrackingAfterMorph()
	end
end

local function snapCameraAfterMorph()
	-- Snap multiple times to defeat all timing edge cases (DjAbilityPhase still set,
	-- humanoid not yet ready, etc). Each call is cheap (just sets CameraSubject + CFrame).
	task.spawn(AvatarReplace.waitAndSnapLocalCamera, 4)
	task.delay(0.3, function()
		task.spawn(AvatarReplace.waitAndSnapLocalCamera, 4)
	end)
	task.delay(1.0, function()
		task.spawn(AvatarReplace.waitAndSnapLocalCamera, 2)
	end)
end

local function maybeSnapCameraAfterMorph()
	if not pendingAuraMorphSnap then
		return
	end
	pendingAuraMorphSnap = false
	snapCameraAfterMorph()
end

function AuraShopController:KnitStart()
	print("[iseesupes][AuraShop][Client] KnitStart")

	-- After any character swap (aura morph → replacePlayerCharacter fires CharacterAdded):
	-- re-bind the camera and refresh the cape rig so it follows the new skeleton.
	player.CharacterAdded:Connect(function(character)
		resetSteerAfterMorph()
		maybeSnapCameraAfterMorph()
		task.defer(function()
			CapeVfx.refreshAfterShowcaseEquip(character)
		end)
	end)

	local AuraShopService = Knit.GetService("AuraShopService")
	AuraShopService.RequestProductPrompt:Connect(function(productId: number, displayName: string)
		print("[iseesupes][AuraShop][Client] server requested prompt", displayName)
		promptPurchase(productId, displayName)
	end)

	local lastOwned: { [string]: boolean } = {}
	DataLib.OnChanged(function(data)
		if not data or typeof(data.OwnedAuras) ~= "table" then
			return
		end
		for _, offer in AuraShopConfigs.Offers do
			local nowOwned = data.OwnedAuras[offer.Key] == true
			local wasOwned = lastOwned[offer.Key] == true
			if nowOwned and not wasOwned then
				pendingAuraMorphSnap = true
				NotificationManager.show(offer.DisplayName .. " unlocked!", "Success")
				task.delay(1, function()
					maybeSnapCameraAfterMorph()
				end)
			end
			lastOwned[offer.Key] = nowOwned
		end
	end)

	task.spawn(function()
		for attempt = 1, 30 do
			local count = scanAndBindClient()
			if count > 0 then
				break
			end
			if attempt == 1 or attempt % 5 == 0 then
				print("[iseesupes][AuraShop][Client] retry scan attempt", attempt)
			end
			task.wait(2)
		end
	end)

	local showcase = AuraShopWorld.getShowcaseFolder()
	if showcase then
		showcase.DescendantAdded:Connect(function(desc)
			if desc.Name == AuraShopConfigs.TouchPartName and desc:IsA("BasePart") then
				task.defer(scanAndBindClient)
			end
		end)
	end

	print("[iseesupes] AuraShopController ready.")
end

return AuraShopController
