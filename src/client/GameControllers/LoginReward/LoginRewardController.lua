--!strict

-- Daily streak + offline reward UI. Frames are built in Studio:
-- GUI.Frames.DailyStreak (Day1..Day7 cards, ClaimButton, Footer)
-- GUI.Frames.OfflineReward (AwayTime, Amount, ClaimButton)
-- Both are excluded from FrameNavigator; this controller owns open/close.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local LoginRewardConfigs = require(ReplicatedStorage.Shared.Configs.LoginRewardConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)

local LoginRewardController = Knit.CreateController({ Name = "LoginRewardController" })

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 200, 40)
local HUD_GIFT_ICON = "rbxassetid://80861029762439"

function LoginRewardController:KnitStart()
	local LoginRewardService = Knit.GetService("LoginRewardService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		return
	end
	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		return
	end

	local streakFrame = frames:WaitForChild(LoginRewardConfigs.UI.StreakFrameName, 15) :: Frame?
	local offlineFrame = frames:WaitForChild(LoginRewardConfigs.UI.OfflineFrameName, 15) :: Frame?
	if not streakFrame or not offlineFrame then
		warn("[iseesupes] LoginRewardController: DailyStreak / OfflineReward frames missing (build them in Studio).")
		return
	end

	HudAnimations.rememberBaseSize(streakFrame)
	HudAnimations.rememberBaseSize(offlineFrame)
	streakFrame.Visible = false
	offlineFrame.Visible = false

	local state: any = nil
	local streakOpen = false
	local offlineOpen = false
	local lastCanClaim: boolean? = nil
	local autoShownOffline = false
	local autoShownStreakDay: number? = nil
	local hudClaimButton: GuiObject? = nil
	local updateHudClaimButton: () -> ()

	local function closeFrame(frame: Frame, onDone: (() -> ())?)
		HudAnimations.closeFrameY(frame, nil, onDone)
	end

	local function getLevel(): number
		local data = DataLib.GetData()
		if data and type(data.Level) == "number" then
			return data.Level
		end
		return 1
	end

	-- ── Streak frame ────────────────────────────────────────────────
	local background = streakFrame:WaitForChild("Background") :: Frame
	local claimButton = streakFrame:WaitForChild("ClaimButton") :: TextButton
	local claimText = claimButton:WaitForChild("Text") :: TextLabel
	local footer = streakFrame:WaitForChild("Footer") :: TextLabel
	local closeStreak = streakFrame:WaitForChild("Close") :: TextButton

	local function renderStreak()
		if not state then
			return
		end
		local level = getLevel()
		for day = 1, 7 do
			local card = background:FindFirstChild("Day" .. day)
			if not card then
				continue
			end
			local reward = LoginRewardConfigs.GetStreakDayReward(day)
			local xp = LoginRewardConfigs.GetStreakXp(day, level)

			local rewardLabel = card:FindFirstChild("Reward") :: TextLabel?
			if rewardLabel then
				-- Game-wide terminology: the XP currency is called "Speed" (see Online Rewards cards).
				rewardLabel.Text = "+" .. NumberFormatter.Format(xp) .. " Speed"
			end
			local winsLabel = card:FindFirstChild("Wins") :: TextLabel?
			if winsLabel then
				winsLabel.Visible = reward.Wins > 0
				winsLabel.Text = "+" .. reward.Wins .. " Wins"
			end

			local claimedInCycle = day < state.dayInCycle
				or (day == state.dayInCycle and not state.canClaim)
			local claimedOverlay = card:FindFirstChild("Claimed") :: ImageLabel?
			if claimedOverlay then
				claimedOverlay.Visible = claimedInCycle
			end

			local stroke = card:FindFirstChild("UIStroke") :: UIStroke?
			if stroke then
				local isToday = day == state.dayInCycle and state.canClaim
				stroke.Thickness = if isToday then 4 else 0
				stroke.Color = HIGHLIGHT_COLOR
			end
		end

		if state.canClaim then
			claimText.Text = "CLAIM DAY " .. state.dayInCycle
		else
			claimText.Text = "CLAIMED"
		end

		local streakCount = state.totalStreak
		local dayWord = if streakCount == 1 then "day" else "days"
		footer.Text = if state.canClaim
			then "Streak: " .. streakCount .. " " .. dayWord .. " — claim to keep it going!"
			else "Streak: " .. streakCount .. " " .. dayWord .. " — come back tomorrow!"
	end

	local function openStreak()
		if offlineOpen then
			return
		end
		if streakOpen then
			return
		end
		streakOpen = true
		renderStreak()
		HudAnimations.openFrameY(streakFrame)
	end

	closeStreak.MouseButton1Click:Connect(function()
		streakOpen = false
		closeFrame(streakFrame)
	end)

	claimButton.MouseButton1Click:Connect(function()
		if not state or not state.canClaim then
			return
		end
		LoginRewardService:ClaimStreak()
			:andThen(function(ok: boolean)
				if ok then
					task.delay(1.2, function()
						if streakOpen then
							streakOpen = false
							closeFrame(streakFrame)
						end
					end)
				end
			end)
			:catch(function() end)
	end)

	-- ── Offline frame ───────────────────────────────────────────────
	local offlineBg = offlineFrame:WaitForChild("Background") :: Frame
	local awayLabel = offlineBg:WaitForChild("AwayTime") :: TextLabel
	local amountLabel = offlineBg:WaitForChild("Amount") :: TextLabel
	local offlineClaimButton = offlineFrame:WaitForChild("ClaimButton") :: TextButton
	local closeOffline = offlineFrame:WaitForChild("Close") :: TextButton

	local function maybeOpenStreakNext()
		if state and state.canClaim and not streakOpen then
			task.delay(0.35, openStreak)
		end
	end

	local function openOffline()
		if offlineOpen or not state or state.offlineXp <= 0 then
			return
		end
		offlineOpen = true
		awayLabel.Text = "You were away " .. LoginRewardConfigs.FormatAway(state.awaySeconds)
		amountLabel.Text = "+" .. NumberFormatter.Format(state.offlineXp) .. " Speed"
		HudAnimations.openFrameY(offlineFrame)
		updateHudClaimButton()
	end

	local function closeOfflineFrame()
		if not offlineOpen then
			return
		end
		offlineOpen = false
		updateHudClaimButton()
		closeFrame(offlineFrame, maybeOpenStreakNext)
	end

	closeOffline.MouseButton1Click:Connect(closeOfflineFrame)

	offlineClaimButton.MouseButton1Click:Connect(function()
		if not state or state.offlineXp <= 0 then
			closeOfflineFrame()
			return
		end
		LoginRewardService:ClaimOffline()
			:andThen(function(ok: boolean)
				if ok and state then
					state.offlineXp = 0
				end
				task.delay(0.8, closeOfflineFrame)
			end)
			:catch(function() end)
	end)

	local function shouldDeferStreakForOffline(): boolean
		if offlineOpen then
			return true
		end
		if state and state.offlineXp > 0 then
			return true
		end
		return false
	end

	local function updateHudClaimButtonImpl()
		if not hudClaimButton then
			return
		end
		local claimable = state ~= nil and state.canClaim == true
		hudClaimButton.Visible = claimable and not shouldDeferStreakForOffline()
	end
	updateHudClaimButton = updateHudClaimButtonImpl

	local function resolveHudClickTarget(root: Instance): GuiButton?
		if root:IsA("GuiButton") then
			return root
		end
		local nested = root:FindFirstChild("Button", true)
		if nested and nested:IsA("GuiButton") then
			return nested
		end
		return nil
	end

	local function ensureHudClaimButton(): GuiButton?
		local hud = gui:FindFirstChild("HUD")
		if not hud then
			return nil
		end

		local path = LoginRewardConfigs.UI.HudButtonPath
		if typeof(path) ~= "table" or #path < 1 then
			return nil
		end

		local parent: Instance = hud
		for i = 1, #path - 1 do
			local child = parent:FindFirstChild(path[i])
			if not child then
				return nil
			end
			parent = child
		end

		local buttonName = path[#path]
		local existing = parent:FindFirstChild(buttonName)
		if existing then
			local clickTarget = resolveHudClickTarget(existing)
			if clickTarget then
				hudClaimButton = if existing:IsA("GuiObject") then existing else (clickTarget :: GuiObject)
				return clickTarget
			end
		end

		local root = Instance.new("ImageButton")
		root.Name = buttonName
		root.BackgroundTransparency = 1
		root.Size = UDim2.new(0, 56, 0, 56)
		root.Image = HUD_GIFT_ICON
		root.ScaleType = Enum.ScaleType.Fit
		root.Visible = false
		root.LayoutOrder = 5
		root.Parent = parent

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = root

		hudClaimButton = root
		return root
	end

	local hudClickButton = ensureHudClaimButton()
	if hudClickButton then
		hudClickButton.MouseButton1Click:Connect(function()
			if state and state.canClaim then
				openStreak()
			end
		end)
	end

	-- ── State + auto-show ───────────────────────────────────────────
	local function tryAutoShow()
		local data = DataLib.GetData()
		local step = if data and type(data.TutorialStep) == "number" then data.TutorialStep else 1
		if step < LoginRewardConfigs.UI.MinTutorialStep then
			return
		end
		if not state then
			return
		end

		if state.offlineXp > 0 and not autoShownOffline and not offlineOpen then
			autoShownOffline = true
			openOffline()
			return
		end

		if state.canClaim and not streakOpen and not shouldDeferStreakForOffline() then
			local newDay = state.dayInCycle
			local becameClaimable = lastCanClaim == false
			if autoShownStreakDay ~= newDay or becameClaimable then
				autoShownStreakDay = newDay
				openStreak()
			end
		end
	end

	local function onStateUpdated(newState: any)
		local prevCanClaim = if state then state.canClaim else nil
		state = newState
		if streakOpen then
			renderStreak()
		end
		if newState and prevCanClaim == false and newState.canClaim == true then
			autoShownStreakDay = nil
		end
		lastCanClaim = if newState then newState.canClaim else lastCanClaim
		updateHudClaimButton()
		tryAutoShow()
	end

	LoginRewardService.StateChanged:Connect(onStateUpdated)

	LoginRewardService:GetState()
		:andThen(function(initial: any?)
			if initial then
				onStateUpdated(initial)
			else
				tryAutoShow()
			end
		end)
		:catch(function() end)

	task.delay(LoginRewardConfigs.UI.AutoShowDelay, tryAutoShow)

	StudioLog.ready("LoginRewardController")
end

return LoginRewardController
