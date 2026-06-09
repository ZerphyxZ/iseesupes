--!strict

-- VisionMobile tap → heat vision (F). Fill shows solar energy (charges while flying only).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)
local VisionMobileUI = require(ReplicatedStorage.Shared.Utils.VisionMobileUI)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local VisionMobileController = Knit.CreateController({ Name = "VisionMobileController" })

local player = Players.LocalPlayer
local ATTR = HeatVisionConfigs.Attributes

local C_IDLE = Color3.fromRGB(255, 120, 60)
local C_ACTIVE = Color3.fromRGB(255, 200, 80)
local C_EMPTY = Color3.fromRGB(120, 120, 120)

type Refs = {
	visionFrame: Frame,
	baseButton: ImageButton,
	emptyMask: Frame,
}

local HeatVisionService: any = nil
local HeatVisionController: any = nil
local currentRefs: Refs? = nil
local buttonTapConn: RBXScriptConnection? = nil
local lastRejectedToastAt = -math.huge

local function isActive(): boolean
	return player:GetAttribute(ATTR.Active) == true
end

local function localActiveViaController(): boolean
	if HeatVisionController and HeatVisionController.IsLocalActive then
		return HeatVisionController:IsLocalActive()
	end
	return false
end

local function getSolarFill(): number
	local data = DataLib.GetData()
	if not data then
		return 1
	end
	local current = data.SolarCurrent
	local max = data.SolarMax
	if typeof(current) ~= "number" or typeof(max) ~= "number" or max <= 0 then
		return 1
	end
	return math.clamp(current / max, 0, 1)
end

local function hasEnoughSolar(): boolean
	local data = DataLib.GetData()
	if not data then
		return false
	end
	local current = if typeof(data.SolarCurrent) == "number" then data.SolarCurrent else 0
	local max = if typeof(data.SolarMax) == "number" and data.SolarMax > 0 then data.SolarMax else nil
	return current >= HeatVisionConfigs.getMinSolarToStart(max)
end

local function getButtonTint(): Color3
	if isActive() then
		return C_ACTIVE
	end
	if not hasEnoughSolar() then
		return C_EMPTY
	end
	return C_IDLE
end

local function setupFill(visionFrame: Frame): Refs?
	local baseButton = visionFrame:FindFirstChildOfClass("ImageButton") :: ImageButton?
	if not baseButton then
		warn("[iseesupes][VisionMobile] No ImageButton inside VisionMobile")
		return nil
	end

	if not baseButton:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = baseButton
	end
	baseButton.ClipsDescendants = true

	local mask = baseButton:FindFirstChild("_EmptyMask") :: Frame?
	if not mask then
		mask = Instance.new("Frame")
		mask.Name = "_EmptyMask"
		mask.AnchorPoint = Vector2.new(0, 0)
		mask.Position = UDim2.fromScale(0, 0)
		mask.Size = UDim2.fromScale(1, 0)
		mask.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		mask.BackgroundTransparency = 0.42
		mask.BorderSizePixel = 0
		mask.ZIndex = baseButton.ZIndex + 1
		mask.Active = false
		mask.Selectable = false
		mask.Parent = baseButton
	end

	return { visionFrame = visionFrame, baseButton = baseButton, emptyMask = mask :: Frame }
end

local function applyVisuals(refs: Refs)
	local fill = getSolarFill()
	local active = isActive()
	refs.emptyMask.Size = UDim2.fromScale(1, 1 - fill)
	refs.emptyMask.BackgroundTransparency = if active then 0.28 else 0.42
	refs.baseButton.ImageColor3 = getButtonTint()
end

local function notifyRejected(reason: string?)
	local now = os.clock()
	if now - lastRejectedToastAt < 0.6 then
		return
	end
	lastRejectedToastAt = now
	if reason == "no_solar" then
		NotificationManager.show("Fly to recharge solar energy for heat vision", "Info")
	elseif reason == "active" then
		return
	elseif reason == "flying" then
		NotificationManager.show("Land before using heat vision", "Info")
	else
		NotificationManager.show("Heat vision unavailable", "Info")
	end
end

local function onButtonTapped()
	if isActive() or localActiveViaController() then
		if HeatVisionController and HeatVisionController.Cancel then
			HeatVisionController:Cancel()
		elseif HeatVisionService then
			HeatVisionService:RequestCancel():catch(warn)
		end
		return
	end

	if not hasEnoughSolar() then
		notifyRejected("no_solar")
		return
	end

	if HeatVisionController then
		HeatVisionController:Begin()
		return
	end

	if not HeatVisionService then
		return
	end

	HeatVisionService:RequestStart():andThen(function(ok: boolean, reason: string?)
		if not ok then
			notifyRejected(reason)
		end
	end):catch(warn)
end

local function bindVisionButton(refs: Refs)
	if buttonTapConn then
		buttonTapConn:Disconnect()
		buttonTapConn = nil
	end

	refs.baseButton.Active = true
	refs.baseButton.Selectable = true
	currentRefs = refs
	applyVisuals(refs)

	buttonTapConn = refs.baseButton.MouseButton1Click:Connect(onButtonTapped)
end

local function refsAreAlive(refs: Refs?): boolean
	if not refs then
		return false
	end
	return refs.visionFrame.Parent ~= nil and refs.baseButton.Parent ~= nil
end

local function tryAttachVisionMobile(playerGui: PlayerGui): boolean
	local visionFrame = VisionMobileUI.findVisionMobile(playerGui)
	if not visionFrame then
		return false
	end

	local refs = setupFill(visionFrame)
	if not refs then
		return false
	end

	if currentRefs and currentRefs.baseButton == refs.baseButton then
		applyVisuals(refs)
		return true
	end

	bindVisionButton(refs)
	return true
end

function VisionMobileController:KnitStart()
	if not CharacterConfigs.Features.UseHeatVision then
		return
	end

	HeatVisionService = Knit.GetService("HeatVisionService")
	HeatVisionController = Knit.GetController("HeatVisionController")

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local deadline = os.clock() + 30
	while not currentRefs and os.clock() < deadline do
		if tryAttachVisionMobile(playerGui) then
			break
		end
		task.wait(0.25)
	end

	if not currentRefs then
		warn("[iseesupes][VisionMobile] VisionMobile not found — skipping.")
	end

	player:GetAttributeChangedSignal(ATTR.Active):Connect(function()
		local refs = currentRefs
		if refsAreAlive(refs) then
			applyVisuals(refs :: Refs)
		end
	end)

	HeatVisionService.AbilityEnded:Connect(function()
		local refs = currentRefs
		if refsAreAlive(refs) then
			applyVisuals(refs :: Refs)
		end
	end)

	HeatVisionService.Rejected:Connect(function(reason: string)
		notifyRejected(reason)
	end)

	DataLib.OnSolarChanged(function()
		local refs = currentRefs
		if refsAreAlive(refs) then
			applyVisuals(refs :: Refs)
		end
	end)

	DataLib.OnChanged(function()
		local refs = currentRefs
		if refsAreAlive(refs) then
			applyVisuals(refs :: Refs)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local refs = currentRefs
		if not refsAreAlive(refs) then
			return
		end
		if isActive() then
			applyVisuals(refs :: Refs)
		end
	end)

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "VisionMobile" and descendant:IsA("Frame") then
			task.defer(function()
				tryAttachVisionMobile(playerGui)
			end)
		end
	end)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			tryAttachVisionMobile(playerGui)
		end)
	end)
end

return VisionMobileController
