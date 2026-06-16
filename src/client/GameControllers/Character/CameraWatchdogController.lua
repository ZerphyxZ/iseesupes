--!strict

-- Camera soft-lock safety net.
--
-- Symptom this guards against: CurrentCamera left on Scriptable by a cutscene / auto-fly
-- camera that never handed control back — the player can still move but the camera is
-- frozen. We can't always prevent every leak upstream, so this watchdog detects a
-- Scriptable camera that NO ability legitimately owns and that nothing is animating, and
-- restores normal player control.
--
-- Safe against real cutscenes: a live cutscene either reports ownership (auto-fly,
-- heat-vision) or is actively moving the camera CFrame every frame. We only step in when
-- the camera has been Scriptable, unowned, AND frozen for longer than any brief intro
-- hold (~1.2s) — see STUCK_SECONDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local Knit = require(ReplicatedStorage.Packages.Knit)

local AutoFlyCamera = require(script.Parent.Parent.Parent.Modules.AutoFlyCamera)
local HeatVisionCamera = require(script.Parent.Parent.Parent.Modules.HeatVisionCamera)

local CameraWatchdogController = Knit.CreateController({ Name = "CameraWatchdogController" })

local player = Players.LocalPlayer

-- Frozen, unowned Scriptable time before we force the camera back. Comfortably above the
-- tutorial intro's static "hold" (~1.2s) so a legitimate cutscene is never interrupted.
local STUCK_SECONDS = 2.5
local CHECK_INTERVAL = 0.2
local STILL_EPSILON = 0.05

local accum = 0
local frozenSince: number? = nil
local lastPos: Vector3? = nil

local function ownedByAbility(): boolean
	local ok, busy = pcall(function()
		return AutoFlyCamera.isBusy() or HeatVisionCamera.isActive()
	end)
	return ok and busy == true
end

local function restore(camera: Camera)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid.AutoRotate = true
	end
	frozenSince = nil
	lastPos = nil
	StudioLog.print("Gameplay", "[iseesupes] CameraWatchdog: recovered a stuck Scriptable camera")
end

local function tick(dt: number)
	accum += dt
	if accum < CHECK_INTERVAL then
		return
	end
	accum = 0

	local camera = Workspace.CurrentCamera
	if not camera then
		frozenSince = nil
		lastPos = nil
		return
	end

	-- Stale-subject leak (camera frozen, but the player can still move): an ability
	-- camera restored CameraSubject to the PREVIOUS character because the new Humanoid
	-- had not streamed in yet — common on a slow cold join right after a server restart.
	-- The camera is left on Custom pointing at a now-destroyed subject, which the
	-- Scriptable check below never catches. Re-attach to the live humanoid. A destroyed
	-- subject is never a legitimate state, so this cannot interrupt a real cutscene.
	if camera.CameraType == Enum.CameraType.Custom and not ownedByAbility() then
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			local subject = camera.CameraSubject
			if subject == nil or not subject:IsDescendantOf(game) then
				camera.CameraSubject = humanoid
				humanoid.AutoRotate = true
				frozenSince = nil
				lastPos = nil
				StudioLog.print(
					"Gameplay",
					"[iseesupes] CameraWatchdog: re-attached camera to current character (stale subject)"
				)
				return
			end
		end
	end

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		frozenSince = nil
		lastPos = nil
		return
	end

	if ownedByAbility() then
		frozenSince = nil
		lastPos = camera.CFrame.Position
		return
	end

	-- Scriptable + unowned. If a script is still moving the camera it's a brief cutscene;
	-- only a frozen camera is a genuine leak.
	local pos = camera.CFrame.Position
	if lastPos and (pos - lastPos).Magnitude < STILL_EPSILON then
		frozenSince = frozenSince or os.clock()
		if os.clock() - (frozenSince :: number) >= STUCK_SECONDS then
			restore(camera)
			return
		end
	else
		frozenSince = nil
	end
	lastPos = pos
end

function CameraWatchdogController:KnitStart()
	RunService.Heartbeat:Connect(tick)
	StudioLog.ready("CameraWatchdogController")
end

return CameraWatchdogController
