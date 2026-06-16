--!strict

-- Slowly rotates the "Shine" ImageLabel inside configured HUD buttons (e.g. StarterPack).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)

local ShineSpinController = Knit.CreateController({ Name = "ShineSpinController" })

local player = Players.LocalPlayer

local shineLabels: { GuiObject } = {}

local function getCfg(): any
	return HudConfigs.ShineSpin or {}
end

local function collectShineLabels()
	table.clear(shineLabels)

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local cfg = getCfg()
	local shineName = cfg.ShineName or "Shine"
	local buttonNames: { string } = cfg.ButtonNames or {}

	for _, buttonName in buttonNames do
		local button = playerGui:FindFirstChild(buttonName, true)
		if button then
			local shine = button:FindFirstChild(shineName)
			if shine and shine:IsA("GuiObject") then
				table.insert(shineLabels, shine)
			end
		end
	end
end

function ShineSpinController:KnitStart()
	local cfg = getCfg()
	local degreesPerSecond = if type(cfg.DegreesPerSecond) == "number" then cfg.DegreesPerSecond else 30
	local rescanSeconds = if type(cfg.RescanSeconds) == "number" then cfg.RescanSeconds else 5

	task.spawn(function()
		player:WaitForChild("PlayerGui", 30)
		collectShineLabels()
		while true do
			task.wait(rescanSeconds)
			collectShineLabels()
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		for _, shine in shineLabels do
			if shine.Parent then
				shine.Rotation = (shine.Rotation + degreesPerSecond * dt) % 360
			end
		end
	end)

	StudioLog.ready("ShineSpinController")
end

return ShineSpinController
