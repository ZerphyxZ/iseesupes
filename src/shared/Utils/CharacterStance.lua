--!strict

-- Resets a character to a standing, animated rig after flight, ragdoll, or prone poses.

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
