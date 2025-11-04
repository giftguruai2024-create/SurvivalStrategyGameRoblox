-- WorldStateScript.lua
-- Module script for managing the world grid state in the survival strategy game

local WorldState = {}

-- Configuration
local CELL_SIZE = 3 -- Each cell is 3x3 studs
local GRID_SIZE = 50 -- Example: 50x50 grid (adjust as needed)

-- Grid data structure
WorldState.Grid = {}
WorldState.CellSize = CELL_SIZE

-- Initialize the grid
function WorldState:InitializeGrid()
	print("Initializing world grid...")

	-- Create empty grid
	for x = 1, GRID_SIZE do
		self.Grid[x] = {}
		for z = 1, GRID_SIZE do
			self.Grid[x][z] = {
				occupied = false,
				structure = nil
			}
		end
	end

	print("Grid initialized: " .. GRID_SIZE .. "x" .. GRID_SIZE .. " cells")
end

-- Calculate grid cell dimensions for a structure
function WorldState:GetStructureGridSize(structurePath)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- Navigate to the structure
	local structure = ReplicatedStorage:FindFirstChild("Structures")
	if not structure then
		warn("Structures folder not found in ReplicatedStorage")
		return nil
	end

	local model = structure:FindFirstChild(structurePath)
	if not model then
		warn("Structure '" .. structurePath .. "' not found in ReplicatedStorage/Structures")
		return nil
	end

	-- Get PrimaryPart
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		warn("PrimaryPart not set for " .. structurePath)
		return nil
	end

	-- Get size from PrimaryPart
	local size = primaryPart.Size

	-- Calculate grid cells (divide X and Z by CELL_SIZE)
	local cellsX = math.ceil(size.X / CELL_SIZE)
	local cellsZ = math.ceil(size.Z / CELL_SIZE)

	print(structurePath .. " dimensions:")
	print("  Studs: " .. size.X .. " x " .. size.Z)
	print("  Grid cells: " .. cellsX .. " x " .. cellsZ .. " (" .. cellsX * cellsZ .. " total cells)")

	return {
		studsX = size.X,
		studsZ = size.Z,
		cellsX = cellsX,
		cellsZ = cellsZ,
		totalCells = cellsX * cellsZ
	}
end

-- Build the grid and calculate TownHall occupancy
function WorldState:BuildGrid()
	print("Building world grid...")

	-- Initialize the grid structure
	self:InitializeGrid()

	-- Get TownHall grid size
	local townHallGridSize = self:GetStructureGridSize("TownHall")

	if townHallGridSize then
		print("TownHall will occupy " .. townHallGridSize.cellsX .. "x" .. townHallGridSize.cellsZ .. " cells on the grid")
	else
		warn("Could not calculate TownHall grid size")
	end

	return townHallGridSize
end

-- Check if a grid area is available
function WorldState:IsAreaAvailable(startX, startZ, sizeX, sizeZ)
	-- Check bounds
	if startX < 1 or startZ < 1 or
	   startX + sizeX - 1 > GRID_SIZE or
	   startZ + sizeZ - 1 > GRID_SIZE then
		return false, "Out of bounds"
	end

	-- Check if cells are occupied
	for x = startX, startX + sizeX - 1 do
		for z = startZ, startZ + sizeZ - 1 do
			if self.Grid[x][z].occupied then
				return false, "Area occupied"
			end
		end
	end

	return true
end

-- Place a structure on the grid
function WorldState:PlaceStructure(structureName, startX, startZ, gridSize)
	local sizeX = gridSize.cellsX
	local sizeZ = gridSize.cellsZ

	local available, reason = self:IsAreaAvailable(startX, startZ, sizeX, sizeZ)

	if not available then
		warn("Cannot place " .. structureName .. ": " .. reason)
		return false
	end

	-- Mark cells as occupied
	for x = startX, startX + sizeX - 1 do
		for z = startZ, startZ + sizeZ - 1 do
			self.Grid[x][z].occupied = true
			self.Grid[x][z].structure = structureName
		end
	end

	print("Placed " .. structureName .. " at grid position (" .. startX .. ", " .. startZ .. ")")
	return true
end

-- Convert world position to grid coordinates
function WorldState:WorldToGrid(worldX, worldZ)
	local gridX = math.floor(worldX / CELL_SIZE) + 1
	local gridZ = math.floor(worldZ / CELL_SIZE) + 1
	return gridX, gridZ
end

-- Convert grid coordinates to world position (center of cell)
function WorldState:GridToWorld(gridX, gridZ)
	local worldX = (gridX - 0.5) * CELL_SIZE
	local worldZ = (gridZ - 0.5) * CELL_SIZE
	return worldX, worldZ
end

return WorldState
