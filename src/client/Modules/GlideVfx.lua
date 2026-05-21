--!strict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)

local GlideVfx = {}

type CharacterState = {
	glideActive: boolean,
	flyLoopSound: Sound?,
}

local characterStates: { [Model]: CharacterState } = {}

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

local function getAllBones(capeModel: Instance?): { Bone }
	local bones: { Bone } = {}
	if not capeModel then
		return bones
	end
	for _, desc in capeModel:GetDescendants() do
		if desc:IsA("Bone") then
			table.insert(bones, desc)
		end
	end
	return bones
end

local function getState(character: Model): CharacterState
	local state = characterStates[character]
	if state then
		return state
	end
	state = {
		glideActive = false,
		flyLoopSound = nil,
	}
	characterStates[character] = state
	return state
end

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

local function enableCapeGlide(character: Model)
	local cape = character:FindFirstChild(GlideVfxConfigs.CapeModelName)
	local cape2 = cape and cape:FindFirstChild(GlideVfxConfigs.CapePartName)
	if not cape2 or not cape2:IsA("BasePart") then
		return
	end

	TweenService:Create(cape2, GlideVfxConfigs.Tween.CapeFadeIn, {
		Transparency = GlideVfxConfigs.Cape.GlideTransparency,
	}):Play()

	for _, child in cape2:GetChildren() do
		if child:IsA("Texture") then
			TweenService:Create(child, GlideVfxConfigs.Tween.Texture, {
				Transparency = GlideVfxConfigs.Cape.TextureGlideTransparency,
			}):Play()
		end
	end

	cape2.EnableFluidForces = true

	local bones = getAllBones(cape)
	local spread = GlideVfxConfigs.Cape.BoneSpreadOffset
	for _, bone in bones do
		local current = bone.CFrame
		TweenService:Create(bone, GlideVfxConfigs.Tween.Bone, {
			CFrame = current * spread,
		}):Play()
	end
end

local function disableCapeGlide(character: Model)
	local cape = character:FindFirstChild(GlideVfxConfigs.CapeModelName)
	local cape2 = cape and cape:FindFirstChild(GlideVfxConfigs.CapePartName)
	if not cape2 or not cape2:IsA("BasePart") then
		return
	end

	TweenService:Create(cape2, GlideVfxConfigs.Tween.CapeFadeOut, {
		Transparency = GlideVfxConfigs.Cape.HiddenTransparency,
	}):Play()

	for _, child in cape2:GetChildren() do
		if child:IsA("Texture") then
			TweenService:Create(child, GlideVfxConfigs.Tween.Texture, {
				Transparency = 1,
			}):Play()
		end
	end

	cape2.EnableFluidForces = false

	local initialPoses = cape:FindFirstChild(GlideVfxConfigs.InitialPosesFolderName)
	if initialPoses then
		for _, bone in getAllBones(cape) do
			local boneInitial = initialPoses:FindFirstChild(bone.Name .. "_Initial")
			if boneInitial and boneInitial:IsA("CFrameValue") then
				TweenService:Create(bone, GlideVfxConfigs.Tween.Bone, {
					CFrame = boneInitial.Value,
				}):Play()
			end
		end
	end
end

local function startGlide(character: Model, state: CharacterState, sounds: Folder?)
	ensureGlideTrails(character)
	setTrailsEnabled(character, true)
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

	enableCapeGlide(character)
end

local function stopGlide(character: Model, state: CharacterState, sounds: Folder?)
	setTrailsEnabled(character, false)
	stopFlyLoop(state)

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local woosh = sounds and sounds:FindFirstChild("Woosh")
		if woosh and woosh:IsA("Sound") then
			playOneShot(woosh, hrp, 3)
		end
	end

	disableCapeGlide(character)

	local head = character:FindFirstChild("Head")
	if head then
		local clothing = sounds and sounds:FindFirstChild("Clothing")
		if clothing and clothing:IsA("Sound") then
			playOneShot(clothing, head, 2)
		end
	end
end

function GlideVfx.isGlidePhase(phase: string?): boolean
	if not phase then
		return false
	end
	return GlideVfxConfigs.GlidePhases[phase] == true
end

function GlideVfx.setGlideActive(character: Model?, active: boolean, sounds: Folder?)
	if not GlideVfxConfigs.Enabled or not character then
		return
	end

	local state = getState(character)
	if state.glideActive == active then
		return
	end
	state.glideActive = active

	if active then
		startGlide(character, state, sounds)
	else
		stopGlide(character, state, sounds)
	end
end

function GlideVfx.cleanupCharacter(character: Model)
	local state = characterStates[character]
	if not state then
		return
	end
	if state.glideActive then
		stopGlide(character, state, nil)
	end
	characterStates[character] = nil
end

return GlideVfx
