--!strict

-- Brings the designed-but-dead HUD offer buttons to life:
--  * GUI.HUD.StarterPack — limited-time bundle with live countdown (StarterPackConfigs)
--  * Workspace.Map.StarterPackStand — 3D gift-box stand near spawn (touch = buy,
--    billboard timer, spin/bob; hidden locally only after purchase)
-- Buttons stay hidden when ProductId is 0 or after purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local StarterPackConfigs = require(ReplicatedStorage.Shared.Configs.StarterPackConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)

local MonetizationHudController = Knit.CreateController({ Name = "MonetizationHudController" })

type StandParts = {
	stand: Model,
	box: BasePart,
	touchPart: BasePart,
	standTimer: TextLabel,
}

local LOADING_TIMER_TEXT = "..."

local function getOfferRemaining(data: any?): (boolean, number?)
	if not data then
		return false, nil
	end
	local now = os.time()
	if not StarterPackConfigs.IsOfferActive(data, now) then
		return false, 0
	end
	local remaining = StarterPackConfigs.GetRemainingSeconds(data, now)
	if remaining <= 0 then
		return false, 0
	end
	return true, remaining
end

local function resolveStandParts(stand: Model): StandParts?
	local box = stand:FindFirstChild(StarterPackConfigs.GiftBoxPartName)
	local touchPart = stand:FindFirstChild(StarterPackConfigs.TouchPartName)
	local billboard = if box then box:FindFirstChild(StarterPackConfigs.BillboardName) else nil
	local standTimer = if billboard
		then billboard:FindFirstChild(StarterPackConfigs.BillboardTimerName, true)
		else nil

	if not box or not box:IsA("BasePart") then
		warn(
			"[iseesupes][StarterPack] missing GiftBox part on",
			stand:GetFullName(),
			"— run scripts/build-starter-pack-stand.luau or match hierarchy"
		)
		return nil
	end
	if not touchPart or not touchPart:IsA("BasePart") then
		warn("[iseesupes][StarterPack] missing Touch part on", stand:GetFullName())
		return nil
	end
	if not billboard or not billboard:IsA("BillboardGui") then
		warn("[iseesupes][StarterPack] missing Billboard on", box:GetFullName())
		return nil
	end
	if not standTimer or not standTimer:IsA("TextLabel") then
		warn("[iseesupes][StarterPack] missing Timer label on", billboard:GetFullName())
		return nil
	end

	touchPart.CanTouch = true
	return {
		stand = stand,
		box = box,
		touchPart = touchPart,
		standTimer = standTimer,
	}
end

local function setStandLocallyVisible(parts: StandParts, visible: boolean)
	for _, desc in parts.stand:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.LocalTransparencyModifier = if visible then 0 else 1
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			desc.Enabled = visible
		end
	end
	parts.touchPart.CanTouch = visible
end

function MonetizationHudController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	local hud = gui and gui:WaitForChild("HUD", 30)
	if not hud then
		return
	end

	-- ── Starter Pack HUD ────────────────────────────────────────────
	local packButton = hud:WaitForChild(StarterPackConfigs.HudButtonName, 10) :: ImageButton?
	local timerLabel: TextLabel? = nil

	if packButton then
		for _, d in packButton:GetDescendants() do
			if d:IsA("LocalScript") then
				d:Destroy()
			end
		end

		timerLabel = packButton:FindFirstChild("Timer") :: TextLabel?

		packButton.MouseButton1Click:Connect(function()
			if StarterPackConfigs.ProductId == 0 then
				return
			end
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, StarterPackConfigs.ProductId)
			end)
		end)
	else
		warn("[iseesupes] MonetizationHudController: HUD." .. StarterPackConfigs.HudButtonName .. " missing.")
	end

	-- ── Starter Pack world stand ───────────────────────────────────
	local standParts: StandParts? = nil
	local standHidden = false
	local touchConn: RBXScriptConnection? = nil
	local lastTouchPrompt = 0

	local function hideStand()
		if standHidden then
			return
		end
		if standParts then
			setStandLocallyVisible(standParts, false)
		end
		standHidden = true
	end

	local function showStand()
		standHidden = false
		if standParts then
			setStandLocallyVisible(standParts, true)
		end
	end

	local function refreshOfferUi()
		local data = DataLib.GetData()
		local active, remaining = getOfferRemaining(data)

		if packButton then
			if not data then
				packButton.Visible = false
				if timerLabel then
					timerLabel.Text = LOADING_TIMER_TEXT
				end
			else
				packButton.Visible = active
				if timerLabel then
					if active and remaining then
						timerLabel.Text = StarterPackConfigs.FormatRemaining(remaining)
					else
						timerLabel.Text = LOADING_TIMER_TEXT
					end
				end
			end
		end

		if not standParts then
			return
		end

		if not data then
			standParts.standTimer.Text = LOADING_TIMER_TEXT
			showStand()
			return
		end

		if not active then
			hideStand()
			return
		end

		showStand()
		if remaining then
			standParts.standTimer.Text = StarterPackConfigs.FormatRemaining(remaining)
		end
	end

	local function bindStandAnimation(parts: StandParts)
		local stand = parts.stand
		local box = parts.box
		local baseCf = box.CFrame
		local animated: { { part: BasePart, offset: CFrame } } = {}
		for _, name in { "GiftBox", "RibbonX", "RibbonZ", "Lid" } do
			local part = stand:FindFirstChild(name) :: BasePart?
			if part then
				table.insert(animated, { part = part, offset = baseCf:ToObjectSpace(part.CFrame) })
			end
		end
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			if standHidden or not stand.Parent then
				return
			end
			t += dt
			local cf = CFrame.new(baseCf.Position + Vector3.new(0, math.sin(t * 1.6) * 0.35, 0))
				* CFrame.Angles(0, t * 0.9, 0)
			for _, entry in animated do
				if entry.part.Parent then
					entry.part.CFrame = cf * entry.offset
				end
			end
		end)
	end

	local function bindStandTouch(parts: StandParts)
		if touchConn then
			touchConn:Disconnect()
			touchConn = nil
		end

		touchConn = parts.touchPart.Touched:Connect(function(hit)
			if standHidden then
				return
			end
			local character = player.Character
			if not character or not hit:IsDescendantOf(character) then
				return
			end
			local data = DataLib.GetData()
			local active, _remaining = getOfferRemaining(data)
			if not active then
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

	local function tryBindStand(stand: Instance): boolean
		if not stand:IsA("Model") then
			return false
		end
		if standParts and standParts.stand == stand then
			return true
		end

		local parts = resolveStandParts(stand)
		if not parts then
			return false
		end

		if touchConn then
			touchConn:Disconnect()
			touchConn = nil
		end

		standParts = parts
		standHidden = false
		parts.standTimer.Text = LOADING_TIMER_TEXT
		bindStandTouch(parts)
		bindStandAnimation(parts)
		refreshOfferUi()
		print("[iseesupes][StarterPack] bound stand at", stand:GetFullName())
		return true
	end

	local function findStandModel(): Model?
		local map = MapWorld.getMapFolder()
		if not map then
			return nil
		end
		local stand = map:FindFirstChild(StarterPackConfigs.StandModelName)
		return if stand and stand:IsA("Model") then stand else nil
	end

	local function tryResolveAndBindStand(): boolean
		local stand = findStandModel()
		if stand then
			return tryBindStand(stand)
		end
		local map = MapWorld.getMapFolder()
		if not map then
			return false
		end
		local waited = map:WaitForChild(StarterPackConfigs.StandModelName, StarterPackConfigs.ResolveTimeoutSeconds)
		if waited and waited:IsA("Model") then
			return tryBindStand(waited)
		end
		return false
	end

	task.spawn(function()
		local maxAttempts = StarterPackConfigs.MaxResolveAttempts or 30
		local retrySeconds = StarterPackConfigs.ResolveRetrySeconds or 2
		for attempt = 1, maxAttempts do
			if tryResolveAndBindStand() then
				return
			end
			if attempt == 1 or attempt == maxAttempts then
				warn(
					"[iseesupes][StarterPack] stand not ready (attempt",
					attempt,
					"/",
					maxAttempts,
					") — waiting for",
					StarterPackConfigs.StandModelName
				)
			end
			task.wait(retrySeconds)
		end
		warn(
			"[iseesupes][StarterPack] could not bind",
			StarterPackConfigs.StandModelName,
			"after",
			maxAttempts,
			"attempts"
		)
	end)

	local map = MapWorld.getMapFolder()
	if map then
		map.DescendantAdded:Connect(function(desc)
			if desc.Name == StarterPackConfigs.StandModelName and desc:IsA("Model") then
				task.defer(function()
					tryBindStand(desc)
				end)
				return
			end
			if desc.Name == StarterPackConfigs.TouchPartName and desc:IsA("BasePart") then
				local stand = desc:FindFirstAncestor(StarterPackConfigs.StandModelName)
				if stand and stand:IsA("Model") then
					task.defer(function()
						tryBindStand(stand)
					end)
				end
			end
		end)
	end

	DataLib.OnChanged(refreshOfferUi)
	task.spawn(function()
		while true do
			refreshOfferUi()
			task.wait(1)
		end
	end)

	StudioLog.ready("MonetizationHudController")
end

return MonetizationHudController
