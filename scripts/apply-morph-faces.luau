-- Applies HD face decals to the AvatarsShowcase morphs (and through them, to
-- players — AvatarReplace clones these models on equip).
--
-- HOW TO USE:
-- 1. Studio → View → Asset Manager → Bulk Import → select everything in
--    Downloads\SupesFaces-Upload (12 Face##-*.png + 7 AURA-*.png).
-- 2. After moderation, right-click each imported image → Copy Asset ID and
--    paste into FACE_IDS / AURA_FACE_IDS below (keep the order).
-- 3. Run this script in Studio (command bar / MCP execute_luau, EDIT mode).
--    Idempotent — re-running replaces existing plates.
--
-- Technique: heads use custom SpecialMeshes (decals directly on the part
-- misalign), so each face rides a thin invisible "FacePlate" welded just in
-- front of the visual face surface (~0.88 studs from part center, probed
-- empirically — tweak PLATE_OFFSET if a specific morph's plate floats or sinks).

local FACE_IDS = {
	[1] = 81826939399256, -- Face01-Nervous
	[2] = 127380338665589, -- Face02-Optimist
	[3] = 113743794005651, -- Face03-CheerfulGrin
	[4] = 128274924926748, -- Face04-WinningSmile
	[5] = 88851290124181, -- Face05-CheckIt
	[6] = 123082141566922, -- Face06-Daring
	[7] = 135319089845777, -- Face07-Fearless
	[8] = 138609626132568, -- Face08-DrillSergeant
	[9] = 130131826839144, -- Face09-SeriousScarFace
	[10] = 135892749441834, -- Face10-IAmNotAmused
	[11] = 131620964982703, -- Face11-RedSeriousScarFace
	[12] = 128774658937072, -- Face12-CrimsonLaserVision
}

--- Aura showcase skins (matched by aura color; 0 = skip).
local AURA_FACE_IDS = {
	["B-AURA"] = 85237371948660, -- AURA-SapphireLaserVision
	["C-AURA"] = 122234266435199, -- AURA-YellowGlowingEyes
	["E-AURA"] = 100163478426544, -- AURA-EmeraldLaserVision
	["L-AURA"] = 124531904712398, -- AURA-EyesOfEverflame
	["M-AURA"] = 106711758249269, -- AURA-GoldenEvilEye
	["R-AURA"] = 102873040540118, -- AURA-RedGlowingEyes
	["U-AURA"] = 124851930152004, -- AURA-GreenGlowingEyes
}

local PLATE_OFFSET = 0.88
local PLATE_NAME = "FacePlate"

local function applyFace(model: Model, assetId: number)
	if assetId == 0 then
		return false
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		warn("[apply-morph-faces] no Head in " .. model:GetFullName())
		return false
	end

	local old = head:FindFirstChild(PLATE_NAME)
	if old then
		old:Destroy()
	end

	local plate = Instance.new("Part")
	plate.Name = PLATE_NAME
	plate.Size = Vector3.new(head.Size.X * 1.5, head.Size.Y * 1.3, 0.02)
	plate.CFrame = head.CFrame * CFrame.new(0, 0, -PLATE_OFFSET)
	plate.Transparency = 1
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Massless = true
	plate.Anchored = head.Anchored

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = plate
	weld.Parent = plate

	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Face = Enum.NormalId.Front
	decal.Texture = "rbxassetid://" .. assetId
	decal.Parent = plate

	plate.Parent = head
	return true
end

local showcase = workspace.Map.AvatarsShowcase
local applied = 0
for num, id in FACE_IDS do
	local model = showcase:FindFirstChild(tostring(num))
	if model and applyFace(model, id) then
		applied += 1
	end
end
for name, id in AURA_FACE_IDS do
	local model = showcase:FindFirstChild(name)
	if model and applyFace(model, id) then
		applied += 1
	end
end

print("[apply-morph-faces] applied " .. applied .. " faces")
