--!strict

-- Server-side character trail visuals (replicates to all clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)

local TrailVisuals = {}

local function createAttachments(character: Model): (Attachment?, Attachment?)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil, nil
	end

	local halfHeight = rootPart.Size.Y / 2
	local offset = halfHeight

	local att0 = rootPart:FindFirstChild("TrailAtt0") :: Attachment?
	if not att0 then
		att0 = Instance.new("Attachment")
		att0.Name = "TrailAtt0"
		att0.Parent = rootPart
	end
	att0.Position = Vector3.new(0, offset, 0)

	local att1 = rootPart:FindFirstChild("TrailAtt1") :: Attachment?
	if not att1 then
		att1 = Instance.new("Attachment")
		att1.Name = "TrailAtt1"
		att1.Parent = rootPart
	end
	att1.Position = Vector3.new(0, -offset, 0)

	return att0, att1
end

function TrailVisuals.Update(player: Player, trailId: string)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local oldTrail = rootPart:FindFirstChild("PlayerTrail")
	if oldTrail then
		oldTrail:Destroy()
	end

	if trailId == "" then
		return
	end

	local info = TrailConfigs.GetTrailById(trailId)
	if not info then
		return
	end

	local att0, att1 = createAttachments(character)
	if not att0 or not att1 then
		return
	end

	local trail = Instance.new("Trail")
	trail.Name = "PlayerTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.FaceCamera = true
	trail.Lifetime = 0.5
	trail.MinLength = 0
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0)
	trail.WidthScale = NumberSequence.new(1)

	if info.Color then
		trail.Color = info.Color
	end

	trail.Parent = rootPart
end

-- Calls getEquippedId() whenever the character spawns; pass current equipped trail id.
function TrailVisuals.BindPlayer(player: Player, getEquippedId: () -> string)
	local function apply()
		TrailVisuals.Update(player, getEquippedId())
	end

	player.CharacterAdded:Connect(function()
		task.wait(1)
		apply()
	end)

	if player.Character then
		apply()
	end
end

return TrailVisuals
