--!strict

-- Resets a character to a standing, animated rig after flight, ragdoll, or prone poses.

local DEFAULT_MAX_HEALTH = 100

local CharacterStance = {}

function CharacterStance.buildUprightCFrame(root: BasePart?, baseCf: CFrame): CFrame
	local pos = baseCf.Position
	local look = baseCf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		if root then
			local rootLook = root.CFrame.LookVector
			flat = Vector3.new(rootLook.X, 0, rootLook.Z)
		end
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
	else
		flat = flat.Unit
	end
	return CFrame.lookAt(pos, pos + flat)
end

export type ObstacleHitOptions = {
	knockbackHorizontal: number?,
	knockbackVertical: number?,
}

--- Knockback away from a hazard part, then clean death (no joint break). Matches Obstacle Studio script.
function CharacterStance.applyObstacleStyleHit(
	character: Model,
	sourcePart: BasePart?,
	options: ObstacleHitOptions?
)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	humanoid.BreakJointsOnDeath = false

	if sourcePart then
		local horizontal = if options and options.knockbackHorizontal then options.knockbackHorizontal else 80
		local vertical = if options and options.knockbackVertical then options.knockbackVertical else 30
		local direction = rootPart.Position - sourcePart.Position
		if direction.Magnitude < 1 then
			direction = Vector3.new(0, 0, 1)
		end
		direction = direction.Unit
		rootPart.AssemblyLinearVelocity = direction * horizontal + Vector3.new(0, vertical, 0)
	end

	humanoid.Health = 0
end

function CharacterStance.resetHealthToFull(humanoid: Humanoid)
	humanoid.MaxHealth = DEFAULT_MAX_HEALTH
	humanoid.Health = DEFAULT_MAX_HEALTH
end

function CharacterStance.resetToStanding(character: Model, uprightCFrame: CFrame?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	for _, desc in character:GetDescendants() do
		if desc:IsA("Motor6D") then
			desc.Enabled = true
		end
	end

	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid.AutoRotate = true
	end

	if hrp then
		if uprightCFrame then
			hrp.CFrame = uprightCFrame
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	if humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end
end

return CharacterStance
