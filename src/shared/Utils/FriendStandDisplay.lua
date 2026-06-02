--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local Workspace = game:GetService("Workspace")

local FriendStandConfigs = require(script.Parent.Parent.Configs.FriendStandConfigs)
local FriendStandDebug = require(script.Parent.FriendStandDebug)

local STRIP_SCRIPT_NAMES = { "Animate" }

local FriendStandDisplay = {}

local activeRunTracks: { [Model]: AnimationTrack } = {}

local function stripScripts(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end
	for _, name in STRIP_SCRIPT_NAMES do
		local child = root:FindFirstChild(name)
		if child and (child:IsA("Script") or child:IsA("LocalScript")) then
			child:Destroy()
		end
	end
end

local function getRunAnimation(): Animation?
	local folder = ReplicatedStorage:FindFirstChild(FriendStandConfigs.RunAnimFolderName)
	if not folder or not folder:IsA("Folder") then
		FriendStandDebug.warn("missing anim folder", FriendStandConfigs.RunAnimFolderName)
		return nil
	end
	local anim = folder:FindFirstChild(FriendStandConfigs.RunAnimName)
	if anim and anim:IsA("Animation") then
		return anim
	end
	FriendStandDebug.warn("missing anim", FriendStandConfigs.RunAnimName)
	return nil
end

function FriendStandDisplay.createFriendModel(friendId: number): Model?
	local model: Model? = nil

	local descOk, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(friendId)
	end)
	if descOk and description then
		local modelOk, fromDesc = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if modelOk and fromDesc and fromDesc:IsA("Model") then
			model = fromDesc
			FriendStandDebug.log("createFriendModel: from description userId", friendId)
		end
	end

	if not model then
		local userOk, fromUser = pcall(function()
			return Players:CreateHumanoidModelFromUserId(friendId)
		end)
		if userOk and fromUser and fromUser:IsA("Model") then
			model = fromUser
			FriendStandDebug.log("createFriendModel: from userId", friendId)
		else
			FriendStandDebug.warn("createFriendModel: both loaders failed for", friendId, fromUser)
		end
	end

	return model
end

function FriendStandDisplay.stopRunOnModel(model: Model)
	local track = activeRunTracks[model]
	if track then
		pcall(function()
			track:Stop(0.1)
		end)
		activeRunTracks[model] = nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, playing in animator:GetPlayingAnimationTracks() do
			playing:Stop(0.1)
		end
	end
end

function FriendStandDisplay.playRunAnimation(humanoid: Humanoid): AnimationTrack?
	local runAnim = getRunAnimation()
	if not runAnim then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local track = animator:LoadAnimation(runAnim)
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.1)
	track:AdjustWeight(1)

	local parentModel = humanoid.Parent
	if parentModel and parentModel:IsA("Model") then
		activeRunTracks[parentModel] = track
		FriendStandDebug.log("playRunAnimation: playing on", parentModel.Name)
	end
	return track
end

function FriendStandDisplay.waitForRigReady(model: Model, timeout: number?): boolean
	local limit = timeout or FriendStandConfigs.RigReadyTimeout
	local deadline = os.clock() + limit

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	while not humanoid and os.clock() < deadline do
		task.wait(0.05)
		humanoid = model:FindFirstChildOfClass("Humanoid")
	end
	if not humanoid then
		FriendStandDebug.warn("waitForRigReady: no Humanoid")
		return false
	end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	while not hrp and os.clock() < deadline do
		task.wait(0.05)
		hrp = model:FindFirstChild("HumanoidRootPart")
	end
	if not hrp or not hrp:IsA("BasePart") then
		FriendStandDebug.warn("waitForRigReady: no HumanoidRootPart")
		return false
	end

	task.wait(0.25)
	FriendStandDebug.log("waitForRigReady: ok", model.Name, "parts=", #model:GetDescendants())
	return true
end

function FriendStandDisplay.getDisplayParent(standModel: Model): Instance
	if FriendStandConfigs.ParentDisplayToWorkspace then
		return Workspace
	end
	return standModel
end

function FriendStandDisplay.computeShowcaseCFrame(spawnCFrame: CFrame, lookAtWorld: Vector3?): CFrame
	local height = FriendStandConfigs.DisplayHeightOffset
	local pos = spawnCFrame.Position + Vector3.new(0, height, 0)

	local cf: CFrame
	if lookAtWorld then
		local flatTarget = Vector3.new(lookAtWorld.X, pos.Y, lookAtWorld.Z)
		if (flatTarget - pos).Magnitude > 0.05 then
			cf = CFrame.lookAt(pos, flatTarget)
		else
			cf = CFrame.new(pos) * spawnCFrame.Rotation
		end
	else
		cf = CFrame.new(pos) * spawnCFrame.Rotation
	end

	local yaw = math.rad(FriendStandConfigs.DisplayYawOffsetDegrees)
	return cf * CFrame.Angles(0, yaw, 0)
end

function FriendStandDisplay.alignModelFacing(model: Model, spawn: BasePart, lookAtWorld: Vector3?)
	FriendStandDisplay.placeModelOnSpawn(model, spawn, lookAtWorld)
end

function FriendStandDisplay.placeModelOnSpawn(model: Model, spawn: BasePart, lookAtWorld: Vector3?)
	local faceTarget = lookAtWorld
	if faceTarget == nil and FriendStandConfigs.FaceLocalPlayer then
		faceTarget = FriendStandDisplay.getLocalPlayerLookTarget()
	end

	model:PivotTo(FriendStandDisplay.computeShowcaseCFrame(spawn.CFrame, faceTarget))

	local bboxCF, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCF.Position.Y - bboxSize.Y * 0.5
	local spawnTopY = spawn.Position.Y + spawn.Size.Y * 0.5
	local lift = (spawnTopY - bottomY) + FriendStandConfigs.DisplayHeightOffset
	if math.abs(lift) > 0.01 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
end

function FriendStandDisplay.getLocalPlayerLookTarget(): Vector3?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

function FriendStandDisplay.prepareShowcaseModel(
	model: Model,
	spawn: BasePart,
	lookAtWorld: Vector3?,
	displayName: string?
): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		FriendStandDebug.warn("prepareShowcaseModel: no Humanoid")
		return false
	end

	model.Name = displayName or FriendStandConfigs.DisplayModelName

	stripScripts(model)

	local partCount = 0
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			partCount += 1
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.AssemblyLinearVelocity = Vector3.zero
			desc.AssemblyAngularVelocity = Vector3.zero
			if desc.Transparency >= 1 then
				desc.Transparency = 0
			end
		end
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false

	FriendStandDisplay.placeModelOnSpawn(model, spawn, lookAtWorld)
	local cf = model:GetPivot()

	local runTrack = FriendStandDisplay.playRunAnimation(humanoid)
	if runTrack and not runTrack.IsPlaying then
		runTrack:Play(0)
	end
	FriendStandDebug.log(
		"prepareShowcaseModel: done",
		model.Name,
		"at",
		tostring(cf.Position),
		"parts=",
		partCount,
		"run=",
		runTrack ~= nil
	)
	return true
end

function FriendStandDisplay.promptGameInvite(player: Player, friendUserId: number?): (boolean, string?)
	local canInviteOk, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if canInviteOk and canInvite == false then
		return false, "invites_disabled"
	end

	local ok, err = pcall(function()
		if friendUserId and friendUserId > 0 then
			local options = Instance.new("ExperienceInviteOptions")
			options.InviteUser = friendUserId
			options.PromptMessage = "Invite this friend for +700 Speed!"
			SocialService:PromptGameInvite(player, options)
		else
			SocialService:PromptGameInvite(player)
		end
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

function FriendStandDisplay.destroyDisplayIn(root: Instance, displayName: string?)
	local name = displayName or FriendStandConfigs.DisplayModelName
	local existing = root:FindFirstChild(name, true)
	if existing and existing:IsA("Model") then
		FriendStandDisplay.stopRunOnModel(existing)
		existing:Destroy()
	elseif existing then
		existing:Destroy()
	end
end

return FriendStandDisplay
