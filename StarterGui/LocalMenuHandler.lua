-- @ScriptType: LocalScript
-- LocalMenuHandler - Manages both BuildingMenu and SelectionMenu + Resource Selection
-- Place this LocalScript inside StarterGui

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local starterGui = script.Parent
local events = ReplicatedStorage:WaitForChild('Events')
local remote = events:WaitForChild('Clicked')
local structures = ReplicatedStorage:WaitForChild('Structures')

-- Resource selection remote events
local selectResourceRemote = events:WaitForChild("SelectResource")
local createHarvestTaskRemote = events:WaitForChild("CreateHarvestTask")

-- Wait for UI elements with correct structure
local toolsScreenGui = starterGui:WaitForChild("ToolsScreenGui")
local buildingMenuButton = toolsScreenGui:WaitForChild("BuildingMenuButton")
local buildingMenu = toolsScreenGui:WaitForChild("BuildingMenu")
local selectionMenuButton = toolsScreenGui:WaitForChild("SelectionMenuButton")

-- Get the specific components we need
local buildingClickDetector = buildingMenuButton:FindFirstChild("ClickDetector")
local buildingTextButton = buildingMenuButton:FindFirstChild("TextButton")
local buildingHandle = buildingTextButton and buildingTextButton:FindFirstChild("Handle")

local selectionClickDetector = selectionMenuButton:FindFirstChild("ClickDetector")
local selectionTextButton = selectionMenuButton:FindFirstChild("TextButton")
local selectionHandle = selectionTextButton and selectionTextButton:FindFirstChild("Handle")

print("--- LocalMenuHandler Loaded ---")
print("Managing BuildingMenu and SelectionMenu from ToolsScreenGui")
print("BuildingMenuButton found:", buildingMenuButton and "✅" or "❌")
print("SelectionMenuButton found:", selectionMenuButton and "✅" or "❌")
print("Building Handle found:", buildingHandle and "✅" or "❌")
print("Selection Handle found:", selectionHandle and "✅" or "❌")

-- ================================
-- RESOURCE SELECTION SYSTEM
-- ================================

-- Resource selection state
local selectedResources = {}
local isResourceSelectionActive = false

-- Resource selection GUI
local resourceGUI = nil
local resourceFrame = nil
local selectionToggleButton = nil
local selectedCountLabel = nil
local clearButton = nil

-- ================================
-- MENU-RELATIVE BUTTON POSITIONING
-- ================================

-- Track all UI elements that should move with menus
local menuRelativeElements = {
	-- Elements that move with building menu
	buildingMenu = {},
	-- Elements that move with other menus
	general = {}
}

-- Store relative positions of UI elements
local function updateMenuRelativePositions()
	-- Store positions of buttons relative to their menus
	if buildingMenu and buildingMenuButton then
		local menuPos = buildingMenu.Position
		local buttonPos = buildingMenuButton.Position

		-- Calculate relative position
		local relativePos = UDim2.new(
			buttonPos.X.Scale - menuPos.X.Scale,
			buttonPos.X.Offset - menuPos.X.Offset,
			buttonPos.Y.Scale - menuPos.Y.Scale,
			buttonPos.Y.Offset - menuPos.Y.Offset
		)

		menuRelativeElements.buildingMenu.button = {
			element = buildingMenuButton,
			relativePos = relativePos
		}
	end

	-- Add resource selection GUI to menu-relative elements
	if resourceFrame then
		menuRelativeElements.general.resourceGUI = {
			element = resourceFrame,
			relativePos = UDim2.new(1, -320, 1, -120) -- Bottom right position
		}
	end
end

-- ================================
-- BUILDING MENU CONFIGURATION
-- ================================

-- Menu position settings for building menu
local BUILDING_MENU_OPEN_POS = UDim2.new(0.008, 0, 0.185, 0)
local BUILDING_MENU_CLOSE_POS = UDim2.new(-0.28, 0, 0.185, 0)
local BUILDING_BUTTON_OPEN_POS = UDim2.new(0.26, 0, 0.185, 0)
local BUILDING_BUTTON_CLOSE_POS = UDim2.new(0, 0, 0.185, 0)
local MENU_TWEEN_TIME = 0.4

-- Building menu variables
local buildingScrollingFrame = nil
local buildingShopHeader = nil
local structureButtons = {}
local isBuildingMenuOpen = false

-- ================================
-- SELECTION MENU CONFIGURATION
-- ================================

-- Button highlighting settings for selection menu
local HIGHLIGHT_COLOR = Color3.fromRGB(100, 255, 100)
local NORMAL_COLOR = Color3.fromRGB(255, 255, 255)
local SELECTION_GLOW_SIZE = UDim2.new(1.2, 0, 1.2, 0)
local NORMAL_SIZE = UDim2.new(1, 0, 1, 0)

-- Selection state
local isSelectionSelected = false

-- ================================
-- SHARED HOVERING CONFIGURATION
-- ================================

-- Hovering settings (shared by both menus)
local HOVER_HEIGHT = 0.3
local HOVER_SPEED = 2
local ROTATION_SPEED = 1
local MAX_ROTATION = 15

-- Hovering states
local isBuildingHovering = true
local isSelectionHovering = true

-- Store original positions and orientations for both buttons
local buildingOriginalData = {}
local selectionOriginalData = {}

-- ================================
-- BUILDING MENU FUNCTIONS
-- ================================

-- Function to create the shop header
local function createShopHeader()
	if buildingShopHeader then return end

	buildingShopHeader = Instance.new("TextLabel")
	buildingShopHeader.Name = "ShopHeader"
	buildingShopHeader.Parent = buildingMenu
	buildingShopHeader.Size = UDim2.new(1, 0, 0, 50)
	buildingShopHeader.Position = UDim2.new(0, 0, 0, 0)
	buildingShopHeader.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	buildingShopHeader.BorderSizePixel = 0
	buildingShopHeader.Text = "🔨 BUILDING SHOP 🔨"
	buildingShopHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
	buildingShopHeader.TextScaled = true
	buildingShopHeader.Font = Enum.Font.SourceSansBold

	-- Add a subtle gradient
	local gradient = Instance.new("UIGradient")
	gradient.Parent = buildingShopHeader
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))
	}
	gradient.Rotation = 90

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = buildingShopHeader
	corner.CornerRadius = UDim.new(0, 8)
end

-- Function to create the scrolling frame
local function createScrollingFrame()
	if buildingScrollingFrame then return end

	buildingScrollingFrame = Instance.new("ScrollingFrame")
	buildingScrollingFrame.Name = "StructuresScrollFrame"
	buildingScrollingFrame.Parent = buildingMenu
	buildingScrollingFrame.Size = UDim2.new(1, 0, 1, -60)
	buildingScrollingFrame.Position = UDim2.new(0, 0, 0, 60)
	buildingScrollingFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	buildingScrollingFrame.BorderSizePixel = 0
	buildingScrollingFrame.ScrollBarThickness = 8
	buildingScrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = buildingScrollingFrame
	corner.CornerRadius = UDim.new(0, 8)

	-- Add layout for the buttons
	local listLayout = Instance.new("UIListLayout")
	listLayout.Parent = buildingScrollingFrame
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 5)

	-- Add padding inside the scroll frame
	local padding = Instance.new("UIPadding")
	padding.Parent = buildingScrollingFrame
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
end

-- Function to create a structure button
local function createStructureButton(structure, index)
	local buttonFrame = Instance.new("Frame")
	buttonFrame.Name = structure.Name .. "Button"
	buttonFrame.Parent = buildingScrollingFrame
	buttonFrame.Size = UDim2.new(1, -20, 0, 60)
	buttonFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	buttonFrame.BorderSizePixel = 0

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = buttonFrame
	corner.CornerRadius = UDim.new(0, 6)

	-- Add hover effect gradient
	local gradient = Instance.new("UIGradient")
	gradient.Parent = buttonFrame
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 55, 55)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 45, 45))
	}
	gradient.Rotation = 45

	-- Create the actual button
	local button = Instance.new("TextButton")
	button.Name = "ClickButton"
	button.Parent = buttonFrame
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.Text = ""

	-- Structure name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Parent = buttonFrame
	nameLabel.Size = UDim2.new(0.7, 0, 0.6, 0)
	nameLabel.Position = UDim2.new(0.05, 0, 0.2, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = structure.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Price label
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Parent = buttonFrame
	priceLabel.Size = UDim2.new(0.25, 0, 0.4, 0)
	priceLabel.Position = UDim2.new(0.7, 0, 0.3, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "$" .. (index * 100)
	priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	priceLabel.TextScaled = true
	priceLabel.Font = Enum.Font.SourceSansBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Icon/Preview
	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "IconFrame"
	iconFrame.Parent = buttonFrame
	iconFrame.Size = UDim2.new(0, 40, 0, 40)
	iconFrame.Position = UDim2.new(0, 5, 0.5, -20)
	iconFrame.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	iconFrame.BorderSizePixel = 0

	local iconCorner = Instance.new("UICorner")
	iconCorner.Parent = iconFrame
	iconCorner.CornerRadius = UDim.new(0, 4)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Parent = iconFrame
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "🏠"
	iconLabel.TextScaled = true

	-- Hover effects
	button.MouseEnter:Connect(function()
		TweenService:Create(buttonFrame, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(buttonFrame, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		}):Play()
	end)

	-- Button click functionality
	button.MouseButton1Click:Connect(function()
		print("Selected structure:", structure.Name)
		remote:FireServer("BuildStructure", structure.Name)

		-- Visual feedback
		TweenService:Create(buttonFrame, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(100, 255, 100)
		}):Play()

		task.wait(0.1)

		TweenService:Create(buttonFrame, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		}):Play()
	end)

	table.insert(structureButtons, buttonFrame)
	return buttonFrame
end

-- Function to populate the menu with structures
local function populateStructureMenu()
	print("🏗️ Creating structure menu...")

	-- Clear existing buttons
	for _, button in pairs(structureButtons) do
		button:Destroy()
	end
	structureButtons = {}

	-- Get all structures and create buttons
	local structureList = structures:GetChildren()
	local totalHeight = 0

	for index, structure in pairs(structureList) do
		if structure:IsA("Model") or structure:IsA("Folder") then
			createStructureButton(structure, index)
			totalHeight = totalHeight + 65
		end
	end

	-- Update canvas size for scrolling
	if buildingScrollingFrame then
		buildingScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 20)
	end

	print("✅ Created " .. #structureButtons .. " structure buttons")
end

-- Function to initialize the building menu
local function initializeBuildingMenu()
	print("🎮 Initializing building menu...")

	-- Create header
	createShopHeader()

	-- Create scrolling frame
	createScrollingFrame()

	-- Populate with structures
	populateStructureMenu()

	print("✅ Building menu initialized!")
end

-- ================================
-- RESOURCE SELECTION GUI FUNCTIONS
-- ================================

local function createResourceSelectionGUI()
	-- Create resource selection GUI
	resourceGUI = Instance.new("ScreenGui")
	resourceGUI.Name = "ResourceSelectionGUI"
	resourceGUI.Parent = toolsScreenGui
	resourceGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main frame - positioned at bottom right
	resourceFrame = Instance.new("Frame")
	resourceFrame.Name = "ResourceSelectionFrame"
	resourceFrame.Size = UDim2.new(0, 300, 0, 110)
	resourceFrame.Position = UDim2.new(1, -320, 1, -130) -- Bottom right with margin
	resourceFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	resourceFrame.BorderSizePixel = 0
	resourceFrame.Parent = resourceGUI

	-- Add gradient and styling
	local gradient = Instance.new("UIGradient")
	gradient.Parent = resourceFrame
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))
	}
	gradient.Rotation = 90

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = resourceFrame

	-- Header
	local headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "Header"
	headerLabel.Size = UDim2.new(1, 0, 0, 25)
	headerLabel.Position = UDim2.new(0, 0, 0, 0)
	headerLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	headerLabel.Text = "🎯 RESOURCE SELECTOR"
	headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	headerLabel.TextScaled = true
	headerLabel.Font = Enum.Font.SourceSansBold
	headerLabel.Parent = resourceFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = headerLabel

	-- Selection toggle button
	selectionToggleButton = Instance.new("TextButton")
	selectionToggleButton.Name = "SelectionToggle"
	selectionToggleButton.Size = UDim2.new(0, 120, 0, 30)
	selectionToggleButton.Position = UDim2.new(0, 10, 0, 35)
	selectionToggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
	selectionToggleButton.Text = "▶ Start Selection"
	selectionToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	selectionToggleButton.TextScaled = true
	selectionToggleButton.Font = Enum.Font.SourceSansBold
	selectionToggleButton.Parent = resourceFrame

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 4)
	toggleCorner.Parent = selectionToggleButton

	-- Selected count label
	selectedCountLabel = Instance.new("TextLabel")
	selectedCountLabel.Name = "SelectedCount"
	selectedCountLabel.Size = UDim2.new(0, 120, 0, 30)
	selectedCountLabel.Position = UDim2.new(0, 140, 0, 35)
	selectedCountLabel.BackgroundTransparency = 1
	selectedCountLabel.Text = "📦 Queued: 0"
	selectedCountLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	selectedCountLabel.TextScaled = true
	selectedCountLabel.Font = Enum.Font.SourceSansBold
	selectedCountLabel.Parent = resourceFrame

	-- Clear button
	clearButton = Instance.new("TextButton")
	clearButton.Name = "ClearButton"
	clearButton.Size = UDim2.new(0, 80, 0, 25)
	clearButton.Position = UDim2.new(0, 10, 0, 75)
	clearButton.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
	clearButton.Text = "🗑️ Clear"
	clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	clearButton.TextScaled = true
	clearButton.Font = Enum.Font.SourceSans
	clearButton.Parent = resourceFrame

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 4)
	clearCorner.Parent = clearButton

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0, 180, 0, 25)
	statusLabel.Position = UDim2.new(0, 100, 0, 75)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Click resources to auto-queue tasks"
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.Parent = resourceFrame

	-- Connect button events
	selectionToggleButton.MouseButton1Click:Connect(toggleResourceSelection)
	clearButton.MouseButton1Click:Connect(clearAllResourceSelections)

	-- Add to menu-relative tracking
	updateMenuRelativePositions()

	print("🎯 Resource Selection GUI created at bottom right")
end

local function toggleResourceSelection()
	isResourceSelectionActive = not isResourceSelectionActive

	if isResourceSelectionActive then
		selectionToggleButton.Text = "⏸️ Stop Selection"
		selectionToggleButton.BackgroundColor3 = Color3.fromRGB(120, 60, 0)
		mouse.Icon = "rbxasset://textures/ArrowFarCursor.png"
		print("🎯 Resource selection ACTIVATED")
	else
		selectionToggleButton.Text = "▶ Start Selection"
		selectionToggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
		mouse.Icon = ""
		print("🎯 Resource selection DEACTIVATED")
	end
end

local function clearAllResourceSelections()
	-- Clear all selected resources and notify server
	for resourceId, _ in pairs(selectedResources) do
		selectResourceRemote:FireServer("unselect", resourceId)
	end

	selectedResources = {}
	updateResourceSelectedCount()
	print("🗑️ Cleared all resource selections")
end

local function updateResourceSelectedCount()
	local count = 0
	for _ in pairs(selectedResources) do
		count = count + 1
	end

	if selectedCountLabel then
		selectedCountLabel.Text = "📦 Queued: " .. count
	end
end

-- ================================
-- RESOURCE SELECTION CLICK HANDLING
-- ================================

local function onMouseClickResource()
	if not isResourceSelectionActive then
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
				-- Unselect and remove from tasks
				selectResourceRemote:FireServer("unselect", resourceId)
				createHarvestTaskRemote:FireServer("remove", resourceId)
				selectedResources[resourceId] = nil
				print("❌ Unselected and removed task for", resourceType, "resource")
			else
				-- Select and auto-queue task
				local position = resourceModel.PrimaryPart and resourceModel.PrimaryPart.Position or Vector3.new(0, 0, 0)

				-- Select the resource visually
				selectResourceRemote:FireServer("select", resourceId, resourceType, position)

				-- Immediately create harvest task
				createHarvestTaskRemote:FireServer("add", {
					resourceId = resourceId,
					resourceType = resourceType,
					position = position
				})

				selectedResources[resourceId] = {
					resourceType = resourceType,
					position = position
				}
				print("✅ Selected and queued task for", resourceType, "resource")
			end

			updateResourceSelectedCount()
		else
			print("⚠️ Clicked object is not a resource")
		end
	end
end

-- ================================
-- RESOURCE SELECTION REMOTE HANDLERS
-- ================================

-- Handle server responses about resource selection
selectResourceRemote.OnClientEvent:Connect(function(action, resourceId, success, message)
	if action == "select_result" then
		if not success then
			-- Server rejected selection, remove from local list
			selectedResources[resourceId] = nil
			updateResourceSelectedCount()
			print("❌ Server rejected selection:", message)
		end
	elseif action == "unselect_result" then
		selectedResources[resourceId] = nil
		updateResourceSelectedCount()
	elseif action == "resource_destroyed" then
		-- Resource was destroyed, remove from selections
		if selectedResources[resourceId] then
			selectedResources[resourceId] = nil
			updateResourceSelectedCount()
			print("💥 Resource destroyed, removed from queue")
		end
	end
end)

-- Handle server responses about task creation
createHarvestTaskRemote.OnClientEvent:Connect(function(action, success, message, resourceId)
	if action == "add_result" then
		if not success then
			print("❌ Failed to create harvest task:", message)
			-- Remove from local selection if task creation failed
			if resourceId and selectedResources[resourceId] then
				selectedResources[resourceId] = nil
				updateResourceSelectedCount()
			end
		else
			print("✅ Harvest task created:", message)
		end
	elseif action == "remove_result" then
		if success then
			print("🗑️ Harvest task removed:", message)
		else
			print("❌ Failed to remove harvest task:", message)
		end
	end
end)

-- ================================
-- MENU-RELATIVE POSITIONING FUNCTIONS
-- ================================

local function moveMenuRelativeElements(menuName, menuOffset)
	-- Move all elements that should be relative to specific menu positions
	if menuRelativeElements[menuName] then
		for elementName, elementData in pairs(menuRelativeElements[menuName]) do
			if elementData.element and elementData.element.Parent then
				local newPos = UDim2.new(
					elementData.relativePos.X.Scale + menuOffset.X.Scale,
					elementData.relativePos.X.Offset + menuOffset.X.Offset,
					elementData.relativePos.Y.Scale + menuOffset.Y.Scale,
					elementData.relativePos.Y.Offset + menuOffset.Y.Offset
				)

				-- Animate the movement
				TweenService:Create(elementData.element, TweenInfo.new(MENU_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = newPos
				}):Play()
			end
		end
	end

	-- Also move general elements (like resource GUI) when any menu opens
	for elementName, elementData in pairs(menuRelativeElements.general) do
		if elementData.element and elementData.element.Parent then
			local newPos = UDim2.new(
				elementData.relativePos.X.Scale + (menuOffset.X.Scale * 0.3), -- Move general elements less dramatically
				elementData.relativePos.X.Offset + (menuOffset.X.Offset * 0.2),
				elementData.relativePos.Y.Scale,
				elementData.relativePos.Y.Offset
			)

			-- Animate the movement
			TweenService:Create(elementData.element, TweenInfo.new(MENU_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = newPos
			}):Play()
		end
	end
end

-- Function to create selection highlight effect
local function createSelectionHighlight()
	local existingHighlight = selectionMenuButton:FindFirstChild("SelectionHighlight")
	if existingHighlight then
		return existingHighlight
	end

	local highlight = Instance.new("Frame")
	highlight.Name = "SelectionHighlight"
	highlight.Parent = selectionMenuButton
	highlight.Size = NORMAL_SIZE
	highlight.Position = UDim2.new(0, 0, 0, 0)
	highlight.BackgroundColor3 = HIGHLIGHT_COLOR
	highlight.BackgroundTransparency = 0.7
	highlight.BorderSizePixel = 0
	highlight.ZIndex = -1

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = highlight
	corner.CornerRadius = UDim.new(0, 8)

	-- Add glow effect
	local gradient = Instance.new("UIGradient")
	gradient.Parent = highlight
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 255, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 255, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 100))
	}

	-- Start hidden
	highlight.BackgroundTransparency = 1
	highlight.Size = NORMAL_SIZE

	return highlight
end

-- Function to show selection highlight
local function showSelectionHighlight()
	local highlight = createSelectionHighlight()

	TweenService:Create(highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.3,
		Size = SELECTION_GLOW_SIZE
	}):Play()

	-- Add pulsing effect
	local pulseIn = TweenService:Create(highlight, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		BackgroundTransparency = 0.5
	})
	local pulseOut = TweenService:Create(highlight, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		BackgroundTransparency = 0.3
	})

	pulseIn.Completed:Connect(function()
		if isSelectionSelected then
			pulseOut:Play()
		end
	end)
	pulseOut.Completed:Connect(function()
		if isSelectionSelected then
			pulseIn:Play()
		end
	end)

	pulseIn:Play()
end

-- Function to hide selection highlight
local function hideSelectionHighlight()
	local highlight = selectionMenuButton:FindFirstChild("SelectionHighlight")
	if highlight then
		TweenService:Create(highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			Size = NORMAL_SIZE
		}):Play()
	end
end

-- Function to update selection button appearance
local function updateSelectionButtonAppearance()
	for _, child in pairs(selectionMenuButton:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			if isSelectionSelected then
				TweenService:Create(child, TweenInfo.new(0.3), {
					TextColor3 = HIGHLIGHT_COLOR
				}):Play()
			else
				TweenService:Create(child, TweenInfo.new(0.3), {
					TextColor3 = NORMAL_COLOR
				}):Play()
			end
		end
	end
end

-- ================================
-- SHARED POSITION TRACKING FUNCTIONS
-- ================================

-- Function to store original positions for building button handle
local function storeBuildingOriginalData()
	print("📍 Capturing building button handle current positions as original data...")
	buildingOriginalData = {}

	if not buildingHandle then 
		print("⚠️ No building handle found to store data for")
		return 
	end

	-- Store data for the Handle object specifically
	if buildingHandle:IsA("BasePart") then
		buildingOriginalData[buildingHandle] = {
			Position = buildingHandle.Position,
			CFrame = buildingHandle.CFrame
		}
		print("  📍 Stored building Handle BasePart at position:", buildingHandle.Position)
	elseif buildingHandle:IsA("Model") and buildingHandle.PrimaryPart then
		buildingOriginalData[buildingHandle] = {
			Position = buildingHandle.PrimaryPart.Position,
			CFrame = buildingHandle:GetPivot()
		}
		print("  📍 Stored building Handle Model at position:", buildingHandle.PrimaryPart.Position)
	end

	-- Also check for any other 3D children in the button frame
	for _, v in pairs(buildingMenuButton:GetDescendants()) do
		if v:IsA("LocalScript") or v == buildingHandle then continue end

		if v:IsA("BasePart") then
			buildingOriginalData[v] = {
				Position = v.Position,
				CFrame = v.CFrame
			}
			print("  📍 Stored building button BasePart:", v.Name, "at position:", v.Position)
		elseif v:IsA("Model") and v.PrimaryPart then
			buildingOriginalData[v] = {
				Position = v.PrimaryPart.Position,
				CFrame = v:GetPivot()
			}
			print("  📍 Stored building button Model:", v.Name, "at position:", v.PrimaryPart.Position)
		end
	end

	local count = 0
	for _ in pairs(buildingOriginalData) do count = count + 1 end
	print("✅ Stored building button data for", count, "objects")
end

-- Function to store original positions for selection button handle
local function storeSelectionOriginalData()
	print("📍 Capturing selection button handle current positions as original data...")
	selectionOriginalData = {}

	if not selectionHandle then 
		print("⚠️ No selection handle found to store data for")
		return 
	end

	-- Store data for the Handle object specifically
	if selectionHandle:IsA("BasePart") then
		selectionOriginalData[selectionHandle] = {
			Position = selectionHandle.Position,
			CFrame = selectionHandle.CFrame
		}
		print("  📍 Stored selection Handle BasePart at position:", selectionHandle.Position)
	elseif selectionHandle:IsA("Model") and selectionHandle.PrimaryPart then
		selectionOriginalData[selectionHandle] = {
			Position = selectionHandle.PrimaryPart.Position,
			CFrame = selectionHandle:GetPivot()
		}
		print("  📍 Stored selection Handle Model at position:", selectionHandle.PrimaryPart.Position)
	end

	-- Also check for any other 3D children in the button frame
	for _, v in pairs(selectionMenuButton:GetDescendants()) do
		if v:IsA("LocalScript") or v == selectionHandle then continue end

		if v:IsA("BasePart") then
			selectionOriginalData[v] = {
				Position = v.Position,
				CFrame = v.CFrame
			}
			print("  📍 Stored selection button BasePart:", v.Name, "at position:", v.Position)
		elseif v:IsA("Model") and v.PrimaryPart then
			selectionOriginalData[v] = {
				Position = v.PrimaryPart.Position,
				CFrame = v:GetPivot()
			}
			print("  📍 Stored selection button Model:", v.Name, "at position:", v.PrimaryPart.Position)
		end
	end

	local count = 0
	for _ in pairs(selectionOriginalData) do count = count + 1 end
	print("✅ Stored selection button data for", count, "objects")
end

-- ================================
-- INITIALIZATION
-- ================================

-- Initialize everything
task.spawn(function()
	task.wait(1)

	print("🚀 Starting LocalMenuHandler initialization...")

	-- Store original data for both buttons
	storeBuildingOriginalData()
	storeSelectionOriginalData()

	-- Initialize building menu
	initializeBuildingMenu()

	-- Create selection highlight
	createSelectionHighlight()

	-- Create resource selection GUI
	createResourceSelectionGUI()

	-- Connect mouse click for resource selection
	mouse.Button1Down:Connect(onMouseClickResource)

	-- Set initial positions
	if buildingMenu then
		buildingMenu.Position = BUILDING_MENU_CLOSE_POS
	end

	-- Update menu-relative positions after everything is created
	updateMenuRelativePositions()

	print("🎉 LocalMenuHandler initialization complete!")
	print("🎯 Resource selection system ready!")
end)

-- ================================
-- HOVERING ANIMATION LOOP
-- ================================

local timeElapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	timeElapsed = timeElapsed + deltaTime

	local hoverOffset = math.sin(timeElapsed * HOVER_SPEED) * HOVER_HEIGHT
	local rotationY = math.sin(timeElapsed * ROTATION_SPEED) * math.rad(MAX_ROTATION)
	local rotationZ = math.cos(timeElapsed * ROTATION_SPEED * 0.7) * math.rad(MAX_ROTATION * 0.5)

	-- Animate building button handle and other objects
	if isBuildingHovering and buildingMenuButton then
		for _, v in pairs(buildingMenuButton:GetDescendants()) do
			if v:IsA("LocalScript") or not buildingOriginalData[v] then continue end

			if v:IsA("BasePart") then
				local originalPos = buildingOriginalData[v].Position
				local originalCFrame = buildingOriginalData[v].CFrame
				local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)
				local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
				local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame
				v.CFrame = newCFrame

			elseif v:IsA("Model") and v.PrimaryPart then
				local originalPos = buildingOriginalData[v].Position
				local originalCFrame = buildingOriginalData[v].CFrame
				local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)
				local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
				local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame
				v:PivotTo(newCFrame)

			elseif v:IsA("GuiObject") then
				local rotation2D = math.sin(timeElapsed * ROTATION_SPEED) * MAX_ROTATION * 0.5
				v.Rotation = rotation2D
			end
		end
	end

	-- Animate selection button handle and other objects
	if isSelectionHovering and selectionMenuButton then
		for _, v in pairs(selectionMenuButton:GetDescendants()) do
			if v:IsA("LocalScript") or not selectionOriginalData[v] then continue end

			if v:IsA("BasePart") then
				local originalPos = selectionOriginalData[v].Position
				local originalCFrame = selectionOriginalData[v].CFrame
				local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)
				local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
				local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame
				v.CFrame = newCFrame

			elseif v:IsA("Model") and v.PrimaryPart then
				local originalPos = selectionOriginalData[v].Position
				local originalCFrame = selectionOriginalData[v].CFrame
				local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)
				local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
				local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame
				v:PivotTo(newCFrame)

			elseif v:IsA("GuiObject") then
				local rotation2D = math.sin(timeElapsed * ROTATION_SPEED) * MAX_ROTATION * 0.5
				v.Rotation = rotation2D
			end
		end
	end
end)

-- ================================
-- BUTTON CLICK HANDLERS
-- ================================

-- Building button click handler
if buildingTextButton then
	buildingTextButton.MouseButton1Click:Connect(function()
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local menuTi = TweenInfo.new(MENU_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		if isBuildingHovering then
			-- HAMMER DOWN + OPEN MENU
			print("\n🔨 BUILDING MENU - HAMMER DOWN! Opening menu")
			isBuildingHovering = false
			isBuildingMenuOpen = true

			-- Calculate menu offset for moving other elements
			local menuOffset = UDim2.new(
				BUILDING_MENU_OPEN_POS.X.Scale - BUILDING_MENU_CLOSE_POS.X.Scale,
				BUILDING_MENU_OPEN_POS.X.Offset - BUILDING_MENU_CLOSE_POS.X.Offset,
				BUILDING_MENU_OPEN_POS.Y.Scale - BUILDING_MENU_CLOSE_POS.Y.Scale,
				BUILDING_MENU_OPEN_POS.Y.Offset - BUILDING_MENU_CLOSE_POS.Y.Offset
			)

			-- Tween menu position to OPEN
			if buildingMenu then
				TweenService:Create(buildingMenu, menuTi, {
					Position = BUILDING_MENU_OPEN_POS
				}):Play()
			end

			-- Move menu-relative elements
			moveMenuRelativeElements("buildingMenu", menuOffset)

			local targetOrientation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(90))

			for _, v in pairs(buildingMenuButton:GetDescendants()) do
				if v:IsA("LocalScript") or not buildingOriginalData[v] then continue end

				if v:IsA("BasePart") then
					local originalPos = buildingOriginalData[v].Position
					local targetCFrame = CFrame.new(originalPos) * targetOrientation
					TweenService:Create(v, ti, {CFrame = targetCFrame}):Play()

				elseif v:IsA("Model") and v.PrimaryPart then
					local originalPos = buildingOriginalData[v].Position
					local targetCFrame = CFrame.new(originalPos) * targetOrientation
					TweenService:Create(v, ti, {WorldPivot = targetCFrame}):Play()

				elseif v:IsA("GuiObject") then
					TweenService:Create(v, ti, {Rotation = 90}):Play()
				end
			end
		else
			-- LIFT UP + CLOSE MENU
			print("\n⬆️ BUILDING MENU - LIFTING UP! Closing menu")
			isBuildingMenuOpen = false

			-- Calculate menu offset for returning elements to original positions
			local menuOffset = UDim2.new(
				BUILDING_MENU_CLOSE_POS.X.Scale - BUILDING_MENU_OPEN_POS.X.Scale,
				BUILDING_MENU_CLOSE_POS.X.Offset - BUILDING_MENU_OPEN_POS.X.Offset,
				BUILDING_MENU_CLOSE_POS.Y.Scale - BUILDING_MENU_OPEN_POS.Y.Scale,
				BUILDING_MENU_CLOSE_POS.Y.Offset - BUILDING_MENU_OPEN_POS.Y.Offset
			)

			-- Tween menu position to CLOSED
			if buildingMenu then
				TweenService:Create(buildingMenu, menuTi, {
					Position = BUILDING_MENU_CLOSE_POS
				}):Play()
			end

			-- Move menu-relative elements back
			moveMenuRelativeElements("buildingMenu", menuOffset)

			for _, v in pairs(buildingMenuButton:GetDescendants()) do
				if v:IsA("LocalScript") or not buildingOriginalData[v] then continue end

				if v:IsA("BasePart") then
					local originalCFrame = buildingOriginalData[v].CFrame
					TweenService:Create(v, ti, {CFrame = originalCFrame}):Play()

				elseif v:IsA("Model") and v.PrimaryPart then
					local originalCFrame = buildingOriginalData[v].CFrame
					TweenService:Create(v, ti, {WorldPivot = originalCFrame}):Play()

				elseif v:IsA("GuiObject") then
					TweenService:Create(v, ti, {Rotation = 0}):Play()
				end
			end

			task.delay(0.3, function()
				isBuildingHovering = true
			end)
		end

		remote:FireServer("BuildingMenu", isBuildingMenuOpen)
	end)
else
	print("⚠️ BuildingTextButton not found - click handler not connected")
end

-- Selection button click handler
if selectionTextButton then
	selectionTextButton.MouseButton1Click:Connect(function()
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		if not isSelectionSelected then
			-- SELECT + HIGHLIGHT
			print("\n✅ SELECTION MENU - BUTTON SELECTED! Showing highlight")
			isSelectionSelected = true
			isSelectionHovering = false

			showSelectionHighlight()
			updateSelectionButtonAppearance()

			local targetOrientation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(90))

			for _, v in pairs(selectionMenuButton:GetDescendants()) do
				if v:IsA("LocalScript") or not selectionOriginalData[v] then continue end

				if v:IsA("BasePart") then
					local originalPos = selectionOriginalData[v].Position
					local targetCFrame = CFrame.new(originalPos) * targetOrientation
					TweenService:Create(v, ti, {CFrame = targetCFrame}):Play()

				elseif v:IsA("Model") and v.PrimaryPart then
					local originalPos = selectionOriginalData[v].Position
					local targetCFrame = CFrame.new(originalPos) * targetOrientation
					TweenService:Create(v, ti, {WorldPivot = targetCFrame}):Play()

				elseif v:IsA("GuiObject") then
					TweenService:Create(v, ti, {Rotation = 90}):Play()
				end
			end
		else
			-- DESELECT + REMOVE HIGHLIGHT
			print("\n❌ SELECTION MENU - BUTTON DESELECTED! Hiding highlight")
			isSelectionSelected = false

			hideSelectionHighlight()
			updateSelectionButtonAppearance()

			for _, v in pairs(selectionMenuButton:GetDescendants()) do
				if v:IsA("LocalScript") or not selectionOriginalData[v] then continue end

				if v:IsA("BasePart") then
					local originalCFrame = selectionOriginalData[v].CFrame
					TweenService:Create(v, ti, {CFrame = originalCFrame}):Play()

				elseif v:IsA("Model") and v.PrimaryPart then
					local originalCFrame = selectionOriginalData[v].CFrame
					TweenService:Create(v, ti, {WorldPivot = originalCFrame}):Play()

				elseif v:IsA("GuiObject") then
					TweenService:Create(v, ti, {Rotation = 0}):Play()
				end
			end

			task.delay(0.3, function()
				isSelectionHovering = true
			end)
		end

		remote:FireServer("SelectionMenu", isSelectionSelected)
	end)
else
	print("⚠️ SelectionTextButton not found - click handler not connected")
end

-- ================================
-- UTILITY FUNCTIONS
-- ================================

-- Global functions for external control
_G.LocalMenuHandler = {
	-- Building Menu Functions
	OpenBuildingMenu = function()
		if buildingTextButton and isBuildingHovering then
			buildingTextButton.MouseButton1Click:Fire()
		end
	end,

	CloseBuildingMenu = function()
		if buildingTextButton and not isBuildingHovering then
			buildingTextButton.MouseButton1Click:Fire()
		end
	end,

	IsBuildingMenuOpen = function()
		return isBuildingMenuOpen
	end,

	-- Selection Menu Functions
	SelectButton = function()
		if selectionTextButton and not isSelectionSelected then
			selectionTextButton.MouseButton1Click:Fire()
		end
	end,

	DeselectButton = function()
		if selectionTextButton and isSelectionSelected then
			selectionTextButton.MouseButton1Click:Fire()
		end
	end,

	IsButtonSelected = function()
		return isSelectionSelected
	end,

	-- Utility Functions
	RecalibrateBuildingPositions = function()
		storeBuildingOriginalData()
	end,

	RecalibrateSelectionPositions = function()
		storeSelectionOriginalData()
	end,

	RecalibrateAllPositions = function()
		storeBuildingOriginalData()
		storeSelectionOriginalData()
	end,

	-- Resource Selection Functions
	StartResourceSelection = function()
		if not isResourceSelectionActive then
			toggleResourceSelection()
		end
	end,

	StopResourceSelection = function()
		if isResourceSelectionActive then
			toggleResourceSelection()
		end
	end,

	IsResourceSelectionActive = function()
		return isResourceSelectionActive
	end,

	ClearResourceSelections = function()
		clearAllResourceSelections()
	end,

	GetSelectedResourceCount = function()
		local count = 0
		for _ in pairs(selectedResources) do
			count = count + 1
		end
		return count
	end,

	GetSelectedResources = function()
		return selectedResources
	end,

	UpdateMenuRelativePositions = function()
		updateMenuRelativePositions()
	end,

	-- Debug Functions
	GetBuildingComponents = function()
		return {
			MenuButton = buildingMenuButton,
			TextButton = buildingTextButton,
			Handle = buildingHandle,
			Menu = buildingMenu
		}
	end,

	GetSelectionComponents = function()
		return {
			MenuButton = selectionMenuButton,
			TextButton = selectionTextButton,
			Handle = selectionHandle
		}
	end,

	GetResourceGUIComponents = function()
		return {
			GUI = resourceGUI,
			Frame = resourceFrame,
			ToggleButton = selectionToggleButton,
			CountLabel = selectedCountLabel,
			ClearButton = clearButton
		}
	end
}

print("💡 LocalMenuHandler loaded with global functions:")
print("  🏗️ Building Menu: OpenBuildingMenu(), CloseBuildingMenu(), IsBuildingMenuOpen()")
print("  ⚡ Selection Menu: SelectButton(), DeselectButton(), IsButtonSelected()")
print("  🎯 Resource Selection: StartResourceSelection(), StopResourceSelection(), ClearResourceSelections()")
print("  🔧 Utilities: RecalibrateAllPositions(), UpdateMenuRelativePositions()")
print("  🐛 Debug: GetBuildingComponents(), GetSelectionComponents(), GetResourceGUIComponents()")