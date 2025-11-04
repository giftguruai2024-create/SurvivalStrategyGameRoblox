-- @ScriptType: LocalScript
-- Local script for camera control system
-- Place this in StarterPlayer > StarterPlayerScripts

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Wait for the GridReady event
local gridReadyEvent = ReplicatedStorage:WaitForChild("GridReady")
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
local MIN_ZOOM = 20 -- Minimum height above ground
local MAX_ZOOM = 100 -- Maximum height above ground
local INITIAL_HEIGHT = 50 -- Starting height above grid center
local CAMERA_ANGLE = 90 -- Angle of camera (degrees from horizontal) - 90 = straight down
local CHARACTER_OFFSET = 5 -- How far above the camera to keep the character (in studs)
local CURSOR_ROTATION_STRENGTH = 0.15 -- How much the camera rotates towards cursor (0 = none, 1 = full)
local CURSOR_ROTATION_SMOOTHNESS = 0.1 -- How smoothly camera follows cursor (lower = smoother)
-- ========================================

-- Calculate grid boundaries
local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
local gridWorldSize = totalGridSize * CELL_SIZE
local halfGridSize = gridWorldSize / 2

-- Camera state
local cameraPosition = Vector3.new(0, INITIAL_HEIGHT, 0) -- Start at center
local cameraHeight = INITIAL_HEIGHT
local keysPressed = {
	W = false,
	A = false,
	S = false,
	D = false
}

-- Cursor tracking state
local currentCursorOffset = Vector3.new(0, 0, 0)
local targetCursorOffset = Vector3.new(0, 0, 0)

-- Character references
local character = nil
local humanoidRootPart = nil

-- Convert camera angle to radians
local angleRadians = math.rad(CAMERA_ANGLE)

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

-- Function to get world position of mouse on a plane at a given height
local function getMouseWorldPosition(planeHeight)
	local mouse = player:GetMouse()
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Calculate intersection with horizontal plane at planeHeight
	-- Ray equation: P = Origin + Direction * t
	-- Plane equation: Y = planeHeight
	-- Solve for t: Origin.Y + Direction.Y * t = planeHeight

	if math.abs(mouseRay.Direction.Y) > 0.0001 then -- Avoid division by zero
		local t = (planeHeight - mouseRay.Origin.Y) / mouseRay.Direction.Y
		if t > 0 then -- Only consider intersections in front of camera
			local worldPos = mouseRay.Origin + mouseRay.Direction * t
			return worldPos
		end
	end

	return nil
end

-- Function to update camera position and orientation
local function updateCamera()
	-- Calculate movement direction based on keys pressed
	local moveDirection = Vector3.new(0, 0, 0)

	if keysPressed.A then
		moveDirection = moveDirection + Vector3.new(0, 0, -1) -- Forward (negative Z)
	end
	if keysPressed.D then
		moveDirection = moveDirection + Vector3.new(0, 0, 1) -- Backward (positive Z)
	end
	if keysPressed.S then
		moveDirection = moveDirection + Vector3.new(-1, 0, 0) -- Left (negative X)
	end
	if keysPressed.W then
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

	-- MOVE CHARACTER WITH CAMERA (This prevents the player from dying)
	if humanoidRootPart then
		-- Keep character above the camera, following camera's X, Y, and Z position
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end

	-- Get mouse world position on ground plane
	local mouseWorldPos = getMouseWorldPosition(0)

	if mouseWorldPos then
		-- Calculate direction from camera to mouse position
		local directionToMouse = (mouseWorldPos - cameraPosition).Unit

		-- Calculate target offset based on cursor position
		-- We want to tilt the camera slightly towards the cursor
		local offsetStrength = CURSOR_ROTATION_STRENGTH * cameraHeight * 0.5
		targetCursorOffset = Vector3.new(
			directionToMouse.X * offsetStrength,
			0,
			directionToMouse.Z * offsetStrength
		)
	end

	-- Smoothly interpolate current offset towards target offset
	currentCursorOffset = currentCursorOffset:Lerp(targetCursorOffset, CURSOR_ROTATION_SMOOTHNESS)

	-- Calculate look-at point based on angle and cursor offset
	if CAMERA_ANGLE >= 90 then
		-- Look straight down with slight offset towards cursor
		local lookAtPoint = cameraPosition - Vector3.new(0, cameraHeight, 0) + currentCursorOffset
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	else
		-- Angled view with cursor offset
		local lookAtOffset = Vector3.new(0, 0, cameraHeight / math.tan(angleRadians))
		local lookAtPoint = cameraPosition - lookAtOffset + currentCursorOffset
		camera.CFrame = CFrame.new(cameraPosition, lookAtPoint)
	end
end

-- Handle keyboard input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = true
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
	end
end)

-- Handle zoom with scroll wheel
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Negative delta = scroll up = zoom in (decrease height)
		-- Positive delta = scroll down = zoom out (increase height)
		cameraHeight = cameraHeight - (input.Position.Z * ZOOM_SPEED)

		-- Clamp height to zoom limits
		cameraHeight = math.clamp(cameraHeight, MIN_ZOOM, MAX_ZOOM)
	end
end)

-- Camera is ready to update
local cameraReady = false

-- Listen for GridReady event from server
gridReadyEvent.OnClientEvent:Connect(function(gridCenter, initialHeight)
	print("Grid ready! Initializing camera at: " .. tostring(gridCenter))

	-- Update character references
	updateCharacterReferences()

	-- Set camera to scriptable mode (detached from character)
	camera.CameraType = Enum.CameraType.Scriptable

	-- Set initial position to center of grid (from server)
	cameraPosition = Vector3.new(gridCenter.X, initialHeight, gridCenter.Z)
	cameraHeight = initialHeight

	-- Move character to grid center immediately (above the camera)
	if humanoidRootPart then
		local characterHeight = initialHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(gridCenter.X, characterHeight, gridCenter.Z)
	end

	cameraReady = true

	print("Camera initialized at grid center")
	print("Controls: WASD to move, Scroll Wheel to zoom")
	print("Camera bounds: X(" .. -halfGridSize .. " to " .. halfGridSize .. "), Z(" .. -halfGridSize .. " to " .. halfGridSize .. ")")
end)

-- Initialize camera
local function initializeCamera()
	-- Wait for character to load
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
	wait(0.1) -- Small delay to ensure everything is loaded
	updateCharacterReferences()
	camera.CameraType = Enum.CameraType.Scriptable

	-- Move character back to last camera position (above the camera)
	if humanoidRootPart then
		local characterHeight = cameraHeight + CHARACTER_OFFSET
		humanoidRootPart.CFrame = CFrame.new(cameraPosition.X, characterHeight, cameraPosition.Z)
	end
end)