--!strict
-- StreamingAssistController
--
-- Keeps content streamed in around the local player wherever they go, so they never
-- end up looking at empty ocean / falling through un-streamed space. Three jobs:
--   1. Teleport detection — a large single-frame position jump (Skip Stage, lobby
--      return, kill respawn) pulls geometry in at the new spot immediately.
--   2. High-speed lookahead — while flying/long-jumping fast, pre-streams AHEAD along
--      the velocity vector so the player doesn't outrun streaming (flight hits ~450
--      studs/s; default streaming can't always keep up over this 220k-stud map).
--   3. Proactive Skip Stage handshake — the server fires PrepareTeleport with the
--      landing position BEFORE it moves the player, giving us a head start to stream
--      the destination (the paid Skip Stage used to drop players into the void).
--
-- Mirrors the proven RequestStreamAroundAsync pattern from KryptPlatformController,
-- generalized to the whole player instead of just the Stage 8 Krypts course.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local StreamingAssistController = Knit.CreateController({ Name = "StreamingAssistController" })

local player = Players.LocalPlayer

-- Tunables
local TELEPORT_JUMP_STUDS = 150 -- a single-frame move larger than this counts as a teleport
local AHEAD_SPEED_THRESHOLD = 80 -- studs/s above which we pre-stream ahead of the player
local AHEAD_LEAD_TIME = 0.8 -- seconds of velocity to look ahead
local PRIME_INTERVAL = 0.5 -- min seconds between throttled (non-immediate) stream requests
local STREAM_TIMEOUT = 3 -- per-request streaming timeout (seconds)

local lastPos: Vector3? = nil
local lastPrimeAt = 0
local priming = false

local function getRoot(): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Request streaming around `pos`. `immediate` bypasses the throttle (used for teleports
-- and the Skip Stage handshake, where we can't afford to wait a interval).
local function prime(pos: Vector3, immediate: boolean?)
	if Workspace.StreamingEnabled ~= true then
		return
	end
	local now = os.clock()
	if not immediate and (priming or now - lastPrimeAt < PRIME_INTERVAL) then
		return
	end
	lastPrimeAt = now
	priming = true
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(pos, STREAM_TIMEOUT)
		end)
		priming = false
	end)
end

-- Public: pull geometry in around a world position right now.
function StreamingAssistController:PrimeAround(pos: Vector3)
	prime(pos, true)
end

local function onHeartbeat()
	local root = getRoot()
	if not root then
		lastPos = nil
		return
	end
	local pos = root.Position
	local prev = lastPos
	lastPos = pos
	if not prev then
		return
	end

	local delta = (pos - prev).Magnitude
	if delta > TELEPORT_JUMP_STUDS then
		-- Teleported somewhere new — stream it in immediately.
		prime(pos, true)
		return
	end

	-- Moving fast (flight / long jump): pre-stream ahead so we don't outrun streaming.
	local vel = root.AssemblyLinearVelocity
	if vel.Magnitude > AHEAD_SPEED_THRESHOLD then
		prime(pos + vel * AHEAD_LEAD_TIME)
	end
end

function StreamingAssistController:KnitStart()
	RunService.Heartbeat:Connect(onHeartbeat)

	-- Proactive Skip Stage: server hands us the landing position before it teleports.
	local ok, SkipStageService = pcall(function()
		return Knit.GetService("SkipStageService")
	end)
	if ok and SkipStageService and SkipStageService.PrepareTeleport then
		SkipStageService.PrepareTeleport:Connect(function(targetPos: Vector3)
			prime(targetPos, true)
		end)
	end
end

return StreamingAssistController
