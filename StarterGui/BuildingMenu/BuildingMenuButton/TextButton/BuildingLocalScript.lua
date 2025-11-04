-- @ScriptType: LocalScript
local button = script.Parent
local view = button.Parent
local screenGui = view.Parent
local buildingMenu = screenGui:WaitForChild("BuildingMenu")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local replicated = game:GetService('ReplicatedStorage')
local events = replicated:WaitForChild('Events')
local remote = events:WaitForChild('Clicked')
local structures = replicated:WaitForChild('Structures')

-- Menu position settings
local MENU_OPEN_POS = UDim2.new(0.008, 0, 0.185, 0)
local MENU_CLOSE_POS = UDim2.new(-0.28, 0, 0.185, 0)
local BUTTON_OPEN_POS = UDim2.new(0.26, 0, 0.185, 0)
local BUTTON_CLOSE_POS = UDim2.new(0, 0, 0.185, 0)
local MENU_TWEEN_TIME = 0.4

-- Hovering settings
local HOVER_HEIGHT = 0.3 -- How high it floats up and down
local HOVER_SPEED = 2 -- Speed of the hovering motion (higher = faster)
local ROTATION_SPEED = 1 -- Speed of the rotation
local MAX_ROTATION = 15 -- Maximum degrees of rotation

-- Model's neutral orientation
local NEUTRAL_ORIENTATION = CFrame.Angles(0, math.rad(180), 0)

-- Hovering state
local isHovering = true

-- Store original positions and orientations
local originalData = {}

-- Menu creation variables
local scrollingFrame = nil
local shopHeader = nil
local structureButtons = {}

print("--- Hovering Button System Loaded ---")
print("Objects will hover up/down and rotate smoothly")
print("Click to open menu (hammer down) / Click again to close menu (lift up)")

-- Set initial positions to closed
buildingMenu.Position = MENU_CLOSE_POS
view.Position = BUTTON_CLOSE_POS

-- Function to create the shop header
local function createShopHeader()
	shopHeader = Instance.new("TextLabel")
	shopHeader.Name = "ShopHeader"
	shopHeader.Parent = buildingMenu
	shopHeader.Size = UDim2.new(1, 0, 0, 50)
	shopHeader.Position = UDim2.new(0, 0, 0, 0)
	shopHeader.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	shopHeader.BorderSizePixel = 0
	shopHeader.Text = "🔨 BUILDING SHOP 🔨"
	shopHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopHeader.TextScaled = true
	shopHeader.Font = Enum.Font.SourceSansBold

	-- Add a subtle gradient
	local gradient = Instance.new("UIGradient")
	gradient.Parent = shopHeader
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))
	}
	gradient.Rotation = 90

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = shopHeader
	corner.CornerRadius = UDim.new(0, 8)
end

-- Function to create the scrolling frame
local function createScrollingFrame()
	scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "StructuresScrollFrame"
	scrollingFrame.Parent = buildingMenu
	scrollingFrame.Size = UDim2.new(1, 0, 1, -60) -- Full width, height minus header space
	scrollingFrame.Position = UDim2.new(0, 0, 0, 60) -- Start below header
	scrollingFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.ScrollBarThickness = 8
	scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)

	-- Add corner rounding
	local corner = Instance.new("UICorner")
	corner.Parent = scrollingFrame
	corner.CornerRadius = UDim.new(0, 8)

	-- Add layout for the buttons
	local listLayout = Instance.new("UIListLayout")
	listLayout.Parent = scrollingFrame
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 5)

	-- Add padding inside the scroll frame
	local padding = Instance.new("UIPadding")
	padding.Parent = scrollingFrame
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
end

-- Function to create a structure button
local function createStructureButton(structure, index)
	local buttonFrame = Instance.new("Frame")
	buttonFrame.Name = structure.Name .. "Button"
	buttonFrame.Parent = scrollingFrame
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

	-- Price label (you can modify this based on your pricing system)
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Parent = buttonFrame
	priceLabel.Size = UDim2.new(0.25, 0, 0.4, 0)
	priceLabel.Position = UDim2.new(0.7, 0, 0.3, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "$" .. (index * 100) -- Example pricing
	priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	priceLabel.TextScaled = true
	priceLabel.Font = Enum.Font.SourceSansBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Icon/Preview (simplified - you can enhance this)
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
	iconLabel.Text = "🏠" -- You can use different icons based on structure type
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
		-- Add your building logic here
		-- You can fire a remote event with the structure data
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
			totalHeight = totalHeight + 65 -- 60 height + 5 padding
		end
	end

	-- Update canvas size for scrolling
	if scrollingFrame then
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 20)
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

-- Function to store original positions and orientations
local function storeOriginalData()
	-- Clear existing data first
	originalData = {}

	for _, v in pairs(button:GetChildren()) do
		if v:IsA("LocalScript") then continue end

		if v:IsA("BasePart") then
			originalData[v] = {
				Position = v.Position,
				CFrame = v.CFrame
			}
		elseif v:IsA("Model") and v.PrimaryPart then
			originalData[v] = {
				Position = v.PrimaryPart.Position,
				CFrame = v:GetPivot()
			}
		end
	end

	-- Use pairs to count the entries properly
	local count = 0
	for _ in pairs(originalData) do
		count = count + 1
	end

	print("✅ Stored original data for", count, "objects")

	-- Debug: List what objects we found
	if count == 0 then
		print("⚠️ No objects found in button to store! Button children:")
		for i, v in pairs(button:GetChildren()) do
			print("  -", i, ":", v.Name, "(" .. v.ClassName .. ")")
		end
	end
end

-- Initialize everything
task.spawn(function()
	-- Wait a moment for everything to load
	task.wait(1)

	-- Store original data
	storeOriginalData()

	-- Initialize the building menu
	initializeBuildingMenu()
end)

-- Continuous hovering loop (FIXED with nil checks)
local timeElapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	if not isHovering then return end

	timeElapsed = timeElapsed + deltaTime

	-- Calculate hover offset using sine wave
	local hoverOffset = math.sin(timeElapsed * HOVER_SPEED) * HOVER_HEIGHT

	-- Calculate rotation using sine wave
	local rotationY = math.sin(timeElapsed * ROTATION_SPEED) * math.rad(MAX_ROTATION)
	local rotationZ = math.cos(timeElapsed * ROTATION_SPEED * 0.7) * math.rad(MAX_ROTATION * 0.5)

	for _, v in pairs(button:GetChildren()) do
		if v:IsA("LocalScript") then continue end

		-- SAFETY CHECK: Only proceed if we have original data for this object
		if not originalData[v] then
			continue -- Skip this object if no original data
		end

		if v:IsA("BasePart") then
			local originalPos = originalData[v].Position
			local originalCFrame = originalData[v].CFrame

			-- Create new position with hover offset
			local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)

			-- Create rotation relative to original orientation
			local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
			local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame

			v.CFrame = newCFrame

		elseif v:IsA("Model") and v.PrimaryPart then
			local originalPos = originalData[v].Position
			local originalCFrame = originalData[v].CFrame

			-- Create new position with hover offset
			local newPosition = originalPos + Vector3.new(0, hoverOffset, 0)

			-- Create rotation relative to original orientation
			local rotationCFrame = CFrame.Angles(0, rotationY, rotationZ)
			local newCFrame = CFrame.new(newPosition) * (originalCFrame - originalCFrame.Position) * rotationCFrame

			v:PivotTo(newCFrame)

		elseif v:IsA("GuiObject") then
			-- For GUI objects, just rotate them
			local rotation2D = math.sin(timeElapsed * ROTATION_SPEED) * MAX_ROTATION * 0.5
			v.Rotation = rotation2D
		end
	end
end)

-- Click handler - toggles between hovering and hammer-down states, opens/closes menu
button.MouseButton1Click:Connect(function()
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local menuTi = TweenInfo.new(MENU_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if isHovering then
		-- HAMMER DOWN + OPEN MENU
		print("\n🔨 HAMMER DOWN! - Opening menu")
		isHovering = false

		-- Tween menu and button positions to OPEN
		TweenService:Create(buildingMenu, menuTi, {
			Position = MENU_OPEN_POS
		}):Play()

		TweenService:Create(view, menuTi, {
			Position = BUTTON_OPEN_POS
		}):Play()

		local targetOrientation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(90))

		for _, v in pairs(button:GetChildren()) do
			if v:IsA("LocalScript") then continue end

			-- SAFETY CHECK: Only proceed if we have original data for this object
			if not originalData[v] then
				continue -- Skip this object if no original data
			end

			if v:IsA("BasePart") then
				local originalPos = originalData[v].Position
				local targetCFrame = CFrame.new(originalPos) * targetOrientation
				TweenService:Create(v, ti, {
					CFrame = targetCFrame
				}):Play()

			elseif v:IsA("Model") and v.PrimaryPart then
				local originalPos = originalData[v].Position
				local targetCFrame = CFrame.new(originalPos) * targetOrientation
				TweenService:Create(v, ti, {
					WorldPivot = targetCFrame
				}):Play()

			elseif v:IsA("GuiObject") then
				TweenService:Create(v, ti, {
					Rotation = 90
				}):Play()
			end
		end
	else
		-- LIFT UP + CLOSE MENU
		print("\n⬆️ LIFTING UP! - Closing menu")

		-- Tween menu and button positions to CLOSED
		TweenService:Create(buildingMenu, menuTi, {
			Position = MENU_CLOSE_POS
		}):Play()

		TweenService:Create(view, menuTi, {
			Position = BUTTON_CLOSE_POS
		}):Play()

		for _, v in pairs(button:GetChildren()) do
			if v:IsA("LocalScript") then continue end

			-- SAFETY CHECK: Only proceed if we have original data for this object
			if not originalData[v] then
				continue -- Skip this object if no original data
			end

			if v:IsA("BasePart") then
				local originalCFrame = originalData[v].CFrame
				TweenService:Create(v, ti, {
					CFrame = originalCFrame
				}):Play()

			elseif v:IsA("Model") and v.PrimaryPart then
				local originalCFrame = originalData[v].CFrame
				TweenService:Create(v, ti, {
					WorldPivot = originalCFrame
				}):Play()

			elseif v:IsA("GuiObject") then
				TweenService:Create(v, ti, {
					Rotation = 0
				}):Play()
			end
		end

		-- Resume hovering after animation completes
		task.delay(0.3, function()
			isHovering = true
		end)
	end

	remote:FireServer()
end)