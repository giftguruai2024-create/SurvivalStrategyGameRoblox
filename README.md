# Survival Strategy Game - Roblox

A survival strategy game for Roblox with a grid-based building system.

## WorldStateScript Module

The `WorldStateScript` is a ModuleScript that manages the world grid state and structure placement.

### Features

- **Grid-based world system**: 3x3 studs per cell (configurable)
- **Automatic structure size calculation**: Calculates grid occupancy from model dimensions
- **Structure placement management**: Tracks which cells are occupied
- **Coordinate conversion**: Convert between world positions and grid coordinates

### How It Works

#### Grid Cell Calculation

The system automatically calculates how many grid cells a structure occupies:

1. Reads the structure's `PrimaryPart.Size` (X and Z dimensions)
2. Divides each dimension by `CELL_SIZE` (3 studs)
3. Rounds up to get the number of cells

**Example:**
- TownHall PrimaryPart size: 6x6 studs
- Grid cells: 6÷3 = 2, so it occupies **2x2 cells** (4 total cells)
- Total stud coverage: 6x6 studs

### Setup Instructions

1. **Place the ModuleScript:**
   - Put `WorldStateScript.lua` in `ServerScriptService` or `ReplicatedStorage`

2. **Create your structures:**
   - In `ReplicatedStorage`, create a folder called `Structures`
   - Add your structure models (e.g., `TownHall`)
   - **Important:** Set the `PrimaryPart` for each model

3. **Use in a ServerScript:**
   ```lua
   local WorldStateScript = require(path.to.WorldStateScript)

   -- Build the grid and calculate structure sizes
   local townHallSize = WorldStateScript:BuildGrid()

   -- Place a structure
   WorldStateScript:PlaceStructure("TownHall", 10, 10, townHallSize)
   ```

### API Reference

#### `WorldState:BuildGrid()`
Initializes the grid and calculates TownHall dimensions.
- **Returns:** Grid size data for TownHall

#### `WorldState:GetStructureGridSize(structureName)`
Calculates grid cell occupancy for a structure.
- **Parameters:** `structureName` - Name of model in ReplicatedStorage/Structures
- **Returns:** Table with `studsX`, `studsZ`, `cellsX`, `cellsZ`, `totalCells`

#### `WorldState:PlaceStructure(name, gridX, gridZ, gridSize)`
Places a structure on the grid.
- **Returns:** `true` if successful, `false` otherwise

#### `WorldState:IsAreaAvailable(startX, startZ, sizeX, sizeZ)`
Checks if a grid area is unoccupied.
- **Returns:** `available` (boolean), `reason` (string if not available)

#### `WorldState:WorldToGrid(worldX, worldZ)`
Converts world coordinates to grid coordinates.

#### `WorldState:GridToWorld(gridX, gridZ)`
Converts grid coordinates to world position.

### Configuration

Edit these values in `WorldStateScript.lua`:
- `CELL_SIZE`: Size of each grid cell in studs (default: 3)
- `GRID_SIZE`: Number of cells in the grid (default: 50x50)

### Example Structure Setup

In Roblox Studio:
1. Create a Part for your TownHall
2. Set its Size to 6x6x6 (or any size divisible by 3)
3. Group it into a Model
4. Set the Model's `PrimaryPart` to the part you created
5. Place the model in `ReplicatedStorage/Structures/TownHall`

The script will automatically calculate that a 6x6 structure = 2x2 grid cells!
