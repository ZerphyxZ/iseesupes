--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)

local ThrustConfigs = SpeedConfigs.Thrust

local ThrustController = Knit.CreateController({ Name = "ThrustController" })

local ROBUX_PREFIX = utf8.char(0xE002)
local priceCache: { [number]: number } = {}

local player = Players.LocalPlayer

local thrustBoostsFrame: Frame? = nil
local strengthFrames: { [number]: Frame } = {}
local lastTouchTime = 0
local isFrameOpen = false
local isFrameBusy = false
local cachedData: any = nil

-- ──────────────────────────────────────────────────────────────────────────────
-- HELPERS
-- ──────────────────────────────────────────────────────────────────────────────

local function getLabel(parent: Instance, name: string): TextLabel?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA("TextLabel") then child :: TextLabel else nil
end

--- Studio paths (StarterGui.GUI.Frames.ThrustBoosts | JumpBoosts): StrengthN > Buy > Button, Buy > Layout, BuyRobux > Button, BuyRobux > Amount
local function getPurchaseButton(row: Frame, containerName: string): GuiButton?
	local container = row:FindFirstChild(containerName)
	if not container then
		return nil
	end
	local btn = container:FindFirstChild("Button")
	return if btn and btn:IsA("GuiButton") then btn :: GuiButton else nil
end

local function getBuyPriceLabel(row: Frame): TextLabel?
	local buyBtn = getPurchaseButton(row, "Buy")
	if not buyBtn then
		return nil
	end
	local textChild = buyBtn:FindFirstChild("Text")
	return if textChild and textChild:IsA("TextLabel") then textChild :: TextLabel else nil
end

local function getRobuxPriceLabel(row: Frame): TextLabel?
	local buyRobux = row:FindFirstChild("BuyRobux")
	if not buyRobux then
		return nil
	end
	local amount = buyRobux:FindFirstChild("Amount")
	return if amount and amount:IsA("TextLabel") then amount :: TextLabel else nil
end

local function setRobuxButtonLabel(btn: GuiButton?, productId: number)
	if not btn then
		return
	end

	local function applyText(txt: string)
		-- If the button itself is a TextButton, write directly.
		if btn:IsA("TextButton") then
			btn.Text = txt
			return
		end

		-- Otherwise try common child names used for text inside the button.
		local child = btn:FindFirstChild("Text")
			or btn:FindFirstChild("Label")
			or btn:FindFirstChild("Amount")
			or btn:FindFirstChild("Price")
		if child and child:IsA("TextLabel") then
			child.Text = txt
		end
	end

	if productId == 0 then
		applyText("—")
		return
	end

	if priceCache[productId] then
		applyText(ROBUX_PREFIX .. tostring(priceCache[productId]))
		return
	end

	applyText("...")
	task.spawn(function()
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if success and productInfo and btn.Parent then
			priceCache[productId] = productInfo.PriceInRobux
			applyText(ROBUX_PREFIX .. tostring(productInfo.PriceInRobux))
		elseif btn.Parent then
			applyText("Error")
		end
	end)
end

local function getFrame(parent: Instance, name: string): Frame?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA("Frame") then child :: Frame else nil
end

local function setGuiVisible(parent: Instance, name: string, visible: boolean)
	local child = parent:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		(child :: GuiObject).Visible = visible
	end
end

local function formatStrength(value: number): string
	return NumberFormatter.Format(math.floor(value))
end

local FRAME_CLICK_BLOCKERS = { "Layout", "Title", "Icon" }
local ROW_CLICK_BLOCKERS = { "Layout" }
local BUY_CLICK_BLOCKERS = { "Layout" }
local BUY_ROBUX_CLICK_BLOCKERS = { "Amount" }

local function setGuiInputEnabled(inst: Instance?, enabled: boolean)
	if inst and inst:IsA("GuiObject") then
		(inst :: GuiObject).Active = enabled
	end
end

local function unblockStrengthClicks(frame: Frame)
	for _, name in FRAME_CLICK_BLOCKERS do
		setGuiInputEnabled(frame:FindFirstChild(name), false)
	end
end

local function unblockPurchaseButtons(row: Frame)
	for _, name in ROW_CLICK_BLOCKERS do
		setGuiInputEnabled(row:FindFirstChild(name), false)
	end

	local buy = row:FindFirstChild("Buy")
	if buy then
		setGuiInputEnabled(buy, true)
		for _, name in BUY_CLICK_BLOCKERS do
			setGuiInputEnabled(buy:FindFirstChild(name), false)
		end
	end

	local buyRobux = row:FindFirstChild("BuyRobux")
	if buyRobux then
		setGuiInputEnabled(buyRobux, true)
		for _, name in BUY_ROBUX_CLICK_BLOCKERS do
			setGuiInputEnabled(buyRobux:FindFirstChild(name), false)
		end
	end
end

-- ...existing code...

local function setRobuxPriceLabel(label: TextLabel?, productId: number)
	if not label then
		return
	end

	if productId == 0 then
		label.Text = "—"
		return
	end

	if priceCache[productId] then
		label.Text = ROBUX_PREFIX .. tostring(priceCache[productId])
		return
	end

	label.Text = "..."
	task.spawn(function()
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if success and productInfo and label.Parent then
			priceCache[productId] = productInfo.PriceInRobux
			label.Text = ROBUX_PREFIX .. tostring(productInfo.PriceInRobux)
		elseif label.Parent then
			label.Text = "Error"
		end
	end)
end

local function bindPurchaseClick(row: Frame, containerName: string, onPurchase: () -> ())
	unblockPurchaseButtons(row)

	local lastClickAt = 0
	local function tryPurchase()
		local now = os.clock()
		if now - lastClickAt < 0.35 then
			return
		end
		lastClickAt = now
		onPurchase()
	end

	local btn = getPurchaseButton(row, containerName)
	if btn then
		btn.MouseButton1Click:Connect(tryPurchase)
	end

	local container = row:FindFirstChild(containerName)
	if container and container:IsA("GuiObject") then
		(container :: GuiObject).InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			tryPurchase()
		end)
	end
end

local function resolveCloseButton(frame: Instance): GuiButton?
	-- ThrustBoosts: direct TextButton/ImageButton named Close, or Close > Button (shop template).
	local closeRoot = frame:FindFirstChild("Close")
	if closeRoot then
		if closeRoot:IsA("GuiButton") then
			return closeRoot :: GuiButton
		end
		local inner = closeRoot:FindFirstChild("Button")
		if inner and (inner:IsA("TextButton") or inner:IsA("ImageButton")) then
			return inner :: GuiButton
		end
	end

	for _, name in HudConfigs.CloseButtonNames do
		local direct = frame:FindFirstChild(name)
		if direct and direct:IsA("GuiButton") then
			return direct :: GuiButton
		end
	end
	return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- UI POPULATION
-- ──────────────────────────────────────────────────────────────────────────────

-- ...existing code...
-- ...existing code...

local function refreshShopUI(data: any)
	if not thrustBoostsFrame then
		return
	end

	local currentTier = if type(data.ThrustUpgradeTier) == "number" then data.ThrustUpgradeTier else 0

	for tier = 1, 3 do
		local sf = strengthFrames[tier]
		if not sf then
			continue
		end

		local cfg = ThrustUpgradeConfigs.Tiers[tier]

		local fuelBefore = ThrustConfigs.BaseMaxFuel + ThrustUpgradeConfigs.GetTotalBonusForTier(tier - 1)
		local fuelAfter = ThrustConfigs.BaseMaxFuel + ThrustUpgradeConfigs.GetTotalBonusForTier(tier)

		local currentLabel = getLabel(sf, "CurrentStrength")
		local nextLabel = getLabel(sf, "NextStrength")
		local infoLabel = getLabel(sf, "Info")
		local buyFrame = getFrame(sf, "Buy")
		local buyBtn = getPurchaseButton(sf, "Buy")
		local buyRobuxBtn = getPurchaseButton(sf, "BuyRobux")
		local buyPriceLabel = getBuyPriceLabel(sf)
		local robuxPriceLabel = getRobuxPriceLabel(sf)

		if currentLabel then
			currentLabel.Text = formatStrength(fuelBefore)
		end
		if nextLabel then
			nextLabel.Text = formatStrength(fuelAfter)
		end
		if infoLabel then
			infoLabel.Text = string.format("+%d Thrust Boost", cfg.FuelBonus)
		end

		setGuiVisible(sf, "Owned", false)
		if buyFrame then
			buyFrame.Visible = true
		end
		setGuiVisible(sf, "BuyRobux", true)

		if buyPriceLabel then
			buyPriceLabel.Text = NumberFormatter.Format(cfg.WinCost)
		end
		if robuxPriceLabel then
			setRobuxPriceLabel(robuxPriceLabel, cfg.ProductId)
		end

		if buyBtn then
			if buyBtn:IsA("TextButton") then
				buyBtn.Text = ""
			end
			buyBtn.Active = true
			buyBtn.AutoButtonColor = true
		end

		if buyRobuxBtn then
			if buyRobuxBtn:IsA("TextButton") then
				buyRobuxBtn.Text = ""
			end
			setRobuxButtonLabel(buyRobuxBtn, cfg.ProductId)
			buyRobuxBtn.Active = (cfg.ProductId ~= 0)
			buyRobuxBtn.AutoButtonColor = (cfg.ProductId ~= 0)
		end

		unblockPurchaseButtons(sf)
	end
end
-- ──────────────────────────────────────────────────────────────────────────────
-- FRAME OPEN / CLOSE
-- ──────────────────────────────────────────────────────────────────────────────

local function openShop()
	if not thrustBoostsFrame or isFrameOpen or isFrameBusy then
		return
	end

	unblockStrengthClicks(thrustBoostsFrame)
	if cachedData then
		refreshShopUI(cachedData)
	end

	isFrameBusy = true
	isFrameOpen = true
	HudAnimations.openFrameY(thrustBoostsFrame, HudConfigs.OpenDuration, function()
		isFrameBusy = false
	end)
end

local function closeShop()
	if not thrustBoostsFrame or not isFrameOpen or isFrameBusy then
		return
	end

	isFrameBusy = true
	isFrameOpen = false
	HudAnimations.closeFrameY(thrustBoostsFrame, HudConfigs.CloseDuration, function()
		isFrameBusy = false
	end)
end

local function bindCloseButton(frame: Instance)
	local closeBtn = resolveCloseButton(frame)
	if not closeBtn then
		warn("[iseesupes] ThrustController: Close button not found under ThrustBoosts")
		return
	end

	closeBtn.MouseButton1Click:Connect(function()
		closeShop()
	end)
end

local CLOSE_DISTANCE = 20

local function startProximityWatcher(touchPart: BasePart)
	RunService.Heartbeat:Connect(function()
		if not isFrameOpen then
			return
		end
		local character = player.Character
		if not character then
			closeShop()
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		if (root.Position - touchPart.Position).Magnitude > CLOSE_DISTANCE then
			closeShop()
		end
	end)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- KNIT START
-- ──────────────────────────────────────────────────────────────────────────────

function ThrustController:KnitStart()
	local DataService = Knit.GetService("DataService")
	local ThrustUpgradeService = Knit.GetService("ThrustUpgradeService")

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 60)
	if not gui then
		warn("[iseesupes] ThrustController: timed out waiting for PlayerGui.GUI")
		return
	end

	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		warn("[iseesupes] ThrustController: no Frames container in GUI")
		return
	end

	thrustBoostsFrame = (
		frames:FindFirstChild("ThrustBoosts")
		or frames:FindFirstChild("JumpBoosts")
		or frames:FindFirstChild("UPGRADES")
	) :: Frame?
	if not thrustBoostsFrame then
		warn("[iseesupes] ThrustController: ThrustBoosts / UPGRADES frame not found under GUI.Frames")
		return
	end

	HudAnimations.rememberBaseSize(thrustBoostsFrame)
	thrustBoostsFrame.Visible = false
	unblockStrengthClicks(thrustBoostsFrame)

	bindCloseButton(thrustBoostsFrame)

	for i = 1, 3 do
		local sf = thrustBoostsFrame:FindFirstChild("Strength" .. i) :: Frame?
		if sf then
			strengthFrames[i] = sf
			unblockPurchaseButtons(sf)
		end
	end

	-- Wire Buy (wins) and BuyRobux buttons for each tier
	-- ...existing code...
	-- Wire Buy (wins) and BuyRobux buttons for each tier
	for tier = 1, 3 do
		local sf = strengthFrames[tier]
		if not sf then
			continue
		end

		local tierCfg = ThrustUpgradeConfigs.Tiers[tier]
		local t = tier

		-- removed client-side "Already owned" guard so purchases can be repeated
		bindPurchaseClick(sf, "Buy", function()
			ThrustUpgradeService:BuyUpgrade(t)
		end)

		if tierCfg then
			bindPurchaseClick(sf, "BuyRobux", function()
				if tierCfg.ProductId == 0 then
					NotificationManager.show(
						"Robux upgrade not configured yet — add ProductId in ThrustUpgradeConfigs.",
						"Info"
					)
					return
				end
				MarketplaceService:PromptProductPurchase(player, tierCfg.ProductId)
			end)
		end
	end
	-- ...existing code...
	-- Refresh UI on every data replicate
	DataService.DataReplicated:Connect(function(data: any)
		cachedData = data
		if isFrameOpen then
			refreshShopUI(data)
		end
	end)

	-- Handle purchase results
	ThrustUpgradeService.UpgradeResult:Connect(function(result: string, tier: number)
		if result == "Success" then
			NotificationManager.show("Thrust upgraded to Tier " .. tier .. "!", "Success")
			if cachedData then
				refreshShopUI(cachedData)
			end
		elseif result == "NotEnoughWins" then
			NotificationManager.show("Not enough Wins!", "Error")
		elseif result == "AlreadyOwned" then
			NotificationManager.show("Already owned.", "Info")
		elseif result == "MustBuyPrevious" then
			NotificationManager.show("Buy the previous tier first.", "Info")
		end
	end)

	-- Find touch part in workspace
	local shopFolder = MapWorld.findChildInMap(ThrustUpgradeConfigs.FolderName)
	if not shopFolder then
		warn("[iseesupes] ThrustController: Workspace.Map." .. ThrustUpgradeConfigs.FolderName .. " not found")
		return
	end

	local uTouch = shopFolder:FindFirstChild(ThrustUpgradeConfigs.TouchModelName)
	if not uTouch then
		warn("[iseesupes] ThrustController: UTouch model not found")
		return
	end

	local touchPart = uTouch:FindFirstChild(ThrustUpgradeConfigs.TouchPartName) :: BasePart?
	if not touchPart or not touchPart:IsA("BasePart") then
		warn("[iseesupes] ThrustController: Touch part not found in UTouch")
		return
	end

	touchPart.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		if Players:GetPlayerFromCharacter(character) ~= player then
			return
		end

		local now = os.clock()
		if now - lastTouchTime < ThrustUpgradeConfigs.TouchDebounce then
			return
		end
		lastTouchTime = now

		if cachedData == nil then
			cachedData = DataService:RequestData()
		end
		openShop()
	end)

	startProximityWatcher(touchPart)

	-- Apply row visibility before first open (Robux rows, prices).
	task.defer(function()
		if cachedData == nil then
			cachedData = DataService:RequestData()
		end
		if cachedData then
			refreshShopUI(cachedData)
		else
			refreshShopUI({ ThrustUpgradeTier = 0 })
		end
	end)

	print("[iseesupes] ThrustController ready.")
end

return ThrustController
