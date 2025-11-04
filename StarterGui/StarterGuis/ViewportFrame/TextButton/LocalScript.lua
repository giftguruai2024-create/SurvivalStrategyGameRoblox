-- @ScriptType: LocalScript
local button = script.Parent
local view = button.Parent
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local replicated = game:GetService('ReplicatedStorage')
local events = replicated:WaitForChild('Events')
local remote = events:WaitForChild('Clicked')  -- No require() needed!
-- Settings
local ROTATION_STRENGTH = 0.25 -- How much the head tilts (0.1 = subtle, 0.5 = noticeable)
local TWEEN_SPEED = 0.5 -- How fast it follows the mouse
local MAX_TILT = 80 -- Maximum degrees of tilt in any direction

-- Dynamic size settings
local MAX_SIZE = Vector3.new(2.5, 1.25, 1.25) -- Maximum size at center
local ENABLE_SIZE_SCALING = true -- Toggle size scaling feature
local SIZE_CENTER_POSITION = UDim2.new(0.086, 0, 0.76, 0) -- Specific center point for sizing

-- Model's neutral orientation (facing the camera)
local NEUTRAL_ORIENTATION = Vector3.new(0, 180, 0)

-- Toggle state
local isTrackingEnabled = true

-- Logging settings
local LOG_EVERY_N_FRAMES = 3000 -- Log every 30 frames (about twice per second at 60fps)
local frameCounter = 0

-- Store original sizes for each object
local originalSizes = {}

print("--- Continuous Head Tracking System Loaded ---")
print("Click the button to toggle tracking on/off")
print("🔥 Dynamic size scaling: ENABLED (grows when mouse near custom center)")
print(string.format("📍 Size center: {%.3f, %d},{%.3f, %d}", SIZE_CENTER_POSITION.X.Scale, SIZE_CENTER_POSITION.X.Offset, SIZE_CENTER_POSITION.Y.Scale, SIZE_CENTER_POSITION.Y.Offset))

-- Function to store original sizes
local function storeOriginalSizes()
	for _, v in pairs(button:GetChildren()) do
		if v:IsA("LocalScript") then continue end

		if v:IsA("BasePart") then
			originalSizes[v] = v.Size
		elseif v:IsA("Model") and v.PrimaryPart then
			originalSizes[v] = v.PrimaryPart.Size
		end
	end
	print("✅ Stored original sizes for", #originalSizes, "objects")
end

-- Call this once at startup
storeOriginalSizes()

-- Function to calculate distance from the custom size center
local function calculateDistanceFromSizeCenter()
	local mousePos = UserInputService:GetMouseLocation()

	-- Convert UDim2 position to absolute screen position
	local sizeCenterX = (view.AbsolutePosition.X + (SIZE_CENTER_POSITION.X.Scale * view.AbsoluteSize.X))+55
	local sizeCenterY = (view.AbsolutePosition.Y + (SIZE_CENTER_POSITION.Y.Scale * view.AbsoluteSize.Y))+20

	-- Calculate offset from size center
	local offsetX = mousePos.X - sizeCenterX
	local offsetY = mousePos.Y - sizeCenterY

	-- Calculate distance from center (normalized 0-1)
	local maxDistance = math.sqrt((view.AbsoluteSize.X/2)^2 + (view.AbsoluteSize.Y/2)^2)
	local currentDistance = math.sqrt(offsetX^2 + offsetY^2)
	local normalizedDistance = math.clamp(currentDistance / maxDistance, 0, 1)

	return normalizedDistance, sizeCenterX, sizeCenterY
end

-- Function to calculate size based on distance from center
local function calculateSizeFromDistance(originalSize, distanceFromCenter)
	if not ENABLE_SIZE_SCALING then
		return originalSize
	end

	-- distanceFromCenter ranges from 0 (at center) to 1 (at edges)
	-- We want size to be MAX at center (distance = 0) and original at edges (distance = 1)
	local sizeFactor = 1 - distanceFromCenter -- 1 at center, 0 at edges

	-- Interpolate between original size and max size
	-- At center: full MAX_SIZE, at edges: original size
	local targetSize = originalSize:Lerp(MAX_SIZE, sizeFactor)

	-- Maintain proportional shape: for every X change, Y and Z change by half
	-- Calculate the X difference from original
	local xDiff = targetSize.X - originalSize.X

	-- Apply the proportional rule
	local newY = originalSize.Y + (xDiff * 0.5)
	local newZ = originalSize.Z + (xDiff * 0.5)

	return Vector3.new(targetSize.X, newY, newZ)
end

-- Function to calculate rotation to look at mouse
local function calculateLookAtCFrame(basePart)
	local mousePos = UserInputService:GetMouseLocation()
	local viewCenter = view.AbsolutePosition + (view.AbsoluteSize / 2)

	-- Calculate offset from center (for rotation)
	local offsetX = mousePos.X - viewCenter.X
	local offsetY = mousePos.Y - viewCenter.Y

	-- Get distance from size center (for size scaling)
	local sizeDistance, sizeCenterX, sizeCenterY = calculateDistanceFromSizeCenter()

	-- Normalize based on view size
	local normalizedX = offsetX / (view.AbsoluteSize.X / 2)
	local normalizedY = offsetY / (view.AbsoluteSize.Y / 2)

	-- Clamp to -1 to 1 range
	normalizedX = math.clamp(normalizedX, -1, 1)
	normalizedY = math.clamp(normalizedY, -1, 1)

	-- Calculate rotation in degrees
	local rotateY = normalizedX * MAX_TILT * ROTATION_STRENGTH -- Yaw (left/right)
	local rotateX = -normalizedY * MAX_TILT * ROTATION_STRENGTH -- Pitch (up/down)
	local rotateZ = normalizedX * (MAX_TILT * 0.3) * ROTATION_STRENGTH -- Slight roll

	-- Periodic logging
	frameCounter = frameCounter + 1
	if frameCounter >= LOG_EVERY_N_FRAMES then
		frameCounter = 0
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("📍 MOUSE POSITION:")
		print(string.format("   Mouse: (%.1f, %.1f)", mousePos.X, mousePos.Y))
		print(string.format("   Rotation Center: (%.1f, %.1f)", viewCenter.X, viewCenter.Y))
		print(string.format("   Size Center: (%.1f, %.1f)", sizeCenterX, sizeCenterY))
	
		print("\n📏 SIZE SCALE:")
		print(string.format("   Distance from SIZE center: %.3f (0=center, 1=edge)", sizeDistance))
		print(string.format("   Scale factor: %.2f%% (100%% at size center)", (1 - sizeDistance) * 100))
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	end

	-- Create CFrame from neutral orientation using Euler angles
	local neutralCFrame = CFrame.fromEulerAnglesYXZ(
		math.rad(NEUTRAL_ORIENTATION.X),
		math.rad(NEUTRAL_ORIENTATION.Y),
		math.rad(NEUTRAL_ORIENTATION.Z)
	)

	-- Create tilt CFrame using Euler angles (convert degrees to radians)
	local tiltCFrame = CFrame.fromEulerAnglesYXZ(
		math.rad(rotateX),
		math.rad(rotateY),
		math.rad(rotateZ)
	)

	-- Compose the rotations: neutral * tilt, preserving the original position
	local finalCFrame = CFrame.new(basePart.Position) * neutralCFrame * tiltCFrame

	return finalCFrame, sizeDistance
end

-- Continuous tracking loop
RunService.RenderStepped:Connect(function()
	if not isTrackingEnabled then return end

	local ti = TweenInfo.new(TWEEN_SPEED, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, v in pairs(button:GetChildren()) do
		if v:IsA("LocalScript") then continue end

		-- Use CFrame for 3D objects (BasePart, Model, etc.)
		if v:IsA("BasePart") then
			local targetCFrame, distance = calculateLookAtCFrame(v)
			local originalSize = originalSizes[v] or v.Size
			local targetSize = calculateSizeFromDistance(originalSize, distance)

			TweenService:Create(v, ti, {
				CFrame = targetCFrame,
				Size = targetSize
			}):Play()
		elseif v:IsA("Model") and v.PrimaryPart then
			local targetCFrame, distance = calculateLookAtCFrame(v.PrimaryPart)
			local originalSize = originalSizes[v] or v.PrimaryPart.Size
			local targetSize = calculateSizeFromDistance(originalSize, distance)

			-- Apply size to PrimaryPart
			TweenService:Create(v.PrimaryPart, ti, {
				Size = targetSize
			}):Play()

			-- Apply rotation to model
			TweenService:Create(v, ti, {
				WorldPivot = targetCFrame
			}):Play()

			-- Use Rotation for 2D GUI objects (ImageLabel, TextLabel, etc.)
		elseif v:IsA("GuiObject") then
			-- For GUI, calculate a simple 2D rotation
			local mousePos = UserInputService:GetMouseLocation()
			local viewCenter = view.AbsolutePosition + (view.AbsoluteSize / 2)
			local offsetX = mousePos.X - viewCenter.X
			local normalizedX = math.clamp(offsetX / (view.AbsoluteSize.X / 2), -1, 1)

			local targetRotation2D = normalizedX * MAX_TILT * ROTATION_STRENGTH * 0.7
			TweenService:Create(v, ti, {
				Rotation = targetRotation2D
			}):Play()
		end
	end
end)


-- Pop effect on button click
button.MouseButton1Click:Connect(function()
	print("\n💥 POP EFFECT!")

	-- Grow phase - bigger than max
	local growTi = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local shrinkTi = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local popSize = MAX_SIZE * 1.4 -- 40% bigger than max size

	for _, v in pairs(button:GetChildren()) do
		if v:IsA("LocalScript") then continue end

		if v:IsA("BasePart") then
			local originalSize = originalSizes[v] or v.Size

			-- Grow
			local growTween = TweenService:Create(v, growTi, {
				Size = popSize
			})
			growTween:Play()

			-- Shrink back after delay
			task.delay(0.15, function()
				TweenService:Create(v, shrinkTi, {
					Size = originalSize
				}):Play()
			end)

		elseif v:IsA("Model") and v.PrimaryPart then
			local originalSize = originalSizes[v] or v.PrimaryPart.Size

			-- Grow
			local growTween = TweenService:Create(v.PrimaryPart, growTi, {
				Size = popSize
			})
			growTween:Play()

			-- Shrink back after delay
			task.delay(0.15, function()
				TweenService:Create(v.PrimaryPart, shrinkTi, {
					Size = originalSize
				}):Play()
			end)
		end
	end
	remote:FireServer()
end)