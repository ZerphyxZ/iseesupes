--!strict



local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UpgradeWinsConfigs = require(script.Parent.Parent.Configs.UpgradeWinsConfigs)
local CapeRigEnsure = require(script.Parent.CapeRigEnsure)

local CLOTHING_CHILD_NAMES = { "Shirt", "Pants", "ShirtGraphic" }

local DJ_PHASE_ATTR = "DjAbilityPhase"
local EQUIPPED_SHOWCASE_ATTR = "EquippedShowcaseAvatarId"

type EquipShowcaseResult = {
	ok: boolean,
	usedVisualOnly: boolean,
}

local AvatarReplace = {
	EQUIPPED_SHOWCASE_ATTR = EQUIPPED_SHOWCASE_ATTR,
}

local function isLocalPlayerInDoubleJumpFlight(): boolean
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return false
	end
	local phase = localPlayer:GetAttribute(DJ_PHASE_ATTR)
	return typeof(phase) == "string" and phase ~= ""
end



local function prepareCloneForPlay(clone: Model, humanoid: Humanoid)

	for _, desc in clone:GetDescendants() do

		if desc:IsA("BasePart") then

			desc.Anchored = false

			desc.AssemblyLinearVelocity = Vector3.zero

			desc.AssemblyAngularVelocity = Vector3.zero

		end

	end



	humanoid.PlatformStand = false

	humanoid.Sit = false

	humanoid.AutoRotate = true

	humanoid.BreakJointsOnDeath = false



	if humanoid.MaxHealth <= 0 then

		humanoid.MaxHealth = 100

	end

	humanoid.Health = humanoid.MaxHealth



	pcall(function()

		humanoid:ChangeState(Enum.HumanoidStateType.Running)

	end)

end

local function copyHumanoidMovementPhysics(dst: Humanoid, src: Humanoid)
	dst.HipHeight = src.HipHeight
	dst.WalkSpeed = src.WalkSpeed
	dst.JumpHeight = src.JumpHeight
	dst.JumpPower = src.JumpPower
	dst.UseJumpPower = src.UseJumpPower
	dst.AutoRotate = src.AutoRotate
end

-- Humanoid only: do not copy HRP density/size from another rig (breaks avatar 2+ assemblies).
local function applyMorphPhysicsParity(clone: Model, source: Model)
	local srcHum = source:FindFirstChildOfClass("Humanoid")
	local dstHum = clone:FindFirstChildOfClass("Humanoid")
	if srcHum and dstHum then
		copyHumanoidMovementPhysics(dstHum, srcHum)
	end

	local dstRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if dstRoot then
		clone.PrimaryPart = dstRoot
	end
end

local function getMeshIdToken(part: BasePart): string
	if part:IsA("MeshPart") then
		return part.MeshId
	end
	local special = part:FindFirstChildOfClass("SpecialMesh")
	if special then
		return special.MeshId
	end
	return ""
end

local function buildAutoRigSignature(model: Model): string
	local tokens: { string } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			table.insert(
				tokens,
				string.format("%s|%s|%s", part.Name, tostring(part.Size), getMeshIdToken(part))
			)
		end
	end
	table.sort(tokens)
	return table.concat(tokens, ";")
end

local function getRigGroupKey(model: Model): string
	local attrName = UpgradeWinsConfigs.ShowcaseRigIdAttribute
	local attr = model:GetAttribute(attrName)
	if typeof(attr) == "string" and attr ~= "" then
		return "attr:" .. attr
	end
	return "sig:" .. buildAutoRigSignature(model)
end

function AvatarReplace.rigsMatchForVisualMorph(a: Model, b: Model): boolean
	return getRigGroupKey(a) == getRigGroupKey(b)
end

function AvatarReplace.willUseVisualOnlyEquip(player: Player, template: Model, avatarId: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	if UpgradeWinsConfigs.UseVisualOnlyShowcaseEquip then
		return true
	end
	if not UpgradeWinsConfigs.UseVisualOnlyMorphWhenRigMatches then
		return false
	end
	local currentId = character:GetAttribute(EQUIPPED_SHOWCASE_ATTR)
	if typeof(currentId) == "string" and currentId == avatarId then
		return true
	end
	return AvatarReplace.rigsMatchForVisualMorph(character, template)
end

local function getPartPath(part: BasePart, root: Model): string
	local segments: { string } = {}
	local current: Instance? = part
	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end
	return table.concat(segments, "/")
end

local function buildPartPathMap(model: Model): { [string]: BasePart }
	local map: { [string]: BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			map[getPartPath(desc, model)] = desc
		end
	end
	return map
end

local function clearSurfaceAppearances(part: BasePart)
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
end

local function replaceSurfaceAppearance(dstPart: BasePart, srcPart: BasePart)
	clearSurfaceAppearances(dstPart)
	local srcSA = srcPart:FindFirstChildOfClass("SurfaceAppearance")
	if srcSA then
		srcSA:Clone().Parent = dstPart
	end
end

local function syncSpecialMesh(dst: BasePart, src: BasePart)
	local srcMesh = src:FindFirstChildOfClass("SpecialMesh")
	local dstMesh = dst:FindFirstChildOfClass("SpecialMesh")
	if not srcMesh then
		if dstMesh then
			dstMesh:Destroy()
		end
		return
	end
	if not dstMesh then
		srcMesh:Clone().Parent = dst
		return
	end
	dstMesh.MeshType = srcMesh.MeshType
	dstMesh.MeshId = srcMesh.MeshId
	dstMesh.TextureId = srcMesh.TextureId
	dstMesh.VertexColor = srcMesh.VertexColor
	dstMesh.Scale = srcMesh.Scale
	dstMesh.Offset = srcMesh.Offset
end

local function syncDecals(dst: BasePart, src: BasePart)
	local srcByName: { [string]: Decal } = {}
	for _, child in src:GetChildren() do
		if child:IsA("Decal") then
			srcByName[child.Name] = child
		end
	end

	for _, child in dst:GetChildren() do
		if child:IsA("Decal") and not srcByName[child.Name] then
			child:Destroy()
		end
	end

	for name, srcDecal in srcByName do
		local dstDecal = dst:FindFirstChild(name)
		if dstDecal and dstDecal:IsA("Decal") then
			dstDecal.Color3 = srcDecal.Color3
			dstDecal.Transparency = srcDecal.Transparency
			dstDecal.Texture = srcDecal.Texture
			dstDecal.Face = srcDecal.Face
		else
			srcDecal:Clone().Parent = dst
		end
	end
end

local function applyPartVisuals(dst: BasePart, src: BasePart)
	dst.Color = src.Color
	dst.Material = src.Material
	dst.Transparency = src.Transparency
	dst.Reflectance = src.Reflectance

	if dst:IsA("MeshPart") and src:IsA("MeshPart") then
		dst.TextureID = src.TextureID
		pcall(function()
			dst.MaterialVariant = src.MaterialVariant
		end)
	end

	syncSpecialMesh(dst, src)
	replaceSurfaceAppearance(dst, src)
	syncDecals(dst, src)
end

local function applyBodyColorsVisuals(dstCharacter: Model, srcCharacter: Model)
	local srcBody = srcCharacter:FindFirstChildOfClass("BodyColors")
	if not srcBody then
		return
	end
	local dstBody = dstCharacter:FindFirstChildOfClass("BodyColors")
	if not dstBody then
		srcBody:Clone().Parent = dstCharacter
		return
	end
	dstBody.HeadColor3 = srcBody.HeadColor3
	dstBody.LeftArmColor3 = srcBody.LeftArmColor3
	dstBody.LeftLegColor3 = srcBody.LeftLegColor3
	dstBody.RightArmColor3 = srcBody.RightArmColor3
	dstBody.RightLegColor3 = srcBody.RightLegColor3
	dstBody.TorsoColor3 = srcBody.TorsoColor3
end

local function templateUsesMeshPartBody(template: Model): boolean
	for _, desc in template:GetDescendants() do
		if desc:IsA("MeshPart") and desc.Name ~= "HumanoidRootPart" then
			return true
		end
	end
	return false
end

local function shouldApplyBodyColorsOnMorph(template: Model): boolean
	if not UpgradeWinsConfigs.ApplyBodyColorsOnVisualMorph then
		return false
	end
	if not template:FindFirstChildOfClass("BodyColors") then
		return false
	end
	return not templateUsesMeshPartBody(template)
end

local function applyShowcaseClothing(character: Model, template: Model)
	for _, childName in CLOTHING_CHILD_NAMES do
		local existing = character:FindFirstChild(childName)
		if existing then
			existing:Destroy()
		end
		local src = template:FindFirstChild(childName)
		if src and (src:IsA("Shirt") or src:IsA("Pants") or src:IsA("ShirtGraphic")) then
			src:Clone().Parent = character
		end
	end
end

local function applyShowcaseVisuals(character: Model, template: Model)
	local templateParts = buildPartPathMap(template)
	local characterParts = buildPartPathMap(character)

	for path, dstPart in characterParts do
		local srcPart = templateParts[path]
		if srcPart then
			applyPartVisuals(dstPart, srcPart)
		end
	end

	if shouldApplyBodyColorsOnMorph(template) then
		applyBodyColorsVisuals(character, template)
	end

	applyShowcaseClothing(character, template)
	CapeRigEnsure.ensureOnCharacter(character, template)
end

local function syncHumanoidFromTemplate(character: Model, template: Model)
	local templateHumanoid = template:FindFirstChildOfClass("Humanoid")
	local characterHumanoid = character:FindFirstChildOfClass("Humanoid")
	if templateHumanoid and characterHumanoid then
		copyHumanoidMovementPhysics(characterHumanoid, templateHumanoid)
	end
end

local function ensurePlayerOwnsCharacter(player: Player, character: Model)
	if not RunService:IsServer() then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local function assign()
		if player.Character ~= character or root.Parent == nil then
			return
		end
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	assign()
	task.defer(assign)
end

function AvatarReplace.equipShowcaseVisualOnly(player: Player, template: Model, avatarId: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	applyShowcaseVisuals(character, template)
	syncHumanoidFromTemplate(character, template)
	character:SetAttribute(EQUIPPED_SHOWCASE_ATTR, avatarId)
	ensurePlayerOwnsCharacter(player, character)
	return true
end

local function suppressDeathOnSwap(humanoid: Humanoid)

	humanoid.BreakJointsOnDeath = false

	pcall(function()

		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

	end)

end



function AvatarReplace.getButtonIndex(button: Model): number?

	local prefix = UpgradeWinsConfigs.ButtonNamePrefix

	local indexStr = string.match(button.Name, "^" .. prefix .. "(%d+)$")

	if not indexStr then

		return nil

	end

	local index = tonumber(indexStr)

	if not index or index <= 0 then

		return nil

	end

	return math.floor(index)

end



-- All showcase buttons (1–12): visual-only when rig matches; otherwise full swap.
function AvatarReplace.equipShowcaseAvatar(player: Player, template: Model, avatarId: string): EquipShowcaseResult
	local character = player.Character
	if character then
		local currentId = character:GetAttribute(EQUIPPED_SHOWCASE_ATTR)
		if typeof(currentId) == "string" and currentId == avatarId then
			return { ok = true, usedVisualOnly = true }
		end
	end

	if AvatarReplace.willUseVisualOnlyEquip(player, template, avatarId) then
		local ok = AvatarReplace.equipShowcaseVisualOnly(player, template, avatarId)
		return { ok = ok, usedVisualOnly = true }
	end

	local ok = AvatarReplace.replacePlayerCharacter(player, template, avatarId)
	return { ok = ok, usedVisualOnly = false }
end

function AvatarReplace.getAvatarId(button: Model): string?

	local attr = button:GetAttribute(UpgradeWinsConfigs.AvatarIdAttribute)

	if typeof(attr) == "number" and attr > 0 then

		return tostring(math.floor(attr))

	end

	local index = AvatarReplace.getButtonIndex(button)

	if index then

		return tostring(index)

	end

	return nil

end



function AvatarReplace.replacePlayerCharacter(player: Player, template: Model, avatarId: string?): boolean

	local character = player.Character

	local humanoid = template:FindFirstChildOfClass("Humanoid")

	if not humanoid then

		warn("[iseesupes] AvatarReplace: template has no Humanoid:", template:GetFullName())

		return false

	end



	local clone = template:Clone()

	clone.Name = player.Name



	local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")

	if not cloneHumanoid then

		warn("[iseesupes] AvatarReplace: clone has no Humanoid")

		return false

	end

	prepareCloneForPlay(clone, cloneHumanoid)
	if character and UpgradeWinsConfigs.MorphCopyPhysicsFromCurrentCharacter then
		applyMorphPhysicsParity(clone, character)
	end
	if typeof(avatarId) == "string" and avatarId ~= "" then
		clone:SetAttribute(EQUIPPED_SHOWCASE_ATTR, avatarId)
	end

	local newRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if newRoot and RunService:IsStudio() then
		local look = newRoot.CFrame.LookVector
		local horizontalMag = math.sqrt(look.X * look.X + look.Z * look.Z)
		if horizontalMag < 0.15 then
			warn(
				"[iseesupes] AvatarReplace: HumanoidRootPart look vector is mostly vertical for",
				template.Name,
				"- E-glide bank may look wrong. Align HRP forward with character facing."
			)
		end
	end

	local oldHumanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	local oldRoot = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil



	if oldHumanoid then

		suppressDeathOnSwap(oldHumanoid)

	end



	local targetCFrame: CFrame? = nil

	if newRoot and oldRoot then

		targetCFrame = oldRoot.CFrame

	elseif newRoot and character then

		targetCFrame = character:GetPivot()

	end



	clone.Parent = workspace

	player.Character = clone

	-- Let Roblox remove the old character; do not Destroy() it (avoids client death VFX).



	local placedRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?

	if placedRoot and targetCFrame then

		placedRoot.CFrame = targetCFrame

	end



	if placedRoot then

		placedRoot.AssemblyLinearVelocity = Vector3.zero

		placedRoot.AssemblyAngularVelocity = Vector3.zero

	end

	ensurePlayerOwnsCharacter(player, clone)

	return true

end



-- Local player only: re-bind default follow camera after a morph.

function AvatarReplace.snapLocalCamera(character: Model?)

	local localPlayer = Players.LocalPlayer

	if not localPlayer then

		return

	end

	if isLocalPlayerInDoubleJumpFlight() then

		return

	end

	if not character or character.Parent == nil then

		character = localPlayer.Character

	end

	if not character or character ~= localPlayer.Character then

		return

	end



	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then

		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?

	end

	if not humanoid then

		return

	end



	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local camera = workspace.CurrentCamera

	if not camera then

		return

	end



	camera.CameraType = Enum.CameraType.Custom

	camera.CameraSubject = humanoid



	if root then

		local offset = Vector3.new(0, 2, 10)

		camera.CFrame = CFrame.lookAt(root.Position + offset, root.Position + Vector3.new(0, 1.5, 0))

		camera.Focus = CFrame.new(root.Position)

	end

end



function AvatarReplace.waitAndSnapLocalCamera(maxWait: number?)

	local localPlayer = Players.LocalPlayer

	if not localPlayer then

		return

	end

	if isLocalPlayerInDoubleJumpFlight() then

		return

	end

	local deadline = os.clock() + (maxWait or 3)

	local character = localPlayer.Character

	while not character and os.clock() < deadline do

		character = localPlayer.CharacterAdded:Wait()

	end

	if not character then

		return

	end



	character:WaitForChild("Humanoid", 5)

	task.wait()

	AvatarReplace.snapLocalCamera(character)

	task.delay(0.1, function()

		if localPlayer.Character then

			AvatarReplace.snapLocalCamera(localPlayer.Character)

		end

	end)

end



return AvatarReplace


