--!strict

local LeaderstatsSync = {}

local function ensureInt(folder: Folder, name: string, value: number): IntValue
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("IntValue") then
		existing.Value = value
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local iv = Instance.new("IntValue")
	iv.Name = name
	iv.Value = value
	iv.Parent = folder
	return iv
end

function LeaderstatsSync.Apply(player: Player, data: any)
	local folder = player:FindFirstChild("leaderstats")
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	local level = 1
	local speed = 0
	local rebirths = 0
	local wins = 0
	if type(data.Level) == "number" then
		level = data.Level
	end
	if type(data.Speed) == "number" then
		speed = math.floor(data.Speed)
	end
	if type(data.Rebirths) == "number" then
		rebirths = data.Rebirths
	end
	if type(data.Wins) == "number" then
		wins = data.Wins
	end

	ensureInt(folder, "Level", level)
	ensureInt(folder, "Speed", speed)
	ensureInt(folder, "Rebirths", rebirths)
	ensureInt(folder, "Wins", wins)
end

return LeaderstatsSync
