--!strict

-- Plays rebirth fireworks from Studio assets when available:
--   ReplicatedStorage → Particles → Fireworks (ParticleEmitter, Model, or Folder of emitters)

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FIREWORKS_PATH = { "Particles", "Fireworks" }
local DEFAULT_LIFETIME = 4

local Fireworks = {}

local function waitPath(root: Instance, segments: { string }, timeout: number?): Instance?
	local current: Instance? = root
	for _, name in segments do
		if not current then
			return nil
		end
		current = current:WaitForChild(name, timeout or 5)
	end
	return current
end

local function emitFromInstance(instance: Instance)
	if instance:IsA("ParticleEmitter") then
		local count = instance:GetAttribute("EmitCount")
		if type(count) == "number" and count > 0 then
			instance:Emit(count)
		else
			instance:Emit(30)
		end
	elseif instance:IsA("BasePart") then
		for _, desc in instance:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				emitFromInstance(desc)
			end
		end
	else
		for _, desc in instance:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				emitFromInstance(desc)
			end
		end
	end
end

function Fireworks.PlayFireworks(attachTo: BasePart)
	local template = waitPath(ReplicatedStorage, FIREWORKS_PATH, 2)
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Parent = attachTo

	if clone:IsA("BasePart") then
		clone.CFrame = attachTo.CFrame
	elseif clone:IsA("Model") then
		clone:PivotTo(attachTo.CFrame)
	else
		for _, child in clone:GetChildren() do
			if child:IsA("BasePart") then
				child.CFrame = attachTo.CFrame
			end
		end
	end

	emitFromInstance(clone)

	local lifetime = clone:GetAttribute("Lifetime")
	if type(lifetime) ~= "number" then
		lifetime = DEFAULT_LIFETIME
	end
	Debris:AddItem(clone, lifetime)
end

return Fireworks
