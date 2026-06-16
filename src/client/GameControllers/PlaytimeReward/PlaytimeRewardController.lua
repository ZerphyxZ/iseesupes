--!strict

-- Playtime rewards HUD. Countdown pill stays hidden (surprise popup when ready).
-- Timer does not run until tutorial is complete (server + client gate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local PlaytimeRewardConfigs = require(ReplicatedStorage.Shared.Configs.PlaytimeRewardConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local PlaytimeRewardController = Knit.CreateController({ Name = "PlaytimeRewardController" })

local player = Players.LocalPlayer

local state: any = { elapsedSeconds = 0, claimableIndex = nil, nextIndex = nil, nextSeconds = nil, claimed = {} }
local lastStateAt = os.clock()
local isClaiming = false

local function localElapsed(): number
	return state.elapsedSeconds + (os.clock() - lastStateAt)
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function minTutorialStepForPlaytime(): number
	local ui = PlaytimeRewardConfigs.UI
	if ui and typeof(ui.MinTutorialStep) == "number" then
		return ui.MinTutorialStep
	end
	return TutorialConfigs.Step.Complete
end

local function isTutorialCompleteForPlaytime(): boolean
	local data = DataLib.GetData()
	local step = if data and type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	return step >= minTutorialStepForPlaytime()
end

local function shouldShowCountdownPill(): boolean
	local ui = PlaytimeRewardConfigs.UI
	return ui ~= nil and ui.ShowCountdownPill == true
end

function PlaytimeRewardController:KnitStart()
	local PlaytimeRewardService = Knit.GetService("PlaytimeRewardService")
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaytimeReward"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- ── Bottom-left countdown pill ─────────────────────────────────────────────
	local pill = Instance.new("TextButton")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0, 1)
	pill.Position = UDim2.new(0, 14, 1, -14)
	pill.Size = UDim2.new(0, 196, 0, 46)
	pill.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	pill.BackgroundTransparency = 0.12
	pill.AutoButtonColor = false
	pill.Text = ""
	pill.Visible = shouldShowCountdownPill()
	pill.Parent = gui
	Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 12)
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = Color3.fromRGB(90, 160, 255)
	pillStroke.Thickness = 1.5
	pillStroke.Transparency = 0.5
	pillStroke.Parent = pill

	local pillIcon = Instance.new("TextLabel")
	pillIcon.BackgroundTransparency = 1
	pillIcon.AnchorPoint = Vector2.new(0, 0.5)
	pillIcon.Position = UDim2.new(0, 10, 0.5, 0)
	pillIcon.Size = UDim2.new(0, 28, 0, 28)
	pillIcon.Font = Enum.Font.GothamBold
	pillIcon.TextScaled = true
	pillIcon.Text = "⏱"
	pillIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	pillIcon.Parent = pill

	local pillTitle = Instance.new("TextLabel")
	pillTitle.BackgroundTransparency = 1
	pillTitle.AnchorPoint = Vector2.new(0, 0.5)
	pillTitle.Position = UDim2.new(0, 44, 0.5, -6)
	pillTitle.Size = UDim2.new(1, -52, 0, 18)
	pillTitle.Font = Enum.Font.GothamBold
	pillTitle.TextXAlignment = Enum.TextXAlignment.Left
	pillTitle.TextScaled = true
	pillTitle.TextColor3 = Color3.fromRGB(235, 240, 255)
	pillTitle.Text = "Playtime reward"
	pillTitle.Parent = pill

	local pillSub = Instance.new("TextLabel")
	pillSub.BackgroundTransparency = 1
	pillSub.AnchorPoint = Vector2.new(0, 0.5)
	pillSub.Position = UDim2.new(0, 44, 0.5, 12)
	pillSub.Size = UDim2.new(1, -52, 0, 14)
	pillSub.Font = Enum.Font.Gotham
	pillSub.TextXAlignment = Enum.TextXAlignment.Left
	pillSub.TextScaled = true
	pillSub.TextColor3 = Color3.fromRGB(150, 165, 195)
	pillSub.Text = "Next in 2:00"
	pillSub.Parent = pill

	-- ── Center claimable popup (hidden until a milestone is ready) ─────────────
	local popup = Instance.new("Frame")
	popup.Name = "ClaimPopup"
	-- Styled to match the game's reward panels (Daily Streak / Offline): white panel +
	-- gold→orange gradient, 3px black stroke, FredokaOne font, red rounded "X" close.
	local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
	local GOTHAM_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	local BLACK = Color3.new(0, 0, 0)

	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 0, 0.4, 0)
	popup.Size = UDim2.new(0, 360, 0, 200)
	popup.BackgroundColor3 = Color3.new(1, 1, 1)
	popup.Visible = false
	popup.Parent = gui
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 10)
	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = BLACK
	popupStroke.Thickness = 3
	popupStroke.Parent = popup
	local popupGradient = Instance.new("UIGradient")
	popupGradient.Color = ColorSequence.new(Color3.fromRGB(255, 199, 38), Color3.fromRGB(242, 115, 13))
	popupGradient.Rotation = 90
	popupGradient.Parent = popup

	-- Title row: gift icon + "Playtime Reward!"
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.AnchorPoint = Vector2.new(0.5, 0)
	titleRow.Position = UDim2.new(0.5, 0, 0, 14)
	titleRow.Size = UDim2.new(0.86, 0, 0, 30)
	titleRow.Parent = popup
	local titleList = Instance.new("UIListLayout")
	titleList.FillDirection = Enum.FillDirection.Horizontal
	titleList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	titleList.VerticalAlignment = Enum.VerticalAlignment.Center
	titleList.Padding = UDim.new(0, 6)
	titleList.Parent = titleRow
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Size = UDim2.new(0, 28, 0, 28)
	titleIcon.Image = "rbxassetid://80861029762439" -- gift icon (game ICON_GIFT)
	titleIcon.Parent = titleRow
	local popupTitle = Instance.new("TextLabel")
	popupTitle.BackgroundTransparency = 1
	popupTitle.Size = UDim2.new(0, 240, 1, 0)
	popupTitle.FontFace = GOTHAM_BOLD
	popupTitle.TextScaled = true
	popupTitle.TextColor3 = Color3.new(1, 1, 1)
	popupTitle.Text = "Playtime Reward!"
	popupTitle.Parent = titleRow
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = BLACK
	titleStroke.Thickness = 3
	titleStroke.Parent = popupTitle

	-- Reward amount
	local popupReward = Instance.new("TextLabel")
	popupReward.BackgroundTransparency = 1
	popupReward.AnchorPoint = Vector2.new(0.5, 0.5)
	popupReward.Position = UDim2.new(0.5, 0, 0.49, 0)
	popupReward.Size = UDim2.new(0.85, 0, 0, 52)
	popupReward.FontFace = FREDOKA
	popupReward.TextScaled = true
	popupReward.TextColor3 = Color3.new(1, 1, 1)
	popupReward.Text = "+15 Wins"
	popupReward.Parent = popup
	local rewardStroke = Instance.new("UIStroke")
	rewardStroke.Color = BLACK
	rewardStroke.Thickness = 3
	rewardStroke.Parent = popupReward

	-- CLAIM button (white + green gradient, FredokaOne) — matches the reward panels.
	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "Claim"
	claimBtn.AnchorPoint = Vector2.new(0.5, 1)
	claimBtn.Position = UDim2.new(0.5, 0, 1, -16)
	claimBtn.Size = UDim2.new(0.7, 0, 0, 48)
	claimBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	claimBtn.AutoButtonColor = true
	claimBtn.Text = ""
	claimBtn.Parent = popup
	Instance.new("UICorner", claimBtn).CornerRadius = UDim.new(0, 8)
	local claimGradient = Instance.new("UIGradient")
	claimGradient.Color = ColorSequence.new(Color3.fromRGB(64, 230, 77), Color3.fromRGB(13, 153, 31))
	claimGradient.Rotation = 90
	claimGradient.Parent = claimBtn
	local claimBtnStroke = Instance.new("UIStroke")
	claimBtnStroke.Color = Color3.fromRGB(0, 77, 0)
	claimBtnStroke.Thickness = 3
	claimBtnStroke.Parent = claimBtn
	local claimText = Instance.new("TextLabel")
	claimText.BackgroundTransparency = 1
	claimText.AnchorPoint = Vector2.new(0.5, 0.5)
	claimText.Position = UDim2.new(0.5, 0, 0.5, 0)
	claimText.Size = UDim2.new(0.9, 0, 0.72, 0)
	claimText.FontFace = FREDOKA
	claimText.TextScaled = true
	claimText.TextColor3 = Color3.new(1, 1, 1)
	claimText.Text = "CLAIM"
	claimText.Parent = claimBtn
	local claimTextStroke = Instance.new("UIStroke")
	claimTextStroke.Color = Color3.fromRGB(0, 77, 0)
	claimTextStroke.Thickness = 2
	claimTextStroke.Parent = claimText

	-- Close: red rounded square with a white "X" (the game's close-button style).
	local dismissBtn = Instance.new("TextButton")
	dismissBtn.Name = "Dismiss"
	dismissBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	dismissBtn.Position = UDim2.new(1, -2, 0, 2)
	dismissBtn.Size = UDim2.new(0, 36, 0, 36)
	dismissBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	dismissBtn.AutoButtonColor = true
	dismissBtn.Text = ""
	dismissBtn.ZIndex = 5
	dismissBtn.Parent = popup
	Instance.new("UICorner", dismissBtn).CornerRadius = UDim.new(0, 8)
	local dismissGradient = Instance.new("UIGradient")
	dismissGradient.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 85, 127))
	dismissGradient.Rotation = 90
	dismissGradient.Parent = dismissBtn
	local dismissBtnStroke = Instance.new("UIStroke")
	dismissBtnStroke.Color = Color3.fromRGB(100, 0, 0)
	dismissBtnStroke.Thickness = 3
	dismissBtnStroke.Parent = dismissBtn
	local dismissText = Instance.new("TextLabel")
	dismissText.BackgroundTransparency = 1
	dismissText.AnchorPoint = Vector2.new(0.5, 0.5)
	dismissText.Position = UDim2.new(0.5, 0, 0.5, 0)
	dismissText.Size = UDim2.new(0.85, 0, 0.85, 0)
	dismissText.FontFace = FREDOKA
	dismissText.TextScaled = true
	dismissText.TextColor3 = Color3.new(1, 1, 1)
	dismissText.Text = "X"
	dismissText.ZIndex = 6
	dismissText.Parent = dismissBtn
	local dismissTextStroke = Instance.new("UIStroke")
	dismissTextStroke.Color = Color3.fromRGB(100, 0, 0)
	dismissTextStroke.Thickness = 3
	dismissTextStroke.Parent = dismissText

	gui.Parent = playerGui
	print("[iseesupes] PlaytimeRewardController: pill built")

	-- ── Logic ─────────────────────────────────────────────────────────────────
	local lastPopupIndex: number? = nil -- the milestone the popup has already surfaced

	local function doClaim(index: number?)
		if isClaiming or not index then
			return
		end
		isClaiming = true
		PlaytimeRewardService:ClaimMilestone(index)
			:andThen(function(ok: boolean)
				isClaiming = false
				if ok then
					local m = PlaytimeRewardConfigs.GetMilestone(index)
					NotificationManager.show("Playtime reward: " .. (m and m.Label or "claimed") .. "!", "Success")
					popup.Visible = false
				end
			end)
			:catch(function()
				isClaiming = false
			end)
	end

	local function render()
		if not isTutorialCompleteForPlaytime() then
			pill.Visible = false
			popup.Visible = false
			return
		end

		pill.Visible = shouldShowCountdownPill()

		local ci = state.claimableIndex
		-- Pill (optional countdown — hidden by default)
		if shouldShowCountdownPill() then
			if ci then
				local m = PlaytimeRewardConfigs.GetMilestone(ci)
				pillIcon.Text = "🎁"
				pillTitle.Text = m and m.Label or "Reward ready!"
				pillSub.Text = "Tap to CLAIM"
				pillSub.TextColor3 = Color3.fromRGB(120, 255, 150)
				pillStroke.Color = Color3.fromRGB(120, 255, 150)
				pillStroke.Transparency = 0
			else
				pillIcon.Text = "⏱"
				pillStroke.Color = Color3.fromRGB(90, 160, 255)
				pillStroke.Transparency = 0.5
				pillSub.TextColor3 = Color3.fromRGB(150, 165, 195)
				if state.nextSeconds then
					pillTitle.Text = "Playtime reward"
					pillSub.Text = "Next in " .. formatTime(state.nextSeconds - localElapsed())
				else
					pillTitle.Text = "All rewards claimed"
					pillSub.Text = "Resets next session"
				end
			end
		end

		-- Center popup: surface once per newly-claimable milestone.
		if ci and ci ~= lastPopupIndex then
			lastPopupIndex = ci
			local m = PlaytimeRewardConfigs.GetMilestone(ci)
			popupReward.Text = m and m.Label or "Reward!"
			popup.Visible = true
		elseif not ci then
			popup.Visible = false
		end
	end

	local function refreshState()
		PlaytimeRewardService:GetState()
			:andThen(function(s: any)
				if s then
					state = s
					lastStateAt = os.clock()
					render()
				end
			end)
			:catch(function() end)
	end

	PlaytimeRewardService.StateChanged:Connect(function(newState: any)
		state = newState
		lastStateAt = os.clock()
		render()
	end)
	DataLib.OnChanged(function()
		render()
	end)
	refreshState()

	pill.MouseButton1Click:Connect(function()
		doClaim(state.claimableIndex)
	end)
	claimBtn.MouseButton1Click:Connect(function()
		doClaim(state.claimableIndex)
	end)
	dismissBtn.MouseButton1Click:Connect(function()
		popup.Visible = false -- dismissed; still claimable later via the green pill
	end)

	-- 1s ticker: smooth countdown + pull fresh state the moment we cross a milestone
	-- locally (the server heartbeat is coarse) so the reward surfaces promptly.
	task.spawn(function()
		while gui.Parent do
			if state.nextSeconds and not state.claimableIndex and localElapsed() >= state.nextSeconds then
				refreshState()
			end
			render()
			task.wait(1)
		end
	end)
end

return PlaytimeRewardController
