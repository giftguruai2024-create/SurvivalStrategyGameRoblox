-- @ScriptType: LocalScript
-- Client-side UI Script for WorldState
-- Place this in StarterPlayer > StarterPlayerScripts
-- Displays game time and total resources

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for remote functions
local getTimeEvent = ReplicatedStorage:WaitForChild("GetGameTime", 10)
local getResourcesEvent = ReplicatedStorage:WaitForChild("GetTotalResources", 10)

-- Create UI
local function createUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WorldStateUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Create main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 250, 0, 150)
	mainFrame.Position = UDim2.new(1, -260, 0, 10)
	mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	mainFrame.BorderSizePixel = 2
	mainFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
	mainFrame.Parent = screenGui

	-- Add corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = mainFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	title.BorderSizePixel = 0
	title.Text = "🌍 WORLD STATUS"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.Parent = mainFrame

	-- Title corner
	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 8)
	titleCorner.Parent = title

	-- Time label
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.Size = UDim2.new(1, -20, 0, 25)
	timeLabel.Position = UDim2.new(0, 10, 0, 40)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "⏰ Time: 00:00 (Day 1)"
	timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timeLabel.TextSize = 14
	timeLabel.Font = Enum.Font.Gotham
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Parent = mainFrame

	-- Resources frame
	local resourcesFrame = Instance.new("Frame")
	resourcesFrame.Name = "ResourcesFrame"
	resourcesFrame.Size = UDim2.new(1, -20, 0, 70)
	resourcesFrame.Position = UDim2.new(0, 10, 0, 70)
	resourcesFrame.BackgroundTransparency = 1
	resourcesFrame.Parent = mainFrame

	-- Resources list layout
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = resourcesFrame

	return screenGui, timeLabel, resourcesFrame
end

-- Update UI with current data
local function updateUI(screenGui, timeLabel, resourcesFrame)
	-- Update time
	if getTimeEvent then
		local success, timeData = pcall(function()
			return getTimeEvent:InvokeServer()
		end)

		if success and timeData then
			local timeIcon = timeData.isNight and "🌙" or "☀️"
			timeLabel.Text = string.format("%s Time: %s (Day %d)", 
				timeIcon, timeData.time, timeData.day)
		end
	end

	-- Update resources
	if getResourcesEvent then
		local success, resources = pcall(function()
			return getResourcesEvent:InvokeServer()
		end)

		if success and resources then
			-- Clear existing resource labels
			for _, child in pairs(resourcesFrame:GetChildren()) do
				if child:IsA("TextLabel") then
					child:Destroy()
				end
			end

			-- Create resource labels
			local resourceIcons = {
				WOOD = "🪵",
				STONE = "🪨",
				FOOD = "🍎",
				GOLD = "🏆",
			}

			local resourceColors = {
				WOOD = Color3.fromRGB(101, 67, 33),
				STONE = Color3.fromRGB(150, 150, 150),
				FOOD = Color3.fromRGB(255, 100, 100),
				GOLD = Color3.fromRGB(255, 215, 0),
			}

			local index = 0
			for resourceType, count in pairs(resources) do
				local label = Instance.new("TextLabel")
				label.Name = resourceType .. "Label"
				label.Size = UDim2.new(1, 0, 0, 16)
				label.BackgroundTransparency = 1
				label.Text = string.format("%s %s: %d", 
					resourceIcons[resourceType] or "📦", 
					resourceType, 
					count)
				label.TextColor3 = resourceColors[resourceType] or Color3.fromRGB(255, 255, 255)
				label.TextSize = 12
				label.Font = Enum.Font.Gotham
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.LayoutOrder = index
				label.Parent = resourcesFrame

				index = index + 1
			end
		end
	end
end

-- Main
local function main()
	print("[WorldStateUI] Starting client UI...")

	-- Wait a moment for remote events to be available
	wait(2)

	-- Create UI
	local screenGui, timeLabel, resourcesFrame = createUI()

	-- Update loop
	spawn(function()
		while wait(1) do -- Update every second
			if screenGui and screenGui.Parent then
				updateUI(screenGui, timeLabel, resourcesFrame)
			else
				break
			end
		end
	end)

	print("[WorldStateUI] Client UI initialized")
end

-- Run
main()