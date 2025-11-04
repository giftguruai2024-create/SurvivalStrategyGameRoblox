-- @ScriptType: ModuleScript
-- PathfindingModule
-- Place this in ReplicatedStorage
-- Implements A* pathfinding using WorldState grid cells

local PathfindingModule = {}
PathfindingModule.__index = PathfindingModule

-- ========================================
-- PATHFINDING CONFIGURATION
-- ========================================

local PATHFINDING_CONFIG = {
	MAX_SEARCH_NODES = 1000, -- Prevent infinite loops
	DIAGONAL_MOVEMENT = true, -- Allow diagonal movement
	DIAGONAL_COST = 1.414, -- sqrt(2) for diagonal movement cost
	STRAIGHT_COST = 1.0, -- Cost for horizontal/vertical movement
	MAX_PATH_LENGTH = 100, -- Maximum path length
	AVOID_NPCS = true, -- Consider NPC-occupied cells as higher cost
	NPC_COST_MULTIPLIER = 2, -- Cost multiplier for cells with NPCs
}

-- ========================================
-- A* PATHFINDING IMPLEMENTATION
-- ========================================

function PathfindingModule:FindPath(startX, startZ, goalX, goalZ, worldState, options)
	-- Main pathfinding function using A* algorithm
	options = options or {}

	-- Validate inputs
	if not worldState then
		warn("[Pathfinding] WorldState not provided")
		return nil
	end

	if not self:IsValidCell(startX, startZ, worldState) or not self:IsValidCell(goalX, goalZ, worldState) then
		warn("[Pathfinding] Invalid start or goal coordinates")
		return nil
	end

	-- If start and goal are the same, return empty path
	if startX == goalX and startZ == goalZ then
		return {}
	end

	-- Initialize A* data structures
	local openSet = {} -- Nodes to be evaluated
	local closedSet = {} -- Already evaluated nodes
	local cameFrom = {} -- Path reconstruction
	local gScore = {} -- Distance from start
	local fScore = {} -- gScore + heuristic

	-- Helper function to create node key
	local function nodeKey(x, z)
		return x .. "," .. z
	end

	-- Initialize start node
	local startKey = nodeKey(startX, startZ)
	gScore[startKey] = 0
	fScore[startKey] = self:Heuristic(startX, startZ, goalX, goalZ)
	table.insert(openSet, {x = startX, z = startZ, f = fScore[startKey]})

	local searchedNodes = 0

	while #openSet > 0 and searchedNodes < PATHFINDING_CONFIG.MAX_SEARCH_NODES do
		-- Find node with lowest f score
		table.sort(openSet, function(a, b) return a.f < b.f end)
		local current = table.remove(openSet, 1)
		local currentKey = nodeKey(current.x, current.z)

		-- Check if we reached the goal
		if current.x == goalX and current.z == goalZ then
			return self:ReconstructPath(cameFrom, currentKey, startX, startZ)
		end

		-- Move current to closed set
		closedSet[currentKey] = true

		-- Check all neighbors
		local neighbors = self:GetNeighbors(current.x, current.z)
		for _, neighbor in ipairs(neighbors) do
			local neighborKey = nodeKey(neighbor.x, neighbor.z)

			-- Skip if already evaluated or invalid
			if not closedSet[neighborKey] and self:IsTraversable(neighbor.x, neighbor.z, worldState, options) then
				-- Calculate tentative g score
				local moveCost = neighbor.isDiagonal and PATHFINDING_CONFIG.DIAGONAL_COST or PATHFINDING_CONFIG.STRAIGHT_COST
				local cellCost = self:GetCellCost(neighbor.x, neighbor.z, worldState, options)
				local tentativeGScore = gScore[currentKey] + moveCost + cellCost

				-- Check if this path to neighbor is better
				if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
					cameFrom[neighborKey] = currentKey
					gScore[neighborKey] = tentativeGScore
					fScore[neighborKey] = tentativeGScore + self:Heuristic(neighbor.x, neighbor.z, goalX, goalZ)

					-- Add to open set if not already there
					local inOpenSet = false
					for _, node in ipairs(openSet) do
						if node.x == neighbor.x and node.z == neighbor.z then
							node.f = fScore[neighborKey]
							inOpenSet = true
							break
						end
					end

					if not inOpenSet then
						table.insert(openSet, {x = neighbor.x, z = neighbor.z, f = fScore[neighborKey]})
					end
				end
			end
		end

		searchedNodes = searchedNodes + 1
	end

	-- No path found
	warn(string.format("[Pathfinding] No path found from (%d,%d) to (%d,%d) after searching %d nodes", 
		startX, startZ, goalX, goalZ, searchedNodes))
	return nil
end

function PathfindingModule:GetNeighbors(x, z)
	-- Get all valid neighboring cells
	local neighbors = {}

	-- Straight neighbors (N, S, E, W)
	local directions = {
		{x = 0, z = 1},   -- North
		{x = 0, z = -1},  -- South
		{x = 1, z = 0},   -- East
		{x = -1, z = 0},  -- West
	}

	-- Add diagonal neighbors if enabled
	if PATHFINDING_CONFIG.DIAGONAL_MOVEMENT then
		table.insert(directions, {x = 1, z = 1})   -- Northeast
		table.insert(directions, {x = 1, z = -1})  -- Southeast
		table.insert(directions, {x = -1, z = 1})  -- Northwest
		table.insert(directions, {x = -1, z = -1}) -- Southwest
	end

	for _, dir in ipairs(directions) do
		local newX = x + dir.x
		local newZ = z + dir.z
		local isDiagonal = math.abs(dir.x) + math.abs(dir.z) == 2

		table.insert(neighbors, {
			x = newX,
			z = newZ,
			isDiagonal = isDiagonal
		})
	end

	return neighbors
end

function PathfindingModule:IsValidCell(x, z, worldState)
	-- Check if cell coordinates are within the grid bounds
	if not worldState.cellStates then
		return false
	end

	return worldState.cellStates[x] and worldState.cellStates[x][z]
end

function PathfindingModule:IsTraversable(x, z, worldState, options)
	-- Check if a cell can be moved through
	if not self:IsValidCell(x, z, worldState) then
		return false
	end

	local cellState = worldState.cellStates[x][z]

	-- Check if cell is occupied by structures
	if cellState.occupied then
		return false
	end

	-- Allow movement through cells with resources (NPCs can walk around them)
	-- Allow movement through cells with other NPCs (just higher cost)

	return true
end

function PathfindingModule:GetCellCost(x, z, worldState, options)
	-- Calculate the cost to move through a cell
	if not self:IsValidCell(x, z, worldState) then
		return math.huge
	end

	local cellState = worldState.cellStates[x][z]
	local cost = 0

	-- Add cost for NPCs in the cell (to encourage spreading out)
	if PATHFINDING_CONFIG.AVOID_NPCS and cellState.npcCount and cellState.npcCount > 0 then
		cost = cost + (cellState.npcCount * PATHFINDING_CONFIG.NPC_COST_MULTIPLIER)
	end

	-- Could add other costs here (terrain types, etc.)

	return cost
end

function PathfindingModule:Heuristic(x1, z1, x2, z2)
	-- Manhattan distance heuristic (good for grid-based movement)
	local dx = math.abs(x2 - x1)
	local dz = math.abs(z2 - z1)

	if PATHFINDING_CONFIG.DIAGONAL_MOVEMENT then
		-- Diagonal distance heuristic
		local diagonal = math.min(dx, dz)
		local straight = math.abs(dx - dz)
		return diagonal * PATHFINDING_CONFIG.DIAGONAL_COST + straight * PATHFINDING_CONFIG.STRAIGHT_COST
	else
		-- Manhattan distance
		return (dx + dz) * PATHFINDING_CONFIG.STRAIGHT_COST
	end
end

function PathfindingModule:ReconstructPath(cameFrom, currentKey, startX, startZ)
	-- Reconstruct the path from goal to start
	local path = {}

	-- Parse current position
	local x, z = currentKey:match("([^,]+),([^,]+)")
	x, z = tonumber(x), tonumber(z)

	-- Build path backwards
	while currentKey do
		table.insert(path, 1, {x = x, z = z}) -- Insert at beginning
		currentKey = cameFrom[currentKey]

		if currentKey then
			x, z = currentKey:match("([^,]+),([^,]+)")
			x, z = tonumber(x), tonumber(z)
		end

		-- Safety check
		if #path > PATHFINDING_CONFIG.MAX_PATH_LENGTH then
			warn("[Pathfinding] Path too long, truncating")
			break
		end
	end

	-- Remove start position (NPC is already there)
	if #path > 0 and path[1].x == startX and path[1].z == startZ then
		table.remove(path, 1)
	end

	return path
end

-- ========================================
-- PATHFINDING UTILITIES
-- ========================================

function PathfindingModule:GridToWorldPosition(gridX, gridZ)
	-- Convert grid coordinates to world position
	-- This should match your grid system
	if _G.GridToWorld then
		local worldPos = _G.GridToWorld(gridX, gridZ)
		if worldPos then
			return worldPos
		else
			-- gridToWorld returned nil, try fallback
			warn(string.format("[PathfindingModule] GridToWorld returned nil for (%d, %d), using fallback", gridX, gridZ))
			local cellSize = 3
			return Vector3.new((gridX - 17) * cellSize, 0, (gridZ - 17) * cellSize) -- Offset from center
		end
	else
		-- Fallback calculation (adjust based on your grid size)
		local cellSize = 3 -- Assumed cell size
		return Vector3.new((gridX - 17) * cellSize, 0, (gridZ - 17) * cellSize) -- Offset from center
	end
end

function PathfindingModule:WorldToGridPosition(worldPos)
	-- Convert world position to grid coordinates
	if _G.WorldToGrid then
		return _G.WorldToGrid(worldPos)
	else
		-- Fallback calculation
		local cellSize = 3
		return math.floor(worldPos.X / cellSize), math.floor(worldPos.Z / cellSize)
	end
end

function PathfindingModule:SmoothPath(path, worldState)
	-- Smooth the path by removing unnecessary waypoints
	if not path or #path <= 2 then
		return path
	end

	local smoothedPath = {path[1]} -- Always keep first waypoint

	for i = 2, #path - 1 do
		local prev = smoothedPath[#smoothedPath]
		local current = path[i]
		local next = path[i + 1]

		-- Check if we can go directly from prev to next
		if not self:HasLineOfSight(prev.x, prev.z, next.x, next.z, worldState) then
			table.insert(smoothedPath, current)
		end
	end

	-- Always keep last waypoint
	table.insert(smoothedPath, path[#path])

	return smoothedPath
end

function PathfindingModule:HasLineOfSight(x1, z1, x2, z2, worldState)
	-- Check if there's a clear line between two points using Bresenham's line algorithm
	local dx = math.abs(x2 - x1)
	local dz = math.abs(z2 - z1)
	local x, z = x1, z1
	local xInc = x1 < x2 and 1 or -1
	local zInc = z1 < z2 and 1 or -1
	local error = dx - dz

	dx = dx * 2
	dz = dz * 2

	while true do
		-- Check if current cell is traversable
		if not self:IsTraversable(x, z, worldState, {}) then
			return false
		end

		if x == x2 and z == z2 then
			break
		end

		if error > 0 then
			x = x + xInc
			error = error - dz
		else
			z = z + zInc
			error = error + dx
		end
	end

	return true
end

function PathfindingModule:GetPathLength(path)
	-- Calculate total path length
	if not path or #path == 0 then
		return 0
	end

	local length = 0
	for i = 2, #path do
		local prev = path[i-1]
		local current = path[i]
		local dx = current.x - prev.x
		local dz = current.z - prev.z
		length = length + math.sqrt(dx*dx + dz*dz)
	end

	return length
end

-- ========================================
-- DEBUG FUNCTIONS
-- ========================================

function PathfindingModule:DebugPath(path, worldFolder)
	-- Create visual representation of path for debugging
	if not path then
		return
	end

	-- Clean up old debug parts
	for _, obj in pairs(worldFolder:GetChildren()) do
		if obj.Name == "PathDebug" then
			obj:Destroy()
		end
	end

	-- Create path visualization
	for i, waypoint in ipairs(path) do
		local part = Instance.new("Part")
		part.Name = "PathDebug"
		part.Size = Vector3.new(0.5, 1, 0.5)
		part.Material = Enum.Material.Neon
		part.BrickColor = BrickColor.new("Bright green")
		part.Anchored = true
		part.CanCollide = false

		local worldPos = self:GridToWorldPosition(waypoint.x, waypoint.z)
		part.Position = worldPos + Vector3.new(0, 2, 0)
		part.Parent = worldFolder

		-- Add number label
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(2, 0, 2, 0)
		gui.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = tostring(i)
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Font = Enum.Font.SourceSansBold
		label.Parent = gui
	end
end

return PathfindingModule