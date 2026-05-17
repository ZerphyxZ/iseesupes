--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local function loadFolder(folder: Instance?)
	if not folder then
		return
	end
	for _, module in folder:GetDescendants() do
		if module:IsA("ModuleScript") then
			require(module)
		end
	end
end

loadFolder(script:FindFirstChild("GlobalServices"))
loadFolder(script:FindFirstChild("GameServices"))

Knit.Start()
	:andThen(function()
		print("[iseesupes] Server started.")
	end)
	:catch(function(err)
		warn("[iseesupes] Server Knit failed:", tostring(err))
	end)
