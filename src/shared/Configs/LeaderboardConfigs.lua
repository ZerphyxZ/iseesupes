--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)

export type LeaderboardConfig = {
	StoreName: string,
	ModelName: string,
	GetScore: (data: any) -> number?,
	ScoreFormatter: (score: number) -> string,
}

local LeaderboardConfigs = {}

LeaderboardConfigs.RefreshInterval = 60
LeaderboardConfigs.SaveInterval = 60
LeaderboardConfigs.TopN = 50
LeaderboardConfigs.FolderName = "Leaderboards"
LeaderboardConfigs.EntryTemplateName = "LeaderboardEntry"
LeaderboardConfigs.TemplatePath = { "Templates", "LeaderboardEntry" }

local function profileInt(data: any, key: string): number?
	if not data then
		return nil
	end
	local v = data[key]
	if type(v) == "number" then
		return math.floor(v)
	end
	return nil
end

LeaderboardConfigs.Boards = {
	Speed = {
		StoreName = "GlobalSpeed_v1",
		ModelName = "SpeedLeaderboard",
		GetScore = function(data)
			return profileInt(data, "Speed")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Speed"
		end,
	} :: LeaderboardConfig,
	Wins = {
		StoreName = "GlobalWins_v1",
		ModelName = "WinsLeaderboard",
		GetScore = function(data)
			return profileInt(data, "Wins")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Wins"
		end,
	} :: LeaderboardConfig,
	Rebirths = {
		StoreName = "GlobalRebirths_v1",
		ModelName = "RebirthLeaderboard",
		GetScore = function(data)
			return profileInt(data, "Rebirths")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Rebirths"
		end,
	} :: LeaderboardConfig,
}

return LeaderboardConfigs
