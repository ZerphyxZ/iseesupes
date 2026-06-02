--!strict

-- Workspace/Map/GiveWins stage-end buttons (Button1, Button2, …) with Touch + WinAmount label.

export type GiveWinsConfig = {
	FolderName: string,
	TouchPartName: string,
	WinAmountLabelName: string,
	WinAmountAttribute: string,
	TouchDebounce: number,
	DoubleWinsGamepassKey: string,
}

local GiveWinsConfigs: GiveWinsConfig = {
	FolderName = "GiveWins",
	TouchPartName = "Touch",
	WinAmountLabelName = "WinAmount",
	WinAmountAttribute = "WinAmount",
	TouchDebounce = 1.5,
	DoubleWinsGamepassKey = "DoubleWins",
}

return GiveWinsConfigs
