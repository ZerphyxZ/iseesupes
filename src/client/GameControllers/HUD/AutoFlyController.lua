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

local function clearRoute(releaseCam: boolean?)
	activeRoute = nil
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
		}

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

			if hasArrived(root, route.destination) then
				route.landing = true
				pcall(function()
					DoubleJumpService:SetHolding(false)
				end)
			end
		else
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
