--!strict

-- Procedural cape bone animator.
-- Replaces the broken CapeVfx bone-drive (which assumed linear chains but capes have branching trees).
-- CapeVfxController still runs alongside: it handles glide trails, sounds, and Motor6D mesh tilt.
-- GlideVfxConfigs.Procedural.Enabled = false prevents write conflicts.
--
-- Supports both cape structures found in this project:
--   Type B  char.Suit.UT.Cape  → Bone (root) branches Bone.006 / Bone.001  (main Superman)
--   Type A  char.Cape2.Cape    → different root names, same depth-based logic applies

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)

local CapeAnimatorController = Knit.CreateController({ Name = "CapeAnimatorController" })

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"
local TAU = math.pi * 2

-- ── Tuning ────────────────────────────────────────────────────────────────────
-- ROOT bones (depth 0, direct children of cape MeshPart).
-- They carry the coarse motion; all descendant bones inherit it in world-space.
local ROOT_IDLE_AMP  = math.rad(6)    -- ± idle sway at root
local ROOT_WALK_AMP  = math.rad(14)   -- ± walk flutter at root
local ROOT_FLY_BACK  = math.rad(22)   -- root sweeps this far back during flight

-- CHILD bones (depth ≥ 1): small ripple, phase-shifted per depth for a wave.
local CHILD_AMP      = math.rad(2.5)  -- ± oscillation per child bone
local CHILD_FLY_EACH = math.rad(3)    -- each depth level adds this much fly-back

-- Frequencies in Hz
local IDLE_FREQ      = 0.8
local WALK_FREQ      = 2.5

-- Phase offset (radians) between consecutive depths — creates the travelling wave
local DEPTH_PHASE    = 0.45

-- Blend rates (per second)
local FLY_IN_RATE    = 5
local FLY_OUT_RATE   = 8

-- Landing spring
local LAND_KICK      = math.rad(18)   -- root kicks forward this far on landing
local LAND_DECAY     = 7              -- spring decay rate (per second)

-- ── Per-character state ───────────────────────────────────────────────────────

type BoneEntry = { bone: Bone, depth: number }

type CharState = {
	bones    : { BoneEntry },
	time     : number,
	flyBlend : number,
	landPulse: number,
	wasFlying: boolean,
}

local states: { [Model]: CharState } = {}
local lastCapeTickAt = 0

-- ── Cape discovery ────────────────────────────────────────────────────────────

local function findCapeMesh(character: Model): BasePart?
	-- Type B: Suit.UT.Cape
	local suit = character:FindFirstChild("Suit")
	if suit then
		local ut = suit:FindFirstChild("UT")
		if ut then
			local c = ut:FindFirstChild("Cape")
			if c and c:IsA("BasePart") then
				return c :: BasePart
			end
		end
	end
	-- Type A: Cape2 > Cape
	local cape2 = character:FindFirstChild("Cape2")
	if cape2 then
		local c = cape2:FindFirstChild("Cape")
		if c and c:IsA("BasePart") then
			return c :: BasePart
		end
	end
	return nil
end

local function collectBones(parent: Instance, depth: number, out: { BoneEntry })
	for _, child in parent:GetChildren() do
		if child:IsA("Bone") then
			table.insert(out, { bone = child :: Bone, depth = depth })
			collectBones(child, depth + 1, out)
		end
	end
end

local function tryBuildState(character: Model): CharState?
	local mesh = findCapeMesh(character)
	if not mesh then
		return nil
	end

	local entries: { BoneEntry } = {}
	collectBones(mesh, 0, entries)

	if #entries == 0 then
		return nil
	end

	-- Disable cloth-sim so Roblox doesn't override our Bone.Transform writes
	pcall(function()
		mesh:SetAttribute("Roots", nil)
	end)

	return {
		bones     = entries,
		time      = 0,
		flyBlend  = 0,
		landPulse = 0,
		wasFlying = false,
	}
end

-- ── Per-frame animation ───────────────────────────────────────────────────────

local function tickCharacter(character: Model, cs: CharState, dt: number)
	cs.time += dt

	-- Flight state
	local isFlying = player:GetAttribute(PHASE_ATTR) ~= nil

	-- Landing pulse fires on the frame flight ends
	if cs.wasFlying and not isFlying then
		cs.landPulse = 1
	end
	cs.wasFlying = isFlying

	cs.landPulse = math.max(0, cs.landPulse - dt * LAND_DECAY)

	local blendRate = if isFlying then FLY_IN_RATE else FLY_OUT_RATE
	local flyTarget = if isFlying then 1 else 0
	cs.flyBlend += (flyTarget - cs.flyBlend) * math.min(1, blendRate * dt)

	-- Horizontal walk speed
	local walkBlend = 0
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local v = hrp.AssemblyLinearVelocity
		walkBlend = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 10, 0, 1)
	end

	local t      = cs.time
	local fb     = cs.flyBlend
	local pulse  = cs.landPulse

	for _, entry in cs.bones do
		local bone  = entry.bone
		local depth = entry.depth

		if not bone.Parent then
			continue
		end

		local phase    = depth * DEPTH_PHASE
		local isRoot   = (depth == 0)

		-- Oscillation: root uses larger range; children use smaller ripple
		local idleAmp  = if isRoot then ROOT_IDLE_AMP else CHILD_AMP
		local walkAmp  = if isRoot then ROOT_WALK_AMP else CHILD_AMP * 1.4

		local idleSway = math.sin(t * IDLE_FREQ * TAU + phase) * idleAmp
		local walkWave = math.sin(t * WALK_FREQ * TAU + phase) * walkAmp * walkBlend

		-- Ground motion damps out a bit while flying (cape is already swept back)
		local groundMotion = (idleSway + walkWave) * (1 - fb * 0.45)

		-- Fly-back angle:
		--   Root bone carries the full coarse tilt; children each add a small extra
		--   per depth level, creating a natural curve toward the tip.
		local flyAngle = (if isRoot then ROOT_FLY_BACK else CHILD_FLY_EACH) * fb
		if not isRoot then
			-- slight extra per additional depth
			flyAngle += math.rad(0.8) * (depth - 1) * fb
		end

		-- Landing kick: root kicks forward (negative = forward), decays away
		local kickAngle = (if isRoot then LAND_KICK else LAND_KICK * 0.4) * pulse

		-- Final transform: X = forward/back tilt, Z = gentle side sway
		local xAngle = flyAngle + groundMotion - kickAngle
		local zAngle = (idleSway * 0.35 + walkWave * 0.2) * (1 - fb * 0.6)

		bone.Transform = CFrame.Angles(xAngle, 0, zAngle)
	end
end

-- ── Knit wiring ───────────────────────────────────────────────────────────────

function CapeAnimatorController:KnitStart()
	local function setupCharacter(character: Model)
		states[character] = nil

		character.Destroying:Once(function()
			states[character] = nil
		end)

		-- Retry up to 5 seconds — Suit.UT.Cape may take a moment to replicate
		task.spawn(function()
			for attempt = 1, 10 do
				if not character.Parent then
					return
				end
				local cs = tryBuildState(character)
				if cs then
					states[character] = cs
					print(string.format(
						"[iseesupes] CapeAnimator: %s — %d bones (attempt %d)",
						character.Name,
						#cs.bones,
						attempt
					))
					return
				end
				task.wait(0.5)
			end
			warn("[iseesupes] CapeAnimator: no cape bones found on", character.Name)
		end)
	end

	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local interval = ClientPerformance.getCapeTickInterval()
		if interval > 0 then
			local now = os.clock()
			if now - lastCapeTickAt < interval then
				return
			end
			lastCapeTickAt = now
			if interval > dt then
				dt = interval
			end
		end

		for character, cs in states do
			if character.Parent then
				local ok, err = pcall(tickCharacter, character, cs, dt)
				if not ok then
					warn("[iseesupes] CapeAnimator error:", err)
					states[character] = nil
				end
			else
				states[character] = nil
			end
		end
	end)

	StudioLog.ready("CapeAnimatorController")
end

return CapeAnimatorController
