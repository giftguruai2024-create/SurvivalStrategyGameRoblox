-- @ScriptType: LocalScript
-- Multi-mode camera control system
-- Place this in StarterPlayer > StarterPlayerScripts
-- 
-- Camera Modes:
-- 1. FREE MODE (default) - Original WASD movement camera
-- 2. ORBIT MODE - Rotate around fixed grid center with Q/E
-- 3. EDGE PAN MODE - Move camera by moving mouse to screen edges
--
-- Controls:
-- TAB - Switch between camera modes
-- WASD - Move camera (in FREE and ORBIT modes)
-- Q/E - Rotate camera (in ORBIT mode only)
-- Mouse Wheel - Zoom in/out (all modes)
-- Mouse edges - Move camera (in EDGE PAN mode only)

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild('Events')
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Wait for the GridReady event
local gridReadyEvent = Events:WaitForChild("GridReady")
player.CameraMaxZoomDistance = 1000
player.CameraMinZoomDistance = 0.5

-- ========================================
-- CONFIGURATION
-- ========================================
local GRID_SIZE = 100 -- Must match server configuration
local CELL_SIZE = 2 -- Must match server configuration
local BEACH_THICKNESS = 2 -- Must match server configuration

-- Camera settings
local CAMERA_SPEED = 0.5 -- How fast the camera moves
local ZOOM_SPEED = 2 -- How fast zoom changes
local ROTATION_SPEED = 1 -- How fast rotation changes (degrees per frame when held)
local MIN_ZOOM = 20 -- Minimum height above ground
local MAX_ZOOM = 100 -- Maximum height above ground
local INITIAL_HEIGHT = 50 -- Starting height above grid center
local CAMERA_ANGLE = 15 -- Angle of camera (degrees from horizontal) - 90 = straight down
local CHARACTER_OFFSET = 5 -- How far above the camera to keep the character (in studs)

-- Edge pan settings
local EDGE_PAN_MARGIN = 50 -- Pixels from screen edge to start panning
local EDGE_PAN_SPEED = 0.3 -- Speed of edge panning
-- ========================================

-- Calculate grid boundaries
local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
local gridWorldSize = totalGridSize * CELL_SIZE
local halfGridSize = gridWorldSize / 2

-- Camera modes
local CAMERA_MODES = {
	FREE = 1,
	ORBIT = 2,
	EDGE_PAN = 3
}

local CAMERA_MODE_NAMES = {
	[CAMERA_MODES.FREE] = "FREE MODE",
	[CAMERA_MODES.ORBIT] = "ORBIT MODE", 
	[CAMERA_MODES.EDGE_PAN] = "EDGE PAN MODE"
}

-- Camera state
local currentMode = CAMERA_MODES.FREE
local gridCenter = Vector3.new(0, 0, 0) -- Fixed pivot point for orbit mode
local cameraPosition = Vector3.new(0, INITIAL_HEIGHT, 0) -- Start at center
local cameraHeight = INITIAL_HEIGHT
local keysPressed = {
	W = false,
	A = false,
	S = false,
	D = false,
	Q = false,
	E = false
}

-- Character references
local character = nil
local humanoidRootPart = nil

-- Convert camera angle to radians
local angleRadians = math.rad(CAMERA_ANGLE)

-- Function to display camera mode
local function showCameraMode()
	StarterGui:SetCore("ChatMakeSystemMessage", {
		Text = "Camera Mode: " .. CAMERA_MODE_NAMES[currentMode];
		Color = Color3.fromRGB(255, 255, 0);
		Font = Enum.Font.GothamBold;
		FontSize = Enum.FontSize.Size18;
	})
end

-- Function to update character references
local function updateCharacterReferences()
	character = player.Character
	if character then
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	end
end

-- Function to clamp camera position within grid bounds
local function clampToGridBounds(position)
	local clampedX = math.clamp(position.X, -halfGridSize, halfGridSize)
	local clampedZ = math.clamp(position.Z, -halfGridSize, halfGridSize)
	return Vector3.new(clampedX, position.Y, clampedZ)
end

-- FREE MODE: Original camera behavior
local function updateFreeMode()
	-- Calculate movement direction based on keys pressed
	local moveDirection = Vector3.new(0, 0, 0)

	if keysPressed.W then
		moveDirection = moveDirection + Vector3.new(0, 0, -1) -- Forward (negative Z)
	end
	if keysPressed.S then
		moveDirection = moveDirection + Vector3.new(0, 0, 1) -- Backward (positive Z)
	end
	if keysPressed.A then
		moveDirection = moveDirection + Vector3.new(-1, 0, 0) -- Left (negative X)
	end
	if keysPressed.D then
		moveDirection = moveDirection + Vector3.new(1, 0, 0) -- Right (positive X)
	end

	-- Normalize movement if moving diagonally
	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit
	end

	-- Apply movement with speed scaling based on height (higher = faster movement)
	local speedMultiplier = cameraHeight / INITIAL_HEIGHT
	cameraPosition = cameraPosition + (moveDirection * CAMERA_SPEED * speedMultiplier)

	-- Update Y position based on current height
	cameraPosition = Vector3.new(cameraPosition.X, cameraHeight, cameraPosition.Z)

	-- Clamp position to grid bounds
	cameraPosition = clampToGridBounds(cameraPosition)

	-- MOVE CHARACTER WITH CAMERA
	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end

	-- Calculate look-at point based on angle
	if CAMERA_ANGLE >= 90 then
		local lookAtPoint = cameraPosition - Vector3.new(0, cameraHeight, 0)
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	else
		local maxForwardDistance = math.min(cameraHeight / math.tan(angleRadians), halfGridSize * 0.5)
		local lookAtOffset = Vector3.new(0, 0, maxForwardDistance)
		local lookAtPoint = cameraPosition - Vector3.new(0, cameraHeight, 0) - lookAtOffset
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	end
end

-- ORBIT MODE: Rotate around fixed grid center
local function updateOrbitMode()
	-- Handle rotation around the FIXED grid center
	if keysPressed.Q then
		local offsetX = cameraPosition.X - gridCenter.X
		local offsetZ = cameraPosition.Z - gridCenter.Z
		local cosRot = math.cos(-math.rad(ROTATION_SPEED))
		local sinRot = math.sin(-math.rad(ROTATION_SPEED))
		local newOffsetX = offsetX * cosRot - offsetZ * sinRot
		local newOffsetZ = offsetX * sinRot + offsetZ * cosRot
		cameraPosition = Vector3.new(
			gridCenter.X + newOffsetX,
			cameraPosition.Y,
			gridCenter.Z + newOffsetZ
		)
	end
	if keysPressed.E then
		local offsetX = cameraPosition.X - gridCenter.X
		local offsetZ = cameraPosition.Z - gridCenter.Z
		local cosRot = math.cos(math.rad(ROTATION_SPEED))
		local sinRot = math.sin(math.rad(ROTATION_SPEED))
		local newOffsetX = offsetX * cosRot - offsetZ * sinRot
		local newOffsetZ = offsetX * sinRot + offsetZ * cosRot
		cameraPosition = Vector3.new(
			gridCenter.X + newOffsetX,
			cameraPosition.Y,
			gridCenter.Z + newOffsetZ
		)
	end

	-- Calculate movement direction for WASD
	local moveDirection = Vector3.new(0, 0, 0)

	if keysPressed.W then
		moveDirection = moveDirection + Vector3.new(0, 0, -1)
	end
	if keysPressed.S then
		moveDirection = moveDirection + Vector3.new(0, 0, 1)
	end
	if keysPressed.A then
		moveDirection = moveDirection + Vector3.new(-1, 0, 0)
	end
	if keysPressed.D then
		moveDirection = moveDirection + Vector3.new(1, 0, 0)
	end

	-- Normalize movement if moving diagonally
	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit
	end

	-- Apply normal camera movement
	local speedMultiplier = cameraHeight / INITIAL_HEIGHT
	cameraPosition = cameraPosition + (moveDirection * CAMERA_SPEED * speedMultiplier)

	-- Update Y position and clamp
	cameraPosition = Vector3.new(cameraPosition.X, cameraHeight, cameraPosition.Z)
	cameraPosition = clampToGridBounds(cameraPosition)

	-- MOVE CHARACTER WITH CAMERA
	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end

	-- Always look towards the FIXED grid center
	camera.CFrame = CFrame.new(cameraPosition, gridCenter)
end

-- EDGE PAN MODE: Move camera by moving mouse to screen edges
local function updateEdgePanMode()
	local mouse = player:GetMouse()
	local screenSize = camera.ViewportSize
	local mousePos = Vector2.new(mouse.X, mouse.Y)

	local moveDirection = Vector3.new(0, 0, 0)

	-- Check screen edges
	if mousePos.X <= EDGE_PAN_MARGIN then
		moveDirection = moveDirection + Vector3.new(-1, 0, 0) -- Left
	elseif mousePos.X >= screenSize.X - EDGE_PAN_MARGIN then
		moveDirection = moveDirection + Vector3.new(1, 0, 0) -- Right
	end

	if mousePos.Y <= EDGE_PAN_MARGIN then
		moveDirection = moveDirection + Vector3.new(0, 0, -1) -- Up
	elseif mousePos.Y >= screenSize.Y - EDGE_PAN_MARGIN then
		moveDirection = moveDirection + Vector3.new(0, 0, 1) -- Down
	end

	-- Normalize movement if moving diagonally
	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit
	end

	-- Apply movement
	local speedMultiplier = cameraHeight / INITIAL_HEIGHT
	cameraPosition = cameraPosition + (moveDirection * EDGE_PAN_SPEED * speedMultiplier)

	-- Update Y position and clamp
	cameraPosition = Vector3.new(cameraPosition.X, cameraHeight, cameraPosition.Z)
	cameraPosition = clampToGridBounds(cameraPosition)

	-- MOVE CHARACTER WITH CAMERA
	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end

	-- Calculate look-at point based on angle (same as free mode)
	if CAMERA_ANGLE >= 90 then
		local lookAtPoint = cameraPosition - Vector3.new(0, cameraHeight, 0)
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	else
		local maxForwardDistance = math.min(cameraHeight / math.tan(angleRadians), halfGridSize * 0.5)
		local lookAtOffset = Vector3.new(0, 0, maxForwardDistance)
		local lookAtPoint = cameraPosition - Vector3.new(0, cameraHeight, 0) - lookAtOffset
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	end
end

-- Main camera update function
local function updateCamera()
	if currentMode == CAMERA_MODES.FREE then
		updateFreeMode()
	elseif currentMode == CAMERA_MODES.ORBIT then
		updateOrbitMode()
	elseif currentMode == CAMERA_MODES.EDGE_PAN then
		updateEdgePanMode()
	end
end

-- Function to switch camera modes
local function switchCameraMode()
	currentMode = currentMode + 1
	if currentMode > 3 then
		currentMode = 1
	end
	showCameraMode()
end

-- Handle keyboard input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Tab then
		switchCameraMode()
	elseif input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = true
	elseif input.KeyCode == Enum.KeyCode.Q then
		keysPressed.Q = true
	elseif input.KeyCode == Enum.KeyCode.E then
		keysPressed.E = true
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = false
	elseif input.KeyCode == Enum.KeyCode.Q then
		keysPressed.Q = false
	elseif input.KeyCode == Enum.KeyCode.E then
		keysPressed.E = false
	end
end)

-- Handle zoom with scroll wheel
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		cameraHeight = cameraHeight - (input.Position.Z * ZOOM_SPEED)
		cameraHeight = math.clamp(cameraHeight, MIN_ZOOM, MAX_ZOOM)
	end
end)

-- Camera is ready to update
local cameraReady = false

-- Listen for GridReady event from server
gridReadyEvent.OnClientEvent:Connect(function(gridCenterFromServer, initialHeight)
	print("Grid ready! Initializing camera at: " .. tostring(gridCenterFromServer))

	-- Update character references
	updateCharacterReferences()

	-- Set camera to scriptable mode (detached from character)
	camera.CameraType = Enum.CameraType.Scriptable

	-- Set the FIXED grid center for orbit mode
	gridCenter = Vector3.new(gridCenterFromServer.X, gridCenterFromServer.Y, gridCenterFromServer.Z)
	cameraHeight = initialHeight

	-- Start camera at the grid center
	cameraPosition = Vector3.new(gridCenter.X, cameraHeight, gridCenter.Z)

	-- Move character to camera position initially
	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end

	cameraReady = true

	print("Multi-mode camera initialized!")
	print("TAB - Switch camera modes")
	print("WASD - Move camera (FREE/ORBIT modes)")
	print("Q/E - Rotate camera (ORBIT mode only)")
	print("Mouse edges - Move camera (EDGE PAN mode)")
	print("Mouse Wheel - Zoom")
	showCameraMode()
end)

-- Initialize camera
local function initializeCamera()
	player.CharacterAdded:Wait()
	updateCharacterReferences()
	print("Character loaded, waiting for grid...")
end

-- Update camera every frame (only if camera is ready)
RunService.RenderStepped:Connect(function()
	if cameraReady then
		updateCamera()
	end
end)

-- Initialize when script loads
initializeCamera()

-- Re-initialize if player respawns
player.CharacterAdded:Connect(function()
	wait(0.1)
	updateCharacterReferences()
	camera.CameraType = Enum.CameraType.Scriptable

	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end
end)