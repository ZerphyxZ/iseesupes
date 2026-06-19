--!strict

-- Stage 5 STATIONARY "SuperLaserGirl" heat-vision turrets (server-authoritative).
--
-- Each rig tagged SuperLaserGirlConfigs.Tag holds an idle pose. When a player comes within
-- DetectRadius, after a short charge she fires the Superman heat-vision beam (the SupermanHeatVision
-- asset, via the shared HeatVisionRig the player's own heat vision uses) at them for a brief burst
-- with an arcade "phew" sound and light, recoverable damage. Intermittent (charge -> beam ->
-- cooldown), never constant. The rig is ANCHORED, so — like the patrolling SuperGirl — the Humanoid
-- is destroyed and an AnimationController drives the idle pose (an anchored Humanoid ragdolls). 0 HP
-- routes through TreadmillService hazard death/respawn. The beam is parented under the rig Model, so
-- it replicates to all clients (no client controller needed).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SuperLaserGirlConfigs = require(ReplicatedStorage.Shared.Configs.SuperLaserGirlConfigs)
local HeatVisionRig = require(ReplicatedStorage.Shared.Utils.HeatVisionRig)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local SuperLaserGirlService = Knit.CreateService({
	Name = "SuperLaserGirlService",
	Client = {},
})

type Turret = {
	model: Model,
	root: BasePart,
	head: BasePart,
	stage: number,
	hvRig: HeatVisionRig.HeatVisionRig?,
	idleTrack: AnimationTrack?,
	nextFireAt: number,
	firing: boolean,
	fireUntil: number,
	shotTarget: Player?,
	dormant: boolean,
	lastTarget: Player?,
	lastDetectAt: number,
}

local TreadmillService: any = nil

local bound: { [Model]: Turret } = {}
--- Tagged instance -> the rig Model it resolved to (so removing the tag unbinds the right rig,
--- and two tagged nodes resolving to one rig don't double-bind).
local boundTag: { [Instance]: Model } = {}
local lastHitAt: { [Player]: number } = {}
local deathCooldownUntil: { [Player]: number } = {}

local function dbg(...: any)
	if SuperLaserGirlConfigs.DebugPrint and RunService:IsStudio() then
		print("[iseesupes][SuperLaserGirl]", ...)
	end
end

local function makeAnimation(animId: string): Animation
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	return anim
end

local function modelRoot(model: Model): BasePart?
	local pp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return if pp and pp:IsA("BasePart") then pp else nil
end

--- Rotate the anchored rig in place to face a world position (yaw only, keeps her standing
--- upright and at her spot) — so she turns toward the player she's lasering.
local function faceToward(root: BasePart, towardPos: Vector3)
	local pos = root.Position
	local flat = Vector3.new(towardPos.X - pos.X, 0, towardPos.Z - pos.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
end

--- Spread the heat-vision beam's two origin attachments out to her ACTUAL eyes. The asset's eye
--- spacing is authored for a normal ~2-stud head, so on the ~8x rig the two beams sit on top of
--- each other and read as ONE beam from her forehead. Re-place them at her face, scaled to her
--- head (same math the SuperGirl custom beam uses), so a beam fires from BOTH eyes.
local function spreadEyesToRig(rig: HeatVisionRig.HeatVisionRig, head: BasePart)
	local hp = rig.headPart
	local eyeR = hp:FindFirstChild("Attachment")
	local eyeL = hp:FindFirstChild("Attachment1")
	if not (eyeR and eyeR:IsA("Attachment") and eyeL and eyeL:IsA("Attachment")) then
		return
	end
	local face = head:FindFirstChild("FaceFrontAttachment")
	local baseCF = if face and face:IsA("Attachment")
		then (face :: Attachment).WorldCFrame
		else head.CFrame * CFrame.new(0, head.Size.Y * 0.08, -head.Size.Z * 0.5)
	local eyeDx = head.Size.X * 0.16
	;(eyeR :: Attachment).WorldPosition = (baseCF * CFrame.new(eyeDx, 0, 0)).Position
	;(eyeL :: Attachment).WorldPosition = (baseCF * CFrame.new(-eyeDx, 0, 0)).Position
end

--- A rig Model we can drive: has a `Head` BasePart and a Humanoid or AnimationController.
local function hasRig(inst: Instance): boolean
	if not inst:IsA("Model") then
		return false
	end
	local head = inst:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	return inst:FindFirstChildOfClass("Humanoid") ~= nil or inst:FindFirstChildOfClass("AnimationController") ~= nil
end

--- Resolve the real rig Model from a tagged instance. The tag may sit on the rig itself, on an
--- ancestor, or (as on the Black & White rig) on an inner sub-model with no Humanoid — so search
--- self -> ancestors -> descendants for the Model that actually has a Head + Humanoid.
local function resolveRig(tagged: Instance): Model?
	if hasRig(tagged) then
		return tagged :: Model
	end
	local node: Instance? = tagged.Parent
	while node and node ~= Workspace do
		if hasRig(node) then
			return node :: Model
		end
		node = node.Parent
	end
	for _, d in tagged:GetDescendants() do
		if hasRig(d) then
			return d :: Model
		end
	end
	return nil
end

local function targetHrpPos(player: Player?): Vector3?
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
end

--- Nearest alive player within DetectRadius (or nil), plus the distance to the nearest player of
--- ANY kind (for the dormancy gate).
local function findNearestPlayer(head: BasePart): (Player?, number)
	local origin = head.Position
	local best: Player? = nil
	local bestDist = SuperLaserGirlConfigs.DetectRadius
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
			if d <= bestDist then
				bestDist = d
				best = player
			end
		end
	end
	return best, nearestAny
end

local function playLaserSound(turret: Turret)
	local sound = Instance.new("Sound")
	sound.SoundId = SuperLaserGirlConfigs.LaserSoundId
	sound.Volume = SuperLaserGirlConfigs.LaserSoundVolume
	sound.RollOffMaxDistance = 250
	sound.Parent = turret.head
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function applyLaserDamage(turret: Turret, player: Player)
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
	if last and now - last < SuperLaserGirlConfigs.HitDebounce then
		return
	end
	lastHitAt[player] = now

	local dmg = humanoid.MaxHealth * SuperLaserGirlConfigs.DamagePct
	local newHealth = humanoid.Health - dmg
	if newHealth <= 0 then
		if TreadmillService and TreadmillService.ProcessHazardDeath then
			deathCooldownUntil[player] = now + SuperLaserGirlConfigs.DeathCooldown
			TreadmillService:ProcessHazardDeath(player, turret.head)
		end
		return
	end
	humanoid.Health = newHealth
end

--- Start a beam burst at the player: show the heat-vision rig, play the sound, and (once) apply
--- damage only if there is clear line of sight to the player — cover/distance dodges it.
local function beginBurst(turret: Turret, player: Player)
	local rig = turret.hvRig
	if not turret.model.Parent or not rig then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end

	turret.firing = true
	turret.shotTarget = player
	turret.fireUntil = os.clock() + SuperLaserGirlConfigs.BeamSeconds

	HeatVisionRig.setActive(rig, true)
	-- Arcade "phew": the twin beams must reach the player INSTANTLY. HeatVisionRig normally grows the
	-- beam over a ~0.6s extend ramp (perfect for the player's held heat-vision), but our burst is only
	-- BeamSeconds (~0.25s) — far too short for that ramp to finish, so without this the beam is a tiny
	-- stub at her face that never reaches the player. Snap the extend to full so both eye-beams shoot
	-- straight to the target for the whole burst. (updateAim keeps it pinned at 1 via min(1, …).)
	rig.beamExtendAlpha = 1
	HeatVisionRig.updateAim(rig, hrp.Position - rig.headPart.Position, SuperLaserGirlConfigs.BeamMaxRange, 0)
	playLaserSound(turret)

	-- Line-of-sight check (once): only damage if the ray reaches the player's character.
	local origin = rig.headPart.Position
	local toTarget = hrp.Position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { turret.model }
	local result = Workspace:Raycast(origin, toTarget, params)
	local hitPlayer = true
	if result then
		hitPlayer = result.Instance:IsDescendantOf(character :: Instance)
	end
	if hitPlayer then
		applyLaserDamage(turret, player)
	end
end

--- Returns false to request unbind (model gone).
local function updateTurret(turret: Turret, dt: number, now: number): boolean
	if not turret.model.Parent or not turret.root.Parent then
		return false
	end

	-- Detection throttle: ~0.2s active, slower when dormant.
	local interval = if turret.dormant then 0.5 else 0.2
	if now - turret.lastDetectAt >= interval then
		turret.lastDetectAt = now
		local nearest, nearestAny = findNearestPlayer(turret.head)
		turret.lastTarget = nearest
		turret.dormant = nearestAny > SuperLaserGirlConfigs.SleepRange
	end

	-- Rotate to face the player she's engaging (while idle AND firing), so her eyes point at them
	-- and the twin beams clearly come from her face.
	if not turret.dormant then
		local facePos = targetHrpPos(turret.shotTarget or turret.lastTarget)
		if facePos then
			faceToward(turret.root, facePos)
		end
	end

	-- While firing: keep the beam growing + tracking the player, then end after BeamSeconds.
	if turret.firing then
		local rig = turret.hvRig
		local tp = targetHrpPos(turret.shotTarget)
		if rig and tp and now < turret.fireUntil then
			HeatVisionRig.updateAim(rig, tp - rig.headPart.Position, SuperLaserGirlConfigs.BeamMaxRange, dt)
		else
			turret.firing = false
			turret.shotTarget = nil
			if rig then
				HeatVisionRig.setActive(rig, false)
			end
		end
		return true
	end

	if turret.dormant then
		return true
	end

	-- Idle: a player is in radius and we're off cooldown -> charge (telegraph) then fire.
	local target = turret.lastTarget
	if target and target.Parent and now >= turret.nextFireAt then
		-- Bake the whole cycle into nextFireAt up front so nothing re-triggers during it.
		turret.nextFireAt = now
			+ SuperLaserGirlConfigs.ChargeSeconds
			+ SuperLaserGirlConfigs.BeamSeconds
			+ SuperLaserGirlConfigs.FireCooldown
		local shot = target
		task.delay(SuperLaserGirlConfigs.ChargeSeconds, function()
			if not bound[turret.model] or turret.firing or not shot.Parent then
				return
			end
			local tp = targetHrpPos(shot)
			if not tp or (turret.head.Position - tp).Magnitude > SuperLaserGirlConfigs.DetectRadius then
				return -- player left the radius during the charge
			end
			beginBurst(turret, shot)
		end)
	end
	return true
end

local function bindTagged(tagged: Instance)
	if boundTag[tagged] then
		return
	end
	local model = resolveRig(tagged)
	if not model then
		dbg("tagged", tagged:GetFullName(), "has no rig (Head + Humanoid) yet")
		return
	end
	if bound[model] then
		boundTag[tagged] = model -- another tagged node already drives this rig
		return
	end

	local root = modelRoot(model)
	local headInst = model:FindFirstChild("Head")
	local head = if headInst and headInst:IsA("BasePart") then headInst :: BasePart else nil
	if not root or not head then
		dbg("rig missing Root/Head:", model:GetFullName())
		return
	end

	-- Anchor ONLY the root (stationary, exact pose, no physics tug); the Animator drives the rest.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = (d == root)
		end
	end

	-- An anchored Humanoid ragdolls on clients (sits in FallingDown forever) -> destroy it and
	-- drive the pose with an AnimationController + Animator.
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

	local turret: Turret = {
		model = model,
		root = root,
		head = head,
		stage = StageCheckpointWorld.resolveStageFromAncestor(model) or 5,
		hvRig = nil,
		idleTrack = nil,
		nextFireAt = 0,
		firing = false,
		fireUntil = 0,
		shotTarget = nil,
		dormant = false,
		lastTarget = nil,
		lastDetectAt = 0,
	}

	-- Idle pose (looped, always playing).
	local okIdle, idleTrack = pcall(function()
		return animator:LoadAnimation(makeAnimation(SuperLaserGirlConfigs.IdleAnimationId))
	end)
	if okIdle and idleTrack then
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Movement
		idleTrack:Play(0.1)
		idleTrack:AdjustWeight(1)
		turret.idleTrack = idleTrack
	else
		dbg("idle animation failed to load:", tostring(idleTrack))
	end

	-- Mount the SupermanHeatVision beam rig, hidden until she fires.
	local rig = HeatVisionRig.mount(model)
	if rig then
		HeatVisionRig.setActive(rig, false)
		spreadEyesToRig(rig, head)
		turret.hvRig = rig
	else
		dbg("HeatVisionRig.mount failed for", model:GetFullName())
	end

	bound[model] = turret
	boundTag[tagged] = model
	dbg("bound", model.Name, "stage", turret.stage)
end

local function fullyUnbind(model: Model)
	local turret = bound[model]
	if turret then
		if turret.idleTrack then
			pcall(function()
				(turret.idleTrack :: AnimationTrack):Stop()
			end)
		end
		HeatVisionRig.destroy(model)
		bound[model] = nil
	end
	for inst, m in boundTag do
		if m == model then
			boundTag[inst] = nil
		end
	end
end

local function unbindTagged(tagged: Instance)
	local model = boundTag[tagged]
	boundTag[tagged] = nil
	if not model then
		return
	end
	-- Only tear down the rig if no other tagged node still drives it.
	for _, m in boundTag do
		if m == model then
			return
		end
	end
	fullyUnbind(model)
end

function SuperLaserGirlService:KnitStart()
	if SuperLaserGirlConfigs.Enabled ~= true then
		print("[iseesupes] SuperLaserGirlService disabled.")
		return
	end

	TreadmillService = Knit.GetService("TreadmillService")

	local tag = SuperLaserGirlConfigs.Tag
	local function scan()
		for _, inst in CollectionService:GetTagged(tag) do
			bindTagged(inst)
		end
	end

	scan()
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		task.defer(bindTagged, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbindTagged)
	-- Stages stream/clone in after boot; catch late arrivals.
	for _, delay in { 1, 3, 6 } do
		task.delay(delay, scan)
	end

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for model, turret in bound do
			if updateTurret(turret, dt, now) == false then
				fullyUnbind(model)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
		deathCooldownUntil[player] = nil
	end)

	StudioLog.ready("SuperLaserGirlService")
end

return SuperLaserGirlService
