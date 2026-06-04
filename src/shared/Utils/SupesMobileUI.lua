--!strict

local SupesMobileUI = {}

function SupesMobileUI.findSupesMobile(playerGui: PlayerGui): Frame?
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			local f = gui:FindFirstChild("SupesMobile", true)
			if f and f:IsA("Frame") then
				return f
			end
		end
	end
	local f = playerGui:FindFirstChild("SupesMobile", true)
	if f and f:IsA("Frame") then
		return f
	end
	return nil
end

function SupesMobileUI.findSupesImageButton(supesFrame: Frame): ImageButton?
	for _, child in supesFrame:GetDescendants() do
		if child:IsA("ImageButton") then
			return child
		end
	end
	return nil
end

return SupesMobileUI
