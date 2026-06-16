--!strict

-- Stage 4 "SuperGirl" walking laser hazard (server-authoritative).
--
-- One NPC per part named SuperGirlConfigs.WalkPartName: she paces that part with
-- Superman's run animation, and fires an arcade laser at the nearest player within
-- range — air included — for light, recoverable damage (reuses the HealthRed model:
-- a fraction of max health, debounced; 0 HP -> TreadmillService hazard death/respawn).
-- Telegraphed (throw wind-up) and dodgeable; she never blocks progress — the point is
-- to make players run/fly away from the scary laser, not to wall them.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SuperGirlConfigs = require(ReplicatedStorage.Shared.Configs.SuperGirlConfigs)
local HealthRedConfigs = require(ReplicatedStorage.Shared.Configs.HealthRedConfigs)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local SuperGirlService = Knit.CreateService({
	Name = "SuperGirlService",
	Client = {},
})

type SuperGirl = {
	model: Model,
	root: BasePart,
	muzzle: BasePart,
	walkPart: BasePart,
	standY: number,
	center: Vector3,
	axisX: Vector3,
	axisZ: Vector3,
	halfX: number,
	halfZ: number,
	patrolSign: number,
	stage: number,
	runTrack: AnimationTrack?,
	throwTrack: AnimationTrack?,
	idleTrack: AnimationTrack?,
	animator: Animator?,
	muzzleAtt: Attachment?,
	nextFireAt: number,
	dormant: boolean,
	lastTarget: Player?,
	lastDetectAt: number,
}

local TreadmillService: any = nil

local bound: { [Model]: SuperGirl } = {}
local boundWalkParts: { [BasePart]: boolean } = {}
local lastHitAt: { [Player]: number } = {}
local deathCooldownUntil: { [Player]: number } = {}

local function dbg(...: any)
	if SuperGirlConfigs.DebugPrint and RunService:IsStudio() then
		print("[iseesupes][SuperGirl]", ...)
	end
end

local function makeAnimation(animId: string): Animation
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	return anim
end

local function isSuperGirlModel(inst: Instance): boolean
	if not inst:IsA("Model") then
		return false
	end
	if not inst:FindFirstChildOfClass("Humanoid") then
		return false
	end
	return string.find(string.lower(inst.Name), SuperGirlConfigs.ModelNameMatch, 1, true) ~= nil
end

local function modelRoot(model: Model): BasePart?
	local pp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return if pp and pp:IsA("BasePart") then pp else nil
end

local function stageAncestorModel(inst: Instance): Model?
	local node: Instance? = inst
	while node and node ~= Workspace do
		if node:IsA("Model") and string.match(node.Name, "^Stage%d+$") then
			return node :: Model
		end
		node = node.Parent
	end
	return nil
end

--- Find the SuperGirl rig that belongs to a tagged walk part: prefer a tagged rig,
--- else the closest SuperGirl-named humanoid model inside the same Stage<N>, else a
--- nearby ancestor / top-level model. She stands on the part, so "closest" is reliable.
local function findSuperGirlForWalkPart(walkPart: BasePart): Model?
	local origin = walkPart.Position
	local best: Model? = nil
	local bestDist = math.huge

	local function consider(inst: Instance)
		if not inst:IsA("Model") or not inst:FindFirstChildOfClass("Humanoid") then
			return
		end
		local pp = modelRoot(inst)
		if not pp then
			return
		end
		local d = (pp.Position - origin).Magnitude
		if d < bestDist then
			bestDist = d
			best = inst
		end
	end

	for _, inst in CollectionService:GetTagged(SuperGirlConfigs.ModelTag) do
		consider(inst)
	end
	if best then
		return best
	end

	local stageModel = stageAncestorModel(walkPart)
	if stageModel then
		for _, d in stageModel:GetDescendants() do
			if isSuperGirlModel(d) then
				consider(d)
			end
		end
	end
	if best then
		return best
	end

	local node: Instance? = walkPart.Parent
	local hops = 0
	while node and node ~= Workspace and hops < 4 do
		if node:IsA("Model") then
			for _, child in node:GetChildren() do
				if isSuperGirlModel(child) then
					consider(child)
				end
			end
		end
		node = node.Parent
		hops += 1
	end
	for _, child in Workspace:GetChildren() do
		if isSuperGirlModel(child) then
			consider(child)
		end
	end

	return best
end

--- The walkable rectangle of the part: its center (at standY) plus the two horizontal
--- axes with half-extents shrunk by EdgeMargin so she can never roam off the edge.
local function getFootprint(walkPart: BasePart, standY: number): (Vector3, Vector3, Vector3, number, number)
	local cf = walkPart.CFrame
	local size = walkPart.Size
	local axisX = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	axisX = if axisX.Magnitude > 1e-3 then axisX.Unit else Vector3.new(1, 0, 0)
	local axisZ = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	axisZ = if axisZ.Magnitude > 1e-3 then axisZ.Unit else Vector3.new(0, 0, 1)
	local halfX = math.max(1, size.X * 0.5 - SuperGirlConfigs.EdgeMargin)
	local halfZ = math.max(1, size.Z * 0.5 - SuperGirlConfigs.EdgeMargin)
	local center = Vector3.new(walkPart.Position.X, standY, walkPart.Position.Z)
	return center, axisX, axisZ, halfX, halfZ
end

--- Clamp a world position onto the walkable rectangle, so chasing a player keeps her on
--- the part even if the player runs/flies off it (she walks to the nearest on-part point).
local function clampToFootprint(sg: SuperGirl, worldPos: Vector3): Vector3
	local rel = worldPos - sg.center
	local px = math.clamp(rel:Dot(sg.axisX), -sg.halfX, sg.halfX)
	local pz = math.clamp(rel:Dot(sg.axisZ), -sg.halfZ, sg.halfZ)
	return sg.center + sg.axisX * px + sg.axisZ * pz
end

--- How far her HRP sits above her lowest foot, so we can place her FEET on the part
--- (she is a tall / 8x-scale rig, so standing height is large).
local function computeFootOffset(model: Model, root: BasePart): number
	local lowest = root.Position.Y
	for _, name in { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg" } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			lowest = math.min(lowest, p.Position.Y - p.Size.Y * 0.5)
		end
	end
	return math.max(0, root.Position.Y - lowest)
end

local function setUprightFacing(root: BasePart, pos: Vector3, towardPos: Vector3)
	local flat = Vector3.new(towardPos.X - pos.X, 0, towardPos.Z - pos.Z)
	if flat.Magnitude < 1e-3 then
		root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
		return
	end
	root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
end

local function loadAnims(sg: SuperGirl)
	local animator = sg.animator
	if not animator then
		return
	end

	local okRun, runTrack = pcall(function()
		return animator:LoadAnimation(makeAnimation(SuperGirlConfigs.RunAnimationId))
	end)
	if okRun and runTrack then
		runTrack.Looped = true
		runTrack.Priority = Enum.AnimationPriority.Movement
		sg.runTrack = runTrack
	else
		dbg("run animation failed to load:", tostring(runTrack))
	end

	local okThrow, throwTrack = pcall(function()
		return animator:LoadAnimation(makeAnimation(SuperGirlConfigs.ThrowAnimationId))
	end)
	if okThrow and throwTrack then
		throwTrack.Looped = false
		throwTrack.Priority = Enum.AnimationPriority.Action
		sg.throwTrack = throwTrack
	else
		dbg("throw animation failed to load:", tostring(throwTrack))
	end

	local okIdle, idleTrack = pcall(function()
		return animator:LoadAnimation(makeAnimation(SuperGirlConfigs.IdleAnimationId))
	end)
	if okIdle and idleTrack then
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Movement
		sg.idleTrack = idleTrack
	else
		dbg("idle animation failed to load:", tostring(idleTrack))
	end
end

--- Switch locomotion so exactly ONE of run/idle plays: run while she's moving, idle while
--- she's holding position. Without this the looping run plays while she's stationary, which
--- reads as a forward "running in place" face-plant. If idle never loaded we still STOP the
--- run while holding (rest pose) rather than leaving her running on the spot.
local function setMoving(sg: SuperGirl, moving: boolean)
	local want = if moving then sg.runTrack else sg.idleTrack
	local other = if moving then sg.idleTrack else sg.runTrack
	if want and not want.IsPlaying then
		want:Play(0.15)
		want:AdjustWeight(1)
	end
	if other and other.IsPlaying then
		other:Stop(0.15)
	end
end

--- Two laser origins at her eyes (the beam fires from BOTH eyes, like the player's
--- heat vision). Placed relative to the head's FaceFrontAttachment and scaled to the
--- head, so it works on her 8x-scale rig.
local function ensureEyeAttachments(sg: SuperGirl): (Attachment, Attachment)
	local head = sg.muzzle
	local existingR = head:FindFirstChild("SuperGirlEyeR")
	local existingL = head:FindFirstChild("SuperGirlEyeL")
	if existingR and existingR:IsA("Attachment") and existingL and existingL:IsA("Attachment") then
		return existingR, existingL
	end
	local face = head:FindFirstChild("FaceFrontAttachment")
	local baseCF = if face and face:IsA("Attachment")
		then face.CFrame
		else CFrame.new(0, head.Size.Y * 0.08, -head.Size.Z * 0.5)
	local eyeDx = head.Size.X * 0.16
	local r = Instance.new("Attachment")
	r.Name = "SuperGirlEyeR"
	r.Position = (baseCF * CFrame.new(eyeDx, 0, 0)).Position
	r.Parent = head
	local l = Instance.new("Attachment")
	l.Name = "SuperGirlEyeL"
	l.Position = (baseCF * CFrame.new(-eyeDx, 0, 0)).Position
	l.Parent = head
	return r, l
end

local function spawnBeam(sg: SuperGirl, hitPos: Vector3)
	local eyeR, eyeL = ensureEyeAttachments(sg)

	local endPart = Instance.new("Part")
	endPart.Name = "SuperGirlBeamEnd"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.2, 0.2, 0.2)
	endPart.CFrame = CFrame.new(hitPos)
	endPart.Parent = Workspace
	local endAtt = Instance.new("Attachment")
	endAtt.Parent = endPart

	-- Scale beam width to the rig (normal head X ~2 → scale 1; her 16-wide head → ~8).
	local scale = math.max(1, sg.muzzle.Size.X / 2)
	for _, eye in { eyeR, eyeL } do
		local beam = Instance.new("Beam")
		beam.Attachment0 = eye
		beam.Attachment1 = endAtt
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Width0 = SuperGirlConfigs.BeamWidthStart * scale
		beam.Width1 = SuperGirlConfigs.BeamWidthEnd * scale
		beam.Color = ColorSequence.new(SuperGirlConfigs.BeamColorStart, SuperGirlConfigs.BeamColorEnd)
		beam.Transparency = NumberSequence.new(0.05)
		beam.Parent = sg.muzzle
		Debris:AddItem(beam, SuperGirlConfigs.BeamSeconds)
	end
	Debris:AddItem(endPart, SuperGirlConfigs.BeamSeconds)
end

local function playLaserSound(sg: SuperGirl)
	local sound = Instance.new("Sound")
	sound.SoundId = SuperGirlConfigs.LaserSoundId
	sound.Volume = SuperGirlConfigs.LaserSoundVolume
	sound.RollOffMaxDistance = 250
	sound.Parent = sg.muzzle
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function damagePctForStage(stage: number): number
	return HealthRedConfigs.DamagePctByStage[stage] or SuperGirlConfigs.DefaultDamagePct
end

local function applyLaserDamage(sg: SuperGirl, player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if (deathCooldownUntil[player] or 0) > now then
		return
	end
	local last = lastHitAt[player]
	if last and now - last < SuperGirlConfigs.HitDebounce then
		return
	end
	lastHitAt[player] = now

	local dmg = humanoid.MaxHealth * damagePctForStage(sg.stage)
	local newHealth = humanoid.Health - dmg
	if newHealth <= 0 then
		if TreadmillService and TreadmillService.ProcessHazardDeath then
			deathCooldownUntil[player] = now + SuperGirlConfigs.DeathCooldown
			TreadmillService:ProcessHazardDeath(player, sg.walkPart)
		end
		return
	end
	humanoid.Health = newHealth
end

--- Fire the beam at the player's CURRENT position (so flyers are hit), but only deal
--- damage if there is clear line of sight within range — cover/distance dodges it.
local function fireAt(sg: SuperGirl, player: Player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local origin = sg.muzzle.Position
	local toTarget = hrp.Position - origin
	local dist = toTarget.Magnitude
	if dist > SuperGirlConfigs.DetectRange or dist < 1e-3 then
		spawnBeam(sg, origin + (if dist > 1e-3 then toTarget.Unit else sg.root.CFrame.LookVector) * SuperGirlConfigs.DetectRange)
		playLaserSound(sg)
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { sg.model }
	local result = Workspace:Raycast(origin, toTarget, params)

	local endPos = hrp.Position
	local hitPlayer = true
	if result then
		endPos = result.Position
		hitPlayer = result.Instance:IsDescendantOf(character :: Instance)
	end

	spawnBeam(sg, endPos)
	playLaserSound(sg)
	if hitPlayer then
		applyLaserDamage(sg, player)
	end
end

--- Only chase players she can actually engage: within laser range, OR roughly over the
--- part (within FollowEdgeMargin of its edge). A player who flew/respawned far off the part
--- is ignored, so she never walks to the edge to "run in place" at someone unreachable.
local function isEngageable(sg: SuperGirl, hrpPos: Vector3, dist3d: number): boolean
	if dist3d <= SuperGirlConfigs.DetectRange then
		return true
	end
	local rel = hrpPos - sg.center
	local fullHalfX = sg.halfX + SuperGirlConfigs.EdgeMargin
	local fullHalfZ = sg.halfZ + SuperGirlConfigs.EdgeMargin
	local overX = math.max(0, math.abs(rel:Dot(sg.axisX)) - fullHalfX)
	local overZ = math.max(0, math.abs(rel:Dot(sg.axisZ)) - fullHalfZ)
	return (overX * overX + overZ * overZ) <= SuperGirlConfigs.FollowEdgeMargin ^ 2
end

--- Returns the nearest ENGAGEABLE player within FollowRange (or nil), plus the distance to
--- the nearest player of ANY kind (used by the dormant/sleep gate).
local function findNearestPlayer(sg: SuperGirl, range: number): (Player?, number)
	local origin = sg.muzzle.Position
	local best: Player? = nil
	local bestDist = range
	local nearestAny = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local d = (hrp.Position - origin).Magnitude
			if d < nearestAny then
				nearestAny = d
			end
			if d <= bestDist and isEngageable(sg, hrp.Position, d) then
				bestDist = d
				best = player
			end
		end
	end
	return best, nearestAny
end

local function targetHrpPos(player: Player?): Vector3?
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
end

--- Returns false to request unbind (model gone).
local function updateSuperGirl(sg: SuperGirl, dt: number, now: number): boolean
	if not sg.model.Parent or not sg.root.Parent then
		return false
	end

	-- Detection throttle: 0.15s when active, slower when dormant. The scan also reports the
	-- nearest player of ANY kind, so she can sleep when nobody is near the stage.
	local interval = if sg.dormant then 0.5 else 0.15
	if now - sg.lastDetectAt >= interval then
		sg.lastDetectAt = now
		local nearest, nearestAny = findNearestPlayer(sg, SuperGirlConfigs.FollowRange)
		sg.lastTarget = nearest
		sg.dormant = nearestAny > SuperGirlConfigs.SleepRange
	end

	-- Dormant: no player near the stage, so nobody can see her — skip all per-frame work.
	-- She wakes on the next scan the moment a player comes within SleepRange.
	if sg.dormant then
		return true
	end

	local target = sg.lastTarget
	local tp = targetHrpPos(target)

	-- Someone is near: chase the nearest player (clamped onto the part so she can't walk
	-- off) until StopDistance, then HOLD and aim — she never piles on top / runs in place.
	if target and tp then
		local here = Vector3.new(sg.root.Position.X, sg.standY, sg.root.Position.Z)
		local faceAt = Vector3.new(tp.X, sg.standY, tp.Z)

		-- Fire on cooldown once they're within laser range (the beam IS the attack — no
		-- body "throw" anim, which leaned her over).
		if (sg.muzzle.Position - tp).Magnitude <= SuperGirlConfigs.DetectRange and now >= sg.nextFireAt then
			sg.nextFireAt = now + SuperGirlConfigs.FireCooldown
			local shotTarget = target
			task.delay(SuperGirlConfigs.ChargeSeconds, function()
				if sg.model.Parent and shotTarget.Parent then
					fireAt(sg, shotTarget)
				end
			end)
		end

		-- Walk toward the player, but only as far as the part lets her (dest is clamped onto
		-- the surface). Decide run-vs-hold by distance to that REACHABLE dest, not the raw
		-- player: if the player is off the part she'd otherwise sit at the edge running in
		-- place. distToDest is horizontal (dest sits at standY, same as here).
		local gap = (faceAt - here).Magnitude
		local dest = clampToFootprint(sg, tp)
		local toDest = dest - here
		local distToDest = toDest.Magnitude
		if gap > SuperGirlConfigs.StopDistance and distToDest > 2 then
			-- Close in: run toward the reachable point, facing the player.
			setMoving(sg, true)
			local step = SuperGirlConfigs.PatrolSpeed * dt
			local nextPos = if distToDest <= step then dest else here + toDest.Unit * step
			setUprightFacing(sg.root, nextPos, faceAt)
		else
			-- Caught up (or as close as the part allows): stand and aim (idle), not
			-- run-in-place. She still tracks + lasers; if they run/fly off she chases again.
			setMoving(sg, false)
			setUprightFacing(sg.root, here, faceAt)
		end
		return true
	end

	-- No one to engage: pace BACK AND FORTH along the part's long axis (a clean patrol),
	-- easing back to the centerline if a chase left her off it. Anchored root = exact CFrame
	-- move, so she can never fall off.
	setMoving(sg, true)
	local here = Vector3.new(sg.root.Position.X, sg.standY, sg.root.Position.Z)
	local longIsX = sg.halfX >= sg.halfZ
	local patrolAxis = if longIsX then sg.axisX else sg.axisZ
	local crossAxis = if longIsX then sg.axisZ else sg.axisX
	local patrolHalf = if longIsX then sg.halfX else sg.halfZ
	local rel = here - sg.center
	local s = rel:Dot(patrolAxis)
	local cross = rel:Dot(crossAxis)
	local step = SuperGirlConfigs.PatrolSpeed * dt
	-- Reverse BEFORE the hard edge (decide from where the next step would land), so float
	-- precision at the clamp can never leave her pinned against an end "running in place".
	local proposed = s + sg.patrolSign * step
	if proposed >= patrolHalf then
		sg.patrolSign = -1
	elseif proposed <= -patrolHalf then
		sg.patrolSign = 1
	end
	local newS = math.clamp(s + sg.patrolSign * step, -patrolHalf, patrolHalf)
	-- Drift back toward the centerline (half speed) so she doesn't pace a crooked line.
	local newCross = cross - math.sign(cross) * math.min(math.abs(cross), step * 0.5)
	local nextPos = sg.center + patrolAxis * newS + crossAxis * newCross
	setUprightFacing(sg.root, nextPos, nextPos + patrolAxis * sg.patrolSign)
	return true
end

local function bindSuperGirl(walkPart: BasePart)
	if boundWalkParts[walkPart] or not walkPart.Parent then
		return
	end
	local model = findSuperGirlForWalkPart(walkPart)
	if not model then
		dbg("found", walkPart:GetFullName(), "but no SuperGirl rig nearby yet")
		return
	end
	if bound[model] then
		return
	end

	local root = modelRoot(model)
	if not root then
		dbg("SuperGirl missing Root:", model:GetFullName())
		return
	end
	local muzzleInst = model:FindFirstChild(SuperGirlConfigs.MuzzlePartName)
	local muzzle = if muzzleInst and muzzleInst:IsA("BasePart") then muzzleInst else root

	-- Anchor ONLY the root so we position her by CFrame (exact — feet on the part, no
	-- hover, no physics tug-of-war); unanchor the rest so the Animator drives the limbs.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = (d == root)
		end
	end

	-- Drive her with an AnimationController instead of a Humanoid. An ANCHORED Humanoid
	-- can never sense the floor, so it sits in FallingDown forever and goes limp/ragdolls
	-- on clients ("falls over"). With no Humanoid there is no state machine — the anchored
	-- rig just holds the animation pose. The MeshPart rig keeps its full appearance.
	local oldHumanoid = model:FindFirstChildOfClass("Humanoid")
	if oldHumanoid then
		oldHumanoid:Destroy()
	end
	local animController = model:FindFirstChildOfClass("AnimationController")
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = model
	end
	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	-- The part footprint she roams, raised so her FEET sit on it (tall rig).
	local partTop = walkPart.Position.Y + walkPart.Size.Y * 0.5
	local standY = partTop + computeFootOffset(model, root)
	local center, axisX, axisZ, halfX, halfZ = getFootprint(walkPart, standY)

	local sg: SuperGirl = {
		model = model,
		root = root,
		muzzle = muzzle,
		walkPart = walkPart,
		standY = standY,
		center = center,
		axisX = axisX,
		axisZ = axisZ,
		halfX = halfX,
		halfZ = halfZ,
		patrolSign = 1,
		stage = StageCheckpointWorld.resolveStageFromAncestor(walkPart) or 4,
		runTrack = nil,
		throwTrack = nil,
		idleTrack = nil,
		animator = animator,
		muzzleAtt = nil,
		nextFireAt = 0,
		dormant = false,
		lastTarget = nil,
		lastDetectAt = 0,
	}

	local startPos = Vector3.new(root.Position.X, standY, root.Position.Z)
	setUprightFacing(root, startPos, startPos + axisX)
	loadAnims(sg)
	ensureEyeAttachments(sg)
	if sg.runTrack then
		sg.runTrack:Play(0.1)
		sg.runTrack:AdjustWeight(1)
	end

	bound[model] = sg
	boundWalkParts[walkPart] = true
	dbg("bound", model.Name, "→", walkPart:GetFullName(), "stage", sg.stage, "roam", math.floor(halfX * 2) .. "x" .. math.floor(halfZ * 2))
end

local function scanForWalkParts()
	for _, inst in CollectionService:GetTagged(SuperGirlConfigs.WalkPartTag) do
		if inst:IsA("BasePart") then
			bindSuperGirl(inst)
		end
	end
end

function SuperGirlService:KnitStart()
	if SuperGirlConfigs.Enabled ~= true then
		print("[iseesupes] SuperGirlService disabled.")
		return
	end

	TreadmillService = Knit.GetService("TreadmillService")

	scanForWalkParts()
	CollectionService:GetInstanceAddedSignal(SuperGirlConfigs.WalkPartTag):Connect(function(inst)
		if inst:IsA("BasePart") then
			task.defer(bindSuperGirl, inst)
		end
	end)
	-- Stages stream/clone in after boot; catch late arrivals.
	for _, delay in { 1, 3, 6 } do
		task.delay(delay, scanForWalkParts)
	end

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for model, sg in bound do
			if updateSuperGirl(sg, dt, now) == false then
				bound[model] = nil
				boundWalkParts[sg.walkPart] = nil
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
		deathCooldownUntil[player] = nil
	end)

	StudioLog.ready("SuperGirlService")
end

return SuperGirlService
