--!strict

-- Alternating background music: BGSound1 → BGSound2 → BGSound1 (Studio sounds under SoundService).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MusicConfigs = require(ReplicatedStorage.Shared.Configs.MusicConfigs)

local BackgroundMusicController = Knit.CreateController({ Name = "BackgroundMusicController" })

local musicGroup: SoundGroup? = nil
local playlistSounds: { Sound } = {}
local activeSound: Sound? = nil
local currentTrackIndex = 1
local playlistStarted = false
local endedBound = false
local warnedMissingStudio = false

local function debugLog(...: any)
	if MusicConfigs.Debug then
		print("[iseesupes][BGM]", ...)
	end
end

local function getOrCreateMusicGroup(): SoundGroup
	local existing = SoundService:FindFirstChild(MusicConfigs.SoundGroupName)
	if existing and existing:IsA("SoundGroup") then
		existing.Volume = MusicConfigs.Volume
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = MusicConfigs.SoundGroupName
	group.Volume = MusicConfigs.Volume
	group.Parent = SoundService
	return group
end

local function applyMusicGroup(sound: Sound)
	sound.Looped = false
	sound.PlaybackSpeed = MusicConfigs.PlaybackSpeed or 1
	if musicGroup then
		sound.SoundGroup = musicGroup
	end
end

local function fadeInMusicGroup()
	if playlistStarted then
		return
	end
	playlistStarted = true

	local fadeSeconds = MusicConfigs.FadeInSeconds
	local group = musicGroup
	if not group or typeof(fadeSeconds) ~= "number" or fadeSeconds <= 0 then
		return
	end

	local targetVolume = MusicConfigs.Volume
	group.Volume = 0
	local tween = TweenService:Create(group, TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear), { Volume = targetVolume })
	tween:Play()
end

local function isSoundReady(sound: Sound): boolean
	return sound.IsLoaded and sound.TimeLength > 0
end

local function waitForSoundReady(sound: Sound): boolean
	if isSoundReady(sound) then
		return true
	end

	local timeout = MusicConfigs.LoadTimeoutSeconds
	if typeof(timeout) ~= "number" or timeout <= 0 then
		timeout = 30
	end

	pcall(function()
		ContentProvider:PreloadAsync({ sound })
	end)

	local finished = false
	local connLoaded = sound.Loaded:Connect(function()
		finished = true
	end)

	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if isSoundReady(sound) then
			connLoaded:Disconnect()
			return true
		end
		if finished then
			break
		end
		task.wait(0.05)
	end

	connLoaded:Disconnect()
	return isSoundReady(sound)
end

local function stopPlaylistExcept(except: Sound?)
	for _, sound in playlistSounds do
		if sound ~= except and sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function resolveStudioPlaylist(): boolean
	table.clear(playlistSounds)

	local waitTime = MusicConfigs.WaitForStudioSeconds
	if typeof(waitTime) ~= "number" or waitTime < 0 then
		waitTime = 15
	end

	for _, name in MusicConfigs.StudioSoundNames do
		local inst = SoundService:FindFirstChild(name)
		if not inst and waitTime > 0 then
			inst = SoundService:WaitForChild(name, waitTime)
		end
		if inst and inst:IsA("Sound") then
			applyMusicGroup(inst :: Sound)
			table.insert(playlistSounds, inst :: Sound)
			debugLog("found studio sound", name)
		else
			debugLog("missing studio sound", name)
		end
	end

	return #playlistSounds > 0
end

local playTrack: (number) -> ()

playTrack = function(index: number)
	local count = #playlistSounds
	if count == 0 then
		return
	end

	if index < 1 or index > count then
		index = 1
	end

	currentTrackIndex = index
	local sound = playlistSounds[index]

	stopPlaylistExcept(sound)

	local previous = activeSound
	activeSound = sound
	if previous and previous ~= sound and previous.IsPlaying then
		previous:Stop()
	end

	sound.TimePosition = 0

	if not waitForSoundReady(sound) then
		warn("[iseesupes][BGM] Not ready:", sound.Name, sound.SoundId)
		local nextIndex = index % count + 1
		if nextIndex ~= index then
			task.defer(function()
				playTrack(nextIndex)
			end)
		end
		return
	end

	if activeSound ~= sound then
		return
	end

	sound:Play()
	fadeInMusicGroup()

	debugLog("playing", sound.Name, sound.TimeLength)
	if MusicConfigs.Debug then
		print("[iseesupes][BGM] Now playing", sound.Name)
	end
end

local function bindEndedHandlers()
	if endedBound then
		return
	end
	endedBound = true

	for _, sound in playlistSounds do
		sound.Ended:Connect(function()
			if activeSound ~= sound then
				return
			end
			local count = #playlistSounds
			if count == 0 then
				return
			end
			local nextIndex = currentTrackIndex % count + 1
			task.defer(function()
				playTrack(nextIndex)
			end)
		end)
	end
end

local function startPlaylist()
	musicGroup = getOrCreateMusicGroup()

	if resolveStudioPlaylist() then
		bindEndedHandlers()
		playTrack(1)
		return
	end

	if not warnedMissingStudio then
		warnedMissingStudio = true
		warn(
			"[iseesupes][BGM] Add Sound objects to SoundService named:",
			table.concat(MusicConfigs.StudioSoundNames, ", ")
		)
	end
end

function BackgroundMusicController:KnitStart()
	if not MusicConfigs.Enabled then
		return
	end

	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		task.wait(0.25)
		startPlaylist()
	end)

	print("[iseesupes] BackgroundMusicController ready.")
end

return BackgroundMusicController
