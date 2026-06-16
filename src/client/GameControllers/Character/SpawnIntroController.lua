--!strict

-- Watches spawn / win-claim lobby fall and plays the same Superman ground-break landing as flight touchdown.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)
local SupermanGroundVfx = require(script.Parent.Parent.Parent.Modules.SupermanGroundVfx)

local SpawnIntroController = Knit.CreateController({ Name = "SpawnIntroController" })

local player = Players.LocalPlayer
local watchConn: RBXScriptConnection? = nil
local fallTrackConn: RBXScriptConnection? = nil
local peakFallSpeed = 0
local lastHrpY: number? = nil
local lastFallSampleAt: number? = nil
local landingFired = false
local watchActive = false
local warnedSoundsFolder = false

local function getConfig()
	return CharacterConfigs.SpawnIntro
end

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

local function getSoundsFolder(): Folder?
	local folder = resolvePath(ReplicatedStorage, SupermanVfxConfigs.Sounds.FolderPath)
	return if folder and folder:IsA("Folder") then folder :: Folder else nil
end

local function getHrp(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

local function getLowestFootY(character: Model, hrp: BasePart): number
	local lowest = hrp.Position.Y
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			lowest = math.min(lowest, part.Position.Y)
		end
	end
	return lowest
end

local function playLandingSounds()
	local hrp = getHrp()
	if not hrp then
		return
	end
	local folder = getSoundsFolder()
	if not folder then
		if not warnedSoundsFolder then
			warnedSoundsFolder = true
		end
		return
	end
	local sounds = SupermanVfxConfigs.Sounds
	local template = folder:FindFirstChild(sounds.GroundCracking)
	if not template or not template:IsA("Sound") then
		return
	end
	local clone = (template :: Sound):Clone()
	clone.Volume = sounds.GroundCrackingVolume
	clone.Parent = hrp
	clone:Play()
	Debris:AddItem(clone, sounds.GroundCrackingLifetime)
end

local function sampleFallSpeed(hrp: BasePart, now: number): number
	local fromVelocity = math.max(0, -hrp.AssemblyLinearVelocity.Y)
	local fromDrop = 0
	if lastHrpY and lastFallSampleAt then
		local dt = now - lastFallSampleAt
		if dt > 1e-4 then
			local drop = lastHrpY - hrp.Position.Y
			if drop > 0 then
				fromDrop = drop / dt
			end
		end
	end
	lastHrpY = hrp.Position.Y
	lastFallSampleAt = now
	return math.max(fromVelocity, fromDrop)
end

local function stopFallTracking()
	if fallTrackConn then
		fallTrackConn:Disconnect()
		fallTrackConn = nil
	end
	lastHrpY = nil
	lastFallSampleAt = nil
end

local function startFallTracking()
	stopFallTracking()
	peakFallSpeed = 0
	fallTrackConn = RunService.Heartbeat:Connect(function()
		local hrp = getHrp()
		if not hrp then
			return
		end
		local sample = sampleFallSpeed(hrp, os.clock())
		if sample > peakFallSpeed then
			peakFallSpeed = sample
		end
	end)
end

local function stopLandingWatch()
	if watchConn then
		watchConn:Disconnect()
		watchConn = nil
	end
end

local function stopIntroWatch()
	stopLandingWatch()
	stopFallTracking()
	peakFallSpeed = 0
end

local function trySpawnIntroLanding(): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = getHrp()
	if not hrp then
		return false
	end

	local result = SupermanGroundVfx.raycastFloorFromHrp(hrp)
	if not result then
		return false
	end

	local probeY = getLowestFootY(character, hrp)
	local heightAboveFloor = probeY - result.Position.Y
	if heightAboveFloor > SupermanVfxConfigs.TouchdownMaxHeight or heightAboveFloor < -1 then
		return false
	end

	local cfg = getConfig()
	local minSpeed = if cfg and type(cfg.MinLandingSpeed) == "number"
		then cfg.MinLandingSpeed
		else 4
	local closeTouchdown = heightAboveFloor <= (SupermanVfxConfigs.TouchdownCloseHeight or 2.5)
	local fastEnough = peakFallSpeed >= minSpeed
	if not fastEnough and not closeTouchdown then
		return false
	end

	return SupermanGroundVfx.spawnSurfaceBreak("Landing", result, character)
end

local function startLandingWatch()
	local cfg = getConfig()
	if not cfg or cfg.Enabled ~= true then
		return
	end
	if watchActive then
		stopIntroWatch()
		watchActive = false
		landingFired = false
	end
	watchActive = true

	stopIntroWatch()
	landingFired = false
	SupermanGroundVfx.resetAbilityState()
	startFallTracking()

	local maxWatch = if type(cfg.MaxLandingWatchSeconds) == "number" then cfg.MaxLandingWatchSeconds else 8
	task.delay(maxWatch, function()
		if landingFired then
			return
		end
		watchActive = false
		player:SetAttribute("SpawnIntroPending", nil)
		stopIntroWatch()
	end)

	watchConn = RunService.Heartbeat:Connect(function()
		if landingFired then
			stopIntroWatch()
			return
		end

		if trySpawnIntroLanding() then
			landingFired = true
			watchActive = false
			player:SetAttribute("SpawnIntroPending", nil)
			playLandingSounds()
			stopIntroWatch()
		end
	end)
end

local function onSpawnIntroPending()
	if player:GetAttribute("SpawnIntroPending") == true then
		startLandingWatch()
	end
end

function SpawnIntroController:KnitStart()
	local cfg = getConfig()
	if not cfg or cfg.Enabled ~= true then
		return
	end

	local SpawnIntroService = Knit.GetService("SpawnIntroService")
	SpawnIntroService.SpawnIntroLifted:Connect(startLandingWatch)
	player:GetAttributeChangedSignal("SpawnIntroPending"):Connect(onSpawnIntroPending)
	onSpawnIntroPending()

	StudioLog.ready("SpawnIntroController")
end

return SpawnIntroController
