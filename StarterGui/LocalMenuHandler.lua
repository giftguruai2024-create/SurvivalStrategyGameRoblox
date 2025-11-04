-- @ScriptType: LocalScript
-- LocalMenuHandler - Cleaned and Optimized Version
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
-- CONSTANTS AND CONFIGURATIONS
-- ================================

-- Menu position settings
local BUILDING_MENU_OPEN_POS = UDim2.new(0.008, 0, 0.185, 0)
local BUILDING_MENU_CLOSE_POS = UDim2.new(-0.28, 0, 0.185, 0)
local MENU_TWEEN_TIME = 0.4

-- Button highlighting settings
local HIGHLIGHT_COLOR = Color3.fromRGB(100, 255, 100)
local NORMAL_COLOR = Color3.fromRGB(255, 255, 255)
local SELECTION_GLOW_SIZE = UDim2.new(1.2, 0, 1.2, 0)
local NORMAL_SIZE = UDim2.new(1, 0, 1, 0)

-- Hovering settings
local HOVER_HEIGHT = 0.3
local HOVER_SPEED = 2
local ROTATION_SPEED = 1
local MAX_ROTATION = 15

-- ================================
-- STATE VARIABLES
-- ================================

-- Resource selection state
local selectedResources = {}
local isResourceSelectionActive = false

-- Menu states
local isBuildingMenuOpen = false
local isSelectionSelected = false

-- Hovering states
local isBuildingHovering = true
local isSelectionHovering = true

-- UI References
local resourceFrame = nil
local selectedCountLabel = nil
local clearButton = nil
local buildingScrollingFrame = nil
local buildingShopHeader = nil
local structureButtons = {}

-- Position storage
local buildingMenuButtonOriginalPosition = nil
local buildingOriginalData = {}
local selectionOriginalData = {}

-- ================================
-- UTILITY FUNCTIONS
-- ================================

-- Function to store original positions for any button handle
local function storeOriginalData(button, handle, dataStorage, name)
	print("📍 Capturing " .. name .. " button handle current positions as original data...")

	if not handle then 
		print("⚠️ No " .. name .. " handle found to store data for")
		return 
	end

	-- Store data for the Handle object specifically
	if handle:IsA("BasePart") then
		dataStorage[handle] = {
			Position = handle.Position,
			CFrame = handle.CFrame
		}
		print("  📍 Stored " .. name .. " Handle BasePart at position:", handle.Position)
	elseif handle:IsA("Model") and handle.PrimaryPart then
		dataStorage[handle] = {
			Position = handle.PrimaryPart.Position,
			CFrame = handle:GetPivot()
		}
		print("  📍 Stored " .. name .. " Handle Model at position:", handle.PrimaryPart.Position)
	end

	-- Also check for any other 3D children in the button frame
	for _, v in pairs(button:GetDescendants()) do
		if v:IsA("LocalScript") or v == handle then continue end

		if v:IsA("BasePart") then
			dataStorage[v] = {
				Position = v.Position,
				CFrame = v.CFrame
			}
			print("  📍 Stored " .. name .. " button BasePart:", v.Name, "at position:", v.Position)
		elseif v:IsA("Model") and v.PrimaryPart then
			dataStorage[v] = {
				Position = v.PrimaryPart.Position,
				CFrame = v:GetPivot()
			}
			print("  📍 Stored " .. name .. " button Model:", v.Name, "at position:", v.PrimaryPart.Position)
		end
	end

	local count = 0
	for _ in pairs(dataStorage) do count = count + 1 end
	print("✅ Stored " .. name .. " button data for", count, "objects")
end

-- Function to animate button objects with given parameters
local function animateButtonObjects(button, dataStorage, tweenInfo, targetPosition, targetOrientation, restore)
	for _, v in pairs(button:GetDescendants()) do
		if v:IsA("LocalScript") or not dataStorage[v] then continue end

		if v:IsA("BasePart") then
			local target
			if restore then
				target = {CFrame = dataStorage[v].CFrame}
			else
				local originalPos = targetPosition or dataStorage[v].Position
				local targetCFrame = CFrame.new(originalPos) * (targetOrientation or CFrame.new())
				target = {CFrame = targetCFrame}
			end
			TweenService:Create(v, tweenInfo, target):Play()

		elseif v:IsA("Model") and v.PrimaryPart then
			local target
			if restore then
				target = {WorldPivot = dataStorage[v].CFrame}
			else
				local originalPos = targetPosition or dataStorage[v].Position
				local targetCFrame = CFrame.new(originalPos) * (targetOrientation or CFrame.new())
				target = {WorldPivot = targetCFrame}
			end
			TweenService:Create(v, tweenInfo, target):Play()

		elseif v:IsA("GuiObject") then
			local rotationTarget = restore and 0 or 90
			TweenService:Create(v, tweenInfo, {Rotation = rotationTarget}):Play()
		end
	end
end

-- ================================
-- RESOURCE SELECTION FUNCTIONS
-- ================================

local function updateResourceSelectedCount()
	local count = 0
	for _ in pairs(selectedResources) do
		count = count + 1
	end

	if selectedCountLabel then
		selectedCountLabel.Text = "📦 Queued: " .. count
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

local function toggleResourceSelection()
	isResourceSelectionActive = not isResourceSelectionActive

	if isResourceSelectionActive then
		mouse.Icon = "rbxasset://textures/ArrowFarCursor.png"
		print("🎯 Resource selection ACTIVATED")
	else
		mouse.Icon = ""
		print("🎯 Resource selection DEACTIVATED")
	end
end

local function setupResourceSelectionGUI()
	-- Get the existing ResourceSelectionFrame from ToolsScreenGui
	resourceFrame = toolsScreenGui:WaitForChild("ResourceSelectionFrame")

	-- Get the existing UI components
	clearButton = resourceFrame:FindFirstChild("ClearButton")
	selectedCountLabel = resourceFrame:FindFirstChild("SelectedCount")

	-- Connect button events if they exist
	if clearButton then
		clearButton.MouseButton1Click:Connect(clearAllResourceSelections)
		print("🎯 Connected clear button")
	else
		print("⚠️ ClearButton not found in ResourceSelectionFrame")
	end

	if selectedCountLabel then
		print("🎯 Found selected count label")
	else
		print("⚠️ SelectedCount label not found in ResourceSelectionFrame")
	end

	print("🎯 Resource Selection GUI setup complete (using existing frame)")
end

local function showResourceSelectionGUI()
	if not resourceFrame then return end

	TweenService:Create(resourceFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.7, 0, 0.85, 0)
	}):Play()

	print("🎯 Resource Selection GUI animated to open position")
end

local function hideResourceSelectionGUI()
	if not resourceFrame then return end

	-- Stop any resource selection in progress
	if isResourceSelectionActive then
		toggleResourceSelection()
	end

	-- Clear all selections
	clearAllResourceSelections()

	-- Animate to closed position
	TweenService:Create(resourceFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.7, 0, 1.1, 0)
	}):Play()

	print("🎯 Resource Selection GUI animated to closed position")
end

local function onMouseClickResource()
	-- Only allow resource selection if the selection menu button is toggled AND resource selection is active
	if not isSelectionSelected then
		print("⚠️ Selection menu button must be toggled to access resource selection")
		return
	end

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
-- BUILDING MENU FUNCTIONS
-- ================================

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

local function setupBuildingMenu()
	print("🎮 Setting up building menu...")

	-- Get existing elements from BuildingMenu
	buildingShopHeader = buildingMenu:WaitForChild("ShopHeader")
	buildingScrollingFrame = buildingMenu:WaitForChild("StructuresScrollFrame")

	print("🏗️ Found existing ShopHeader:", buildingShopHeader and "✅" or "❌")
	print("🏗️ Found existing StructuresScrollFrame:", buildingScrollingFrame and "✅" or "❌")

	-- Populate with structures
	populateStructureMenu()

	print("✅ Building menu setup complete!")
end

-- ================================
-- SELECTION MENU FUNCTIONS
-- ================================

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

local function showSelectionHighlight()
	local highlight = createSelectionHighlight()

	TweenService:Create(highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.3,
		Size = SELECTION_GLOW_SIZE
	}):Play()

	-- Add pulsing effect
	local function pulseEffect()
		if not isSelectionSelected then return end

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

	pulseEffect()
end

local function hideSelectionHighlight()
	local highlight = selectionMenuButton:FindFirstChild("SelectionHighlight")
	if highlight then
		TweenService:Create(highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			Size = NORMAL_SIZE
		}):Play()
	end
end

local function updateSelectionButtonAppearance()
	for _, child in pairs(selectionMenuButton:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			local targetColor = isSelectionSelected and HIGHLIGHT_COLOR or NORMAL_COLOR
			TweenService:Create(child, TweenInfo.new(0.3), {
				TextColor3 = targetColor
			}):Play()
		end
	end
end

-- ================================
-- BUTTON CLICK HANDLERS
-- ================================

local function handleBuildingMenuToggle()
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local menuTi = TweenInfo.new(MENU_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if isBuildingHovering then
		-- HAMMER DOWN + OPEN MENU
		print("\n🔨 BUILDING MENU - HAMMER DOWN! Opening menu")
		isBuildingHovering = false
		isBuildingMenuOpen = true

		-- Tween menu position to OPEN
		if buildingMenu then
			TweenService:Create(buildingMenu, menuTi, {
				Position = BUILDING_MENU_OPEN_POS
			}):Play()
		end

		local targetOrientation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(90))
		animateButtonObjects(buildingMenuButton, buildingOriginalData, ti, nil, targetOrientation, false)
	else
		-- LIFT UP + CLOSE MENU
		print("\n⬆️ BUILDING MENU - LIFTING UP! Closing menu")
		isBuildingMenuOpen = false

		-- Tween menu position to CLOSED
		if buildingMenu then
			TweenService:Create(buildingMenu, menuTi, {
				Position = BUILDING_MENU_CLOSE_POS
			}):Play()
		end

		-- Return building menu button to its original GUI position
		if buildingMenuButton and buildingMenuButtonOriginalPosition then
			TweenService:Create(buildingMenuButton, menuTi, {
				Position = buildingMenuButtonOriginalPosition
			}):Play()
		end

		animateButtonObjects(buildingMenuButton, buildingOriginalData, ti, nil, nil, true)

		task.delay(0.3, function()
			isBuildingHovering = true
		end)
	end

	remote:FireServer("BuildingMenu", isBuildingMenuOpen)
end

local function handleSelectionMenuToggle()
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if not isSelectionSelected then
		-- SELECT + HIGHLIGHT + SHOW RESOURCE GUI
		print("\n✅ SELECTION MENU - BUTTON SELECTED! Showing highlight and resource GUI")
		isSelectionSelected = true
		isSelectionHovering = false

		-- Show selection highlight
		showSelectionHighlight()

		-- Show resource selection GUI with animation
		showResourceSelectionGUI()

		-- Automatically start resource selection
		if not isResourceSelectionActive then
			toggleResourceSelection()
		end

		-- Update button text colors
		updateSelectionButtonAppearance()

		-- Hammer down animation for the 3D objects
		local targetOrientation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(90))
		animateButtonObjects(selectionMenuButton, selectionOriginalData, ti, nil, targetOrientation, false)
	else
		-- DESELECT + REMOVE HIGHLIGHT + HIDE RESOURCE GUI
		print("\n❌ SELECTION MENU - BUTTON DESELECTED! Hiding highlight and resource GUI")
		isSelectionSelected = false

		-- Hide selection highlight
		hideSelectionHighlight()

		-- Hide resource selection GUI with animation
		hideResourceSelectionGUI()

		-- Update button text colors back to normal
		updateSelectionButtonAppearance()

		-- Lift up animation for the 3D objects
		animateButtonObjects(selectionMenuButton, selectionOriginalData, ti, nil, nil, true)

		task.delay(0.3, function()
			isSelectionHovering = true
		end)
	end

	remote:FireServer("SelectionMenu", isSelectionSelected)
end

-- ================================
-- REMOTE EVENT HANDLERS
-- ================================

-- Handle server responses about resource selection
selectResourceRemote.OnClientEvent:Connect(function(action, resourceId, success, message)
	if action == "select_result" then
		if not success then
			selectedResources[resourceId] = nil
			updateResourceSelectedCount()
			print("❌ Server rejected selection:", message)
		end
	elseif action == "unselect_result" then
		selectedResources[resourceId] = nil
		updateResourceSelectedCount()
	elseif action == "resource_destroyed" then
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
		if success then
			print("✅ Harvest task created:", message)
		else
			-- Check if it's because resource is already being harvested
			if message == "Resource already being harvested" then
				print("⚠️ Resource already being harvested by another unit")
				-- Remove from local selection since it's already taken
				if resourceId and selectedResources[resourceId] then
					selectedResources[resourceId] = nil
					updateResourceSelectedCount()
				end
			else
				print("❌ Failed to create harvest task:", message)
				-- Remove from local selection if task creation failed
				if resourceId and selectedResources[resourceId] then
					selectedResources[resourceId] = nil
					updateResourceSelectedCount()
				end
			end
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
-- HOVERING ANIMATION LOOP
-- ================================

local timeElapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	timeElapsed = timeElapsed + deltaTime

	local hoverOffset = math.sin(timeElapsed * HOVER_SPEED) * HOVER_HEIGHT
	local rotationY = math.sin(timeElapsed * ROTATION_SPEED) * math.rad(MAX_ROTATION)
	local rotationZ = math.cos(timeElapsed * ROTATION_SPEED * 0.7) * math.rad(MAX_ROTATION * 0.5)

	-- Function to animate hovering for any button
	local function animateHovering(button, dataStorage, isHovering)
		if not (isHovering and button) then return end

		for _, v in pairs(button:GetDescendants()) do
			if v:IsA("LocalScript") or not dataStorage[v] then continue end

			if v:IsA("BasePart") then
				local originalPos = dataStorage[v].Position
				local originalCFrame = dataStorage[v].CFrame
				local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)
				local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
				local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame
				v.CFrame = newCFrame

			elseif v:IsA("Model") and v.PrimaryPart then
				local originalPos = dataStorage[v].Position
				local originalCFrame = dataStorage[v].CFrame
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

	-- Animate both buttons
	animateHovering(buildingMenuButton, buildingOriginalData, isBuildingHovering)
	animateHovering(selectionMenuButton, selectionOriginalData, isSelectionHovering)
end)

-- ================================
-- INITIALIZATION
-- ================================

local function initialize()
	task.wait(1)

	print("🚀 Starting LocalMenuHandler initialization...")

	-- Store original GUI position FIRST before any tweening
	if buildingMenuButton then
		buildingMenuButtonOriginalPosition = buildingMenuButton.Position
		print("📍 Stored building menu button original GUI position:", buildingMenuButtonOriginalPosition)
	end

	-- Store original 3D data for both buttons
	storeOriginalData(buildingMenuButton, buildingHandle, buildingOriginalData, "building")
	storeOriginalData(selectionMenuButton, selectionHandle, selectionOriginalData, "selection")

	-- Initialize building menu
	setupBuildingMenu()

	-- Create selection highlight
	createSelectionHighlight()

	-- Setup resource selection GUI
	setupResourceSelectionGUI()

	-- Connect mouse click for resource selection
	mouse.Button1Down:Connect(onMouseClickResource)

	-- Set initial positions
	if buildingMenu then
		buildingMenu.Position = BUILDING_MENU_CLOSE_POS
	end

	if buildingMenuButton and buildingMenuButtonOriginalPosition then
		buildingMenuButton.Position = buildingMenuButtonOriginalPosition
	end

	if resourceFrame then
		resourceFrame.Position = UDim2.new(0.7, 0, 1.1, 0)
	end

	-- Connect button click handlers
	if buildingTextButton then
		buildingTextButton.MouseButton1Click:Connect(handleBuildingMenuToggle)
	else
		print("⚠️ BuildingTextButton not found - click handler not connected")
	end

	if selectionTextButton then
		selectionTextButton.MouseButton1Click:Connect(handleSelectionMenuToggle)
	else
		print("⚠️ SelectionTextButton not found - click handler not connected")
	end

	print("🎉 LocalMenuHandler initialization complete!")
	print("🎯 Resource selection system ready!")
end

-- Start initialization
task.spawn(initialize)

-- ================================
-- GLOBAL API FUNCTIONS
-- ================================

_G.LocalMenuHandler = {
	-- Building Menu Functions
	OpenBuildingMenu = function()
		if buildingTextButton and isBuildingHovering then
			handleBuildingMenuToggle()
		end
	end,

	CloseBuildingMenu = function()
		if buildingTextButton and not isBuildingHovering then
			handleBuildingMenuToggle()
		end
	end,

	IsBuildingMenuOpen = function()
		return isBuildingMenuOpen
	end,

	-- Selection Menu Functions
	SelectButton = function()
		if selectionTextButton and not isSelectionSelected then
			handleSelectionMenuToggle()
		end
	end,

	DeselectButton = function()
		if selectionTextButton and isSelectionSelected then
			handleSelectionMenuToggle()
		end
	end,

	IsButtonSelected = function()
		return isSelectionSelected
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

	-- Utility Functions
	RecalibratePositions = function()
		if buildingMenuButton then
			buildingMenuButtonOriginalPosition = buildingMenuButton.Position
		end
		storeOriginalData(buildingMenuButton, buildingHandle, buildingOriginalData, "building")
		storeOriginalData(selectionMenuButton, selectionHandle, selectionOriginalData, "selection")
	end,

	-- Debug Functions
	GetDebugInfo = function()
		return {
			BuildingMenu = {
				MenuButton = buildingMenuButton,
				TextButton = buildingTextButton,
				Handle = buildingHandle,
				Menu = buildingMenu,
				OriginalPosition = buildingMenuButtonOriginalPosition,
				IsOpen = isBuildingMenuOpen,
				IsHovering = isBuildingHovering
			},
			SelectionMenu = {
				MenuButton = selectionMenuButton,
				TextButton = selectionTextButton,
				Handle = selectionHandle,
				IsSelected = isSelectionSelected,
				IsHovering = isSelectionHovering
			},
			ResourceSelection = {
				Frame = resourceFrame,
				CountLabel = selectedCountLabel,
				ClearButton = clearButton,
				IsActive = isResourceSelectionActive,
				SelectedCount = _G.LocalMenuHandler.GetSelectedResourceCount()
			}
		}
	end
}

print("💡 LocalMenuHandler API loaded:")
print("  🏗️ Building: OpenBuildingMenu(), CloseBuildingMenu(), IsBuildingMenuOpen()")
print("  ⚡ Selection: SelectButton(), DeselectButton(), IsButtonSelected()")
print("  🎯 Resources: StartResourceSelection(), StopResourceSelection(), ClearResourceSelections()")
print("  🔧 Utilities: RecalibratePositions(), GetDebugInfo()")