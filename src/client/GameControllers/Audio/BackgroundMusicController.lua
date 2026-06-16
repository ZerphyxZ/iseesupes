--!strict

-- Alternating background music: BGSound1 → BGSound2 → BGSound1 (Studio sounds under SoundService).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
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
local watchdogRunning = false
local retryLoopRunning = false
local playlistStartAt = 0
local startRetriesLeft = 0

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
	sound.AcousticSimulationEnabled = false
	-- Repair Studio sounds that had RollOffMaxDistance = 0 (inaudible).
	if sound.RollOffMaxDistance <= 0 then
		sound.RollOffMaxDistance = 10000
	end
	if musicGroup then
		sound.SoundGroup = musicGroup
	end
end

local function ensureMusicGroupVolume()
	local group = musicGroup
	if not group then
		return
	end
	local target = MusicConfigs.Volume
	if typeof(target) ~= "number" then
		return
	end
	group.Volume = target
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
	-- TimeLength > 0 means the asset is loaded enough to play; IsLoaded can stay false briefly in Studio.
	if sound.TimeLength > 0 then
		return true
	end
	return sound.IsLoaded
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

local function isAnyTrackPlaying(): boolean
	for _, sound in playlistSounds do
		if sound.IsPlaying then
			return true
		end
	end
	return false
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

local function createFallbackPlaylist(): boolean
	local tracks = MusicConfigs.Tracks
	local names = MusicConfigs.StudioSoundNames
	if type(tracks) ~= "table" or #tracks == 0 then
		return false
	end

	table.clear(playlistSounds)
	for i, soundId in tracks do
		if typeof(soundId) ~= "string" or soundId == "" then
			continue
		end
		local name = if type(names) == "table" and typeof(names[i]) == "string" then names[i] else ("BGSound" .. i)
		local existing = SoundService:FindFirstChild(name)
		local sound: Sound
		if existing and existing:IsA("Sound") then
			sound = existing
			sound.SoundId = soundId
		else
			sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = soundId
			sound.Parent = SoundService
		end
		applyMusicGroup(sound)
		table.insert(playlistSounds, sound)
		debugLog("fallback track", name, soundId)
	end

	return #playlistSounds > 0
end

local function preloadPlaylist()
	if #playlistSounds == 0 then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(playlistSounds)
	end)
	debugLog("preloaded", #playlistSounds, "tracks")
end

local function shouldWatchdogAdvance(sound: Sound): boolean
	if sound.IsPlaying then
		return false
	end
	local len = sound.TimeLength
	if len <= 0 then
		return false
	end
	local pos = sound.TimePosition
	if pos >= len - 0.25 then
		return true
	end
	if pos > 0.5 then
		return true
	end
	return false
end

local function shouldWatchdogRestartNeverStarted(): boolean
	if isAnyTrackPlaying() then
		return false
	end
	if playlistStartAt <= 0 then
		return false
	end
	if os.clock() - playlistStartAt < 3 then
		return false
	end
	local sound = activeSound
	if not sound then
		return true
	end
	if sound.IsPlaying then
		return false
	end
	return sound.TimePosition <= 0.1
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
	ensureMusicGroupVolume()

	local previous = activeSound
	activeSound = sound
	if previous and previous ~= sound and previous.IsPlaying then
		previous:Stop()
	end

	sound.TimePosition = 0

	local ready = isSoundReady(sound)
	if not ready then
		ready = waitForSoundReady(sound)
	end
	if not ready then
		task.wait(1)
		if activeSound == sound then
			ready = isSoundReady(sound) or waitForSoundReady(sound)
		end
	end

	if not ready then
		warn("[iseesupes][BGM] Not ready:", sound.Name, sound.SoundId)
		ensureMusicGroupVolume()
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

	task.defer(function()
		task.wait(0.5)
		if activeSound ~= sound then
			return
		end
		if sound.IsPlaying then
			return
		end
		warn("[iseesupes][BGM] Play() did not start:", sound.Name)
		ensureMusicGroupVolume()
		if waitForSoundReady(sound) then
			sound:Play()
		end
	end)
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

local function startTrackWatchdog()
	if watchdogRunning then
		return
	end
	watchdogRunning = true

	task.spawn(function()
		local interval = MusicConfigs.WatchdogIntervalSeconds
		if typeof(interval) ~= "number" or interval <= 0 then
			interval = 2
		end

		while watchdogRunning and #playlistSounds > 0 do
			task.wait(interval)
			if shouldWatchdogRestartNeverStarted() then
				debugLog("watchdog restart never-started track", currentTrackIndex)
				playTrack(currentTrackIndex)
				continue
			end
			local sound = activeSound
			if sound and shouldWatchdogAdvance(sound) then
				local count = #playlistSounds
				if count == 0 then
					continue
				end
				local nextIndex = currentTrackIndex % count + 1
				debugLog("watchdog advance", sound.Name, "-> track", nextIndex)
				playTrack(nextIndex)
			end
		end
	end)
end

local function startPlaylistRetryLoop()
	if retryLoopRunning then
		return
	end
	retryLoopRunning = true

	task.spawn(function()
		local interval = MusicConfigs.StartRetryIntervalSeconds
		if typeof(interval) ~= "number" or interval <= 0 then
			interval = 8
		end
		local maxRetries = MusicConfigs.MaxStartRetries
		if typeof(maxRetries) ~= "number" or maxRetries < 0 then
			maxRetries = 5
		end
		startRetriesLeft = maxRetries

		while retryLoopRunning and startRetriesLeft > 0 do
			task.wait(interval)
			if isAnyTrackPlaying() then
				continue
			end
			startRetriesLeft -= 1
			debugLog("start retry", startRetriesLeft, "left")
			preloadPlaylist()
			playTrack(currentTrackIndex > 0 and currentTrackIndex or 1)
		end
	end)
end

local function startPlaylist()
	musicGroup = getOrCreateMusicGroup()
	playlistStartAt = os.clock()

	local resolved = resolveStudioPlaylist()
	if not resolved then
		resolved = createFallbackPlaylist()
	end

	if resolved then
		preloadPlaylist()
		bindEndedHandlers()
		startTrackWatchdog()
		startPlaylistRetryLoop()
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

	StudioLog.ready("BackgroundMusicController")
end

return BackgroundMusicController
