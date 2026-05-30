--!strict

-- Ensures CapePoses/Idle|Walk|Fly|Land exist on the cape rig (client runtime).
-- Studio-authored CapePoses folders override these defaults.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)

local CapePoseBootstrap = {}

local function getBones(rigRoot: Instance): { Bone }
	local bones: { Bone } = {}
	for _, desc in rigRoot:GetDescendants() do
		if desc:IsA("Bone") then
			table.insert(bones, desc)
		end
	end
	return bones
end

local function readIdleCFrame(bone: Bone, rigRoot: Instance): CFrame
	local initialPoses = rigRoot:FindFirstChild(GlideVfxConfigs.InitialPosesFolderName)
	if initialPoses then
		local named = initialPoses:FindFirstChild(bone.Name .. "_Initial")
		if named and named:IsA("CFrameValue") then
			return named.Value
		end
		local plain = initialPoses:FindFirstChild(bone.Name)
		if plain and plain:IsA("CFrameValue") then
			return plain.Value
		end
	end
	return bone.CFrame
end

local function isRootBoneName(name: string): boolean
	for _, rootName in GlideVfxConfigs.RootBoneNames do
		if name == rootName then
			return true
		end
	end
	return false
end

local function writePoseFolder(parent: Folder, stateName: string, bones: { Bone }, rigRoot: Instance, offset: CFrame?)
	local folder = parent:FindFirstChild(stateName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = stateName
		folder.Parent = parent
	end

	for _, bone in bones do
		local existing = folder:FindFirstChild(bone.Name)
		if existing and existing:IsA("CFrameValue") then
			continue
		end
		local target = if offset and isRootBoneName(bone.Name) then offset else CFrame.new()
		local value = Instance.new("CFrameValue")
		value.Name = bone.Name
		value.Value = target
		value.Parent = folder
	end
end

local BOOTSTRAP_VERSION = 4

function CapePoseBootstrap.ensureCapePoses(rigRoot: Instance): Folder
	local existing = rigRoot:FindFirstChild(GlideVfxConfigs.PoseFolderName)
	if existing and existing:IsA("Folder") then
		local version = existing:GetAttribute("_BootstrapVersion")
		if version == BOOTSTRAP_VERSION then
			return existing
		end
		existing:Destroy()
	end

	local bones = getBones(rigRoot)
	if #bones == 0 then
		local empty = Instance.new("Folder")
		empty.Name = GlideVfxConfigs.PoseFolderName
		empty.Parent = rigRoot
		return empty
	end

	local poseRoot = Instance.new("Folder")
	poseRoot.Name = GlideVfxConfigs.PoseFolderName
	poseRoot.Parent = rigRoot

	local states = GlideVfxConfigs.States
	local offsets = GlideVfxConfigs.Cape.FallbackOffsets

	writePoseFolder(poseRoot, states.Idle, bones, rigRoot, nil)
	writePoseFolder(poseRoot, states.Walk, bones, rigRoot, offsets.Walk)
	writePoseFolder(poseRoot, states.Fly, bones, rigRoot, offsets.Fly)
	writePoseFolder(poseRoot, states.Land, bones, rigRoot, offsets.Land)

	poseRoot:SetAttribute("_BootstrapVersion", BOOTSTRAP_VERSION)
	return poseRoot
end

return CapePoseBootstrap
