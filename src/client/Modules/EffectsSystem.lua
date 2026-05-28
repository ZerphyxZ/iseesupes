--!strict

-- Floating +Speed / +Wins popups on the HUD.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local EffectsSystem = {}

local POPUP_LIFETIME = 1.1
local RISE_OFFSET = 36

local function getPopupParent(): Instance?
	local player = Players.LocalPlayer
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then
		return nil
	end
	local root = gui:FindFirstChild("GUI")
	return root or gui
end

local function spawnPopup(text: string, color: Color3)
	local parent = getPopupParent()
	if not parent then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "EffectPopup"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(200, 40)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.42, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Text = text
	label.ZIndex = 50
	label.Parent = parent

	local startPos = label.Position
	local endPos = startPos + UDim2.new(0, 0, 0, -RISE_OFFSET)

	local rise = TweenService:Create(label, TweenInfo.new(POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = endPos,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise:Play()
	rise.Completed:Connect(function()
		label:Destroy()
	end)
end

function EffectsSystem.ShowSpeedPopUp(gain: number)
	if gain <= 0 then
		return
	end
	spawnPopup("+" .. tostring(math.floor(gain + 0.5)) .. " Speed", Color3.fromRGB(85, 255, 170))
end

function EffectsSystem.ShowWinPopUp(gain: number)
	if gain <= 0 then
		return
	end
	spawnPopup("+" .. tostring(math.floor(gain + 0.5)) .. " Wins", Color3.fromRGB(255, 220, 80))
end

function EffectsSystem.ShowThrustPopUp(gain: number)
	if gain <= 0 then
		return
	end
	spawnPopup("+" .. tostring(math.floor(gain + 0.5)) .. " Thrust", Color3.fromRGB(255, 120, 100))
end

return EffectsSystem
