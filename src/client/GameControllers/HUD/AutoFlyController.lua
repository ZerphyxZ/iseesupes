--!strict

-- AutoFly: when enabled and standing on a ToggleFly pad, fly toward Destination with locked camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoFlyConfigs = require(ReplicatedStorage.Shared.Configs.AutoFlyConfigs)
local ToggleFlyZone = require(ReplicatedStorage.Shared.Utils.ToggleFlyZone)
local AutoFlyCamera = require(script.Parent.Parent.Parent.Modules.AutoFlyCamera)
local AutoFlyState = require(script.Parent.Parent.Parent.Modules.AutoFlyState)
local TutorialFlyHint = require(script.Parent.Parent.Parent.Modules.TutorialFlyHint)

local AutoFlyController = Knit.CreateController({ Name = "AutoFlyController" })

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"

type RouteState = {
	zoneRoot: Instance,
	destination: BasePart,
	landing: boolean,
	--- Closest 3D distance to the Destination seen so far this flight (for the closest-approach
	--- landing guard — see tickAutoFly).
	minDist: number,
	--- HRP position last frame, to tell whether the player is now moving away from the Destination.
	lastPos: Vector3?,
	--- os.clock() when the flight began (for the MaxAutoFlySeconds failsafe).
	startedAt: number,
}

local heartbeatConn: RBXScriptConnection? = nil
local abilityEndedConn: RBXScriptConnection? = nil
local activeRoute: RouteState? = nil
local startRequestPending = false
local lastAutoStartAt = -math.huge
local lastZoneRoot: Instance? = nil
local DoubleJumpService: any = nil

local function getAttrName(): string
	local name = AutoFlyConfigs.PlayerAttribute
	if typeof(name) == "string" and name ~= "" then
		return name
	end
	return "AutoFlyEnabled"
end

local function isAutoFlyEnabled(): boolean
	if AutoFlyConfigs.Enabled == false then
		return false
	end
	return player:GetAttribute(getAttrName()) == true
end

local function isFlying(): boolean
	return player:GetAttribute(PHASE_ATTR) ~= nil and player:GetAttribute(PHASE_ATTR) ~= ""
end

local function shouldSkipForTutorialHint(): boolean
	if AutoFlyConfigs.SkipWhenTutorialFlyHintActive == false then
		return false
	end
	return TutorialFlyHint.isActive()
end

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--- True only when the character is standing on a surface (not jumping/falling/airborne).
local function isGrounded(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function setAutoFlyActive(active: boolean)
	local attr = AutoFlyConfigs.AutoFlyActiveAttribute or "AutoFlyActive"
	player:SetAttribute(attr, if active then true else nil)
end

local function clearRoute(releaseCam: boolean?)
	activeRoute = nil
	setAutoFlyActive(false)
	AutoFlyState.clear()
	if releaseCam ~= false then
		AutoFlyCamera.release()
	end
end

local function computeSteerDirection(root: BasePart, destination: BasePart): Vector3
	local toTarget = destination.Position - root.Position
	if toTarget.Magnitude < 0.05 then
		return root.CFrame.LookVector
	end
	return toTarget.Unit
end

local function hasArrived(root: BasePart, destination: BasePart): boolean
	local delta = destination.Position - root.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local vertical = math.abs(delta.Y)
	local hLimit = AutoFlyConfigs.ArrivalHorizontalStuds
	local vLimit = AutoFlyConfigs.ArrivalVerticalStuds
	if typeof(hLimit) ~= "number" then
		hLimit = 14
	end
	if typeof(vLimit) ~= "number" then
		vLimit = 12
	end
	return horizontal <= hLimit and vertical <= vLimit
end

local function cancelAutoFlight()
	if DoubleJumpService then
		pcall(function()
			DoubleJumpService:SetHolding(false)
		end)
	end
	clearRoute(true)
end

--- Begin the landing/descent. Releases the flight hold AND clears the steer override so the
--- pursuit steering stops immediately — otherwise the steer stays latched toward the Destination
--- and keeps coasting the player past it during the round-trip before the hold actually ends.
local function beginLanding(route: RouteState)
	route.landing = true
	AutoFlyState.clear()
	if DoubleJumpService then
		pcall(function()
			DoubleJumpService:SetHolding(false)
		end)
	end
end

local function onAbilityEnded()
	clearRoute(true)
	startRequestPending = false
end

local function tryBeginAutoFlight(zoneRoot: Instance, destination: BasePart)
	if startRequestPending or isFlying() or activeRoute then
		return
	end

	local debounce = AutoFlyConfigs.AutoStartDebounceSeconds
	if typeof(debounce) ~= "number" then
		debounce = 1.25
	end
	local now = os.clock()
	if now - lastAutoStartAt < debounce then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	if not DoubleJumpService then
		DoubleJumpService = Knit.GetService("DoubleJumpService")
	end

	startRequestPending = true
	DoubleJumpService:RequestStart():andThen(function(ok: boolean)
		startRequestPending = false
		if not ok or not isAutoFlyEnabled() then
			return
		end

		lastAutoStartAt = os.clock()
		activeRoute = {
			zoneRoot = zoneRoot,
			destination = destination,
			landing = false,
			minDist = math.huge,
			lastPos = nil,
			startedAt = os.clock(),
		}

		setAutoFlyActive(true)
		DoubleJumpService:SetHolding(true)
		AutoFlyCamera.startFollow(character)
	end):catch(function()
		startRequestPending = false
	end)
end

local function tickAutoFly(dt: number)
	if AutoFlyConfigs.Enabled == false then
		if activeRoute then
			cancelAutoFlight()
		end
		return
	end

	if not isAutoFlyEnabled() then
		if activeRoute and isFlying() then
			cancelAutoFlight()
		elseif activeRoute then
			clearRoute(true)
		end
		return
	end

	if shouldSkipForTutorialHint() then
		return
	end

	local root = getRoot()
	if not root then
		clearRoute(true)
		return
	end

	local zoneRoot = ToggleFlyZone.getActiveZoneRoot(root)
	if zoneRoot ~= lastZoneRoot and zoneRoot == nil then
		lastAutoStartAt = -math.huge
	end
	lastZoneRoot = zoneRoot

	local route = activeRoute
	if route and isFlying() then
		if not route.landing then
			local steerDir = computeSteerDirection(root, route.destination)
			AutoFlyState.setSteerOverride(steerDir)
			AutoFlyCamera.update(dt, root, route.destination)

			local toTarget = route.destination.Position - root.Position
			local dist = toTarget.Magnitude
			if dist < route.minDist then
				route.minDist = dist
			end

			-- Closest-approach guard: once the player has come within ArrivalNearStuds of the
			-- Destination and is now moving AWAY from it, the closest point is behind them — land
			-- NOW. The arrival box (hasArrived) is a tight per-frame AND-gate that off-axis or
			-- height-offset approaches slip straight through, which is what lets the player sail
			-- past the Destination into a hazard.
			local near = AutoFlyConfigs.ArrivalNearStuds
			if typeof(near) ~= "number" then
				near = 24
			end
			local moveDelta = if route.lastPos then root.Position - route.lastPos else Vector3.zero
			route.lastPos = root.Position
			local movingAway = moveDelta.Magnitude > 0.05
				and dist > 0.05
				and moveDelta.Unit:Dot(toTarget.Unit) < 0
			local passedClosest = route.minDist <= near and movingAway

			if hasArrived(root, route.destination) or passedClosest then
				beginLanding(route)
			else
				local maxSeconds = AutoFlyConfigs.MaxAutoFlySeconds
				if typeof(maxSeconds) ~= "number" then
					maxSeconds = 8
				end
				if os.clock() - route.startedAt > maxSeconds then
					-- Never reached the pad (mis-placed Destination / diverged path) — stop flying
					-- rather than sail off the map.
					cancelAutoFlight()
				end
			end
		else
			-- Landing: pin the player to the Destination's column and kill horizontal drift so
			-- flight momentum can't coast them sideways off the pad into a hazard. With no
			-- horizontal velocity they drop straight down onto the intended spot.
			if AutoFlyConfigs.SnapToDestinationOnLanding ~= false then
				local dst = route.destination.Position
				root.CFrame = (root.CFrame - root.CFrame.Position) + Vector3.new(dst.X, root.Position.Y, dst.Z)
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
			end
			AutoFlyCamera.update(dt, root, route.destination, true)
		end
		return
	end

	if isFlying() then
		return
	end

	if not zoneRoot then
		return
	end

	local destination = ToggleFlyZone.getDestinationPart(zoneRoot, AutoFlyConfigs.DestinationChildName)
	if not destination then
		return
	end

	-- Only launch when the player is GROUNDED on the pad — never grab them mid-air (jumping
	-- or falling over the zone before they've actually reached the Toggle). The zone extends
	-- above the pad, so without this it fires while they're still in the air.
	if not isGrounded() then
		return
	end

	tryBeginAutoFlight(zoneRoot, destination)
end

function AutoFlyController:KnitStart()
	if AutoFlyConfigs.Enabled == false then
		return
	end

	ToggleFlyZone.ensureInitialized()
	DoubleJumpService = Knit.GetService("DoubleJumpService")

	if abilityEndedConn then
		abilityEndedConn:Disconnect()
	end
	abilityEndedConn = DoubleJumpService.AbilityEnded:Connect(onAbilityEnded)

	player.CharacterAdded:Connect(function()
		clearRoute(true)
		lastZoneRoot = nil
		startRequestPending = false
	end)

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(tickAutoFly)

	StudioLog.ready("AutoFlyController")
end

return AutoFlyController
