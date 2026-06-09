--!strict

-- Server-authoritative heat vision rig (replicates to all clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)

export type HeatVisionRig = {
	folder: Folder,
	root: Instance,
	headPart: BasePart,
	endPart: BasePart,
	rayParams: RaycastParams,
	character: Model,
	extraRayExcludes: { Instance },
	beamExtendAlpha: number,
	targetBeamDistance: number,
	aimDirection: Vector3,
}

local HeatVisionRig = {}

local rigs: { [Model]: HeatVisionRig } = {}
local assetsTemplate: Folder? = nil

local BEAM_TUNING: { [string]: { Width0: number, Width1: number, Brightness: number } } = {
	Inner = { Width0 = 0.35, Width1 = 2.5, Brightness = 4 },
	Outer = { Width0 = 0.45, Width1 = 3.5, Brightness = 8 },
	Outer1 = { Width0 = 1.2, Width1 = 8, Brightness = 3 },
}

local RED_BEAM = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 20)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 80)),
})

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

local function getAssetsTemplate(): Folder?
	if assetsTemplate and assetsTemplate.Parent then
		return assetsTemplate
	end
	local folder = resolvePath(ReplicatedStorage, HeatVisionConfigs.AssetsFolder)
	if folder and folder:IsA("Folder") then
		assetsTemplate = folder
		return folder
	end
	warn(
		"[iseesupes][HeatVisionRig] Missing assets at ReplicatedStorage.",
		table.concat(HeatVisionConfigs.AssetsFolder, ".")
	)
	return nil
end

local function rebuildRayFilter(rig: HeatVisionRig)
	local filter: { Instance } = { rig.character, rig.folder }
	for _, inst in rig.extraRayExcludes do
		if inst.Parent then
			table.insert(filter, inst)
		end
	end
	rig.rayParams.FilterDescendantsInstances = filter
end

local function flatUnit(vector: Vector3): Vector3
	if vector.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return vector.Unit
end

local function findHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function rewireBeams(root: Instance)
	local headPart = root:FindFirstChild("HeadPart")
	local endPart = root:FindFirstChild("EndPart")
	if not headPart or not endPart then
		return
	end

	local eyeRight = headPart:FindFirstChild("Attachment")
	local eyeLeft = headPart:FindFirstChild("Attachment1")
	local endRight = endPart:FindFirstChild("Right")
	local endLeft = endPart:FindFirstChild("Left")
	local endCenter = endPart:FindFirstChild("Attachment")

	for _, desc in root:GetDescendants() do
		if not desc:IsA("Beam") then
			continue
		end
		local beam = desc :: Beam
		local parentAtt = beam.Parent
		if not parentAtt or not parentAtt:IsA("Attachment") then
			continue
		end

		beam.Attachment0 = parentAtt
		if parentAtt == eyeRight and endRight and endRight:IsA("Attachment") then
			beam.Attachment1 = endRight
		elseif parentAtt == eyeLeft and endLeft and endLeft:IsA("Attachment") then
			beam.Attachment1 = endLeft
		elseif endCenter and endCenter:IsA("Attachment") then
			beam.Attachment1 = endCenter
		end
	end
end

local function applyBeamTuning(beam: Beam)
	local tuning = BEAM_TUNING[beam.Name]
	if tuning then
		beam.Width0 = tuning.Width0
		beam.Width1 = tuning.Width1
		beam.Brightness = tuning.Brightness
	end
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Enabled = true
	beam.Color = RED_BEAM
end

local function ensureFallbackBeams(rig: HeatVisionRig)
	local headPart = rig.headPart
	local endPart = rig.endPart

	local eyeRight = headPart:FindFirstChild("Attachment")
	local eyeLeft = headPart:FindFirstChild("Attachment1")
	local endCenter = endPart:FindFirstChild("Attachment")
	if not endCenter or not endCenter:IsA("Attachment") then
		endCenter = Instance.new("Attachment")
		endCenter.Name = "HvEndCenter"
		endCenter.Parent = endPart
	end

	local function ensureBeam(name: string, att0: Attachment, att1: Attachment): Beam
		local existing = att0:FindFirstChild(name)
		if existing and existing:IsA("Beam") then
			existing.Attachment0 = att0
			existing.Attachment1 = att1
			applyBeamTuning(existing)
			return existing
		end
		local beam = Instance.new("Beam")
		beam.Name = name
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Texture = "rbxassetid://446111271"
		beam.TextureLength = 20
		beam.TextureSpeed = 5
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Color = RED_BEAM
		applyBeamTuning(beam)
		beam.Parent = att0
		return beam
	end

	if eyeRight and eyeRight:IsA("Attachment") and endCenter:IsA("Attachment") then
		ensureBeam("_HvBeamR", eyeRight, endCenter)
	end
	if eyeLeft and eyeLeft:IsA("Attachment") and endCenter:IsA("Attachment") then
		ensureBeam("_HvBeamL", eyeLeft, endCenter)
	end
end

local function setEffectsEnabled(root: Instance, enabled: boolean)
	for _, desc in root:GetDescendants() do
		if desc:IsA("Beam") then
			local beam = desc :: Beam
			if enabled then
				applyBeamTuning(beam)
			else
				beam.Enabled = false
			end
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
			desc.Enabled = enabled
		elseif desc:IsA("PointLight") or desc:IsA("SurfaceLight") or desc:IsA("SpotLight") then
			desc.Enabled = enabled
		elseif desc:IsA("Sound") then
			if enabled then
				if not desc.IsPlaying then
					desc:Play()
				end
			else
				desc:Stop()
			end
		end
	end
end

local function getBeamExtendConfig()
	local cfg = HeatVisionConfigs.BeamExtend
	if type(cfg) ~= "table" then
		return {
			Duration = 0.55,
			DurationPerStud = 0.0035,
			MinDuration = 0.45,
			MaxDuration = 1.15,
			StartLength = 0.12,
			Ease = "InOutCubic",
		}
	end
	return cfg
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function easeInOutCubic(t: number): number
	if t < 0.5 then
		return 4 * t * t * t
	end
	return 1 - (-2 * t + 2) ^ 3 / 2
end

local function easeOutExpo(t: number): number
	if t >= 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * t)
end

local function applyBeamExtendEase(alpha: number, easeName: string?): number
	local t = math.clamp(alpha, 0, 1)
	if easeName == "OutExpo" then
		return easeOutExpo(t)
	elseif easeName == "OutQuad" then
		return easeOutQuad(t)
	end
	return easeInOutCubic(t)
end

local function computeBeamExtendDuration(cfg: any, targetDistance: number): number
	local base = if type(cfg.Duration) == "number" then cfg.Duration else 0.55
	local perStud = if type(cfg.DurationPerStud) == "number" then cfg.DurationPerStud else 0.0035
	local minDur = if type(cfg.MinDuration) == "number" then cfg.MinDuration else 0.45
	local maxDur = if type(cfg.MaxDuration) == "number" then cfg.MaxDuration else 1.15
	return math.clamp(base + targetDistance * perStud, minDur, maxDur)
end

local function getEyeOrigin(rig: HeatVisionRig): Vector3
	local eyeRight = rig.headPart:FindFirstChild("Attachment")
	local eyeLeft = rig.headPart:FindFirstChild("Attachment1")
	if eyeRight and eyeRight:IsA("Attachment") and eyeLeft and eyeLeft:IsA("Attachment") then
		return (eyeRight.WorldPosition + eyeLeft.WorldPosition) * 0.5
	end
	return rig.headPart.Position
end

local function placeEndPartAtDistance(rig: HeatVisionRig, distance: number)
	local origin = getEyeOrigin(rig)
	local direction = rig.aimDirection
	local endPos = origin + direction * distance
	rig.endPart.CFrame = CFrame.lookAt(endPos, endPos + direction)
end

function HeatVisionRig.resetBeamExtend(rig: HeatVisionRig)
	local cfg = getBeamExtendConfig()
	local startLen = if type(cfg.StartLength) == "number" then cfg.StartLength else 0.35
	rig.beamExtendAlpha = 0
	rig.targetBeamDistance = startLen
	rig.aimDirection = rig.headPart.CFrame.LookVector
	placeEndPartAtDistance(rig, startLen)
end

function HeatVisionRig.get(character: Model): HeatVisionRig?
	return rigs[character]
end

function HeatVisionRig.mount(character: Model): HeatVisionRig?
	if rigs[character] then
		return rigs[character]
	end

	local template = getAssetsTemplate()
	if not template then
		return nil
	end

	local head = findHead(character)
	if not head then
		warn("[iseesupes][HeatVisionRig] Character has no Head:", character.Name)
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "HeatVisionRig"
	folder.Parent = character

	local clone = template:Clone()
	clone.Name = "SupermanHeatVision"
	clone.Parent = folder
	rewireBeams(clone)

	local headPart = clone:FindFirstChild("HeadPart")
	local endPart = clone:FindFirstChild("EndPart")
	if not headPart or not headPart:IsA("BasePart") or not endPart or not endPart:IsA("BasePart") then
		folder:Destroy()
		warn("[iseesupes][HeatVisionRig] HeadPart/EndPart missing in assets")
		return nil
	end

	headPart.Anchored = false
	headPart.CanCollide = false
	headPart.CanQuery = false
	headPart.CanTouch = false
	headPart.Massless = true
	headPart.CFrame = head.CFrame * HeatVisionConfigs.HeadWeldOffset

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = headPart
	weld.Parent = headPart

	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, folder }

	local rig: HeatVisionRig = {
		folder = folder,
		root = clone,
		headPart = headPart,
		endPart = endPart,
		rayParams = rayParams,
		character = character,
		extraRayExcludes = {},
		beamExtendAlpha = 0,
		targetBeamDistance = 0.35,
		aimDirection = head.CFrame.LookVector,
	}

	ensureFallbackBeams(rig)
	setEffectsEnabled(clone, false)
	HeatVisionRig.resetBeamExtend(rig)
	rigs[character] = rig
	return rig
end

function HeatVisionRig.addRayExclude(rig: HeatVisionRig, instance: Instance)
	for _, existing in rig.extraRayExcludes do
		if existing == instance then
			return
		end
	end
	table.insert(rig.extraRayExcludes, instance)
	rebuildRayFilter(rig)
end

function HeatVisionRig.clearRayExcludes(rig: HeatVisionRig)
	table.clear(rig.extraRayExcludes)
	rebuildRayFilter(rig)
end

function HeatVisionRig.setRayExcludes(rig: HeatVisionRig, instances: { Instance })
	table.clear(rig.extraRayExcludes)
	for _, inst in instances do
		if inst.Parent then
			table.insert(rig.extraRayExcludes, inst)
		end
	end
	rebuildRayFilter(rig)
end

function HeatVisionRig.setActive(rig: HeatVisionRig, active: boolean)
	setEffectsEnabled(rig.root, active)
	if active then
		HeatVisionRig.resetBeamExtend(rig)
	end
end

function HeatVisionRig.updateAim(rig: HeatVisionRig, lookVector: Vector3, maxRange: number, dt: number?): RaycastResult?
	local direction = flatUnit(lookVector)
	rig.aimDirection = direction
	local origin = getEyeOrigin(rig)
	local result = Workspace:Raycast(origin, direction * maxRange, rig.rayParams)
	local fullDist = if result then (result.Position - origin).Magnitude else maxRange
	rig.targetBeamDistance = math.max(fullDist, 0.01)

	if dt and dt > 0 then
		local cfg = getBeamExtendConfig()
		local duration = computeBeamExtendDuration(cfg, rig.targetBeamDistance)
		rig.beamExtendAlpha = math.min(1, rig.beamExtendAlpha + dt / duration)
	end

	local cfg = getBeamExtendConfig()
	local startLen = if type(cfg.StartLength) == "number" then cfg.StartLength else 0.12
	local easeName = if type(cfg.Ease) == "string" then cfg.Ease else "InOutCubic"
	local t = applyBeamExtendEase(rig.beamExtendAlpha, easeName)
	local visualDist = startLen + (rig.targetBeamDistance - startLen) * t
	visualDist = math.clamp(visualDist, startLen, rig.targetBeamDistance)

	placeEndPartAtDistance(rig, visualDist)
	return result
end

function HeatVisionRig.destroy(character: Model)
	local rig = rigs[character]
	if not rig then
		return
	end
	rigs[character] = nil
	if rig.folder.Parent then
		rig.folder:Destroy()
	end
end

return HeatVisionRig
