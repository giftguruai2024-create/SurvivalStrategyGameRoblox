-- ExampleUsage.lua
-- Example script showing how to use the WorldStateScript module
-- This would typically be in a ServerScript in ServerScriptService

local WorldStateScript = require(script.Parent.WorldStateScript)

-- Build the grid and get TownHall dimensions
local townHallGridSize = WorldStateScript:BuildGrid()

-- Example: Place TownHall at grid position (10, 10)
if townHallGridSize then
	local success = WorldStateScript:PlaceStructure("TownHall", 10, 10, townHallGridSize)

	if success then
		print("TownHall successfully placed on the grid!")
	end
end

-- Example: Check if an area is available
local available, reason = WorldStateScript:IsAreaAvailable(15, 15, 3, 3)
print("Area (15,15) with size 3x3 available:", available, reason or "")

-- Example: Convert grid coordinates to world position
local worldX, worldZ = WorldStateScript:GridToWorld(10, 10)
print("Grid (10, 10) = World position (" .. worldX .. ", " .. worldZ .. ")")

-- Example: Get grid size for other structures
-- You can add more structures to ReplicatedStorage/Structures and query them:
-- local barracksSize = WorldStateScript:GetStructureGridSize("Barracks")
