--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local KnitPackageFolder = ReplicatedStorage.Packages:WaitForChild("_Index"):WaitForChild("sleitnick_knit@1.7.0"):WaitForChild("knit")

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

loadFolder(script:FindFirstChild("Controllers"))
loadFolder(script:FindFirstChild("GameControllers"))

local servicesFolder = KnitPackageFolder:WaitForChild("Services", 30)
if not servicesFolder then
	warn("[iseesupes] Timed out waiting for Knit services replication.")
	return
end

Knit.Start()
	:andThen(function()
		print("[iseesupes] Client started.")
	end)
	:catch(function(err)
		warn("[iseesupes] Client Knit failed:", tostring(err))
	end)
