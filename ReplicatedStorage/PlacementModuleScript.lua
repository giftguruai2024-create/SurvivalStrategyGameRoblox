-- @ScriptType: ModuleScript
-- PlacementModuleScript
-- Handles structure placement logic for grid-based systems
-- Place this in ReplicatedStorage or ServerStorage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StructureManager = require(ReplicatedStorage:WaitForChild("StructureManager"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local PlacementModule = {}
PlacementModule.__index = PlacementModule

-- ========================================
-- CONFIGURATION
-- ========================================
local placementDefaults = GameConfig.GetPlacement()

local DEFAULT_CONFIG = {
	CELL_SIZE = placementDefaults.CELL_SIZE,
	PLACEMENT_HEIGHT_OFFSET = placementDefaults.PLACEMENT_HEIGHT_OFFSET,
	DEBUG_PLACEMENT = placementDefaults.DEBUG_PLACEMENT,
}

-- ========================================
-- PLACEMENT CLASS
-- ========================================

function PlacementModule.new(config)
	local self = setmetatable({}, PlacementModule)

	-- Merge config with defaults
	self.config = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		self.config[key] = value
	end
	if config then
		for key, value in pairs(config) do
			self.config[key] = value
		end
	end

	-- Initialize StructureManager
	self.structureManager = StructureManager.new()

	print("[PlacementModule] Initialized with cell size:", self.config.CELL_SIZE)
	return self
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

function PlacementModule:CalculateStructureSize(model)
	-- Calculate how many cells a structure occupies based on its PrimaryPart size
	-- Each world grid cell is 3 studs, so we divide PrimaryPart X and Z by 3
	if not model or not model:IsA("Model") or not model.PrimaryPart then
		warn("[PlacementModule] Invalid model provided to CalculateStructureSize")
		return 1, 1 -- Default to 1x1
	end

	local primaryPart = model.PrimaryPart
	local partSizeX = primaryPart.Size.X
	local partSizeZ = primaryPart.Size.Z

	-- Calculate grid cells: divide by cell size (3 studs) and round
	local cellsX = math.round(partSizeX / self.config.CELL_SIZE)
	local cellsZ = math.round(partSizeZ / self.config.CELL_SIZE)

	-- Ensure minimum size of 1x1 cell
	cellsX = math.max(1, cellsX)
	cellsZ = math.max(1, cellsZ)

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Structure PrimaryPart size: %.1fx%.1f studs", partSizeX, partSizeZ))
		print(string.format("[PlacementModule] Grid calculation: %.1f÷3=%.1f, %.1f÷3=%.1f", 
			partSizeX, partSizeX/3, partSizeZ, partSizeZ/3))
		print(string.format("[PlacementModule] Final grid size: %dx%d cells", cellsX, cellsZ))
	end

	return cellsX, cellsZ
end

function PlacementModule:GetCellWorldPosition(gridCells, x, z)
	-- Get the world position of a specific grid cell
	if gridCells[x] and gridCells[x][z] then
		return gridCells[x][z].Position
	end
	return nil
end

function PlacementModule:SnapToGrid(gridCells, x, z, sizeX, sizeZ)
	-- Snap a structure position to align perfectly with grid cells
	-- For multi-cell structures, we need to ensure they align to cell boundaries

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Snapping %dx%d structure to grid at (%d, %d)", sizeX, sizeZ, x, z))
	end

	-- Get the center cell position
	local centerCell = self:GetCellWorldPosition(gridCells, x, z)
	if not centerCell then
		warn("[PlacementModule] Invalid grid position for snapping:", x, z)
		return nil
	end

	-- For structures larger than 1x1, we need to calculate the proper center position
	-- The structure should span evenly around the center cell
	local offsetX = 0
	local offsetZ = 0

	-- If the structure has an even number of cells, we need to offset by half a cell
	if sizeX % 2 == 0 then
		offsetX = self.config.CELL_SIZE / 2
	end
	if sizeZ % 2 == 0 then
		offsetZ = self.config.CELL_SIZE / 2
	end

	-- Calculate the snapped world position
	local snappedPosition = Vector3.new(
		centerCell.X + offsetX,
		centerCell.Y,
		centerCell.Z + offsetZ
	)

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Snapped position: %s (offset: %.1f, %.1f)", 
			tostring(snappedPosition), offsetX, offsetZ))
	end

	return snappedPosition
end

function PlacementModule:CalculateStructureBounds(centerX, centerZ, sizeX, sizeZ)
	-- Calculate the start and end cell coordinates for a structure
	local startX = centerX - math.floor(sizeX / 2)
	local startZ = centerZ - math.floor(sizeZ / 2)
	local endX = startX + sizeX - 1
	local endZ = startZ + sizeZ - 1

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Structure bounds: (%d,%d) to (%d,%d) for %dx%d structure at center (%d,%d)", 
			startX, startZ, endX, endZ, sizeX, sizeZ, centerX, centerZ))
	end

	return startX, startZ, endX, endZ
end

function PlacementModule:ValidateGridAlignment(model, gridCells, x, z)
	-- Validate that a model will align properly with the grid
	local sizeX, sizeZ = self:CalculateStructureSize(model)
	local snappedPosition = self:SnapToGrid(gridCells, x, z, sizeX, sizeZ)

	if not snappedPosition then
		return false, "Invalid grid position"
	end

	-- Check if all required cells exist
	local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, sizeX, sizeZ)

	for checkX = startX, endX do
		for checkZ = startZ, endZ do
			if not gridCells[checkX] or not gridCells[checkX][checkZ] then
				return false, string.format("Cell (%d, %d) doesn't exist", checkX, checkZ)
			end
		end
	end

	return true, "Grid alignment valid"
end

-- ========================================
-- PLACEMENT VALIDATION
-- ========================================

function PlacementModule:IsAreaClear(cellStates, x, z, sizeX, sizeZ, excludeOccupied, excludeBlocked)
	-- Check if an area is clear for placement
	excludeOccupied = excludeOccupied ~= false -- Default to true
	excludeBlocked = excludeBlocked ~= false -- Default to true

	local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, sizeX, sizeZ)

	for checkX = startX, endX do
		for checkZ = startZ, endZ do
			-- Check if cell exists
			if not cellStates[checkX] or not cellStates[checkX][checkZ] then
				if self.config.DEBUG_PLACEMENT then
					print(string.format("[PlacementModule] Cell (%d, %d) doesn't exist", checkX, checkZ))
				end
				return false
			end

			local cellState = cellStates[checkX][checkZ]

			-- Check if cell is occupied by a player
			if excludeOccupied and cellState.occupied then
				if self.config.DEBUG_PLACEMENT then
					print(string.format("[PlacementModule] Cell (%d, %d) is occupied by player", checkX, checkZ))
				end
				return false
			end

			-- Check if cell is blocked by a structure
			if excludeBlocked and cellState.blocked then
				if self.config.DEBUG_PLACEMENT then
					print(string.format("[PlacementModule] Cell (%d, %d) is blocked by structure: %s", 
						checkX, checkZ, cellState.structureType or "Unknown"))
				end
				return false
			end
		end
	end

	return true
end

function PlacementModule:IsWithinBounds(x, z, sizeX, sizeZ, gridBounds)
	-- Check if structure placement is within grid bounds
	local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, sizeX, sizeZ)

	return startX >= gridBounds.minX and endX <= gridBounds.maxX and
		startZ >= gridBounds.minZ and endZ <= gridBounds.maxZ
end

function PlacementModule:IsValidPlacement(cellStates, gridCells, x, z, sizeX, sizeZ, options)
	-- Comprehensive placement validation
	options = options or {}

	-- Default grid bounds (can be overridden in options)
	local gridBounds = options.gridBounds or {
		minX = 1,
		minZ = 1,
		maxX = #gridCells,
		maxZ = #gridCells[1]
	}

	-- Check bounds
	if not self:IsWithinBounds(x, z, sizeX, sizeZ, gridBounds) then
		if self.config.DEBUG_PLACEMENT then
			print(string.format("[PlacementModule] Structure at (%d, %d) is out of bounds", x, z))
		end
		return false
	end

	-- Check if area is clear
	if not self:IsAreaClear(cellStates, x, z, sizeX, sizeZ, options.excludeOccupied, options.excludeBlocked) then
		return false
	end

	-- Custom validation function
	if options.customValidator and not options.customValidator(x, z, sizeX, sizeZ) then
		if self.config.DEBUG_PLACEMENT then
			print(string.format("[PlacementModule] Custom validation failed for (%d, %d)", x, z))
		end
		return false
	end

	return true
end

-- ========================================
-- PLACEMENT LOCATION FINDING
-- ========================================

function PlacementModule:FindCenterPlacement(cellStates, gridCells, sizeX, sizeZ, options)
	-- Find placement at the center of the grid
	local gridSizeX = #gridCells
	local gridSizeZ = #gridCells[1]

	local centerX = math.floor(gridSizeX / 2)
	local centerZ = math.floor(gridSizeZ / 2)

	if self:IsValidPlacement(cellStates, gridCells, centerX, centerZ, sizeX, sizeZ, options) then
		return centerX, centerZ
	end

	return nil, nil
end

function PlacementModule:FindNearestValidPlacement(cellStates, gridCells, preferredX, preferredZ, sizeX, sizeZ, options)
	-- Find the nearest valid placement to a preferred location
	options = options or {}
	local maxSearchRadius = options.maxSearchRadius or 10

	-- Try the preferred location first
	if self:IsValidPlacement(cellStates, gridCells, preferredX, preferredZ, sizeX, sizeZ, options) then
		return preferredX, preferredZ
	end

	-- Search in expanding radius
	for radius = 1, maxSearchRadius do
		for dx = -radius, radius do
			for dz = -radius, radius do
				-- Only check cells at the current radius distance
				if math.abs(dx) == radius or math.abs(dz) == radius then
					local testX = preferredX + dx
					local testZ = preferredZ + dz

					if self:IsValidPlacement(cellStates, gridCells, testX, testZ, sizeX, sizeZ, options) then
						return testX, testZ
					end
				end
			end
		end
	end

	return nil, nil
end

function PlacementModule:FindRandomPlacement(cellStates, gridCells, sizeX, sizeZ, options)
	-- Find a random valid placement location
	options = options or {}
	local maxAttempts = options.maxAttempts or 100

	local gridBounds = options.gridBounds or {
		minX = 1,
		minZ = 1,
		maxX = #gridCells,
		maxZ = #gridCells[1]
	}

	for attempt = 1, maxAttempts do
		local randomX = math.random(gridBounds.minX, gridBounds.maxX)
		local randomZ = math.random(gridBounds.minZ, gridBounds.maxZ)

		if self:IsValidPlacement(cellStates, gridCells, randomX, randomZ, sizeX, sizeZ, options) then
			return randomX, randomZ
		end
	end

	return nil, nil
end

-- ========================================
-- STRUCTURE PLACEMENT
-- ========================================

function PlacementModule:PlaceStructure(model, gridCells, x, z, worldFolder, options)
	-- Place a structure at the specified grid location with perfect grid snapping
	options = options or {}

	if not model or not model:IsA("Model") or not model.PrimaryPart then
		warn("[PlacementModule] Invalid model provided for placement")
		return nil
	end

	if not worldFolder then
		warn("[PlacementModule] No worldFolder provided for placement")
		return nil
	end

	-- Calculate structure size in grid cells (PrimaryPart size ÷ 3)
	local cellsX, cellsZ = self:CalculateStructureSize(model)

	-- Validate grid alignment
	local isValid, errorMsg = self:ValidateGridAlignment(model, gridCells, x, z)
	if not isValid then
		warn("[PlacementModule] Grid alignment validation failed:", errorMsg)
		return nil
	end

	-- Get the snapped position that aligns perfectly with grid cells
	local snappedPosition = self:SnapToGrid(gridCells, x, z, cellsX, cellsZ)
	if not snappedPosition then
		warn("[PlacementModule] Failed to snap to grid at position:", x, z)
		return nil
	end

	-- Clone the model
	local newStructure = model:Clone()
	local structureName = options.name or (model.Name .. "_" .. x .. "_" .. z)
	newStructure.Name = structureName

	-- Calculate final position with PrimaryPart bottom exactly on top of cells
	local heightOffset = options.heightOffset or self.config.PLACEMENT_HEIGHT_OFFSET
	local primaryPart = newStructure.PrimaryPart

	-- Calculate the top surface of the grid cell
	-- Grid cells are positioned with their center at CELL_SIZE/2, so top is at snappedPosition.Y + CELL_SIZE/2
	local cellTopY = snappedPosition.Y + (self.config.CELL_SIZE / 2)

	-- Position the structure so the bottom of the PrimaryPart sits exactly on the cell top
	-- PrimaryPart center should be at: cell top + half of PrimaryPart height
	local finalPosition = Vector3.new(
		snappedPosition.X,
		cellTopY + (primaryPart.Size.Y / 2) + heightOffset,
		snappedPosition.Z
	)

	-- Apply rotation if specified
	local rotation = options.rotation or CFrame.Angles(0, 0, 0)
	if options.randomRotation then
		rotation = CFrame.Angles(0, math.rad(math.random(0, 3) * 90), 0)
	end

	-- Set the structure's position and rotation
	newStructure:SetPrimaryPartCFrame(CFrame.new(finalPosition) * rotation)

	-- Set properties for all parts
	for _, part in ipairs(newStructure:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = options.anchored ~= false -- Default to true
			if options.canCollide ~= nil then
				part.CanCollide = options.canCollide
			end
			-- Ensure visibility
			if part.Transparency >= 1 and options.makeVisible ~= false then
			end
		end
	end

	-- Add attributes if provided
	if options.attributes then
		for key, value in pairs(options.attributes) do
			newStructure:SetAttribute(key, value)
		end
	end

	-- Parent to world folder
	newStructure.Parent = worldFolder

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Placed %s at grid (%d, %d)", structureName, x, z))
		print(string.format("[PlacementModule] Structure occupies %dx%d cells", cellsX, cellsZ))
		print(string.format("[PlacementModule] PrimaryPart size: %.1fx%.1fx%.1f", 
			primaryPart.Size.X, primaryPart.Size.Y, primaryPart.Size.Z))
		print(string.format("[PlacementModule] Cell top Y: %.1f", cellTopY))
		print(string.format("[PlacementModule] PrimaryPart bottom Y: %.1f", finalPosition.Y - (primaryPart.Size.Y / 2)))
		print(string.format("[PlacementModule] PrimaryPart center Y: %.1f", finalPosition.Y))
		print(string.format("[PlacementModule] Grid-snapped position: %s", tostring(snappedPosition)))
		print(string.format("[PlacementModule] Final world position: %s", tostring(finalPosition)))

		-- Print which cells this structure will occupy
		local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, cellsX, cellsZ)
		local cellsList = {}
		for cellX = startX, endX do
			for cellZ = startZ, endZ do
				table.insert(cellsList, string.format("(%d,%d)", cellX, cellZ))
			end
		end
		print(string.format("[PlacementModule] Occupying cells: %s", table.concat(cellsList, ", ")))
	end

	return newStructure
end

function PlacementModule:BlockCells(cellStates, x, z, sizeX, sizeZ, structureType)
	-- Block cells for a placed structure
	local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, sizeX, sizeZ)
	local blockedCells = {}

	for blockX = startX, endX do
		for blockZ = startZ, endZ do
			if cellStates[blockX] and cellStates[blockX][blockZ] then
				cellStates[blockX][blockZ].blocked = true
				cellStates[blockX][blockZ].structureType = structureType
				table.insert(blockedCells, {x = blockX, z = blockZ})

				if self.config.DEBUG_PLACEMENT then
					print(string.format("[PlacementModule] Blocked cell (%d, %d) for %s", 
						blockX, blockZ, structureType or "Unknown"))
				end
			end
		end
	end

	return blockedCells
end

function PlacementModule:UnblockCells(cellStates, blockedCells)
	-- Unblock cells (e.g., when a structure is removed)
	for _, cell in ipairs(blockedCells) do
		if cellStates[cell.x] and cellStates[cell.x][cell.z] then
			cellStates[cell.x][cell.z].blocked = false
			cellStates[cell.x][cell.z].structureType = nil

			if self.config.DEBUG_PLACEMENT then
				print(string.format("[PlacementModule] Unblocked cell (%d, %d)", cell.x, cell.z))
			end
		end
	end
end

function PlacementModule:VisualizeStructureGrid(model, gridCells, x, z, worldFolder, duration)
	-- Create visual indicators to show which cells a structure will occupy (for debugging)
	duration = duration or 10 -- Default 10 seconds

	local cellsX, cellsZ = self:CalculateStructureSize(model)
	local startX, startZ, endX, endZ = self:CalculateStructureBounds(x, z, cellsX, cellsZ)

	local visualParts = {}

	for cellX = startX, endX do
		for cellZ = startZ, endZ do
			local cell = gridCells[cellX] and gridCells[cellX][cellZ]
			if cell then
				-- Create a visual indicator part
				local indicator = Instance.new("Part")
				indicator.Name = "GridIndicator_" .. cellX .. "_" .. cellZ
				indicator.Size = Vector3.new(self.config.CELL_SIZE * 0.9, 0.1, self.config.CELL_SIZE * 0.9)
				indicator.Position = cell.Position + Vector3.new(0, 0.1, 0)
				indicator.Anchored = true
				indicator.CanCollide = false
				indicator.Material = Enum.Material.Neon
				indicator.Color = Color3.fromRGB(255, 255, 0) -- Yellow
				indicator.Transparency = 0.5
				indicator.Parent = worldFolder

				table.insert(visualParts, indicator)
			end
		end
	end

	-- Remove indicators after duration
	spawn(function()
		wait(duration)
		for _, part in ipairs(visualParts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end)

	print(string.format("[PlacementModule] Visualizing %dx%d grid for %s at (%d, %d) for %d seconds", 
		cellsX, cellsZ, model.Name, x, z, duration))

	return visualParts
end

-- ========================================
-- STRUCTURE MANAGER INTEGRATION
-- ========================================

function PlacementModule:PlaceStructureWithStats(structureType, team, owner, model, gridCells, x, z, worldFolder, cellStates, options)
	-- Place a structure using StructureManager for stats and validation
	options = options or {}

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Attempting to place %s for %s team, owner: %s", 
			structureType, team, owner or "None"))
	end

	-- Check if structure can be placed using StructureManager
	local canPlace, reason = self.structureManager:CanPlaceStructure(structureType, team, owner, options.resources)
	if not canPlace then
		warn("[PlacementModule] Cannot place structure:", reason)
		return nil, nil, nil, nil
	end

	-- Get structure stats and placement options from StructureManager
	local stats, placementOptions = self.structureManager:PrepareStructureForPlacement(
		structureType, team, owner, x, z, options
	)

	if not stats or not placementOptions then
		warn("[PlacementModule] Failed to prepare structure for placement")
		return nil, nil, nil, nil
	end

	-- Calculate structure size using the model
	local cellsX, cellsZ = self:CalculateStructureSize(model)

	-- Validate placement location
	local isValid, errorMsg = self:ValidateGridAlignment(model, gridCells, x, z)
	if not isValid then
		warn("[PlacementModule] Grid alignment validation failed:", errorMsg)
		return nil, nil, nil, nil
	end

	-- Check if area is clear
	if not self:IsValidPlacement(cellStates, gridCells, x, z, cellsX, cellsZ, options) then
		warn("[PlacementModule] Area is not clear for placement")
		return nil, nil, nil, nil
	end

	-- Place the structure using the enhanced PlaceStructure function
	local structureInstance = self:PlaceStructure(model, gridCells, x, z, worldFolder, placementOptions)
	if not structureInstance then
		warn("[PlacementModule] Failed to place structure instance")
		return nil, nil, nil, nil
	end

	-- Block the cells
	local blockedCells = self:BlockCells(cellStates, x, z, cellsX, cellsZ, structureType)

	-- Register with StructureManager
	local success = self.structureManager:OnStructurePlaced(structureInstance, stats, x, z, blockedCells)
	if not success then
		warn("[PlacementModule] Failed to register structure with StructureManager")
		-- Clean up
		structureInstance:Destroy()
		self:UnblockCells(cellStates, blockedCells)
		return nil, nil, nil, nil
	end

	if self.config.DEBUG_PLACEMENT then
		print(string.format("[PlacementModule] Successfully placed %s (ID: %s) at (%d, %d)", 
			structureType, stats.InstanceId, x, z))
	end

	return structureInstance, blockedCells, x, z, stats
end

function PlacementModule:PlaceStructureWithStatsAtCenter(structureType, team, owner, model, gridCells, worldFolder, cellStates, options)
	-- Place a structure with stats at the center of the grid
	options = options or {}

	-- Find center placement location
	local cellsX, cellsZ = self:CalculateStructureSize(model)
	local centerX, centerZ = self:FindCenterPlacement(cellStates, gridCells, cellsX, cellsZ, options)

	if not centerX then
		warn("[PlacementModule] Could not find valid center placement for", structureType)
		return nil, nil, nil, nil
	end

	-- Use the main placement function
	return self:PlaceStructureWithStats(structureType, team, owner, model, gridCells, centerX, centerZ, worldFolder, cellStates, options)
end

function PlacementModule:GetStructureManager()
	-- Get access to the structure manager (for external systems)
	return self.structureManager
end

-- ========================================
-- PRESET PLACEMENT FUNCTIONS
-- ========================================

function PlacementModule:PlaceAtCenter(model, cellStates, gridCells, worldFolder, options)
	-- Place a structure at the center of the grid
	local sizeX, sizeZ = self:CalculateStructureSize(model)
	local centerX, centerZ = self:FindCenterPlacement(cellStates, gridCells, sizeX, sizeZ, options)

	if not centerX then
		warn("[PlacementModule] Could not find valid center placement")
		return nil, nil
	end

	local structure = self:PlaceStructure(model, gridCells, centerX, centerZ, worldFolder, options)
	if structure then
		local blockedCells = self:BlockCells(cellStates, centerX, centerZ, sizeX, sizeZ, options.structureType)
		return structure, blockedCells, centerX, centerZ
	end

	return nil, nil
end

function PlacementModule:PlaceNearLocation(model, cellStates, gridCells, targetX, targetZ, worldFolder, options)
	-- Place a structure near a specific location
	local sizeX, sizeZ = self:CalculateStructureSize(model)
	local placementX, placementZ = self:FindNearestValidPlacement(cellStates, gridCells, targetX, targetZ, sizeX, sizeZ, options)

	if not placementX then
		warn("[PlacementModule] Could not find valid placement near", targetX, targetZ)
		return nil, nil
	end

	local structure = self:PlaceStructure(model, gridCells, placementX, placementZ, worldFolder, options)
	if structure then
		local blockedCells = self:BlockCells(cellStates, placementX, placementZ, sizeX, sizeZ, options.structureType)
		return structure, blockedCells, placementX, placementZ
	end

	return nil, nil
end

function PlacementModule:PlaceRandomly(model, cellStates, gridCells, worldFolder, options)
	-- Place a structure at a random valid location
	local sizeX, sizeZ = self:CalculateStructureSize(model)
	local placementX, placementZ = self:FindRandomPlacement(cellStates, gridCells, sizeX, sizeZ, options)

	if not placementX then
		warn("[PlacementModule] Could not find valid random placement")
		return nil, nil
	end

	local structure = self:PlaceStructure(model, gridCells, placementX, placementZ, worldFolder, options)
	if structure then
		local blockedCells = self:BlockCells(cellStates, placementX, placementZ, sizeX, sizeZ, options.structureType)
		return structure, blockedCells, placementX, placementZ
	end

	return nil, nil
end

return PlacementModule
