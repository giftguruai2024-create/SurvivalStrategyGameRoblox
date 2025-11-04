-- @ScriptType: LocalScript
-- ResourceSelectionScript
-- Place this in StarterPlayer > StarterPlayerScripts
-- Handles clicking on resources to select them for harvesting

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Wait for remote events
local events = ReplicatedStorage:WaitForChild("Events")
local selectResourceRemote = events:WaitForChild("SelectResource")
local createHarvestTaskRemote = events:WaitForChild("CreateHarvestTask")

-- Selection state
local selectedResources = {}
local isSelectionMode = false

-- GUI elements (you can customize this)
local gui = nil
local selectionButton = nil
local selectedCountLabel = nil

-- ========================================
-- GUI CREATION
-- ========================================

local function createSelectionGUI()
	-- Create simple GUI for resource selection
	gui = Instance.new("ScreenGui")
	gui.Name = "ResourceSelectionGUI"
	gui.Parent = player.PlayerGui

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "SelectionFrame"
	frame.Size = UDim2.new(0, 300, 0, 100)
	frame.Position = UDim2.new(0, 10, 0, 10)
	frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- Selection mode button
	selectionButton = Instance.new("TextButton")
	selectionButton.Name = "SelectionButton"
	selectionButton.Size = UDim2.new(0, 140, 0, 30)
	selectionButton.Position = UDim2.new(0, 10, 0, 10)
	selectionButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
	selectionButton.Text = "Start Selection"
	selectionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	selectionButton.TextScaled = true
	selectionButton.Font = Enum.Font.SourceSansBold
	selectionButton.Parent = frame

	-- Selected count label
	selectedCountLabel = Instance.new("TextLabel")
	selectedCountLabel.Name = "SelectedCount"
	selectedCountLabel.Size = UDim2.new(0, 140, 0, 30)
	selectedCountLabel.Position = UDim2.new(0, 160, 0, 10)
	selectedCountLabel.BackgroundTransparency = 1
	selectedCountLabel.Text = "Selected: 0"
	selectedCountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	selectedCountLabel.TextScaled = true
	selectedCountLabel.Font = Enum.Font.SourceSans
	selectedCountLabel.Parent = frame

	-- Clear button
	local clearButton = Instance.new("TextButton")
	clearButton.Name = "ClearButton"
	clearButton.Size = UDim2.new(0, 90, 0, 25)
	clearButton.Position = UDim2.new(0, 10, 0, 50)
	clearButton.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
	clearButton.Text = "Clear All"
	clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	clearButton.TextScaled = true
	clearButton.Font = Enum.Font.SourceSans
	clearButton.Parent = frame

	-- Queue tasks button
	local queueButton = Instance.new("TextButton")
	queueButton.Name = "QueueButton"
	queueButton.Size = UDim2.new(0, 90, 0, 25)
	queueButton.Position = UDim2.new(0, 110, 0, 50)
	queueButton.BackgroundColor3 = Color3.fromRGB(0, 0, 150)
	queueButton.Text = "Queue Tasks"
	queueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	queueButton.TextScaled = true
	queueButton.Font = Enum.Font.SourceSans
	queueButton.Parent = frame

	-- Help label
	local helpLabel = Instance.new("TextLabel")
	helpLabel.Name = "HelpLabel"
	helpLabel.Size = UDim2.new(1, -20, 0, 20)
	helpLabel.Position = UDim2.new(0, 10, 0, 75)
	helpLabel.BackgroundTransparency = 1
	helpLabel.Text = "Click resources while in selection mode to queue harvest tasks"
	helpLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	helpLabel.TextScaled = true
	helpLabel.Font = Enum.Font.SourceSans
	helpLabel.Parent = frame

	-- Connect button events
	selectionButton.MouseButton1Click:Connect(toggleSelectionMode)
	clearButton.MouseButton1Click:Connect(clearAllSelections)
	queueButton.MouseButton1Click:Connect(queueAllTasks)
end

-- ========================================
-- SELECTION FUNCTIONS
-- ========================================

function toggleSelectionMode()
	isSelectionMode = not isSelectionMode

	if isSelectionMode then
		selectionButton.Text = "Stop Selection"
		selectionButton.BackgroundColor3 = Color3.fromRGB(150, 100, 0)
		mouse.Icon = "rbxasset://textures/ArrowFarCursor.png"
	else
		selectionButton.Text = "Start Selection"
		selectionButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
		mouse.Icon = ""
	end

	print("[ResourceSelection] Selection mode:", isSelectionMode and "ON" or "OFF")
end

function clearAllSelections()
	-- Clear all selected resources
	for resourceId, _ in pairs(selectedResources) do
		selectResourceRemote:FireServer("unselect", resourceId)
	end

	selectedResources = {}
	updateSelectedCount()
	print("[ResourceSelection] Cleared all selections")
end

function queueAllTasks()
	-- Send all selected resources as harvest tasks
	if next(selectedResources) == nil then
		print("[ResourceSelection] No resources selected")
		return
	end

	local taskList = {}
	for resourceId, resourceData in pairs(selectedResources) do
		table.insert(taskList, {
			resourceId = resourceId,
			resourceType = resourceData.resourceType,
			position = resourceData.position
		})
	end

	-- Send to server
	createHarvestTaskRemote:FireServer(taskList)

	print(string.format("[ResourceSelection] Queued %d harvest tasks", #taskList))

	-- Clear selections after queuing
	clearAllSelections()
end

function updateSelectedCount()
	local count = 0
	for _ in pairs(selectedResources) do
		count = count + 1
	end

	if selectedCountLabel then
		selectedCountLabel.Text = "Selected: " .. count
	end
end

-- ========================================
-- MOUSE CLICK HANDLING
-- ========================================

function onMouseClick()
	if not isSelectionMode then
		return
	end

	local target = mouse.Target
	if not target then
		return
	end

	-- Check if clicked on a resource
	local resourceModel = target.Parent
	if resourceModel:IsA("Model") then
		-- Check if it's a resource by looking for resource attributes
		local resourceType = resourceModel:GetAttribute("ResourceType")
		local resourceId = resourceModel:GetAttribute("ResourceId")

		if resourceType and resourceId then
			-- Check if already selected
			if selectedResources[resourceId] then
				-- Unselect
				selectResourceRemote:FireServer("unselect", resourceId)
				selectedResources[resourceId] = nil
				print("[ResourceSelection] Unselected", resourceType, "resource")
			else
				-- Select
				local position = resourceModel.PrimaryPart and resourceModel.PrimaryPart.Position or Vector3.new(0, 0, 0)
				selectResourceRemote:FireServer("select", resourceId, resourceType, position)
				selectedResources[resourceId] = {
					resourceType = resourceType,
					position = position
				}
				print("[ResourceSelection] Selected", resourceType, "resource")
			end

			updateSelectedCount()
		else
			print("[ResourceSelection] Clicked object is not a resource")
		end
	end
end

-- ========================================
-- REMOTE EVENT HANDLERS
-- ========================================

-- Handle server responses about resource selection
selectResourceRemote.OnClientEvent:Connect(function(action, resourceId, success)
	if action == "select_result" then
		if not success then
			-- Server rejected selection, remove from local list
			selectedResources[resourceId] = nil
			updateSelectedCount()
		end
	elseif action == "unselect_result" then
		selectedResources[resourceId] = nil
		updateSelectedCount()
	end
end)

-- Handle server responses about task creation
createHarvestTaskRemote.OnClientEvent:Connect(function(success, message)
	if success then
		print("[ResourceSelection] Tasks created successfully:", message)
	else
		print("[ResourceSelection] Failed to create tasks:", message)
	end
end)

-- ========================================
-- INITIALIZATION
-- ========================================

-- Connect mouse click
mouse.Button1Down:Connect(onMouseClick)

-- Create GUI when player spawns
player.CharacterAdded:Connect(function()
	wait(1) -- Wait for character to fully load
	if not gui then
		createSelectionGUI()
	end
end)

-- Create GUI immediately if character already exists
if player.Character then
	createSelectionGUI()
end

print("[ResourceSelection] Local script loaded")