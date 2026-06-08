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

local function getEyeOrigin(rig: HeatVisionRig): Vector3
	local eyeRight = rig.headPart:FindFirstChild("Attachment")
	local eyeLeft = rig.headPart:FindFirstChild("Attachment1")
	if eyeRight and eyeRight:IsA("Attachment") and eyeLeft and eyeLeft:IsA("Attachment") then
		return (eyeRight.WorldPosition + eyeLeft.WorldPosition) * 0.5
	end
	return rig.headPart.Position
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
	}

	ensureFallbackBeams(rig)
	setEffectsEnabled(clone, false)
	rigs[character] = rig
	return rig
end

function HeatVisionRig.setActive(rig: HeatVisionRig, active: boolean)
	setEffectsEnabled(rig.root, active)
end

function HeatVisionRig.updateAim(rig: HeatVisionRig, lookVector: Vector3, maxRange: number): RaycastResult?
	local direction = flatUnit(lookVector)
	local origin = getEyeOrigin(rig)
	local result = Workspace:Raycast(origin, direction * maxRange, rig.rayParams)
	local endPos = if result then result.Position else origin + direction * maxRange
	rig.endPart.CFrame = CFrame.lookAt(endPos, endPos + direction)
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
