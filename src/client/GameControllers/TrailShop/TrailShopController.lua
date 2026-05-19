--!strict

-- Trail shop UI. Expects Studio instances:
--   PlayerGui → GUI → Frames → Trails → Scrolling
--   ReplicatedStorage → Templates → TrailTemplate

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local TrailShopController = Knit.CreateController({ Name = "TrailShopController" })

local ROBUX_PREFIX = utf8.char(0xE002)

local TEMPLATE_PATH_CANDIDATES = {
	TrailConfigs.ShopTemplatePath,
	TrailConfigs.ShopTemplatePathLegacy,
}

local priceCache = {} -- [productId] = robux price

local function waitPath(root: Instance, segments: { string }, timeout: number?)
	local current: Instance? = root
	for _, name in segments do
		if not current then
			return nil
		end
		current = current:WaitForChild(name, timeout or 10)
	end
	return current
end

local function resolveShopRowTemplate(root: Instance): GuiObject?
	for _, segments in TEMPLATE_PATH_CANDIDATES do
		local found = waitPath(root, segments, 3)
		if found and found:IsA("GuiObject") then
			return found
		end
	end
	return nil
end

local function updateButtons(frame: Frame, info: any, isOwned: boolean, isEquipped: boolean)
	local buttons = frame:FindFirstChild("Buttons")
	if not buttons then
		return
	end

	local winBtn = buttons:FindFirstChild("Wins") :: ImageButton?
	local robuxBtn = buttons:FindFirstChild("Robux") :: ImageButton?
	local equipBtn = buttons:FindFirstChild("Equip") :: ImageButton?

	if winBtn then
		winBtn.Visible = false
	end
	if robuxBtn then
		robuxBtn.Visible = false
	end
	if equipBtn then
		equipBtn.Visible = false
	end

	if isOwned then
		if equipBtn then
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
		if winBtn then
			winBtn.Visible = true
			local t = winBtn:FindFirstChild("Text") :: TextLabel?
			if t then
				t.Text = NumberFormatter.Format(info.WinCost)
			end
		end

		if robuxBtn then
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
	local trailsFrame = frames:WaitForChild("Trails", 30)
	if not trailsFrame then
		warn("[iseesupes] TrailShopController: missing GUI.Frames.Trails.")
		return
	end
	local scrolling = trailsFrame:WaitForChild("Scrolling", 30)
	if not scrolling then
		warn("[iseesupes] TrailShopController: missing Frames/Trails/Scrolling under GUI.")
		return
	end

	local template = resolveShopRowTemplate(ReplicatedStorage)
	if not template then
		warn(
			"[iseesupes] TrailShopController: missing template ReplicatedStorage."
				.. table.concat(TrailConfigs.ShopTemplatePath, ".")
				.. " (or legacy "
				.. table.concat(TrailConfigs.ShopTemplatePathLegacy, ".")
				.. ")"
		)
		return
	end

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
		local data = DataLib.GetData()
		local equippedId, owned = getTrailStateFromData(data)

		for _, child in scrolling:GetChildren() do
			if child:IsA("Frame") then
				local info = TrailConfigs.GetTrailById(child.Name)
				if info then
					local isOwned = owned[info.ID] == true
					local isEquipped = equippedId == info.ID
					updateButtons(child, info, isOwned, isEquipped)
				end
			end
		end
	end

	local function populateShop()
		for _, child in scrolling:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, info in TrailConfigs.Trails do
			local clone = template:Clone()
			clone.Name = info.ID
			clone.Visible = true

			local nameLabel = clone:FindFirstChild("Name") :: TextLabel?
			if nameLabel then
				nameLabel.Text = info.Name
			end

			local speedLabel = clone:FindFirstChild("SpeedBoost") :: TextLabel?
			if speedLabel then
				speedLabel.Text = "x" .. tostring(info.SpeedBoost) .. " Points"
			end

			local imageLabel = clone:FindFirstChild("Image") :: ImageLabel?
			if imageLabel and info.Image then
				imageLabel.Image = info.Image
			end

			clone.Parent = scrolling

			local btns = clone:FindFirstChild("Buttons")
			if btns then
				local winBtn = btns:FindFirstChild("Wins") :: ImageButton?
				local robuxBtn = btns:FindFirstChild("Robux") :: ImageButton?
				local equipBtn = btns:FindFirstChild("Equip") :: ImageButton?

				if winBtn then
					winBtn.MouseButton1Click:Connect(function()
						TrailService:BuyWithWins(info.ID):andThen(function(result)
							if not result.success and result.message then
								warn("[iseesupes] BuyWithWins:", result.message)
							end
						end):catch(warn)
					end)
				end

				if robuxBtn then
					robuxBtn.MouseButton1Click:Connect(function()
						if info.ProductId == 0 then
							return
						end
						local localPlayer = Players.LocalPlayer
						MarketplaceService:PromptProductPurchase(localPlayer, info.ProductId)
					end)
				end

				if equipBtn then
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

		refreshShopStates()
	end

	populateShop()
	DataLib.OnChanged(function()
		refreshShopStates()
	end)
end

return TrailShopController
