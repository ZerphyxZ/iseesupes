--!strict
-- WinCelebrationController
--
-- Plays a short, satisfying celebration when the player claims a win — a big centered
-- "+N WINS!" that pops in, holds, then rises and fades — BEFORE they're returned to the
-- lobby. The win-claim previously teleported the player away instantly with no payoff,
-- which is the biggest dopamine gap in the core loop. The WinClaim sound already fires
-- via SpeedController.updateWinsPopups on the wins change; this adds the visual punch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)

local WinCelebrationController = Knit.CreateController({ Name = "WinCelebrationController" })

local player = Players.LocalPlayer

local function celebrate(amount: number)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WinCelebration"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.4, 0)
	label.Size = UDim2.new(0.6, 0, 0, 96)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "+" .. NumberFormatter.Format(amount) .. " WINS!"
	label.TextColor3 = Color3.fromRGB(255, 225, 70)
	label.TextStrokeColor3 = Color3.fromRGB(40, 25, 0)
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label

	gui.Parent = playerGui

	-- Pop in with an overshoot, then settle.
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
	task.delay(0.36, function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.0 }):Play()
		end
	end)
	-- Rise + fade out.
	task.delay(0.95, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, 0, 0.32, 0),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
	task.delay(1.55, function()
		gui:Destroy()
	end)
end

function WinCelebrationController:KnitStart()
	local GiveWinsService = Knit.GetService("GiveWinsService")
	GiveWinsService.WinCelebration:Connect(function(amount: number)
		celebrate(amount)
	end)
end

return WinCelebrationController
