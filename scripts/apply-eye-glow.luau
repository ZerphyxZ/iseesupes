-- Tiered glowing eyes for the morph lineup (heat-vision escalation).
-- Morphs 1-7 keep the stock baked face; 8-9 amber, 10-11 burning orange,
-- 12 full crimson + PointLight. Eye quads are welded, massless, non-colliding —
-- safe on showcase statues AND on live player clones (AvatarReplace).
--
-- Why not face decals/textures: all shared heads use one third-party texture
-- (85679439013460) that EditableImage may not load (no permission), and its UV
-- atlas stores face features as scattered islands — flat face images cannot be
-- composited or overlaid without double-face artifacts. Eye quads sit on the
-- mesh surface at offsets tuned for the shared head mesh (118465555749823).
--
-- Run in Studio (command bar / MCP execute_luau, EDIT mode). Idempotent.

local TIERS: { [string]: Color3 } = {
	["8"] = Color3.fromRGB(255, 176, 40),
	["9"] = Color3.fromRGB(255, 176, 40),
	["10"] = Color3.fromRGB(255, 100, 20),
	["11"] = Color3.fromRGB(255, 100, 20),
	["12"] = Color3.fromRGB(255, 40, 30),
}
local LIGHT_TIERS: { [string]: boolean } = { ["12"] = true }

-- Tuned on the shared head mesh; if a future morph uses a different mesh,
-- re-tune with colored test parts first (see iseesupes memory notes).
-- Z is inset slightly INTO the mesh so the head occludes the quads from
-- side/back angles (at -0.80 they peeked past the silhouette as floating dots).
local EYE_OFFSET_X = 0.195
local EYE_OFFSET_Y = 0.065
local EYE_OFFSET_Z = -0.765
local EYE_SIZE = Vector3.new(0.20, 0.105, 0.012)

local function applyEyes(model: Model, color: Color3, withLight: boolean): boolean
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end
	for _, d in head:GetChildren() do
		if d.Name == "EyeGlow" or d.Name == "_EyeGlowTest" then
			d:Destroy()
		end
	end
	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "EyeGlow"
		eye.Size = EYE_SIZE
		eye.CFrame = head.CFrame * CFrame.new(side * EYE_OFFSET_X, EYE_OFFSET_Y, EYE_OFFSET_Z)
		eye.Material = Enum.Material.Neon
		eye.Color = color
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
		if withLight then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 0.8
			light.Range = 4
			light.Parent = eye
		end
		eye.Parent = head
	end
	return true
end

local showcase = workspace.Map.AvatarsShowcase
local applied = 0
for name, color in TIERS do
	local model = showcase:FindFirstChild(name)
	if model and applyEyes(model, color, LIGHT_TIERS[name] == true) then
		applied += 1
	end
end
print("[apply-eye-glow] applied to " .. applied .. " morphs")
