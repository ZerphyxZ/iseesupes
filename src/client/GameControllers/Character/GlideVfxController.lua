--!strict

-- Cape flutter + limb glide trails during E ability glide phases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local GlideVfx = require(script.Parent.Parent.Parent.Modules.GlideVfx)
local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)

local GlideVfxController = Knit.CreateController({ Name = "GlideVfxController" })

local player = Players.LocalPlayer

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, name in segments do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function findSoundsFolder(): Folder?
	local folder = resolvePath(ReplicatedStorage, GlideVfxConfigs.Assets.GlideSoundsFolder)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function applyPhase(phase: string?)
	if not CharacterConfigs.Features.UseDoubleJump then
		return
	end
	if not GlideVfxConfigs.Enabled or CharacterConfigs.Features.UseGlideVfx == false then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	GlideVfx.setGlideActive(character, GlideVfx.isGlidePhase(phase), findSoundsFolder())
end

function GlideVfxController:KnitStart()
	if not GlideVfxConfigs.Enabled then
		return
	end

	local DoubleJumpService = Knit.GetService("DoubleJumpService")

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		applyPhase(phase)
	end)

	DoubleJumpService.AbilityEnded:Connect(function()
		applyPhase(nil)
	end)

	player.CharacterAdded:Connect(function(character)
		GlideVfx.cleanupCharacter(character)
		character.Destroying:Once(function()
			GlideVfx.cleanupCharacter(character)
		end)
	end)

	if player.Character then
		local character = player.Character
		character.Destroying:Once(function()
			GlideVfx.cleanupCharacter(character)
		end)
	end

	print("[iseesupes] GlideVfxController ready (cape + GlideTrail on E glide).")
end

return GlideVfxController
