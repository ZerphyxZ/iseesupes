--!strict

-- Trail shop UI. Expects:
--   PlayerGui → GUI → Frames → Trails → Scrolling → TrailTemplate (hidden)
--   ReplicatedStorage → Templates → TrailTemplate (fallback)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local TrailShopUi = require(ReplicatedStorage.Shared.Utils.TrailShopUi)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local TrailShopController = Knit.CreateController({ Name = "TrailShopController" })

local ROBUX_PREFIX = utf8.char(0xE002)

local priceCache: { [number]: number } = {}

local scrolling: ScrollingFrame? = nil
local trailsFrame: Frame? = nil
local rowSource: GuiObject? = nil
local populateShop: (() -> ())? = nil

local function updateButtons(frame: Frame, info: TrailConfigs.TrailInfo, isOwned: boolean, isEquipped: boolean)
	local buttons = frame:FindFirstChild("Buttons")
	if not buttons then
		return
	end

	local winBtn = buttons:FindFirstChild("Wins")
	local robuxBtn = buttons:FindFirstChild("Robux")
	local equipBtn = buttons:FindFirstChild("Equip")

	if winBtn and winBtn:IsA("GuiButton") then
		winBtn.Visible = false
	end
	if robuxBtn and robuxBtn:IsA("GuiButton") then
		robuxBtn.Visible = false
	end
	if equipBtn and equipBtn:IsA("GuiButton") then
		equipBtn.Visible = false
	end

	if isOwned then
		if equipBtn and equipBtn:IsA("GuiButton") then
			equipBtn.Visible = true
			local btnText = equipBtn:FindFirstChild("Text") :: TextLabel?
			if isEquipped then
				equipBtn.AutoButtonColor = false
				equipBtn.BackgroundColor3 = Color3.fromRGB(85, 255, 127)
				if btnText then
					btnText.Text = "Unequip"
				end
			else
				equipBtn.AutoButtonColor = true
				equipBtn.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
				if btnText then
					btnText.Text = "Equip"
				end
			end
		end
	else
		local isFreeDefault = info.ID == TrailConfigs.DefaultTrailId and info.WinCost <= 0
		if winBtn and winBtn:IsA("GuiButton") and not isFreeDefault then
			winBtn.Visible = true
			local t = winBtn:FindFirstChild("Text") :: TextLabel?
			if t then
				t.Text = NumberFormatter.Format(info.WinCost)
			end
		end

		if robuxBtn and robuxBtn:IsA("GuiButton") then
			robuxBtn.Visible = info.ProductId ~= 0
			local t = robuxBtn:FindFirstChild("Text") :: TextLabel?
			if t then
				if info.ProductId == 0 then
					t.Text = "—"
				elseif priceCache[info.ProductId] then
					t.Text = ROBUX_PREFIX .. tostring(priceCache[info.ProductId])
				else
					t.Text = "..."

					task.spawn(function()
						local success, productInfo = pcall(function()
							return MarketplaceService:GetProductInfo(info.ProductId, Enum.InfoType.Product)
						end)

						if success and productInfo then
							priceCache[info.ProductId] = productInfo.PriceInRobux
							t.Text = ROBUX_PREFIX .. tostring(productInfo.PriceInRobux)
						else
							t.Text = "Error"
						end
					end)
				end
			end
		end
	end
end

function TrailShopController:KnitStart()
	local ok, err = pcall(function()
		self:_start()
	end)
	if not ok then
		warn("[iseesupes] TrailShopController failed:", err)
	end
end

function TrailShopController:_start()
	local TrailService = Knit.GetService("TrailService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] TrailShopController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		warn("[iseesupes] TrailShopController: missing GUI.Frames.")
		return
	end

	trailsFrame = frames:WaitForChild("Trails", 30) :: Frame?
	if not trailsFrame then
		warn("[iseesupes] TrailShopController: missing GUI.Frames.Trails.")
		return
	end

	scrolling = trailsFrame:WaitForChild("Scrolling", 30) :: ScrollingFrame?
	if not scrolling then
		warn("[iseesupes] TrailShopController: missing Frames/Trails/Scrolling under GUI.")
		return
	end

	local template = TrailShopUi.resolveTrailTemplate(scrolling, ReplicatedStorage)
	if not template then
		warn("[iseesupes] TrailShopController: missing TrailTemplate in Scrolling or ReplicatedStorage.Templates")
		return
	end

	TrailShopUi.prepareTemplate(template)
	rowSource = TrailShopUi.ensureRowSource(scrolling, template)

	local function getTrailStateFromData(data: any)
		if not data then
			return "", {}
		end
		local equipped = ""
		if type(data.EquippedTrail) == "string" then
			equipped = data.EquippedTrail
		end
		local owned = {}
		if type(data.OwnedTrails) == "table" then
			for id, v in data.OwnedTrails do
				if type(id) == "string" and v == true then
					owned[id] = true
				end
			end
		end
		return equipped, owned
	end

	local function refreshShopStates()
		if not scrolling then
			return
		end
		local data = DataLib.GetData()
		local equippedId, owned = getTrailStateFromData(data)

		for _, child in scrolling:GetChildren() do
			if child:IsA("Frame") and TrailConfigs.IsTrailRowName(child.Name) then
				local info = TrailConfigs.GetTrailById(child.Name)
				if info then
					local isOwned = owned[info.ID] == true
					local isEquipped = equippedId == info.ID
					updateButtons(child, info, isOwned, isEquipped)
				end
			end
		end
	end

	local function clearShopRows()
		if not scrolling then
			return
		end
		for _, child in scrolling:GetChildren() do
			if child:IsA("Frame") and TrailConfigs.IsTrailRowName(child.Name) then
				child:Destroy()
			end
		end
	end

	populateShop = function()
		if not scrolling or not rowSource then
			return
		end

		clearShopRows()

		local trailList = TrailConfigs.Trails
		local rowCount = 0

		for index, info in trailList do
			local clone = rowSource:Clone()
			clone.Name = info.ID
			local bindOk, bindErr = pcall(TrailShopUi.bindTrailRowLabels, clone, info, index)
			if not bindOk then
				warn("[iseesupes] TrailShop row bind failed:", info.ID, bindErr)
				clone:Destroy()
				continue
			end
			clone.Parent = scrolling
			rowCount += 1

			local btns = clone:FindFirstChild("Buttons")
			if btns then
				local winBtn = btns:FindFirstChild("Wins")
				local robuxBtn = btns:FindFirstChild("Robux")
				local equipBtn = btns:FindFirstChild("Equip")

				if winBtn and winBtn:IsA("GuiButton") then
					winBtn.MouseButton1Click:Connect(function()
						TrailService:BuyWithWins(info.ID):andThen(function(result)
							if not result.success and result.message then
								warn("[iseesupes] BuyWithWins:", result.message)
							end
						end):catch(warn)
					end)
				end

				if robuxBtn and robuxBtn:IsA("GuiButton") then
					robuxBtn.MouseButton1Click:Connect(function()
						if info.ProductId == 0 then
							return
						end
						MarketplaceService:PromptProductPurchase(player, info.ProductId)
					end)
				end

				if equipBtn and equipBtn:IsA("GuiButton") then
					equipBtn.MouseButton1Click:Connect(function()
						local d = DataLib.GetData()
						local equippedId = (d and type(d.EquippedTrail) == "string") and d.EquippedTrail or ""
						if equippedId == info.ID then
							TrailService:Unequip():andThen(function(result)
								if not result.success and result.message then
									warn("[iseesupes] Unequip:", result.message)
								end
							end):catch(warn)
						else
							TrailService:Equip(info.ID):andThen(function(result)
								if not result.success and result.message then
									warn("[iseesupes] Equip:", result.message)
								end
							end):catch(warn)
						end
					end)
				end
			end
		end

		TrailShopUi.updateScrollingCanvas(scrolling)
		refreshShopStates()
		print("[iseesupes] TrailShop populated", rowCount, "rows")
	end

	local function ensurePopulated()
		if not scrolling then
			return
		end
		if TrailShopUi.countTrailRows(scrolling) == 0 then
			populateShop()
		else
			refreshShopStates()
		end
	end

	populateShop()
	DataLib.OnChanged(function()
		ensurePopulated()
	end)

	trailsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if trailsFrame and trailsFrame.Visible then
			task.defer(ensurePopulated)
		end
	end)

	-- Frame open animation finishes slightly after Visible=true
	task.defer(ensurePopulated)
	task.delay(0.5, ensurePopulated)

	print("[iseesupes] TrailShopController ready.")
end

return TrailShopController
