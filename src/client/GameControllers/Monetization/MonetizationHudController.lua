--!strict

-- Brings the designed-but-dead HUD offer buttons to life:
--  * GUI.HUD.StarterPack — limited-time bundle with live countdown (StarterPackConfigs)
--  * GUI.HUD.RainbowCarpet — GodSpeed Aura quick-buy (GodSpeedAuraConfigs.ProductId)
--  * Workspace.Map.StarterPackStand — 3D gift-box stand near spawn (touch = buy,
--    billboard timer, spin/bob; hidden locally once owned or expired)
-- Buttons stay hidden when their ProductId is 0, after purchase, or past the deadline.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local StarterPackConfigs = require(ReplicatedStorage.Shared.Configs.StarterPackConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local MonetizationHudController = Knit.CreateController({ Name = "MonetizationHudController" })

function MonetizationHudController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	local hud = gui and gui:WaitForChild("HUD", 30)
	if not hud then
		return
	end

	-- ── Starter Pack ────────────────────────────────────────────────
	local packButton = hud:WaitForChild(StarterPackConfigs.HudButtonName, 10) :: ImageButton?
	if packButton then
		-- The button ships with a placeholder TimerScript; this controller owns the timer.
		for _, d in packButton:GetDescendants() do
			if d:IsA("LocalScript") then
				d:Destroy()
			end
		end

		local timerLabel = packButton:FindFirstChild("Timer") :: TextLabel?

		local function refreshPack()
			local data = DataLib.GetData()
			local active = data ~= nil and StarterPackConfigs.IsOfferActive(data, os.time())
			packButton.Visible = active
			if active and timerLabel and data then
				local remaining = StarterPackConfigs.GetDeadline(data) - os.time()
				timerLabel.Text = StarterPackConfigs.FormatRemaining(remaining)
			end
		end

		packButton.MouseButton1Click:Connect(function()
			if StarterPackConfigs.ProductId == 0 then
				return
			end
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, StarterPackConfigs.ProductId)
			end)
		end)

		DataLib.OnChanged(refreshPack)
		task.spawn(function()
			while packButton.Parent do
				refreshPack()
				task.wait(1)
			end
		end)
	else
		warn("[iseesupes] MonetizationHudController: HUD." .. StarterPackConfigs.HudButtonName .. " missing.")
	end

	-- ── Starter Pack world stand (3D presence, like GodSpeed's carpet) ──
	local map = workspace:FindFirstChild("Map")
	local stand = map and map:FindFirstChild("StarterPackStand")
	if stand then
		local box = stand:FindFirstChild("GiftBox") :: BasePart?
		local touchPart = stand:FindFirstChild("Touch") :: BasePart?
		local billboard = box and box:FindFirstChild("Billboard")
		local standTimer = billboard and billboard:FindFirstChild("Timer") :: TextLabel?

		local standRemoved = false
		local function refreshStand()
			if standRemoved or not stand.Parent then
				return
			end
			local data = DataLib.GetData()
			if not data then
				return
			end
			if not StarterPackConfigs.IsOfferActive(data, os.time()) then
				-- Local copy only: other players still see the stand.
				standRemoved = true
				stand:Destroy()
				return
			end
			if standTimer then
				standTimer.Text = StarterPackConfigs.FormatRemaining(
					StarterPackConfigs.GetDeadline(data) - os.time()
				)
			end
		end

		local lastTouchPrompt = 0
		if touchPart then
			touchPart.Touched:Connect(function(hit)
				if standRemoved then
					return
				end
				local character = player.Character
				if not character or not hit:IsDescendantOf(character) then
					return
				end
				local data = DataLib.GetData()
				if not data or not StarterPackConfigs.IsOfferActive(data, os.time()) then
					return
				end
				if os.clock() - lastTouchPrompt < 3 then
					return
				end
				lastTouchPrompt = os.clock()
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, StarterPackConfigs.ProductId)
				end)
			end)
		end

		-- Cosmetic spin + bob, client-side only.
		if box then
			local baseCf = box.CFrame
			local animated = {}
			for _, name in { "GiftBox", "RibbonX", "RibbonZ", "Lid" } do
				local part = stand:FindFirstChild(name) :: BasePart?
				if part then
					table.insert(animated, { part = part, offset = baseCf:ToObjectSpace(part.CFrame) })
				end
			end
			local t = 0
			RunService.Heartbeat:Connect(function(dt)
				if standRemoved or not stand.Parent then
					return
				end
				t += dt
				local cf = CFrame.new(baseCf.Position + Vector3.new(0, math.sin(t * 1.6) * 0.35, 0))
					* CFrame.Angles(0, t * 0.9, 0)
				for _, entry in animated do
					entry.part.CFrame = cf * entry.offset
				end
			end)
		end

		DataLib.OnChanged(refreshStand)
		task.spawn(function()
			while not standRemoved and stand.Parent do
				refreshStand()
				task.wait(1)
			end
		end)
	end

	-- ── GodSpeed Aura quick-buy ─────────────────────────────────────
	local auraButton = hud:FindFirstChild("RainbowCarpet") :: ImageButton?
	if auraButton then
		local auraProductId = GodSpeedAuraConfigs.ProductId
		auraButton.Visible = typeof(auraProductId) == "number" and auraProductId ~= 0
		if auraButton.Visible then
			auraButton.MouseButton1Click:Connect(function()
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, auraProductId)
				end)
			end)
		end
	end

	print("[iseesupes] MonetizationHudController ready.")
end

return MonetizationHudController
