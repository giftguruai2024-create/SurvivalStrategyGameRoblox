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

print("--- Hovering Button System Loaded ---")
print("Objects will hover up/down and rotate smoothly")
print("Click to open menu (hammer down) / Click again to close menu (lift up)")

-- Set initial positions to closed
buildingMenu.Position = MENU_CLOSE_POS
view.Position = BUTTON_CLOSE_POS

-- Function to store original positions and orientations
local function storeOriginalData()
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
	print("✅ Stored original data for", #originalData, "objects")
end

-- Call this once at startup
storeOriginalData()

-- Continuous hovering loop
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