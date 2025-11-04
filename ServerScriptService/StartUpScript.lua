-- @ScriptType: Script
-- @ScriptType: Script
-- Server-side script for grid generation and player management
-- Place this in ServerScriptService

local Players = game:GetService("Players")
local replicated = game:GetService('ReplicatedStorage')

-- Module requires - THIS WAS MISSING!
local WorldStateModule = require(replicated:WaitForChild("WorldStateScript"))
local StructureManagerModule = require(replicated:WaitForChild("StructureManager"))
local NPCManagerModule = require(replicated:WaitForChild("NPCManager"))

local events = replicated:WaitForChild('Events')
local ClickedRemote = Instance.new("RemoteEvent")
ClickedRemote.Name = "Clicked"
ClickedRemote.Parent = events

-- Resource selection remote events
local selectResourceRemote = Instance.new("RemoteEvent")
selectResourceRemote.Name = "SelectResource"
selectResourceRemote.Parent = events

local createHarvestTaskRemote = Instance.new("RemoteEvent")
createHarvestTaskRemote.Name = "CreateHarvestTask"
createHarvestTaskRemote.Parent = events

local cameraReadyEvent = Instance.new("RemoteEvent")
cameraReadyEvent.Name = "GridReady"
cameraReadyEvent.Parent = events
-- ========================================
-- WORLDSTATE INTEGRATION
-- ========================================

-- Declare worldState variable at the top level
local worldState

-- ========================================
-- CONFIGURATION - Adjust these values!
-- ========================================
local GRID_SIZE = 30 -- Number of cells in each direction for playable area (100x100)
local CELL_SIZE = 3 -- Size of each cell in studs (2x2x2)
local MIN_SPAWN_DISTANCE = 10 -- Minimum distance between players (in cells)

-- Beach configuration
local BEACH_THICKNESS = 2 -- Number of cells for beach border (2 cells = 4 studs with CELL_SIZE of 2)

-- Camera configuration
local INITIAL_HEIGHT = 50 -- Initial camera height above grid center
-- ========================================

-- Grid variables
local gridCells = {} -- 2D table to store grid cells for NPC movement reference
local occupiedSpots = {} -- Track which grid cells are occupied by players
local playerSpawnLocations = {} -- Track each player's spawn location
local gridCreated = false

-- Colors for checkerboard pattern
local darkGreen = Color3.fromRGB(34, 139, 34)
local lightGreen = Color3.fromRGB(124, 252, 0)

-- Colors for beach
local sandColor1 = Color3.fromRGB(194, 178, 128) -- Light sand
local sandColor2 = Color3.fromRGB(168, 153, 110) -- Darker sand

-- Function to create organized world folder structure
local function createWorldFolderStructure(worldFolder)
	print("[StartUpScript] Creating organized world folder structure...")

	-- Create main grid folder
	local gridFolder = Instance.new("Folder")
	gridFolder.Name = "Grid_Cells"
	gridFolder.Parent = worldFolder

	-- Create player object folders
	local playerNPCsFolder = Instance.new("Folder")
	playerNPCsFolder.Name = "PlayerNPCs"
	playerNPCsFolder.Parent = worldFolder

	local playerStructuresFolder = Instance.new("Folder")
	playerStructuresFolder.Name = "PlayerStructures"
	playerStructuresFolder.Parent = worldFolder

	-- Create enemy object folders
	local enemyNPCsFolder = Instance.new("Folder")
	enemyNPCsFolder.Name = "EnemyNPCs"
	enemyNPCsFolder.Parent = worldFolder

	local enemyStructuresFolder = Instance.new("Folder")
	enemyStructuresFolder.Name = "EnemyStructures"
	enemyStructuresFolder.Parent = worldFolder

	-- Create resources folder
	local resourcesFolder = Instance.new("Folder")
	resourcesFolder.Name = "Resources"
	resourcesFolder.Parent = worldFolder

	print("[StartUpScript] ✅ Created organized folder structure:")
	print("  - Grid_Cells (for terrain)")
	print("  - PlayerNPCs (for player units)")
	print("  - PlayerStructures (for player buildings)")
	print("  - EnemyNPCs (for enemy units)")
	print("  - EnemyStructures (for enemy buildings)")
	print("  - Resources (for harvestable resources)")

	return gridFolder
end

-- Function to create the grid
local function createGrid(firstPlayerName)
	-- Create the world folder for the first player
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = firstPlayerName .. "_World"
	worldFolder.Parent = workspace

	-- Create organized folder structure
	local gridFolder = createWorldFolderStructure(worldFolder)

	print("Starting grid generation...")

	-- Calculate total grid size including beach
	local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)

	-- Initialize the 2D table
	for x = 1, totalGridSize do
		gridCells[x] = {}
		occupiedSpots[x] = {}
		for z = 1, totalGridSize do
			occupiedSpots[x][z] = false
		end
	end

	-- Generate the grid (including beach border)
	for x = 1, totalGridSize do
		for z = 1, totalGridSize do
			-- Create a new part for this cell
			local cell = Instance.new("Part")
			cell.Name = "Cell_" .. x .. "_" .. z
			cell.Size = Vector3.new(CELL_SIZE, CELL_SIZE, CELL_SIZE)

			-- Position the cell (centered around origin, adjust as needed)
			local offsetX = (totalGridSize * CELL_SIZE) / 2
			local offsetZ = (totalGridSize * CELL_SIZE) / 2
			cell.Position = Vector3.new(
				(x - 1) * CELL_SIZE - offsetX + CELL_SIZE/2,
				CELL_SIZE/2, -- Y position (sits on ground)
				(z - 1) * CELL_SIZE - offsetZ + CELL_SIZE/2
			)

			-- Check if this cell is in the beach zone or grass zone
			local isBeach = (x <= BEACH_THICKNESS or x > GRID_SIZE + BEACH_THICKNESS or
				z <= BEACH_THICKNESS or z > GRID_SIZE + BEACH_THICKNESS)

			if isBeach then
				-- Beach cells
				cell.Material = Enum.Material.Sand
				-- Checkerboard pattern for beach too
				if (x + z) % 2 == 0 then
					cell.Color = sandColor1
				else
					cell.Color = sandColor2
				end
			else
				-- Grass cells (the playable area)
				cell.Material = Enum.Material.Grass
				-- Checkerboard pattern: alternate colors
				if (x + z) % 2 == 0 then
					cell.Color = darkGreen
				else
					cell.Color = lightGreen
				end
			end

			-- Make cells anchored so they don't fall
			cell.Anchored = true
			cell.CanCollide = true

			-- Parent to grid folder (organized structure)
			cell.Parent = gridFolder

			-- Store reference in the table
			gridCells[x][z] = cell
		end

		-- Optional: yield every row to prevent timeout
		if x % 10 == 0 then
			wait()
			print("Generated " .. x .. "/" .. totalGridSize .. " rows")
		end
	end

	print("Grid generation complete! (Including " .. BEACH_THICKNESS .. "-cell beach border)")

	-- ========================================
	-- WORLDSTATE INITIALIZATION
	-- ========================================
	print("[Integration] Initializing WorldState system...")
	worldState = WorldStateModule.new()

	-- Initialize StructureManager and connect it to WorldState
	local structureManager = StructureManagerModule.new()

	-- Initialize NPCManager for AI behavior
	local npcManager = NPCManagerModule.new({
		DEBUG_AI = true,
		UPDATE_FREQUENCY = 10,
	})

	-- Export managers globally for other scripts to access
	_G.StructureManager = structureManager
	_G.NPCManager = npcManager

	-- Give WorldState access to StructureManager for registering placed structures
	worldState:SetStructureManager(structureManager)

	worldState:InitializeCellStates(gridCells, worldFolder)  -- Add worldFolder parameter
	worldState:StartUpdateLoop(gridCells, worldFolder)

	-- Optional: Customize WorldState config
	worldState:SetConfig({
		SPAWN = {
			CHECK_INTERVAL = 5, -- Check every 5 seconds
			ENABLE_AUTO_SPAWN = true,
		}
	})

	print("[Integration] WorldState system initialized!")

	-- Store for access by other functions
	_G.WorldState = worldState
	_G.GridCells = gridCells
	-- ========================================

	-- Fire event to all players that grid is ready
	for _, plr in pairs(Players:GetPlayers()) do
		cameraReadyEvent:FireClient(plr, Vector3.new(0, 0, 0), INITIAL_HEIGHT)
	end
end

-- Function to check if a spot is far enough from all other players
local function isSpotValid(x, z)
	-- Calculate total grid size and grass area bounds
	local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
	local grassStartX = BEACH_THICKNESS + 1
	local grassEndX = BEACH_THICKNESS + GRID_SIZE
	local grassStartZ = BEACH_THICKNESS + 1
	local grassEndZ = BEACH_THICKNESS + GRID_SIZE

	-- Check if spot is within total grid bounds
	if x < 1 or x > totalGridSize or z < 1 or z > totalGridSize then
		return false
	end

	-- Only spawn in grass area (not on beach)
	if x < grassStartX or x > grassEndX or z < grassStartZ or z > grassEndZ then
		return false
	end

	-- Check if spot is already occupied
	if occupiedSpots[x][z] then
		return false
	end

	-- Check distance from all occupied spots
	for occupiedX, row in pairs(occupiedSpots) do
		for occupiedZ, isOccupied in pairs(row) do
			if isOccupied then
				local distance = math.sqrt((x - occupiedX)^2 + (z - occupiedZ)^2)
				if distance < MIN_SPAWN_DISTANCE then
					return false
				end
			end
		end
	end

	return true
end

-- Function to find a suitable spawn location for a player
local function findSpawnLocation()
	local attempts = 0
	local maxAttempts = 1000

	-- Define grass area bounds
	local grassStartX = BEACH_THICKNESS + 1 + MIN_SPAWN_DISTANCE
	local grassEndX = BEACH_THICKNESS + GRID_SIZE - MIN_SPAWN_DISTANCE
	local grassStartZ = BEACH_THICKNESS + 1 + MIN_SPAWN_DISTANCE
	local grassEndZ = BEACH_THICKNESS + GRID_SIZE - MIN_SPAWN_DISTANCE

	while attempts < maxAttempts do
		-- Generate random coordinates within grass area
		local x = math.random(grassStartX, grassEndX)
		local z = math.random(grassStartZ, grassEndZ)

		if isSpotValid(x, z) then
			return x, z
		end

		attempts = attempts + 1
	end

	-- Fallback: find any available spot in grass area
	for x = grassStartX, grassEndX do
		for z = grassStartZ, grassEndZ do
			if isSpotValid(x, z) then
				return x, z
			end
		end
	end

	-- Last resort: return center of grass area if all else fails
	local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
	return math.floor(totalGridSize/2), math.floor(totalGridSize/2)
end

-- Function to make player invincible and anchored
local function makePlayerInvincible(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		-- Make player invincible
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge

		-- Prevent death
		humanoid.BreakJointsOnDeath = false

		-- Connect to health changed to keep them alive
		humanoid.HealthChanged:Connect(function(health)
			if health < humanoid.MaxHealth then
				humanoid.Health = humanoid.MaxHealth
			end
		end)

		-- Prevent the Died event from doing anything
		humanoid.Died:Connect(function()
			humanoid.Health = humanoid.MaxHealth
		end)

		print("Made " .. character.Name .. " invincible")
	end

	if humanoidRootPart then
		-- Anchor the player so they don't fall
		humanoidRootPart.Anchored = true
		print("Anchored " .. character.Name)
	end
end

-- Function to spawn player at a grid location
local function spawnPlayerAtGridLocation(player, gridX, gridZ)
	-- Mark spot as occupied
	occupiedSpots[gridX][gridZ] = true
	playerSpawnLocations[player.UserId] = {x = gridX, z = gridZ}

	-- ========================================
	-- WORLDSTATE NOTIFICATION
	-- ========================================
	-- Notify WorldState that this cell is occupied
	if worldState then
		worldState:SetCellOccupied(gridX, gridZ, true)
		print("[Integration] Marked cell (" .. gridX .. ", " .. gridZ .. ") as occupied for " .. player.Name)
	end
	-- ========================================

	-- Get the world position
	local cell = gridCells[gridX][gridZ]
	if cell then
		local spawnPosition = cell.Position + Vector3.new(0, 5, 0) -- Spawn 5 studs above the cell

		-- Wait for character to load
		player.CharacterAdded:Connect(function(character)
			wait(0.1) -- Small delay to ensure character is fully loaded
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				humanoidRootPart.CFrame = CFrame.new(spawnPosition)
				print("Spawned " .. player.Name .. " at grid location (" .. gridX .. ", " .. gridZ .. ")")
			end

			-- Make player invincible and anchored
			makePlayerInvincible(character)
		end)

		-- If character already exists, teleport them now
		if player.Character then
			local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				humanoidRootPart.CFrame = CFrame.new(spawnPosition)
				print("Teleported " .. player.Name .. " at grid location (" .. gridX .. ", " .. gridZ .. ")")
			end

			-- Make player invincible and anchored
			makePlayerInvincible(player.Character)
		end
	end
end

-- Function to initialize leaderboard for a player
local function setupLeaderboard(player)
	-- Create leaderstats folder if it doesn't exist
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	-- Create OOFs stat
	local oofs = Instance.new("IntValue")
	oofs.Name = "OOFs"
	oofs.Value = 0
	oofs.Parent = leaderstats
	return oofs
end

-- Setup leaderboard and spawn location when player joins
Players.PlayerAdded:Connect(function(player)
	-- Create grid on first player join
	if not gridCreated then
		gridCreated = true
		print("First player joined! Creating grid...")
		createGrid(player.Name)
	else
		-- Grid already exists, fire event immediately for this player
		cameraReadyEvent:FireClient(player, Vector3.new(0, 0, 0), INITIAL_HEIGHT)
	end

	-- Setup leaderboard
	setupLeaderboard(player)

	-- Find and assign spawn location
	local spawnX, spawnZ = findSpawnLocation()
	spawnPlayerAtGridLocation(player, spawnX, spawnZ)
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	local spawnLocation = playerSpawnLocations[player.UserId]
	if spawnLocation then
		-- Free up the spot
		occupiedSpots[spawnLocation.x][spawnLocation.z] = false

		-- ========================================
		-- WORLDSTATE NOTIFICATION
		-- ========================================
		-- Notify WorldState that this cell is now free
		if worldState then
			worldState:SetCellOccupied(spawnLocation.x, spawnLocation.z, false)
			print("[Integration] Freed cell (" .. spawnLocation.x .. ", " .. spawnLocation.z .. ") for " .. player.Name)
		end
		-- ========================================

		playerSpawnLocations[player.UserId] = nil
		print("Freed spawn location for " .. player.Name)
	end
end)

-- Connect to the OnServerEvent and increment OOFs
ClickedRemote.OnServerEvent:Connect(function(player,event,data)

end)

-- Handle resource selection
selectResourceRemote.OnServerEvent:Connect(function(player, action, resourceId, resourceType, position)
	if not worldState then
		warn("[Integration] WorldState not available for resource selection")
		return
	end

	if action == "select" then
		local success = worldState:SelectResource(resourceId, resourceType, position, player.Name)
		selectResourceRemote:FireClient(player, "select_result", resourceId, success)
	elseif action == "unselect" then
		local success = worldState:UnselectResource(resourceId)
		selectResourceRemote:FireClient(player, "unselect_result", resourceId, success)
	end
end)

-- Handle harvest task creation - IMPROVED VERSION
createHarvestTaskRemote.OnServerEvent:Connect(function(player, action, taskData)
	if not worldState then
		warn("[Integration] WorldState not available for task creation")
		createHarvestTaskRemote:FireClient(player, "add_result", false, "WorldState not available")
		return
	end

	if action == "add" then
		if not taskData then
			createHarvestTaskRemote:FireClient(player, "add_result", false, "No task data provided")
			return
		end

		-- Check if resource is already selected before trying to select it
		local isAlreadySelected = worldState:IsResourceSelected(taskData.resourceId)

		if isAlreadySelected then
			-- Resource is already being harvested - this is not a failure, just inform the user
			createHarvestTaskRemote:FireClient(player, "add_result", false, "Resource already being harvested", taskData.resourceId)
			print(string.format("[Integration] %s tried to select already harvested %s resource", player.Name, taskData.resourceType))
			return
		end

		local success = worldState:SelectResource(
			taskData.resourceId, 
			taskData.resourceType, 
			taskData.position, 
			player.Name
		)

		if success then
			createHarvestTaskRemote:FireClient(player, "add_result", true, "Harvest task created", taskData.resourceId)
			print(string.format("[Integration] %s created harvest task for %s resource", player.Name, taskData.resourceType))
		else
			-- This is an actual failure (not just already selected)
			createHarvestTaskRemote:FireClient(player, "add_result", false, "Failed to create harvest task", taskData.resourceId)
		end

	elseif action == "remove" then
		if not taskData then
			createHarvestTaskRemote:FireClient(player, "remove_result", false, "No resource ID provided")
			return
		end

		local success = worldState:UnselectResource(taskData)
		if success then
			createHarvestTaskRemote:FireClient(player, "remove_result", true, "Harvest task removed")
		else
			createHarvestTaskRemote:FireClient(player, "remove_result", false, "Failed to remove harvest task")
		end

	else
		warn("[Integration] Unknown harvest task action: " .. tostring(action))
		createHarvestTaskRemote:FireClient(player, "unknown_action", false, "Unknown action")
	end
end)

-- ========================================
-- WORLDSTATE REMOTE EVENTS (Optional but recommended)
-- ========================================

-- Remote function for clients to get current game time
local getTimeEvent = Instance.new("RemoteFunction")
getTimeEvent.Name = "GetGameTime"
getTimeEvent.Parent = replicated

getTimeEvent.OnServerInvoke = function(player)
	if worldState then
		return {
			time = worldState:GetFormattedTime(),
			hour = worldState:GetTimeOfDay(),
			day = worldState:GetDayNumber(),
			isNight = worldState:IsNight(),
		}
	end
	return nil
end

-- Remote function for clients to get total resources in world
local getResourcesEvent = Instance.new("RemoteFunction")
getResourcesEvent.Name = "GetTotalResources"
getResourcesEvent.Parent = replicated

getResourcesEvent.OnServerInvoke = function(player)
	if worldState then
		return worldState:GetTotalResources()
	end
	return {}
end

-- Remote event for manual resource spawning (admin/testing only)
local spawnResourceEvent = Instance.new("RemoteEvent")
spawnResourceEvent.Name = "SpawnResource"
spawnResourceEvent.Parent = replicated

spawnResourceEvent.OnServerEvent:Connect(function(player, resourceType, gridX, gridZ)
	-- Only allow game owner or admins to manually spawn resources
	if player.UserId == game.CreatorId or player:GetRankInGroup(0) >= 250 then
		if worldState and gridCells then
			local worldFolder = workspace:FindFirstChild(player.Name .. "_World")
			if not worldFolder then
				-- Find any world folder if player's doesn't exist
				worldFolder = workspace:FindFirstChildWhichIsA("Folder")
			end

			if worldFolder then
				local success = worldState:SpawnResource(resourceType, gridX, gridZ, gridCells, worldFolder)
				if success then
					print("[Integration] Manually spawned " .. resourceType .. " at (" .. gridX .. ", " .. gridZ .. ")")
				else
					warn("[Integration] Failed to spawn " .. resourceType .. " at (" .. gridX .. ", " .. gridZ .. ")")
				end
			end
		end
	else
		warn("[Integration] " .. player.Name .. " attempted to spawn resource without permission")
	end
end)

-- ========================================
-- HELPER FUNCTIONS (exported globally)
-- ========================================

function getCell(x, z)
	if gridCells[x] and gridCells[x][z] then
		return gridCells[x][z]
	end
	return nil
end

function worldToGrid(worldPosition)
	local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
	local offsetX = (totalGridSize * CELL_SIZE) / 2
	local offsetZ = (totalGridSize * CELL_SIZE) / 2

	local gridX = math.floor((worldPosition.X + offsetX) / CELL_SIZE) + 1
	local gridZ = math.floor((worldPosition.Z + offsetZ) / CELL_SIZE) + 1

	-- Clamp to grid bounds
	gridX = math.clamp(gridX, 1, totalGridSize)
	gridZ = math.clamp(gridZ, 1, totalGridSize)

	return gridX, gridZ
end

function gridToWorld(x, z)
	local totalGridSize = GRID_SIZE + (BEACH_THICKNESS * 2)
	if not (x >= 1 and x <= totalGridSize and z >= 1 and z <= totalGridSize) then
		return nil
	end

	local cell = getCell(x, z)
	if cell then
		return cell.Position
	end
	return nil
end

-- Export functions globally so other scripts can use them
_G.GridCells = gridCells
_G.GetCell = getCell
_G.WorldToGrid = worldToGrid
_G.GridToWorld = gridToWorld
_G.GetPlayerSpawnLocation = function(player)
	return playerSpawnLocations[player.UserId]
end
_G.WorldState = worldState -- Export WorldState for other scripts to access

print("Grid script loaded. Waiting for players...")
print("[Integration] WorldState integration ready!")