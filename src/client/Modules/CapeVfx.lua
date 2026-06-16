--!strict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)
local CapePoseBootstrap = require(ReplicatedStorage.Shared.Utils.CapePoseBootstrap)
local CapeRigEnsure = require(ReplicatedStorage.Shared.Utils.CapeRigEnsure)

export type CapeVisualState = GlideVfxConfigs.CapeVisualState

type CapeRig = {
	root: Instance,
	mesh: BasePart,
	bones: { Bone },
	poseRoot: Folder,
}

type CharacterState = {
	capeState: CapeVisualState?,
	flyEffectsActive: boolean,
	flyLoopSound: Sound?,
	boneTweens: { Tween },
	rig: CapeRig?,
	hasClothAttrs: boolean,
	skipBoneDrive: boolean,
	walkFlutterTime: number,
	poseBases: { [Bone]: CFrame },
	capeMotor: Motor6D?,
	motorPoseBase: CFrame?,
	boneChains: { { Bone } }?,
	chainMaxDepth: number,
	clothAttrsStripped: boolean,
}

local CapeVfx = {}

local LOG_PREFIX = "[iseesupes][CapeVfx]"

local characterStates: { [Model]: CharacterState } = {}
local equippedTrailColor: ColorSequence? = nil
local warnedNoRig: { [Model]: boolean } = {}
local rigWatchConnections: { [Model]: RBXScriptConnection } = {}
local lastResolveFailLogAt: { [Model]: number } = {}
local lastDynamicsLogAt = 0
local dynamicsRenderBound = false

local function ensureDynamicsRenderLoop()
	if dynamicsRenderBound then
		return
	end
	dynamicsRenderBound = true
	RunService:BindToRenderStep("iseesupesCapeDynamics", Enum.RenderPriority.Last.Value, function(dt)
		for character, state in characterStates do
			if state.rig and state.capeState and character.Parent then
				CapeVfx.tickCapeDynamics(character, dt)
			end
		end
	end)
end

local function cleanupLeftoverCapeVisuals(mesh: BasePart)
	mesh.LocalTransparencyModifier = 0
	mesh.Transparency = GlideVfxConfigs.Cape.VisibleTransparency
	for _, child in mesh:GetDescendants() do
		if child:IsA("Texture") then
			child.Transparency = GlideVfxConfigs.Cape.TextureTransparency
		end
	end
	local parent = mesh.Parent
	if parent then
		local proxy = parent:FindFirstChild("CapeClientVisual")
		if proxy then
			proxy:Destroy()
		end
	end
end

local function debugLog(...)
	if not GlideVfxConfigs.Debug then
		return
	end
	print(LOG_PREFIX, ...)
end

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, name in segments do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function getAllBones(rigRoot: Instance): { Bone }
	local bones: { Bone } = {}
	for _, desc in rigRoot:GetDescendants() do
		if desc:IsA("Bone") then
			table.insert(bones, desc)
		end
	end
	return bones
end

local function usesClothSim(mesh: BasePart): boolean
	return typeof(mesh:GetAttribute("Roots")) == "string"
end

local function findCapeMesh(rigRoot: Instance): BasePart?
	for _, meshName in GlideVfxConfigs.CapeMeshNames do
		if rigRoot.Name == meshName and rigRoot:IsA("BasePart") then
			return rigRoot
		end
		local child = rigRoot:FindFirstChild(meshName)
		if child and child:IsA("BasePart") then
			return child
		end
	end
	if rigRoot:IsA("BasePart") then
		return rigRoot
	end
	return nil
end

local function findDeepSkinnedCape(character: Model): Instance?
	for _, desc in character:GetDescendants() do
		if desc.Name == "Cape" and desc:IsA("MeshPart") then
			for _, child in desc:GetChildren() do
				if child:IsA("Bone") then
					return desc
				end
			end
		end
	end
	return nil
end

local function buildRigFromRoot(found: Instance): CapeRig?
	local mesh = findCapeMesh(found)
	if not mesh then
		return nil
	end
	local poseRoot = CapePoseBootstrap.ensureCapePoses(found)
	return {
		root = found,
		mesh = mesh,
		bones = getAllBones(found),
		poseRoot = poseRoot,
	}
end

function CapeVfx.resolveCapeRig(character: Model): CapeRig?
	for _, segments in GlideVfxConfigs.CapeSearchPaths do
		local found = resolvePath(character, segments)
		if found then
			local rig = buildRigFromRoot(found)
			if rig and #rig.bones > 0 then
				debugLog(
					"resolve path",
					table.concat(segments, "/"),
					"bones=",
					#rig.bones,
					"cloth=",
					usesClothSim(rig.mesh)
				)
				return rig
			end
		end
	end

	local deep = findDeepSkinnedCape(character)
	if deep then
		local rig = buildRigFromRoot(deep)
		if rig and #rig.bones > 0 then
			debugLog("resolve deep", deep:GetFullName(), "bones=", #rig.bones, "cloth=", usesClothSim(rig.mesh))
			return rig
		end
	end

	local legacy = character:FindFirstChild(GlideVfxConfigs.CapeModelName)
	if legacy then
		local rig = buildRigFromRoot(legacy)
		if rig and #rig.bones > 0 then
			debugLog("resolve legacy", legacy:GetFullName(), "bones=", #rig.bones)
			return rig
		end
	end

	local now = os.clock()
	local last = lastResolveFailLogAt[character] or 0
	if GlideVfxConfigs.Debug and now - last > 0.75 then
		lastResolveFailLogAt[character] = now
		debugLog("resolve failed", character:GetFullName())
	end
	return nil
end

function CapeVfx.waitForRig(character: Model, maxSeconds: number?): CapeRig?
	local timeout = maxSeconds or GlideVfxConfigs.RigWaitSeconds or 8
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if not character.Parent then
			return nil
		end
		local rig = CapeVfx.resolveCapeRig(character)
		if rig and #rig.bones > 0 then
			return rig
		end
		task.wait(0.05)
	end
	return nil
end

function CapeVfx.watchForRig(character: Model, onReady: () -> ())
	local existing = rigWatchConnections[character]
	if existing then
		existing:Disconnect()
		rigWatchConnections[character] = nil
	end

	local fired = false
	local function tryReady()
		if fired or not character.Parent then
			return
		end
		local rig = CapeVfx.resolveCapeRig(character)
		if rig and #rig.bones > 0 then
			fired = true
			local conn = rigWatchConnections[character]
			if conn then
				conn:Disconnect()
				rigWatchConnections[character] = nil
			end
			onReady()
		end
	end

	tryReady()
	if fired then
		return
	end

	rigWatchConnections[character] = character.DescendantAdded:Connect(function(desc: Instance)
		if
			desc:IsA("Bone")
			or desc.Name == "Suit"
			or desc.Name == "UT"
			or desc.Name == "Cape"
		then
			tryReady()
		end
	end)
end

function CapeVfx.warnNoRigOnce(character: Model)
	if warnedNoRig[character] then
		return
	end
	warnedNoRig[character] = true
	warn("[iseesupes] CapeVfx: no skinned UT.Cape with bones on", character:GetFullName(), "(waited", GlideVfxConfigs.RigWaitSeconds, "s)")
end

local function getState(character: Model): CharacterState
	local state = characterStates[character]
	if state then
		return state
	end
	state = {
		capeState = nil,
		flyEffectsActive = false,
		flyLoopSound = nil,
		boneTweens = {},
		rig = nil,
		hasClothAttrs = false,
		skipBoneDrive = false,
		walkFlutterTime = 0,
		poseBases = {},
		capeMotor = nil,
		motorPoseBase = nil,
		boneChains = nil,
		chainMaxDepth = 0,
		clothAttrsStripped = false,
	}
	characterStates[character] = state
	return state
end

local function stripClothAttrsForProcedural(mesh: BasePart, charState: CharacterState)
	if charState.clothAttrsStripped then
		return
	end
	if GlideVfxConfigs.StripClothAttrsForProcedural ~= true or GlideVfxConfigs.ClothPluginDrivesBones == true then
		return
	end
	if mesh:GetAttribute("Roots") ~= nil then
		mesh:SetAttribute("Roots", nil)
	end
	charState.clothAttrsStripped = true
	debugLog("stripped cloth Roots on", mesh:GetFullName())
end

local function getMeshMotorOffset(capeState: CapeVisualState): CFrame
	local offsets = GlideVfxConfigs.Cape.MeshMotorOffsets
	if not offsets then
		return CFrame.new()
	end
	return offsets[capeState] or CFrame.new()
end

local function findBoneByName(bones: { Bone }, name: string): Bone?
	for _, bone in bones do
		if bone.Name == name then
			return bone
		end
	end
	return nil
end

local function buildBoneChains(bones: { Bone }): ({ { Bone } }, number)
	local chains: { { Bone } } = {}
	local maxDepth = 0

	for _, rootName in GlideVfxConfigs.RootBoneNames do
		local root = findBoneByName(bones, rootName)
		if not root then
			continue
		end

		local chain: { Bone } = { root }
		local function appendChildren(parent: Bone)
			for _, bone in bones do
				if bone.Parent == parent then
					table.insert(chain, bone)
					appendChildren(bone)
				end
			end
		end
		appendChildren(root)
		maxDepth = math.max(maxDepth, #chain - 1)
		table.insert(chains, chain)
	end

	return chains, maxDepth
end

local function bindRigExtras(character: Model, charState: CharacterState, rig: CapeRig)
	cleanupLeftoverCapeVisuals(rig.mesh)
	stripClothAttrsForProcedural(rig.mesh, charState)
	charState.boneChains, charState.chainMaxDepth = buildBoneChains(rig.bones)
	-- Motor6D is disabled: CapeAnimatorController drives bones; WeldConstraint keeps mesh attached.
	if GlideVfxConfigs.UseMotor6D ~= false then
		charState.capeMotor = CapeRigEnsure.ensureCapeMotor(character, rig.mesh)
	end
end

local function computeDynamics(charState: CharacterState, character: Model, speed: number): CFrame
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vel = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
	local localVel = if hrp then hrp.CFrame:VectorToObjectSpace(vel) else vel

	local proc = GlideVfxConfigs.Procedural
	local velPitch = math.clamp(-localVel.Z * proc.VelocityInfluence, -proc.MaxBonePitch, proc.MaxBonePitch)
	local velLift = math.clamp(localVel.Y * proc.VelocityInfluence * 0.5, -proc.MaxBonePitch, proc.MaxBonePitch)

	local flutterAmp = GlideVfxConfigs.WalkFlutter.AmplitudeRadians
	local flutterFreq = GlideVfxConfigs.WalkFlutter.Frequency
	local wave = 0
	if GlideVfxConfigs.WalkFlutter.Enabled and speed > 2 then
		wave = math.sin(charState.walkFlutterTime * flutterFreq * math.pi * 2) * flutterAmp
	end

	local stateBoost = if charState.capeState == GlideVfxConfigs.States.Fly
		then 1.4
		elseif charState.capeState == GlideVfxConfigs.States.Walk then 1
		else 0.5

	local rootScale = proc.RootFlutterScale or 1
	local motorScale = GlideVfxConfigs.Cape.MeshMotorFlutterScale or 1.8

	return CFrame.Angles(
		(velPitch + velLift) * stateBoost * motorScale,
		wave * 0.35 * motorScale,
		(velPitch * 0.6 + wave * 0.5) * stateBoost * motorScale
	) * CFrame.Angles(
		wave * 0.2 * rootScale,
		0,
		wave * 0.15 * rootScale
	)
end

local function cancelBoneTweens(state: CharacterState)
	for _, tween in state.boneTweens do
		tween:Cancel()
	end
	table.clear(state.boneTweens)
end

local function isRootBone(bone: Bone): boolean
	for _, name in GlideVfxConfigs.RootBoneNames do
		if bone.Name == name then
			return true
		end
	end
	return false
end

local function getPoseCFrame(rig: CapeRig, stateName: CapeVisualState, bone: Bone): CFrame?
	local poseState = stateName
	if stateName ~= GlideVfxConfigs.States.Idle and not isRootBone(bone) then
		poseState = GlideVfxConfigs.States.Idle
	end
	local stateFolder = rig.poseRoot:FindFirstChild(poseState)
	if not stateFolder then
		return nil
	end
	local pose = stateFolder:FindFirstChild(bone.Name)
	if pose and pose:IsA("CFrameValue") then
		return pose.Value
	end
	return nil
end

local function setMeshVisible(mesh: BasePart)
	TweenService:Create(mesh, GlideVfxConfigs.Tween.CapeFadeIn, {
		Transparency = GlideVfxConfigs.Cape.VisibleTransparency,
	}):Play()
	for _, child in mesh:GetChildren() do
		if child:IsA("Texture") then
			TweenService:Create(child, GlideVfxConfigs.Tween.Texture, {
				Transparency = GlideVfxConfigs.Cape.TextureTransparency,
			}):Play()
		end
	end
end

local function setBoneTransform(bone: Bone, offset: CFrame)
	bone.Transform = offset
end

local function applyBoneChainFK(
	charState: CharacterState,
	rootTransforms: { [Bone]: CFrame },
	dynamics: CFrame
)
	local chains = charState.boneChains
	if not chains then
		return
	end

	local maxDepth = math.max(charState.chainMaxDepth, 1)
	for _, chain in chains do
		for index, bone in chain do
			if not bone.Parent then
				continue
			end
			if index == 1 then
				local rootT = rootTransforms[bone]
				if rootT then
					setBoneTransform(bone, rootT * dynamics)
				end
			else
				local parent = chain[index - 1]
				if parent and parent:IsA("Bone") then
					local depthT = (index - 1) / maxDepth
					local tipExtra = CFrame.new():Lerp(dynamics, math.clamp(depthT, 0, 1))
					setBoneTransform(bone, parent.Transform * tipExtra)
				end
			end
		end
	end
end

local function applyMotorPose(charState: CharacterState, capeState: CapeVisualState, dynamics: CFrame)
	local motor = charState.capeMotor
	if not motor then
		return
	end
	local base = getMeshMotorOffset(capeState)
	charState.motorPoseBase = base
	motor.Transform = base * dynamics
end

local function applyAllBonePoses(
	charState: CharacterState,
	rig: CapeRig,
	capeState: CapeVisualState,
	dynamics: CFrame
)
	if charState.skipBoneDrive then
		return
	end

	local rootTransforms: { [Bone]: CFrame } = {}
	for _, bone in rig.bones do
		local target = getPoseCFrame(rig, capeState, bone)
		if not target then
			continue
		end
		charState.poseBases[bone] = target
		if isRootBone(bone) then
			rootTransforms[bone] = target
		end
	end

	applyBoneChainFK(charState, rootTransforms, dynamics)
end

local function applyClothAttributes(mesh: BasePart, capeState: CapeVisualState)
	if GlideVfxConfigs.ApplyClothWindAttributes == false then
		return
	end
	local clothCfg = GlideVfxConfigs.ClothByState[capeState]
	if not clothCfg or not GlideVfxConfigs.ClothAttributes then
		return
	end
	for attrName, enabled in GlideVfxConfigs.ClothAttributes do
		if enabled and mesh:GetAttribute(attrName) ~= nil and clothCfg[attrName] ~= nil then
			mesh:SetAttribute(attrName, clothCfg[attrName])
		end
	end
end

local function applyMeshForState(mesh: BasePart, capeState: CapeVisualState)
	setMeshVisible(mesh)
	local useFluid = GlideVfxConfigs.Cape.EnableFluidForces ~= false
		and not ClientPerformance.shouldReduceCapeDynamics()
	if useFluid then
		mesh.EnableFluidForces = true
	else
		mesh.EnableFluidForces = false
	end
	applyClothAttributes(mesh, capeState)
end

local function tweenBonesToPose(character: Model, state: CharacterState, rig: CapeRig, capeState: CapeVisualState)
	cancelBoneTweens(state)
	table.clear(state.poseBases)

	if not state.skipBoneDrive then
		applyMotorPose(state, capeState, CFrame.new())
	end

	if state.skipBoneDrive then
		for _, bone in rig.bones do
			state.poseBases[bone] = bone.Transform
		end
		return
	end

	applyAllBonePoses(state, rig, capeState, CFrame.new())
end

local function tickClothWind(mesh: BasePart, capeState: CapeVisualState, speed: number)
	local base = GlideVfxConfigs.ClothByState[capeState]
	if not base then
		return
	end
	local speedScale = math.clamp(speed / 40, 0.25, 2.5)
	if mesh:GetAttribute("WindStrength") ~= nil and base.WindStrength then
		mesh:SetAttribute("WindStrength", base.WindStrength * speedScale)
	end
	if mesh:GetAttribute("WindSpeed") ~= nil and base.WindSpeed then
		mesh:SetAttribute("WindSpeed", base.WindSpeed * speedScale)
	end
	if mesh:GetAttribute("WindInfluence") ~= nil and base.WindInfluence then
		mesh:SetAttribute("WindInfluence", base.WindInfluence * math.clamp(speedScale, 0.5, 2))
	end
end

function CapeVfx.applyCapeState(character: Model?, capeState: CapeVisualState, force: boolean?)
	if not GlideVfxConfigs.Enabled or not character then
		return
	end

	local charState = getState(character)
	if not force and charState.capeState == capeState and charState.rig then
		applyMeshForState(charState.rig.mesh, capeState)
		if charState.capeMotor then
			applyMotorPose(charState, capeState, CFrame.new())
		end
		return
	end

	local rig = charState.rig or CapeVfx.resolveCapeRig(character)
	if not rig or #rig.bones == 0 then
		debugLog("apply deferred, no rig", character.Name)
		return
	end
	warnedNoRig[character] = nil
	lastResolveFailLogAt[character] = nil
	charState.rig = rig
	charState.capeState = capeState
	charState.hasClothAttrs = usesClothSim(rig.mesh)
	charState.skipBoneDrive = charState.hasClothAttrs and GlideVfxConfigs.ClothPluginDrivesBones == true

	bindRigExtras(character, charState, rig)

	applyMeshForState(rig.mesh, capeState)
	tweenBonesToPose(character, charState, rig, capeState)
	ensureDynamicsRenderLoop()

	if GlideVfxConfigs.Debug then
		for _, bone in rig.bones do
			if isRootBone(bone) then
				debugLog("root", bone.Name, "Transform=", bone.Transform, "World=", bone.TransformedWorldCFrame.Position)
				break
			end
		end
		if charState.capeMotor then
			debugLog("motor", "Transform=", charState.capeMotor.Transform)
		end
	end

	debugLog(
		"apply",
		capeState,
		"force=",
		force == true,
		"path=",
		rig.root:GetFullName(),
		"bones=",
		#rig.bones,
		"clothAttrs=",
		charState.hasClothAttrs,
		"boneDrive=",
		if charState.skipBoneDrive then "plugin" else "transform+motor",
		"motor=",
		charState.capeMotor ~= nil,
		"fluid=",
		rig.mesh.EnableFluidForces
	)
end

function CapeVfx.forceRefresh(character: Model?)
	if not character then
		return
	end
	local charState = getState(character)
	local state = if charState.capeState then charState.capeState else GlideVfxConfigs.States.Idle
	charState.rig = nil
	debugLog("forceRefresh", character.Name, "state=", state)
	local ok, err = pcall(function()
		CapeVfx.applyCapeState(character, state, true)
	end)
	if not ok then
		warn(LOG_PREFIX, "forceRefresh error:", err)
	end
end

function CapeVfx.refreshAfterShowcaseEquip(character: Model?)
	if not character then
		return
	end
	debugLog("refreshAfterShowcaseEquip", character.Name, "avatar=", character:GetAttribute("EquippedShowcaseAvatarId"))
	CapeVfx.forceRefresh(character)
end

function CapeVfx.needsApply(character: Model?): boolean
	if not character then
		return false
	end
	return CapeVfx.getActiveCapeState(character) == nil
end

function CapeVfx.tickCapeDynamics(character: Model?, dt: number)
	if not character then
		return
	end

	local charState = characterStates[character]
	if not charState or not charState.rig or not charState.capeState then
		return
	end

	if ClientPerformance.shouldReduceCapeDynamics() then
		return
	end

	charState.walkFlutterTime += dt

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vel = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
	local speed = vel.Magnitude

	if GlideVfxConfigs.ApplyClothWindAttributes and charState.hasClothAttrs then
		tickClothWind(charState.rig.mesh, charState.capeState, speed)
	end

	local dynamics = computeDynamics(charState, character, speed)
	local visualState = charState.capeState

	if charState.capeMotor and charState.motorPoseBase then
		charState.capeMotor.Transform = charState.motorPoseBase * dynamics
	elseif charState.capeMotor and visualState then
		applyMotorPose(charState, visualState, dynamics)
	end

	if charState.skipBoneDrive or not GlideVfxConfigs.Procedural.Enabled then
		if GlideVfxConfigs.Debug then
			local now = os.clock()
			if now - lastDynamicsLogAt > 2 then
				lastDynamicsLogAt = now
				debugLog(
					"tick",
					charState.capeState,
					"speed=",
					math.floor(speed),
					"motorOnly=",
					charState.skipBoneDrive,
					if GlideVfxConfigs.ApplyClothWindAttributes and charState.hasClothAttrs then "+wind" else ""
				)
			end
		end
		return
	end

	if charState.rig and charState.capeState and next(charState.poseBases) ~= nil then
		applyAllBonePoses(charState, charState.rig, charState.capeState, dynamics)
	end

	if GlideVfxConfigs.Debug then
		local now = os.clock()
		if now - lastDynamicsLogAt > 2 then
			lastDynamicsLogAt = now
			local poseCount = 0
			for _ in charState.poseBases do
				poseCount += 1
			end
			debugLog(
				"bone tick",
				charState.capeState,
				"speed=",
				math.floor(speed),
				"poses=",
				poseCount,
				"motor=",
				charState.capeMotor ~= nil,
				if GlideVfxConfigs.ApplyClothWindAttributes and charState.hasClothAttrs then "+wind" else ""
			)
		end
	end
end

function CapeVfx.tickWalkFlutter(character: Model?, dt: number)
	CapeVfx.tickCapeDynamics(character, dt)
end

function CapeVfx.getActiveCapeState(character: Model?): CapeVisualState?
	if not character then
		return nil
	end
	local charState = characterStates[character]
	return if charState then charState.capeState else nil
end

function CapeVfx.getResolvedCapePath(character: Model?): string?
	local rig = if character then CapeVfx.resolveCapeRig(character) else nil
	return if rig then rig.root:GetFullName() else nil
end

-- Glide trails + sounds (Fly only)

local function createGlideTrail(limb: BasePart)
	local trailName = GlideVfxConfigs.Trail.Name
	if limb:FindFirstChild(trailName) then
		return
	end

	local cfg = GlideVfxConfigs.Trail

	local att0 = Instance.new("Attachment")
	att0.Name = "AttachmentSky"
	att0.CFrame = cfg.Attachment0Offset
	att0.Parent = limb

	local att1 = Instance.new("Attachment")
	att1.Name = "AttachmentSky2"
	att1.CFrame = cfg.Attachment1Offset
	att1.Parent = limb

	local trail = Instance.new("Trail")
	trail.Name = trailName
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = cfg.Lifetime
	trail.Enabled = false
	trail.Texture = cfg.Texture
	trail.LightInfluence = cfg.LightInfluence
	trail.Brightness = cfg.Brightness
	trail.LightEmission = cfg.LightEmission
	trail.Color = cfg.Color
	trail.Transparency = cfg.Transparency
	trail.WidthScale = cfg.WidthScale
	trail.Parent = limb
end

local function ensureGlideTrails(character: Model)
	for _, limbName in GlideVfxConfigs.LimbNames do
		local limb = character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			createGlideTrail(limb)
		end
	end
end

local function setTrailsEnabled(character: Model, enabled: boolean)
	local trailName = GlideVfxConfigs.Trail.Name
	for _, limbName in GlideVfxConfigs.LimbNames do
		local limb = character:FindFirstChild(limbName)
		if limb then
			local trail = limb:FindFirstChild(trailName)
			if trail and trail:IsA("Trail") then
				trail.Enabled = enabled
			end
		end
	end
end

function CapeVfx.setEquippedTrailColor(color: ColorSequence?)
	equippedTrailColor = color
end

function CapeVfx.setGlideTrailColor(character: Model, color: ColorSequence?)
	local trailColor = color or equippedTrailColor or GlideVfxConfigs.Trail.Color
	local trailName = GlideVfxConfigs.Trail.Name
	for _, limbName in GlideVfxConfigs.LimbNames do
		local limb = character:FindFirstChild(limbName)
		if limb then
			local trail = limb:FindFirstChild(trailName)
			if trail and trail:IsA("Trail") then
				trail.Color = trailColor
			end
		end
	end
end

local function playOneShot(template: Sound?, parent: Instance?, lifetime: number)
	if not template or not parent then
		return
	end
	local clone = template:Clone()
	clone.Parent = parent
	clone:Play()
	Debris:AddItem(clone, lifetime)
end

local function playFlyLoop(character: Model, state: CharacterState)
	if state.flyLoopSound and state.flyLoopSound.Parent then
		if not state.flyLoopSound.IsPlaying then
			state.flyLoopSound:Play()
		end
		return
	end

	local template = resolvePath(ReplicatedStorage, GlideVfxConfigs.Assets.FlyLoop)
	if template and template:IsA("Sound") then
		local parent = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart") or character
		local clone = template:Clone()
		clone.Name = GlideVfxConfigs.Assets.FlyLoopParentName
		clone.Looped = true
		clone.Parent = parent
		clone:Play()
		state.flyLoopSound = clone
		return
	end

	local existing = character:FindFirstChild(GlideVfxConfigs.Assets.FlyLoopParentName, true)
	if existing and existing:IsA("Sound") then
		existing.Looped = true
		existing:Play()
		state.flyLoopSound = existing
	end
end

local function stopFlyLoop(state: CharacterState)
	local sound = state.flyLoopSound
	if not sound then
		return
	end
	if sound.IsPlaying then
		sound:Stop()
	end
	if sound.Parent then
		sound:Destroy()
	end
	state.flyLoopSound = nil
end

local function startFlyEffects(character: Model, state: CharacterState, sounds: Folder?)
	if not ClientPerformance.shouldDisableFlightTrails() then
		ensureGlideTrails(character)
		CapeVfx.setGlideTrailColor(character, equippedTrailColor)
		setTrailsEnabled(character, true)
	end
	playFlyLoop(character, state)

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local woosh = sounds and sounds:FindFirstChild("Woosh")
		local wind = sounds and sounds:FindFirstChild("Wind")
		if woosh and woosh:IsA("Sound") then
			playOneShot(woosh, hrp, 3)
		end
		if wind and wind:IsA("Sound") then
			playOneShot(wind, hrp, 5)
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		local startGlide = head:FindFirstChild(GlideVfxConfigs.Assets.StartGlideSoundName)
		if startGlide and startGlide:IsA("Sound") and not startGlide.IsPlaying then
			startGlide:Play()
		end
		local clothing = sounds and sounds:FindFirstChild("Clothing")
		if clothing and clothing:IsA("Sound") then
			playOneShot(clothing, head, 2)
		end
	end
end

local function stopFlyEffects(character: Model, state: CharacterState, sounds: Folder?)
	setTrailsEnabled(character, false)
	stopFlyLoop(state)

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local woosh = sounds and sounds:FindFirstChild("Woosh")
		if woosh and woosh:IsA("Sound") then
			playOneShot(woosh, hrp, 3)
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		local clothing = sounds and sounds:FindFirstChild("Clothing")
		if clothing and clothing:IsA("Sound") then
			playOneShot(clothing, head, 2)
		end
	end
end

function CapeVfx.setFlyEffectsActive(character: Model?, active: boolean, sounds: Folder?)
	if not GlideVfxConfigs.Enabled or not character then
		return
	end

	local state = getState(character)
	if state.flyEffectsActive == active then
		return
	end
	state.flyEffectsActive = active

	if active then
		startFlyEffects(character, state, sounds)
	else
		stopFlyEffects(character, state, sounds)
	end
end

function CapeVfx.isFlyPhase(phase: string?): boolean
	if not phase then
		return false
	end
	return GlideVfxConfigs.FlyPhases[phase] == true
end

function CapeVfx.isLandPhase(phase: string?): boolean
	if not phase then
		return false
	end
	return GlideVfxConfigs.LandPhases[phase] == true
end

function CapeVfx.isGlidePhase(phase: string?): boolean
	return CapeVfx.isFlyPhase(phase)
end

function CapeVfx.phaseToCapeState(phase: string?): CapeVisualState?
	if CapeVfx.isFlyPhase(phase) then
		return GlideVfxConfigs.States.Fly
	end
	if CapeVfx.isLandPhase(phase) then
		return GlideVfxConfigs.States.Land
	end
	return nil
end

function CapeVfx.locomotionToCapeState(locomotion: string): CapeVisualState
	if locomotion == "run" then
		return GlideVfxConfigs.States.Walk
	end
	if locomotion == "landing" then
		return GlideVfxConfigs.States.Land
	end
	return GlideVfxConfigs.States.Idle
end

function CapeVfx.setGlideActive(character: Model?, active: boolean, sounds: Folder?)
	if not character then
		return
	end
	if active then
		CapeVfx.applyCapeState(character, GlideVfxConfigs.States.Fly)
		CapeVfx.setFlyEffectsActive(character, true, sounds)
	else
		CapeVfx.setFlyEffectsActive(character, false, sounds)
	end
end

function CapeVfx.cleanupCharacter(character: Model)
	local state = characterStates[character]
	if not state then
		return
	end
	if state.flyEffectsActive then
		stopFlyEffects(character, state, nil)
	end
	cancelBoneTweens(state)
	if state.rig then
		cleanupLeftoverCapeVisuals(state.rig.mesh)
	end
	warnedNoRig[character] = nil
	lastResolveFailLogAt[character] = nil
	local watchConn = rigWatchConnections[character]
	if watchConn then
		watchConn:Disconnect()
		rigWatchConnections[character] = nil
	end
	characterStates[character] = nil
	if not next(characterStates) then
		pcall(function()
			RunService:UnbindFromRenderStep("iseesupesCapeDynamics")
		end)
		dynamicsRenderBound = false
	end
end

return CapeVfx
