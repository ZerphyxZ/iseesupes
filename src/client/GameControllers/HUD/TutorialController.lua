--!strict

-- Tutorial hints: fly/laser callouts, thrust shop intro (foot beam optional via TutorialConfigs.FootBeam).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local TutorialWorld = require(ReplicatedStorage.Shared.Utils.TutorialWorld)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
local TutorialFlyHint = require(script.Parent.Parent.Parent.Modules.TutorialFlyHint)
local TutorialLaserHint = require(script.Parent.Parent.Parent.Modules.TutorialLaserHint)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)

local TutorialController = Knit.CreateController({ Name = "TutorialController" })

local player = Players.LocalPlayer

local beamFolder: Folder? = nil
local playerAttachment: Attachment? = nil
local targetAttachment: Attachment? = nil
local beamInstance: Beam? = nil
local beamTargetPart: BasePart? = nil
local billboard: BillboardGui? = nil
local heartbeatConn: RBXScriptConnection? = nil
local retryThread: thread? = nil
local activeStep = 0
local thrustHintBeamUntil = 0
local thrustHintTriggered = false
--- Per-session: tiers whose "affordable" reminder beam has already shown.
local affordableThrustHintTiers: { [number]: boolean } = {}
local thrustShopIntroTriggered = false
local thrustShopHighlight: Highlight? = nil
local stage1TouchConns: { RBXScriptConnection } = {}
local stage1ProximityConn: RBXScriptConnection? = nil
local stage1FlyUiShown = false
local lastStage1FlyTriggerAt = -math.huge
local laserHintBrokenConn: RBXScriptConnection? = nil
local lastSyncedTutorialStep: number? = nil
local attachBeamToStage1Wall: () -> ()

local STAGE1_GATE_NUM = 1

local function isFootBeamEnabled(): boolean
	local footBeam = TutorialConfigs.FootBeam
	return footBeam ~= nil and footBeam.Enabled == true
end

local function isStage1HintActive(): boolean
	return TutorialFlyHint.isActive() or TutorialLaserHint.isActive()
end

local function getTutorialStep(data: any): number
	if not data or type(data.TutorialStep) ~= "number" then
		return TutorialConfigs.Step.GoTreadmill
	end
	return math.clamp(math.floor(data.TutorialStep), TutorialConfigs.Step.GoTreadmill, TutorialConfigs.Step.Complete)
end

local function isTutorialFullyComplete(data: any): boolean
	if not data then
		return false
	end
	return getTutorialStep(data) >= TutorialConfigs.Step.Complete
end

local function shouldOfferStage1FlyLesson(data: any): boolean
	if not data or data.TutorialFlyIntroShown == true then
		return false
	end
	local step = getTutorialStep(data)
	return step >= TutorialConfigs.Step.CoreDone and step < TutorialConfigs.Step.Complete
end

local function destroyBeamVisuals()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if beamInstance then
		beamInstance:Destroy()
		beamInstance = nil
	end
	beamTargetPart = nil
	if targetAttachment then
		targetAttachment:Destroy()
		targetAttachment = nil
	end
	if playerAttachment then
		playerAttachment:Destroy()
		playerAttachment = nil
	end
	if billboard then
		billboard:Destroy()
		billboard = nil
	end
	if beamFolder then
		beamFolder:Destroy()
		beamFolder = nil
	end
end

local function getHrp(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function disconnectStage1Listeners()
	for _, conn in stage1TouchConns do
		conn:Disconnect()
	end
	table.clear(stage1TouchConns)
	if stage1ProximityConn then
		stage1ProximityConn:Disconnect()
		stage1ProximityConn = nil
	end
end

local function shouldUseLaserWallLesson(): boolean
	if TutorialConfigs.LaserIntro.Enabled == false then
		return false
	end
	if CharacterConfigs.Features.UseHeatVision == false then
		return false
	end
	return true
end

local function isStage1WallUnbroken(): boolean
	if not shouldUseLaserWallLesson() then
		return false
	end
	local nextMeltGate: number? = nil
	pcall(function()
		nextMeltGate = Knit.GetController("StageCheckpointController"):GetNextMeltGateStage()
	end)
	return nextMeltGate == STAGE1_GATE_NUM
end

--- Foot beam to Stage 1: laser wall lesson OR post-core path when laser is disabled.
local function shouldBeamTargetStage1(data: any): boolean
	if not data or data.TutorialFlyIntroShown == true then
		return false
	end
	if not shouldOfferStage1FlyLesson(data) then
		return false
	end
	if shouldUseLaserWallLesson() then
		return isStage1WallUnbroken()
	end
	return getTutorialStep(data) >= TutorialConfigs.Step.CoreDone
end

local function resolveBeamStep(data: any): number
	if not isFootBeamEnabled() then
		return TutorialConfigs.Step.CoreDone
	end
	local step = getTutorialStep(data)
	if shouldBeamTargetStage1(data) then
		return TutorialConfigs.Step.GoStage1
	end
	return step
end

local function showStage1FlyIntro()
	destroyBeamVisuals()
	if not TutorialFlyHint.showMainIntro() then
		stage1FlyUiShown = false
		if TutorialConfigs.Debug then
			warn("[iseesupes][Tutorial] Stage1 fly hint could not show (SupesMobile missing?)")
		end
	end
end

local function disconnectLaserHintBrokenListener()
	if laserHintBrokenConn then
		laserHintBrokenConn:Disconnect()
		laserHintBrokenConn = nil
	end
end

--- Laser hint stays up until the Stage 1 wall is melted, then the fly intro takes over.
local function showStage1LaserHintUntilWallBroken(): boolean
	if not TutorialLaserHint.show() then
		return false
	end

	attachBeamToStage1Wall()

	disconnectLaserHintBrokenListener()
	local service = Knit.GetService("StageCheckpointService")
	laserHintBrokenConn = service.CheckpointBroken:Connect(function(stageNum: number)
		if stageNum ~= STAGE1_GATE_NUM then
			return
		end
		disconnectLaserHintBrokenListener()
		TutorialLaserHint.hide()
		showStage1FlyIntro()
	end)
	return true
end

local function triggerStage1FlyLesson()
	if stage1FlyUiShown or isStage1HintActive() then
		return
	end
	local debounce = TutorialConfigs.Stage1TouchDebounceSeconds or 2
	local now = os.clock()
	if now - lastStage1FlyTriggerAt < debounce then
		return
	end

	local data = DataLib.GetData()
	if not shouldOfferStage1FlyLesson(data) then
		return
	end

	lastStage1FlyTriggerAt = now
	stage1FlyUiShown = true
	disconnectStage1Listeners()

	task.spawn(function()
		if isStage1WallUnbroken() and showStage1LaserHintUntilWallBroken() then
			return
		end

		showStage1FlyIntro()
	end)
end

local function isLocalPlayerTouch(hit: Instance): boolean
	local character = player.Character
	if not character then
		return false
	end
	if hit:IsDescendantOf(character) then
		return true
	end
	local touchModel = hit:FindFirstAncestorOfClass("Model")
	return touchModel ~= nil and Players:GetPlayerFromCharacter(touchModel) == player
end

local function onStage1CheckpointTouched(hit: BasePart)
	if not isLocalPlayerTouch(hit) then
		return
	end
	triggerStage1FlyLesson()
end

local function isPlayerNearStage1(parts: { BasePart }): boolean
	local hrp = getHrp()
	if not hrp then
		return false
	end
	local radius = TutorialConfigs.Stage1ProximityRadius or 16
	local hrpPos = hrp.Position
	for _, part in parts do
		if part.Parent then
			local closest = part:GetClosestPointOnSurface(hrpPos)
			if (closest - hrpPos).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

local function startStage1ProximityCheck()
	if stage1ProximityConn then
		return
	end
	stage1ProximityConn = RunService.Heartbeat:Connect(function()
		if stage1FlyUiShown or isStage1HintActive() then
			return
		end
		local data = DataLib.GetData()
		if not shouldOfferStage1FlyLesson(data) then
			return
		end
		local parts = TutorialWorld.getStage1TouchParts()
		if #parts == 0 then
			return
		end
		if isPlayerNearStage1(parts) then
			triggerStage1FlyLesson()
		end
	end)
end

local function bindStage1TouchListener()
	if #stage1TouchConns > 0 then
		return
	end
	local parts = TutorialWorld.getStage1TouchParts()
	if #parts == 0 then
		task.delay(1, bindStage1TouchListener)
		return
	end
	for _, part in parts do
		part.CanTouch = true
		table.insert(stage1TouchConns, part.Touched:Connect(onStage1CheckpointTouched))
	end
	startStage1ProximityCheck()
	if TutorialConfigs.Debug then
		print("[iseesupes][Tutorial] Stage1 touch wired on", #parts, "parts")
	end
end

local function ensureStage1FlyListeners()
	if stage1FlyUiShown or isStage1HintActive() then
		return
	end
	local data = DataLib.GetData()
	if not shouldOfferStage1FlyLesson(data) then
		return
	end
	bindStage1TouchListener()
end

local function ensureBeamFolder(): Folder
	if beamFolder and beamFolder.Parent then
		return beamFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "TutorialBeam"
	folder.Parent = player:WaitForChild("PlayerGui")
	beamFolder = folder
	return folder
end

local function destroyThrustShopHighlight()
	if thrustShopHighlight then
		thrustShopHighlight:Destroy()
		thrustShopHighlight = nil
	end
end

local function waitUntilGrounded(timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		local character = player.Character
		local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.FloorMaterial ~= Enum.Material.Air then
			return true
		end
		task.wait(0.1)
	end
	return getHrp() ~= nil
end

local function releasePlayerCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	camera.CameraType = Enum.CameraType.Custom
	if hum then
		camera.CameraSubject = hum
	end
end

local function tweenCameraTowardShop(shopWorldPos: Vector3, introCfg: any)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local released = false
	local function releaseCutsceneCamera()
		if released then
			return
		end
		released = true
		releasePlayerCamera()
	end

	local hrp = getHrp()
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not hrp or not hum then
		releaseCutsceneCamera()
		return
	end

	local ok, err = pcall(function()
		local lookFrom = hrp.Position + Vector3.new(0, 3, 0)
		local targetCF = CFrame.lookAt(lookFrom, shopWorldPos)
		local tweenIn = TweenInfo.new(introCfg.CameraTweenSeconds or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tweenOut = TweenInfo.new(introCfg.CameraTweenSeconds or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame

		local tweenToShop = TweenService:Create(camera, tweenIn, { CFrame = targetCF })
		tweenToShop:Play()
		tweenToShop.Completed:Wait()
		task.wait(introCfg.CameraHoldSeconds or 1.2)

		local freshHrp = getHrp()
		if freshHrp then
			lookFrom = freshHrp.Position + Vector3.new(0, 3, 0)
			local backCF = CFrame.lookAt(lookFrom, lookFrom + freshHrp.CFrame.LookVector)
			local tweenBack = TweenService:Create(camera, tweenOut, { CFrame = backCF })
			tweenBack:Play()
			tweenBack.Completed:Wait()
		end
	end)

	releaseCutsceneCamera()
	if not ok and TutorialConfigs.Debug then
		warn("[iseesupes][Tutorial] thrust shop camera:", err)
	end
end

local function applyThrustShopHighlight(introCfg: any)
	destroyThrustShopHighlight()

	local adornee: Instance? = TutorialWorld.getThrustShopHighlightModel()
	if not adornee then
		local touch = TutorialWorld.getThrustShopTouch()
		if touch then
			adornee = touch.Parent
		end
	end
	if not adornee then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ThrustShopIntroHighlight"
	highlight.FillColor = introCfg.HighlightFillColor or Color3.fromRGB(255, 180, 0)
	highlight.OutlineColor = introCfg.HighlightOutlineColor or Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = introCfg.HighlightFillTransparency or 0.5
	highlight.OutlineTransparency = introCfg.HighlightOutlineTransparency or 0.2
	highlight.Adornee = adornee
	highlight.Parent = player:WaitForChild("PlayerGui")
	thrustShopHighlight = highlight
end

local function setBeamBillboardMessage(target: BasePart, message: string)
	if billboard then
		billboard:Destroy()
		billboard = nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "TutorialHint"
	gui.Size = UDim2.new(0, 240, 0, 48)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.Adornee = target
	gui.Parent = ensureBeamFolder()
	billboard = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
end

local function updateBillboard(target: BasePart, step: number)
	if billboard then
		billboard:Destroy()
		billboard = nil
	end

	local message = TutorialConfigs.StepMessages[step]
	if not message or message == "" then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "TutorialHint"
	gui.Size = UDim2.new(0, 220, 0, 48)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.Adornee = target
	gui.Parent = ensureBeamFolder()
	billboard = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
end

local function getAttachmentTilt(beamCfg: any): CFrame
	if typeof(beamCfg.AttachmentTilt) == "CFrame" then
		return beamCfg.AttachmentTilt
	end
	local deg = beamCfg.AttachmentTiltDegrees or { X = 90, Y = 0, Z = 90 }
	return CFrame.Angles(math.rad(deg.X), math.rad(deg.Y), math.rad(deg.Z))
end

local function getTargetFloorLocalY(target: BasePart, beamCfg: any): number
	return -target.Size.Y * 0.5 + (beamCfg.TargetSurfaceLift or 0.2)
end

local function getBeamWorldEndpoints(hrp: BasePart, target: BasePart, beamCfg: any): (Vector3, Vector3, number)
	local targetY = getTargetFloorLocalY(target, beamCfg)
	local fromWorld = hrp.CFrame:PointToWorldSpace(beamCfg.FootOffset)
	local toWorld = target.CFrame:PointToWorldSpace(Vector3.new(0, targetY, 0))
	return fromWorld, toWorld, targetY
end

local function floorPathAttachmentCFrame(
	part: BasePart,
	localPosition: Vector3,
	fromWorld: Vector3,
	toWorld: Vector3,
	tilt: CFrame,
	yawOffsetRad: number
): CFrame
	local worldPos = part.CFrame:PointToWorldSpace(localPosition)
	local flat = Vector3.new(toWorld.X - fromWorld.X, 0, toWorld.Z - fromWorld.Z)
	local worldCF: CFrame
	if flat.Magnitude > 1e-3 then
		worldCF = CFrame.lookAt(worldPos, worldPos + flat.Unit)
	else
		worldCF = CFrame.new(worldPos) * (part.CFrame - part.CFrame.Position)
	end
	if yawOffsetRad ~= 0 then
		worldCF = worldCF * CFrame.Angles(0, yawOffsetRad, 0)
	end
	worldCF = worldCF * tilt
	return part.CFrame:ToObjectSpace(worldCF)
end

local function updateBeamAttachmentRotations()
	if not playerAttachment or not targetAttachment or not beamTargetPart then
		return
	end
	local hrp = getHrp()
	local target = beamTargetPart
	if not hrp or not target.Parent then
		return
	end

	local beamCfg = TutorialConfigs.Beam
	local tilt = getAttachmentTilt(beamCfg)
	local yawOffset = math.rad(beamCfg.AttachmentYawOffsetDegrees or 0)
	local fromWorld, toWorld, targetY = getBeamWorldEndpoints(hrp, target, beamCfg)

	playerAttachment.CFrame = floorPathAttachmentCFrame(
		hrp,
		beamCfg.FootOffset,
		fromWorld,
		toWorld,
		tilt,
		yawOffset
	)
	targetAttachment.CFrame = floorPathAttachmentCFrame(
		target,
		Vector3.new(0, targetY, 0),
		fromWorld,
		toWorld,
		tilt,
		yawOffset
	)
end

local function startBeamRotationLoop()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(updateBeamAttachmentRotations)
end

local function attachBeamToTarget(target: BasePart, step: number, billboardMessage: string?)
	if not isFootBeamEnabled() then
		return
	end
	destroyBeamVisuals()

	local hrp = getHrp()
	if not hrp then
		return
	end

	local beamCfg = TutorialConfigs.Beam
	beamTargetPart = target

	local pAttach = Instance.new("Attachment")
	pAttach.Name = "TutorialPlayerAttach"
	pAttach.Parent = hrp
	playerAttachment = pAttach

	local tAttach = Instance.new("Attachment")
	tAttach.Name = "TutorialTargetAttach"
	tAttach.Parent = target
	targetAttachment = tAttach

	updateBeamAttachmentRotations()
	startBeamRotationLoop()

	local beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Attachment0 = pAttach
	beam.Attachment1 = tAttach
	beam.Width0 = beamCfg.Width0
	beam.Width1 = beamCfg.Width1
	beam.Color = ColorSequence.new(beamCfg.Color)
	beam.Texture = beamCfg.Texture or ""
	beam.TextureLength = beamCfg.TextureLength or 4
	beam.TextureSpeed = beamCfg.TextureSpeed or 2
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.LightEmission = beamCfg.LightEmission
	beam.LightInfluence = beamCfg.LightInfluence
	beam.Transparency = beamCfg.Transparency
	if beamCfg.FaceCamera ~= nil then
		beam.FaceCamera = beamCfg.FaceCamera
	else
		beam.FaceCamera = false
	end
	beam.Enabled = true
	beam.Segments = 1
	-- Must live under a 3D instance (not PlayerGui) or the beam will not render.
	beam.Parent = hrp
	beamInstance = beam

	if typeof(billboardMessage) == "string" and billboardMessage ~= "" then
		setBeamBillboardMessage(target, billboardMessage)
	elseif step > 0 then
		updateBillboard(target, step)
	end

	if TutorialConfigs.Debug then
		print("[iseesupes][Tutorial] Beam active step", step, "→", target:GetFullName())
	end
end

local function showBeamForStep(step: number)
	if not isFootBeamEnabled() then
		destroyBeamVisuals()
		activeStep = step
		return
	end
	if step == TutorialConfigs.Step.CoreDone or step >= TutorialConfigs.Step.Complete then
		destroyBeamVisuals()
		activeStep = step
		return
	end

	activeStep = step

	task.spawn(function()
		local target = TutorialWorld.waitForTarget(step, TutorialConfigs.WorldResolveTimeout)
		if activeStep ~= step then
			return
		end
		if not target then
			NotificationManager.show("Tutorial target not found in Map (step " .. tostring(step) .. ")", "Info")
			return
		end
		if getHrp() then
			attachBeamToTarget(target, step, nil)
		else
			local character = player.Character or player.CharacterAdded:Wait()
			character:WaitForChild("HumanoidRootPart", 15)
			if activeStep == step and getHrp() then
				attachBeamToTarget(target, step, nil)
			end
		end
	end)
end

local function cancelRetry()
	if retryThread then
		task.cancel(retryThread)
		retryThread = nil
	end
end

local function scheduleTargetRetry(step: number)
	cancelRetry()
	if step == TutorialConfigs.Step.CoreDone or step >= TutorialConfigs.Step.Complete then
		return
	end
	retryThread = task.spawn(function()
		while activeStep == step and step ~= TutorialConfigs.Step.CoreDone and step < TutorialConfigs.Step.Complete do
			task.wait(TutorialConfigs.TargetRetrySeconds)
			if activeStep ~= step then
				break
			end
			local target = TutorialWorld.getTargetForStep(step)
			if target and not beamInstance then
				attachBeamToTarget(target, step, nil)
			elseif target and beamInstance and billboard then
				billboard.Adornee = target
			end
		end
	end)
end

attachBeamToStage1Wall = function()
	if not isFootBeamEnabled() then
		return
	end
	local target = TutorialWorld.getStage1CheckpointTarget()
	if not target then
		target = TutorialWorld.waitForTarget(TutorialConfigs.Step.GoStage1, 8)
	end
	if target and getHrp() then
		attachBeamToTarget(target, TutorialConfigs.Step.GoStage1, nil)
		scheduleTargetRetry(TutorialConfigs.Step.GoStage1)
	end
end

local function waitForThrustShopTouch(timeoutSeconds: number): BasePart?
	local deadline = os.clock() + timeoutSeconds
	local target = TutorialWorld.getThrustShopTouch()
	while not target and os.clock() < deadline do
		task.wait(0.2)
		target = TutorialWorld.getThrustShopTouch()
	end
	return target
end

local function playThrustShopIntro()
	local introCfg = TutorialConfigs.ThrustShopIntro
	if not introCfg or introCfg.Enabled ~= true then
		return
	end

	local target = waitForThrustShopTouch(8)
	if not target or not getHrp() then
		if TutorialConfigs.Debug then
			warn("[iseesupes][Tutorial] Thrust shop intro skipped - no UpgradeShop touch")
		end
		return
	end

	local DataService = Knit.GetService("DataService")
	pcall(function()
		DataService:MarkTutorialThrustShopIntroShown()
	end)

	waitUntilGrounded(introCfg.GroundedWaitTimeoutSeconds or 5)
	task.wait(0.35)

	local toastText = introCfg.ToastMessage or "Behind you: Upgrade Shop - spend wins later to boost thrust"
	NotificationManager.show(toastText, "Info")
	applyThrustShopHighlight(introCfg)

	local shopPos = target.Position
	tweenCameraTowardShop(shopPos, introCfg)

	local beamSeconds = introCfg.BeamDurationSeconds or 0
	local beamMessage = introCfg.BeamBillboardMessage or "Upgrade thrust here!"
	if getHrp() and beamSeconds > 0 and isFootBeamEnabled() then
		thrustHintBeamUntil = os.clock() + beamSeconds
		attachBeamToTarget(target, 0, beamMessage)
		task.delay(beamSeconds, function()
			thrustHintBeamUntil = 0
			destroyBeamVisuals()
		end)
	end

	destroyThrustShopHighlight()
	releasePlayerCamera()

	local DataServiceAdvance = Knit.GetService("DataService")
	pcall(function()
		DataServiceAdvance:AdvanceTutorialCompleteFromCoreDone()
	end)

	if TutorialConfigs.Debug then
		print("[iseesupes][Tutorial] Thrust shop intro played, tutorial complete")
	end
end

local function tryThrustShopIntro(data: any)
	if not data then
		return
	end
	if getTutorialStep(data) ~= TutorialConfigs.Step.CoreDone then
		return
	end
	if data.TutorialThrustShopIntroShown == true or thrustShopIntroTriggered then
		return
	end

	local introCfg = TutorialConfigs.ThrustShopIntro
	if not introCfg or introCfg.Enabled ~= true then
		pcall(function()
			local DataService = Knit.GetService("DataService")
			DataService:AdvanceTutorialCompleteFromCoreDone()
		end)
		return
	end

	thrustShopIntroTriggered = true
	task.spawn(playThrustShopIntro)
end

local function tryThrustShopHint(data: any)
	if not data then
		return
	end
	if not isTutorialFullyComplete(data) then
		return
	end
	if data.TutorialThrustHintShown == true or thrustHintTriggered then
		return
	end
	thrustHintTriggered = true

	local wins = if type(data.Wins) == "number" then data.Wins else 0
	local tier = if type(data.ThrustUpgradeTier) == "number" then data.ThrustUpgradeTier else 0
	if wins < TutorialConfigs.ThrustHintMinWins or tier > 0 then
		return
	end

	local tier1 = ThrustUpgradeConfigs.Tiers[1]
	local minWins = if tier1 then tier1.WinCost else TutorialConfigs.ThrustHintMinWins
	if wins < minWins then
		return
	end

	-- The one-time hint covers pack 1; skip the recurring reminder this session.
	affordableThrustHintTiers[1] = true

	local introCfg = TutorialConfigs.ThrustShopIntro
	local DataService = Knit.GetService("DataService")
	pcall(function()
		DataService:MarkTutorialThrustHintShown()
	end)

	if data.TutorialThrustShopIntroShown == true then
		local purchaseToast = "You have enough wins - upgrade thrust at the shop behind spawn!"
		if introCfg and introCfg.PurchaseHintToast then
			purchaseToast = introCfg.PurchaseHintToast
		end
		NotificationManager.show(purchaseToast, "Info")
		local shortBeam = 0
		if introCfg and introCfg.PurchaseHintBeamSeconds then
			shortBeam = introCfg.PurchaseHintBeamSeconds
		end
		if shortBeam and shortBeam > 0 and isFootBeamEnabled() then
			local target = waitForThrustShopTouch(4)
			if target and getHrp() then
				thrustHintBeamUntil = os.clock() + shortBeam
				local beamLabel = "Upgrade thrust here!"
				if introCfg and introCfg.BeamBillboardMessage then
					beamLabel = introCfg.BeamBillboardMessage
				end
				attachBeamToTarget(target, 0, beamLabel)
				task.delay(shortBeam, function()
					thrustHintBeamUntil = 0
					destroyBeamVisuals()
				end)
			end
		end
		return
	end

	NotificationManager.show(
		"You have enough wins - visit the Upgrade Shop to boost thrust!",
		"Info"
	)

end

--- Reminder beam when the first thrust pack is affordable. Only for players who
--- never bought a pack (tier 0) and at most once per session — once they have
--- upgraded, they know the shop and no more reminders show.
local function tryThrustAffordableBeam(data: any)
	if not isFootBeamEnabled() then
		return
	end
	if os.clock() < thrustHintBeamUntil then
		return
	end

	local tier = if type(data.ThrustUpgradeTier) == "number" then math.floor(data.ThrustUpgradeTier) else 0
	if tier > 0 then
		return
	end
	local nextCfg = ThrustUpgradeConfigs.Tiers[1]
	if not nextCfg then
		return
	end
	if affordableThrustHintTiers[1] then
		return
	end

	local wins = if type(data.Wins) == "number" then math.floor(data.Wins) else 0
	if wins < nextCfg.WinCost then
		return
	end
	affordableThrustHintTiers[1] = true

	local introCfg = TutorialConfigs.ThrustShopIntro
	local toast = "You have enough wins - upgrade thrust at the shop behind spawn!"
	if introCfg and introCfg.PurchaseHintToast then
		toast = introCfg.PurchaseHintToast
	end
	NotificationManager.show(toast, "Info")

	local beamSeconds = 12
	if introCfg and type(introCfg.AffordableBeamSeconds) == "number" then
		beamSeconds = introCfg.AffordableBeamSeconds
	end

	local target = waitForThrustShopTouch(4)
	if not target or not getHrp() then
		return
	end

	thrustHintBeamUntil = os.clock() + beamSeconds
	local beamMessage = "Upgrade thrust here!"
	if introCfg and introCfg.BeamBillboardMessage then
		beamMessage = introCfg.BeamBillboardMessage
	end
	attachBeamToTarget(target, 0, beamMessage)
	task.delay(beamSeconds, function()
		thrustHintBeamUntil = 0
		destroyBeamVisuals()
	end)
end

local function resetTutorialSessionState()
	thrustShopIntroTriggered = false
	thrustHintTriggered = false
	stage1FlyUiShown = false
	activeStep = 0
	thrustHintBeamUntil = 0
	table.clear(affordableThrustHintTiers)
	cancelRetry()
	disconnectStage1Listeners()
	disconnectLaserHintBrokenListener()
	TutorialLaserHint.hide()
	destroyBeamVisuals()
end

local function syncTutorialFromData(data: any?)
	if not data then
		return
	end

	if not shouldUseLaserWallLesson() then
		TutorialLaserHint.hide()
		disconnectLaserHintBrokenListener()
	end

	local step = getTutorialStep(data)
	if lastSyncedTutorialStep ~= nil and step < lastSyncedTutorialStep then
		resetTutorialSessionState()
	end
	lastSyncedTutorialStep = step

	if os.clock() < thrustHintBeamUntil and step >= TutorialConfigs.Step.CoreDone then
		return
	end

	if isTutorialFullyComplete(data) then
		stage1FlyUiShown = false
		cancelRetry()
		disconnectStage1Listeners()
		destroyBeamVisuals()
		activeStep = TutorialConfigs.Step.Complete
		tryThrustShopHint(data)
		tryThrustAffordableBeam(data)
		TutorialFlyHint.startLowThrustWatcher()
		return
	end

	if shouldOfferStage1FlyLesson(data) and step >= TutorialConfigs.Step.Complete then
		ensureStage1FlyListeners()
		return
	end

	if step == TutorialConfigs.Step.CoreDone then
		cancelRetry()
		activeStep = TutorialConfigs.Step.CoreDone
		tryThrustShopIntro(data)
		if data.TutorialThrustShopIntroShown == true then
			pcall(function()
				Knit.GetService("DataService"):AdvanceTutorialCompleteFromCoreDone()
			end)
		end
		disconnectStage1Listeners()
		destroyBeamVisuals()
		return
	end

	if step == TutorialConfigs.Step.GoStage1 then
		if data.TutorialFlyIntroShown == true or not isStage1HintActive() then
			stage1FlyUiShown = false
		end
		if activeStep ~= TutorialConfigs.Step.GoStage1 and not isStage1HintActive() then
			stage1FlyUiShown = false
		end
		if not isStage1HintActive() then
			if isFootBeamEnabled() then
				if data.TutorialFlyIntroShown == true then
					showBeamForStep(TutorialConfigs.Step.ClaimWins)
					scheduleTargetRetry(TutorialConfigs.Step.ClaimWins)
				elseif not stage1FlyUiShown then
					showBeamForStep(step)
					scheduleTargetRetry(step)
					bindStage1TouchListener()
				end
			elseif not stage1FlyUiShown then
				bindStage1TouchListener()
			end
		end
		return
	end

	-- From Level 2 (ClaimWins) onward the wall can be broken — beam leads to Stage 1
	-- until the gate is melted, then resumes normal step targets (wins / upgrade).
	if shouldOfferStage1FlyLesson(data) then
		ensureStage1FlyListeners()
	else
		disconnectStage1Listeners()
	end
	if isFootBeamEnabled() then
		local beamStep = resolveBeamStep(data)
		showBeamForStep(beamStep)
		scheduleTargetRetry(beamStep)
	else
		destroyBeamVisuals()
	end
end

function TutorialController:KnitStart()
	local UpgradeWinsService = Knit.GetService("UpgradeWinsService")
	UpgradeWinsService.UpgradeResult:Connect(function(kind: string)
		if kind ~= "Unlocked" then
			return
		end
		cancelRetry()
		destroyBeamVisuals()
		task.defer(function()
			syncTutorialFromData(DataLib.GetData())
		end)
	end)

	DataLib.OnChanged(function(data: any)
		syncTutorialFromData(data)
	end)

	player.CharacterAdded:Connect(function()
		-- If the thrust intro camera was interrupted (respawn/death), give control back.
		task.defer(releasePlayerCamera)
		task.defer(function()
			local data = DataLib.GetData()
			if not data then
				return
			end
			syncTutorialFromData(data)
		end)
	end)

	task.spawn(function()
		local character = player.Character
		if not character then
			character = player.CharacterAdded:Wait()
		end
		character:WaitForChild("HumanoidRootPart", 20)

		for _ = 1, 40 do
			local data = DataLib.GetData()
			if data then
				syncTutorialFromData(data)
				break
			end
			task.wait(0.25)
		end
	end)

	TutorialFlyHint.setOnMainDismiss(function()
		stage1FlyUiShown = false
		local data = DataLib.GetData()
		if not data then
			return
		end
		local optimistic = table.clone(data)
		optimistic.TutorialFlyIntroShown = true
		syncTutorialFromData(optimistic)
	end)

	TutorialFlyHint.ensureHidden()
	TutorialLaserHint.ensureHidden()
	TutorialFlyHint.startLowThrustWatcher()

	StudioLog.ready("TutorialController")
end

return TutorialController
