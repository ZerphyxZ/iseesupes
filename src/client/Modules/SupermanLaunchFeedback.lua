--!strict

-- Shared launch burst: whoosh + foot smoke (long jump and similar moves).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)
local SupermanGroundVfx = require(script.Parent.SupermanGroundVfx)

local SupermanLaunchFeedback = {}

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, seg in segments do
		local child = current:FindFirstChild(seg)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function findSoundTemplate(soundNames: { string }, folderPaths: { { string } }): Sound?
	for _, segments in folderPaths do
		local folder = resolvePath(ReplicatedStorage, segments)
		if folder and folder:IsA("Folder") then
			for _, name in soundNames do
				local template = folder:FindFirstChild(name)
				if template and template:IsA("Sound") then
					return template
				end
			end
		end
	end
	return nil
end

local function playWhoosh(hrp: BasePart, soundNames: { string }, folderPaths: { { string } }?)
	local paths = folderPaths
	if not paths then
		paths = { SupermanVfxConfigs.Sounds.FolderPath }
		local alt = SupermanVfxConfigs.Sounds.AlternateFolderPaths
		if alt then
			for _, p in alt do
				table.insert(paths, p)
			end
		end
	end

	local template = findSoundTemplate(soundNames, paths)
	if not template then
		warn(
			"[iseesupes][LongJump] Whoosh sound not found. Add one of",
			table.concat(soundNames, ", "),
			"under Shared/Assets/SupermanFlightSounds or GlideVfxSounds"
		)
		return
	end

	local sounds = SupermanVfxConfigs.Sounds
	local clone = template:Clone()
	clone.Volume = sounds.QuickWhooshVolume or 1
	clone.PlaybackSpeed = sounds.QuickWhooshPlaybackSpeed or 1
	clone.Parent = hrp
	clone:Play()
	Debris:AddItem(clone, sounds.QuickWhooshLifetime or 4)
end

function SupermanLaunchFeedback.playLaunchBurst(
	character: Model,
	options: {
		vfxTier: SupermanVfxConfigs.BreakTier?,
		soundNames: { string }?,
		soundFolders: { { string } }?,
		skipParticles: boolean?,
	}?
)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local sounds = SupermanVfxConfigs.Sounds
	local soundNames = if options and options.soundNames
		then options.soundNames
		else { sounds.QuickWhoosh, "Quick Whoosh", "Woosh" }

	playWhoosh(hrp, soundNames, options and options.soundFolders)

	if options and options.skipParticles == true then
		return
	end

	local tier: SupermanVfxConfigs.BreakTier = if options and options.vfxTier
		then options.vfxTier
		else "LongJumpLaunch"
	SupermanGroundVfx.spawnSurfaceBreakForCharacter(tier, character)
end

return SupermanLaunchFeedback
