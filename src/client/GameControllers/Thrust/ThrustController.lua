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

local function getButton(parent: Instance, name: string): GuiButton?
	local frame = parent:FindFirstChild(name)
	if not frame then
		return nil
	end
	local btn = frame:FindFirstChild("Button")
	if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
		return btn :: GuiButton
	end
	return nil
end

local function getBuyPriceLabel(parent: Instance): TextLabel?
	local buyBtn = getButton(parent, "Buy")
	if not buyBtn then
		return nil
	end
	local textChild = buyBtn:FindFirstChild("Text")
	return if textChild and textChild:IsA("TextLabel") then textChild :: TextLabel else nil
end

local function getRobuxPriceLabel(parent: Instance): TextLabel?
	local robuxBtn = getButton(parent, "BuyRobux")
	if not robuxBtn then
		return nil
	end
	local amount = robuxBtn:FindFirstChild("Amount")
	if amount and amount:IsA("TextLabel") then
		return amount :: TextLabel
	end
	local textChild = robuxBtn:FindFirstChild("Text")
	return if textChild and textChild:IsA("TextLabel") then textChild :: TextLabel else nil
end

local function setRobuxPriceLabel(label: TextLabel, productId: number)
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
			return direct
		end
	end
	for _, desc in frame:GetDescendants() do
		if desc:IsA("GuiButton") then
			for _, name in HudConfigs.CloseButtonNames do
				if desc.Name == name then
					return desc
				end
			end
		end
	end
	return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- UI POPULATION
-- ──────────────────────────────────────────────────────────────────────────────

local function refreshShopUI(data: any)
	if not thrustBoostsFrame then return end

	local currentTier = if type(data.ThrustUpgradeTier) == "number" then data.ThrustUpgradeTier else 0

	for tier = 1, 3 do
		local sf = strengthFrames[tier]
		if not sf then continue end

		local cfg = ThrustUpgradeConfigs.Tiers[tier]
		local owned = currentTier >= tier
		local canBuy = (currentTier == tier - 1)

		local fuelBefore = ThrustConfigs.BaseMaxFuel + ThrustUpgradeConfigs.GetTotalBonusForTier(tier - 1)
		local fuelAfter  = ThrustConfigs.BaseMaxFuel + ThrustUpgradeConfigs.GetTotalBonusForTier(tier)

		local currentLabel = getLabel(sf, "CurrentStrength")
		local nextLabel    = getLabel(sf, "NextStrength")
		local infoLabel    = getLabel(sf, "Info")
		local ownedFrame    = getFrame(sf, "Owned")
		local buyFrame      = getFrame(sf, "Buy")
		local buyBtn          = getButton(sf, "Buy")
		local buyRobuxBtn     = getButton(sf, "BuyRobux")
		local buyPriceLabel   = getBuyPriceLabel(sf)
		local robuxPriceLabel = getRobuxPriceLabel(sf)
		local showRobuxRow = not owned
			and (cfg.ProductId ~= 0 or ThrustUpgradeConfigs.ShowRobuxWhenUnconfigured == true)
		local canPurchaseRobux = canBuy and cfg.ProductId ~= 0

		if currentLabel then currentLabel.Text = formatStrength(fuelBefore) end
		if nextLabel    then nextLabel.Text    = formatStrength(fuelAfter)  end
		if infoLabel    then
			infoLabel.Text = string.format("+%d Thrust Boost", cfg.FuelBonus)
		end

		if ownedFrame then ownedFrame.Visible = owned end
		if buyFrame   then buyFrame.Visible   = not owned end
		setGuiVisible(sf, "BuyRobux", showRobuxRow)

		if buyPriceLabel then
			buyPriceLabel.Text = NumberFormatter.Format(cfg.WinCost)
		end

		if robuxPriceLabel and showRobuxRow then
			setRobuxPriceLabel(robuxPriceLabel, cfg.ProductId)
		end

		if buyBtn then
			if buyBtn:IsA("TextButton") then
				buyBtn.Text = ""
			end
			buyBtn.Active = canBuy
			buyBtn.AutoButtonColor = canBuy
		end

		if buyRobuxBtn then
			if buyRobuxBtn:IsA("TextButton") then
				buyRobuxBtn.Text = ""
			end
			buyRobuxBtn.Active = canPurchaseRobux
			buyRobuxBtn.AutoButtonColor = canPurchaseRobux
		end
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- FRAME OPEN / CLOSE
-- ──────────────────────────────────────────────────────────────────────────────

local function openShop()
	if not thrustBoostsFrame or isFrameOpen or isFrameBusy then
		return
	end

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
		if not isFrameOpen then return end
		local character = player.Character
		if not character then closeShop() return end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
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

	thrustBoostsFrame = (frames:FindFirstChild("ThrustBoosts") or frames:FindFirstChild("UPGRADES")) :: Frame?
	if not thrustBoostsFrame then
		warn("[iseesupes] ThrustController: ThrustBoosts / UPGRADES frame not found under GUI.Frames")
		return
	end

	HudAnimations.rememberBaseSize(thrustBoostsFrame)
	thrustBoostsFrame.Visible = false

	bindCloseButton(thrustBoostsFrame)

	for i = 1, 3 do
		local sf = thrustBoostsFrame:FindFirstChild("Strength" .. i) :: Frame?
		if sf then
			strengthFrames[i] = sf
		end
	end

	-- Wire Buy (wins) and BuyRobux buttons for each tier
	for tier = 1, 3 do
		local sf = strengthFrames[tier]
		if not sf then continue end

		local tierCfg = ThrustUpgradeConfigs.Tiers[tier]
		local t = tier

		local buyBtn = getButton(sf, "Buy")
		if buyBtn then
			buyBtn.MouseButton1Click:Connect(function()
				local ownedTier = if cachedData and type(cachedData.ThrustUpgradeTier) == "number"
					then cachedData.ThrustUpgradeTier else 0
				if ownedTier ~= t - 1 then return end
				ThrustUpgradeService:BuyUpgrade(t)
			end)
		end

		local buyRobuxBtn = getButton(sf, "BuyRobux")
		if buyRobuxBtn and tierCfg then
			buyRobuxBtn.MouseButton1Click:Connect(function()
				local ownedTier = if cachedData and type(cachedData.ThrustUpgradeTier) == "number"
					then cachedData.ThrustUpgradeTier else 0
				if ownedTier ~= t - 1 then return end
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

	-- Refresh UI on every data replicate
	DataService.DataReplicated:Connect(function(data: any)
		cachedData = data
		if isFrameOpen then refreshShopUI(data) end
	end)

	-- Handle purchase results
	ThrustUpgradeService.UpgradeResult:Connect(function(result: string, tier: number)
		if result == "Success" then
			NotificationManager.show("Thrust upgraded to Tier " .. tier .. "!", "Success")
			if cachedData then refreshShopUI(cachedData) end
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
		if not character then return end
		if Players:GetPlayerFromCharacter(character) ~= player then return end

		local now = os.clock()
		if now - lastTouchTime < ThrustUpgradeConfigs.TouchDebounce then return end
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
