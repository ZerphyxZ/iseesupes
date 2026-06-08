--!strict

local VisionMobileUI = {}

function VisionMobileUI.findVisionMobile(playerGui: PlayerGui): Frame?
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			local f = gui:FindFirstChild("VisionMobile", true)
			if f and f:IsA("Frame") then
				return f
			end
		end
	end
	local f = playerGui:FindFirstChild("VisionMobile", true)
	if f and f:IsA("Frame") then
		return f
	end
	return nil
end

function VisionMobileUI.findVisionImageButton(visionFrame: Frame): ImageButton?
	for _, child in visionFrame:GetDescendants() do
		if child:IsA("ImageButton") then
			return child
		end
	end
	return nil
end

return VisionMobileUI
