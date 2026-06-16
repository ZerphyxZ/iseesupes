--!strict

-- Binds hover + click scale effects (GUI) and hover / click SFX (all PlayerGui buttons).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)

local UIButtonEffectsController = Knit.CreateController({ Name = "UIButtonEffectsController" })

local guiRoot: Instance? = nil

local function pathMatchesExcluded(button: GuiButton): boolean
	if not guiRoot then
		return false
	end

	local cfg = HudConfigs.ButtonEffects
	for _, segments in cfg.ExcludePaths do
		local node: Instance? = guiRoot
		local matched = true
		for _, name in segments do
			if not node then
				matched = false
				break
			end
			node = node:FindFirstChild(name)
		end
		if matched and node then
			if button == node or button:IsDescendantOf(node) then
				return true
			end
		end
	end
	return false
end

local function shouldBindScaleEffects(button: GuiButton): boolean
	local cfg = HudConfigs.ButtonEffects
	if button:GetAttribute(cfg.BoundAttribute) == true then
		return false
	end
	if button:GetAttribute(cfg.SkipAttribute) == true then
		return false
	end
	if not button.Active then
		return false
	end
	if pathMatchesExcluded(button) then
		return false
	end
	return true
end

local function shouldBindButtonSounds(button: GuiButton): boolean
	local cfg = HudConfigs.ButtonSounds
	if button:GetAttribute(cfg.BoundAttribute) == true then
		return false
	end
	if not button.Active then
		return false
	end
	return true
end

local function tryBindButton(button: Instance)
	if not button:IsA("GuiButton") then
		return
	end
	if shouldBindButtonSounds(button) then
		HudAnimations.bindButtonSounds(button)
	end
	if shouldBindScaleEffects(button) then
		HudAnimations.bindButtonEffects(button)
	end
end

local function bindTree(root: Instance)
	for _, desc in root:GetDescendants() do
		tryBindButton(desc)
	end
	if root:IsA("GuiButton") then
		tryBindButton(root)
	end
end

function UIButtonEffectsController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local gui = playerGui:WaitForChild("GUI", 120)
	if gui then
		guiRoot = gui
	end

	bindTree(playerGui)

	playerGui.DescendantAdded:Connect(function(desc)
		tryBindButton(desc)
	end)

	StudioLog.ready("UIButtonEffectsController")
end

return UIButtonEffectsController
