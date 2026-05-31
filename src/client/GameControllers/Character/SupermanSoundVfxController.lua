--!strict

-- Manages Superman flight sounds and tiered surface-break VFX on takeoff / landing touchdown.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)
local SupermanGroundVfx = require(script.Parent.Parent.Parent.Modules.SupermanGroundVfx)

local SupermanSoundVfxController = Knit.CreateController({ Name = "SupermanSoundVfxController" })

local player = Players.LocalPlayer
local constantFlyingSound: Sound? = nil
local touchdownConn: RBXScriptConnection? = nil
local fallTrackConn: RBXScriptConnection? = nil
local landingFiredForAbility = false
local peakFallSpeed = 0
local lastHrpY: number? = nil
local lastFallSampleAt: number? = nil
local landingBlockLogged = false
local warnedSoundsFolder = false

local function debugLog(...)
	if SupermanVfxConfigs.Debug then
		print("[iseesupes][SupermanVfx]", ...)
	end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

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

local function playOneShot(soundName: string, lifetime: number, volume: number?)
	local hrp = getHrp()
	if not hrp then
		return
	end
	local folder = getSoundsFolder()
	if not folder then
		if not warnedSoundsFolder then
			warnedSoundsFolder = true
			warn("[iseesupes][SupermanVfx] Sounds folder not found. Create ReplicatedStorage >",
				table.concat(SupermanVfxConfigs.Sounds.FolderPath, " > "))
		end
		return
	end
	local template = folder:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		warn("[iseesupes][SupermanVfx] Sound not found:", soundName)
		return
	end
	local clone = (template :: Sound):Clone()
	if volume ~= nil then
		clone.Volume = volume
	end
	clone.Parent = hrp
	clone:Play()
	Debris:AddItem(clone, lifetime)
end

local function startConstantFlyingLoop(hrp: BasePart)
	if constantFlyingSound and constantFlyingSound.Parent then
		if not constantFlyingSound.IsPlaying then
			constantFlyingSound:Play()
		end
		return
	end
	local folder = getSoundsFolder()
	if not folder then
		return
	end
	local template = folder:FindFirstChild(SupermanVfxConfigs.Sounds.ConstantFlying)
	if not template or not template:IsA("Sound") then
		warn("[iseesupes][SupermanVfx] ConstantFlying sound not found")
		return
	end
	local clone = (template :: Sound):Clone()
	clone.Name = SupermanVfxConfigs.Sounds.ConstantFlyingParentName
	clone.Looped = true
	clone.Parent = hrp
	clone:Play()
	constantFlyingSound = clone
end

local function stopConstantFlyingLoop()
	local s = constantFlyingSound
	if not s then
		return
	end
	if s.IsPlaying then
		s:Stop()
	end
	if s.Parent then
		s:Destroy()
	end
	constantFlyingSound = nil
end

local function playLandingSounds()
	local sounds = SupermanVfxConfigs.Sounds
	playOneShot(
		sounds.GroundCracking,
		sounds.GroundCrackingLifetime,
		sounds.GroundCrackingVolume
	)
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
	lastHrpY = nil
	lastFallSampleAt = nil
	landingBlockLogged = false

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

local function stopTouchdownWatch()
	if touchdownConn then
		touchdownConn:Disconnect()
		touchdownConn = nil
	end
end

local function startTouchdownWatch()
	stopTouchdownWatch()
	landingFiredForAbility = false

	touchdownConn = RunService.Heartbeat:Connect(function()
		if landingFiredForAbility then
			stopTouchdownWatch()
			return
		end

		local hrp = getHrp()
		if not hrp then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		local result = SupermanGroundVfx.raycastFloorFromHrp(hrp)
		if not result then
			return
		end

		local probeY = getLowestFootY(character, hrp)
		local heightAboveFloor = probeY - result.Position.Y
		if heightAboveFloor > SupermanVfxConfigs.TouchdownMaxHeight or heightAboveFloor < -1 then
			return
		end

		local closeTouchdown = heightAboveFloor <= (SupermanVfxConfigs.TouchdownCloseHeight or 2.5)
		local fastEnough = peakFallSpeed >= SupermanVfxConfigs.MinLandingSpeed
		if not fastEnough and not closeTouchdown then
			if not landingBlockLogged then
				landingBlockLogged = true
				debugLog("landing blocked soft fall peak=", math.floor(peakFallSpeed), "height=", heightAboveFloor)
			end
			return
		end

		landingFiredForAbility = true
		local spawned = SupermanGroundVfx.spawnSurfaceBreak("Landing", result, player.Character)
		if spawned then
			playLandingSounds()
		end
		debugLog(
			"landing break fired peak=",
			math.floor(peakFallSpeed),
			"height=",
			math.floor(heightAboveFloor * 10) / 10,
			"spawned=",
			spawned
		)
		stopTouchdownWatch()
	end)
end

-- ── Phase handling ────────────────────────────────────────────────────────────

local function onPhaseChanged(phase: string)
	if phase == "FlightTransit" then
		landingFiredForAbility = false
		startFallTracking()
		SupermanGroundVfx.resetAbilityState()

		playOneShot(
			SupermanVfxConfigs.Sounds.StartFlying,
			SupermanVfxConfigs.Sounds.StartFlyingLifetime,
			SupermanVfxConfigs.Sounds.StartFlyingVolume
		)

		local hrp = getHrp()
		if hrp then
			local result = SupermanGroundVfx.raycastFloorFromHrp(hrp)
			if result then
				SupermanGroundVfx.spawnSurfaceBreak("Takeoff", result)
			end
		end
	elseif phase == "AfterTransition" or phase == "LeanUp" or phase == "DownSupes" or phase == "CancelFall" then
		local hrp = getHrp()
		if hrp then
			startConstantFlyingLoop(hrp)
		end
	elseif phase == "LeapDown" or phase == "CancelLanding" then
		stopConstantFlyingLoop()
		startTouchdownWatch()
	end
end

local function onAbilityEnded()
	stopTouchdownWatch()
	stopFallTracking()
	stopConstantFlyingLoop()
	SupermanGroundVfx.resetAbilityState()
	landingFiredForAbility = false
	peakFallSpeed = 0
end

-- ── Knit wiring ───────────────────────────────────────────────────────────────

function SupermanSoundVfxController:KnitStart()
	local DoubleJumpService = Knit.GetService("DoubleJumpService")

	DoubleJumpService.PhaseChanged:Connect(onPhaseChanged)
	DoubleJumpService.AbilityEnded:Connect(onAbilityEnded)

	player.CharacterAdded:Connect(function()
		constantFlyingSound = nil
		stopTouchdownWatch()
		stopFallTracking()
		landingFiredForAbility = false
		peakFallSpeed = 0
	end)

	print("[iseesupes] SupermanSoundVfxController ready.")
end

return SupermanSoundVfxController
