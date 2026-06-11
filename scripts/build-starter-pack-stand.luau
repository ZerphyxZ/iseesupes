-- Builds Workspace.Map.StarterPackStand: floating gift box on a pedestal near
-- spawn (lobby, beside the treadmill hub) with billboard title/price/timer.
-- MonetizationHudController animates it, runs the countdown, prompts purchase
-- on touch, and hides it locally once the offer is owned/expired.
-- Run from Roblox Studio (command bar / MCP execute_luau) in EDIT mode. Idempotent.

local map = workspace.Map
local old = map:FindFirstChild("StarterPackStand")
if old then
	old:Destroy()
end

local FLOOR_Y = 4360.6
local CX, CZ = -218933, 5015

local model = Instance.new("Model")
model.Name = "StarterPackStand"

local function mk(class: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local pedestal = mk("Part", {
	Name = "Pedestal",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(1.5, 7, 7),
	CFrame = CFrame.new(CX, FLOOR_Y + 0.75, CZ) * CFrame.Angles(0, 0, math.rad(90)),
	Anchored = true,
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(45, 45, 55),
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
}, model) :: BasePart

mk("Part", {
	Name = "TrimRing",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.4, 7.6, 7.6),
	CFrame = CFrame.new(CX, FLOOR_Y + 1.5, CZ) * CFrame.Angles(0, 0, math.rad(90)),
	Anchored = true,
	CanCollide = false,
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(255, 200, 40),
}, model)

local box = mk("Part", {
	Name = "GiftBox",
	Size = Vector3.new(4, 4, 4),
	CFrame = CFrame.new(CX, FLOOR_Y + 5.5, CZ),
	Anchored = true,
	CanCollide = false,
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(200, 30, 45),
}, model) :: BasePart

mk("Part", {
	Name = "RibbonX",
	Size = Vector3.new(4.15, 4.15, 1),
	CFrame = CFrame.new(CX, FLOOR_Y + 5.5, CZ),
	Anchored = true,
	CanCollide = false,
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(255, 200, 40),
}, model)
mk("Part", {
	Name = "RibbonZ",
	Size = Vector3.new(1, 4.15, 4.15),
	CFrame = CFrame.new(CX, FLOOR_Y + 5.5, CZ),
	Anchored = true,
	CanCollide = false,
	Material = Enum.Material.Neon,
	Color = Color3.fromRGB(255, 200, 40),
}, model)
mk("Part", {
	Name = "Lid",
	Size = Vector3.new(4.4, 0.9, 4.4),
	CFrame = CFrame.new(CX, FLOOR_Y + 7.05, CZ),
	Anchored = true,
	CanCollide = false,
	Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(160, 20, 35),
}, model)

local sparkles = Instance.new("Sparkles")
sparkles.SparkleColor = Color3.fromRGB(255, 215, 80)
sparkles.Parent = box

mk("Part", {
	Name = "Touch",
	Size = Vector3.new(9, 10, 9),
	CFrame = CFrame.new(CX, FLOOR_Y + 5, CZ),
	Anchored = true,
	CanCollide = false,
	Transparency = 1,
}, model)

local billboard = Instance.new("BillboardGui")
billboard.Name = "Billboard"
billboard.Size = UDim2.new(14, 0, 5.2, 0)
billboard.StudsOffset = Vector3.new(0, 6.4, 0)
billboard.AlwaysOnTop = false
billboard.MaxDistance = 120
billboard.Parent = box

local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local GOTHAM_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local function label(name: string, posY: number, sizeY: number, text: string, font: Font, color: Color3, strokeColor: Color3)
	local l = mk("TextLabel", {
		Name = name,
		Position = UDim2.new(0.5, 0, posY, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, 0, sizeY, 0),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = font,
		TextColor3 = color,
		TextScaled = true,
	}, billboard)
	mk("UIStroke", { Color = strokeColor, Thickness = 3 }, l)
end

label("Title", 0.18, 0.36, "STARTER PACK", FREDOKA, Color3.new(1, 1, 1), Color3.fromRGB(120, 30, 0))
label("Deal", 0.5, 0.26, "Only 9 R$ — Limited Time!", GOTHAM_BOLD, Color3.fromRGB(255, 230, 120), Color3.new(0, 0, 0))
label("Timer", 0.78, 0.3, "0:00:00", FREDOKA, Color3.new(1, 1, 1), Color3.new(0, 0, 0))

model.PrimaryPart = pedestal
model.Parent = map

print("[build-starter-pack-stand] Built Workspace.Map.StarterPackStand")
