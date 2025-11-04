-- @ScriptType: ModuleScript
-- WorldStateScript Module
-- Place this in ReplicatedStorage or ServerStorage
-- Manages world time, grid cell states, and resource spawning

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage") -- Added for completeness

-- Import required modules
local PlacementModule = require(ReplicatedStorage:WaitForChild("PlacementModuleScript"))
local AllStats = require(ReplicatedStorage:WaitForChild("AllStats"))

local WorldState = {}
WorldState.__index = WorldState

-- ========================================
-- RESOURCE/STRUCTURE MODEL REFERENCES
-- ========================================
local resourcesFolder = ReplicatedStorage:WaitForChild("Resources")
local structuresFolder = ReplicatedStorage:WaitForChild("Structures") -- New folder reference

-- Dedicated table for Resources
local resourceModels = {
	WOOD = resourcesFolder:WaitForChild("Tree"),
	STONE = resourcesFolder:WaitForChild("Rock"),
	FOOD = resourcesFolder:WaitForChild("Food"),
	GOLD = resourcesFolder:WaitForChild("Gold"),
	-- Add more resource mappings
}

-- Dedicated table for Structures (NEW)
local structureModels = {
	TOWNHALL = structuresFolder:WaitForChild("TownHall"),
	-- Add more structure mappings here (e.g., BARRACKS, WALL)
}

-- ========================================
-- CONFIGURATION
-- ========================================
local CONFIG = {
	-- Time system configuration
	TIME = {
		DAY_LENGTH = 600, -- Real seconds for a full day cycle (10 minutes)
		START_TIME = 6, -- Starting hour (0-24)
		TIME_SCALE = 1, -- Multiplier for time speed (1 = normal)
	},

	-- Resource spawning configuration
	RESOURCES = {
		-- Each resource type with its properties
		WOOD = {
			name = "Wood",
			modelName = "Tree",
			spawnChance = 0.5,
			maxPerCell = 1,
			spawnCooldown = 30,
			value = 10,
			heightOffset = 0,
		},
		STONE = {
			name = "Stone",
			modelName = "Rock",
			spawnChance = 0.3,
			maxPerCell = 1,
			spawnCooldown = 45,
			value = 15,
			heightOffset = 0,
		},
		FOOD = {
			name = "Food",
			modelName = nil,
			spawnChance = 0.5,
			maxPerCell = 1,
			spawnCooldown = 20,
			value = 5,
			heightOffset = 0,
			color = Color3.fromRGB(255, 100, 100),
			size = Vector3.new(1.5, 1.5, 1.5),
		},
		GOLD = {
			name = "Gold",
			modelName = nil,
			spawnChance = 0.1,
			maxPerCell = 1,
			spawnCooldown = 120,
			value = 50,
			heightOffset = 0,
			color = Color3.fromRGB(255, 215, 0),
			size = Vector3.new(1, 2, 1),
		},
	},

	-- STRUCTURES configuration (NEW ARRAY)
	STRUCTURES = {
		TOWNHALL = {
			name = "Town Hall",
			modelName = "TownHall", -- Corresponds to the key in structureModels
			health = 500,
			buildTime = 60,
			canBeAttacked = true,
			-- Add more properties like required resources
		},
		-- Future Structures:
		-- BARRACKS = { ... },
		-- WALL = { ... },
	},

	-- Grid configuration (should match your main script)
	GRID = {
		GRID_SIZE = 30,
		CELL_SIZE = 3,
		BEACH_THICKNESS = 2,
	},

	-- Spawning behavior
	SPAWN = {
		CHECK_INTERVAL = 5,
		RESOURCE_HEIGHT_OFFSET = 2,
		ENABLE_AUTO_SPAWN = true,
	},
}

-- ========================================
-- WORLDSTATE CLASS
-- ========================================

function WorldState.new()
	local self = setmetatable({}, WorldState)

	-- Time tracking
	self.startTick = tick()
	self.elapsedTime = 0
	self.currentHour = CONFIG.TIME.START_TIME
	self.currentDay = 1

	-- Grid cell state tracking
	self.cellStates = {} -- Stores state for each cell
	self.resourceInstances = {} -- Stores actual resource part instances
	self.structureInstances = {} -- Stores structure instances (NEW)

	-- Reference to StructureManager (will be set later)
	self.structureManager = nil

	-- Resource spawn tracking
	self.lastSpawnCheck = {}

	-- Initialize spawn timers
	for resourceType, _ in pairs(CONFIG.RESOURCES) do
		self.lastSpawnCheck[resourceType] = 0
	end

	-- Initialize PlacementModule
	self.placementModule = PlacementModule.new({
		CELL_SIZE = CONFIG.GRID.CELL_SIZE,
		DEBUG_PLACEMENT = true,
	})

	-- Initialize town hall storage
	self:InitializeTownHallStorage()

	-- Resource selection system
	self.selectedResources = {} -- {resourceInstanceId = {resourceData, glowing = true}}
	self.harvestQueue = {} -- Queue of harvest tasks

	print("[WorldState] Initialized")
	return self
end

function WorldState:SetStructureManager(structureManager)
	-- Set reference to StructureManager for registering placed structures
	self.structureManager = structureManager
	print("[WorldState] StructureManager reference set")
end

function WorldState:InitializeTownHallStorage()
	-- Initialize town hall storage system
	self.townHallStorage = {
		Wood = 0,
		Stone = 0, 
		Gold = 0,
		Food = 0,
		-- Max capacities
		MaxWood = 50,
		MaxStone = 50,
		MaxGold = 50,
		MaxFood = 50,
	}

	print("[WorldState] Town Hall storage initialized - Max capacity: 50 each resource")
end

function WorldState:InitializeStructureStorageAttributes(structureInstance, structureStats)
	-- Add storage attributes to any structure that has storage capability
	if not structureInstance or not structureStats then
		return
	end

	-- Check if structure has storage (like TownHall)
	if structureStats.StructureType == "Main" or structureStats.HasStorage then
		-- Add current storage amounts
		structureInstance:SetAttribute("StorageWood", 0)
		structureInstance:SetAttribute("StorageStone", 0)
		structureInstance:SetAttribute("StorageGold", 0)
		structureInstance:SetAttribute("StorageFood", 0)

		-- Add max storage capacities
		structureInstance:SetAttribute("MaxStorageWood", 50)
		structureInstance:SetAttribute("MaxStorageStone", 50)
		structureInstance:SetAttribute("MaxStorageGold", 50)
		structureInstance:SetAttribute("MaxStorageFood", 50)

		-- Add general storage info
		structureInstance:SetAttribute("HasStorage", true)
		structureInstance:SetAttribute("StorageType", "General") -- Could be "General", "Wood", "Stone", etc.
		structureInstance:SetAttribute("LastStorageUpdate", tick())

		print(string.format("[WorldState] Added storage attributes to %s", structureInstance.Name))
	else
		-- Mark as no storage
		structureInstance:SetAttribute("HasStorage", false)
	end

	-- Add general structure attributes
	structureInstance:SetAttribute("StructureType", structureStats.StructureType)
	structureInstance:SetAttribute("Team", structureStats.Team)
	structureInstance:SetAttribute("Owner", structureStats.Owner or "System")
	structureInstance:SetAttribute("Health", structureStats.Health)
	structureInstance:SetAttribute("MaxHealth", structureStats.Health)
	structureInstance:SetAttribute("CanBeAttacked", structureStats.CanBeAttacked or false)
	structureInstance:SetAttribute("PlacedTime", tick())

	-- Add spawner attributes if applicable
	if structureStats.Spawner then
		structureInstance:SetAttribute("IsSpawner", true)
		structureInstance:SetAttribute("MaxQueue", structureStats.MaxQueue or 0)
		structureInstance:SetAttribute("CurrentQueue", 0)
		structureInstance:SetAttribute("SpawnTimeMultiplier", structureStats.SpawnTimeMultiplier or 1.0)

		-- Add spawn types as a string list
		if structureStats.SpawnTypes then
			local spawnTypesStr = table.concat(structureStats.SpawnTypes, ",")
			structureInstance:SetAttribute("SpawnTypes", spawnTypesStr)
		end
	else
		structureInstance:SetAttribute("IsSpawner", false)
	end
end

function WorldState:UpdateStructureStorageAttributes(structureInstance, resourceType, newAmount)
	-- Update storage attributes when resources are deposited/withdrawn
	if not structureInstance then
		return false
	end

	local attributeName = "Storage" .. resourceType
	local maxAttributeName = "MaxStorage" .. resourceType

	local maxAmount = structureInstance:GetAttribute(maxAttributeName) or 0
	local clampedAmount = math.clamp(newAmount, 0, maxAmount)

	structureInstance:SetAttribute(attributeName, clampedAmount)
	structureInstance:SetAttribute("LastStorageUpdate", tick())

	return clampedAmount
end

function WorldState:DepositResource(resourceType, amount)
	-- Deposit resources to town hall storage
	if not self.townHallStorage then
		self:InitializeTownHallStorage()
	end

	local storage = self.townHallStorage
	local maxKey = "Max" .. resourceType
	local currentAmount = storage[resourceType] or 0
	local maxAmount = storage[maxKey] or 50

	-- Calculate how much can actually be deposited
	local spaceAvailable = maxAmount - currentAmount
	local actualDeposit = math.min(amount, spaceAvailable)

	if actualDeposit > 0 then
		storage[resourceType] = currentAmount + actualDeposit
		print(string.format("[WorldState] Deposited %d %s to Town Hall (%d/%d)", 
			actualDeposit, resourceType, storage[resourceType], maxAmount))

		return actualDeposit, storage[resourceType] -- Return amount deposited and new total
	else
		print(string.format("[WorldState] Town Hall %s storage full (%d/%d)", 
			resourceType, currentAmount, maxAmount))
		return 0, currentAmount
	end
end

function WorldState:GetStorageInfo()
	-- Get current storage information
	if not self.townHallStorage then
		self:InitializeTownHallStorage()
	end

	return self.townHallStorage
end

function WorldState:CanDepositResource(resourceType, amount)
	-- Check if resources can be deposited
	if not self.townHallStorage then
		self:InitializeTownHallStorage()
	end

	local storage = self.townHallStorage
	local maxKey = "Max" .. resourceType
	local currentAmount = storage[resourceType] or 0
	local maxAmount = storage[maxKey] or 50

	return (currentAmount + amount) <= maxAmount
end

function WorldState:SetCellOccupied(x, z, occupied)
	-- Mark a cell as occupied or free
	if self.cellStates[x] and self.cellStates[x][z] then
		self.cellStates[x][z].occupied = occupied

		if self.config.DEBUG_AI then
			print(string.format("[WorldState] Cell (%d, %d) marked as %s", x, z, occupied and "occupied" or "free"))
		end

		return true
	else
		warn(string.format("[WorldState] Attempted to set invalid cell (%d, %d)", x, z))
		return false
	end
end

function WorldState:IsCellAvailableForSpawn(gridX, gridZ)
	-- Check if a cell is available for NPC spawning

	-- Check if cell exists
	if not self.cellStates[gridX] or not self.cellStates[gridX][gridZ] then
		return false -- Cell doesn't exist
	end

	local cellState = self.cellStates[gridX][gridZ]

	-- Check if cell is occupied by structures
	if cellState.occupied then
		return false
	end

	-- Check if cell has resources (can spawn on resource cells, NPCs can walk around them)
	-- This is optional - you might want NPCs to avoid resource cells or not

	-- Check if cell is in valid spawn area (grass area, not beach)
	local totalGridSize = CONFIG.GRID.GRID_SIZE + (CONFIG.GRID.BEACH_THICKNESS * 2)
	local grassStartX = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndX = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE
	local grassStartZ = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndZ = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE

	if gridX < grassStartX or gridX > grassEndX or gridZ < grassStartZ or gridZ > grassEndZ then
		return false -- Outside grass area (in beach or outside grid)
	end

	-- Check if there are already NPCs in this cell (optional limit)
	local npcCount = cellState.npcCount or 0
	local maxNPCsPerCell = 3 -- Allow up to 3 NPCs per cell
	if npcCount >= maxNPCsPerCell then
		return false
	end

	return true -- Cell is available for spawning
end

function WorldState:RegisterNPCInCell(gridX, gridZ, npcInstanceId)
	-- Register an NPC as occupying a cell (for tracking NPC density)
	if not self.cellStates[gridX] or not self.cellStates[gridX][gridZ] then
		return false
	end

	local cellState = self.cellStates[gridX][gridZ]

	-- Initialize NPC tracking if not present
	if not cellState.npcs then
		cellState.npcs = {}
		cellState.npcCount = 0
	end

	-- Add NPC to cell
	cellState.npcs[npcInstanceId] = true
	cellState.npcCount = cellState.npcCount + 1

	print(string.format("[WorldState] Registered NPC %s in cell (%d, %d). Count: %d", 
		npcInstanceId, gridX, gridZ, cellState.npcCount))

	return true
end

function WorldState:UnregisterNPCFromCell(gridX, gridZ, npcInstanceId)
	-- Remove an NPC from a cell's tracking
	if not self.cellStates[gridX] or not self.cellStates[gridX][gridZ] then
		return false
	end

	local cellState = self.cellStates[gridX][gridZ]

	if cellState.npcs and cellState.npcs[npcInstanceId] then
		cellState.npcs[npcInstanceId] = nil
		cellState.npcCount = math.max((cellState.npcCount or 1) - 1, 0)

		print(string.format("[WorldState] Unregistered NPC %s from cell (%d, %d). Count: %d", 
			npcInstanceId, gridX, gridZ, cellState.npcCount))

		return true
	end

	return false
end

function WorldState:GetCellState(gridX, gridZ)
	-- Get complete state information for a cell
	if self.cellStates[gridX] and self.cellStates[gridX][gridZ] then
		return self.cellStates[gridX][gridZ]
	end
	return nil
end

function WorldState:GetNearbyAvailableCells(centerX, centerZ, radius, maxResults)
	-- Get a list of available cells near a center point
	maxResults = maxResults or 10
	local availableCells = {}

	for dx = -radius, radius do
		for dz = -radius, radius do
			local checkX = centerX + dx
			local checkZ = centerZ + dz

			if self:IsCellAvailableForSpawn(checkX, checkZ) then
				table.insert(availableCells, {
					x = checkX,
					z = checkZ,
					distance = math.sqrt(dx*dx + dz*dz)
				})

				-- Stop if we have enough results
				if #availableCells >= maxResults then
					break
				end
			end
		end

		if #availableCells >= maxResults then
			break
		end
	end

	-- Sort by distance
	table.sort(availableCells, function(a, b) return a.distance < b.distance end)

	return availableCells
end

function WorldState:CanDepositResource(resourceType, amount)
	-- Check if resources can be deposited
	if not self.townHallStorage then
		self:InitializeTownHallStorage()
	end

	local storage = self.townHallStorage
	local maxKey = "Max" .. resourceType
	local currentAmount = storage[resourceType] or 0
	local maxAmount = storage[maxKey] or 50

	return (currentAmount + amount) <= maxAmount
end

function WorldState:SelectResource(resourceInstanceId, resourceType, position, playerName)
	-- Select a resource for harvesting (makes it glow)
	if self.selectedResources[resourceInstanceId] then
		print("[WorldState] Resource already selected:", resourceInstanceId)
		return false
	end

	-- Add to selected resources
	self.selectedResources[resourceInstanceId] = {
		resourceType = resourceType,
		position = position,
		selectedBy = playerName,
		selectedTime = tick(),
		glowing = true,
	}

	-- Find the resource instance and make it glow
	self:MakeResourceGlow(resourceInstanceId, true)

	-- Add to harvest queue
	table.insert(self.harvestQueue, {
		resourceId = resourceInstanceId,
		resourceType = resourceType,
		position = position,
		assignedTo = nil, -- Will be assigned to available villager
		priority = #self.harvestQueue + 1,
	})

	print(string.format("[WorldState] Selected %s resource for harvesting (Queue position: %d)", 
		resourceType, #self.harvestQueue))

	-- Notify nearby villagers
	self:NotifyVillagersOfNewTask()

	return true
end

function WorldState:UnselectResource(resourceInstanceId)
	-- Unselect a resource (stop glowing, remove from queue)
	if not self.selectedResources[resourceInstanceId] then
		return false
	end

	-- Remove glow effect
	self:MakeResourceGlow(resourceInstanceId, false)

	-- Remove from selected resources
	self.selectedResources[resourceInstanceId] = nil

	-- Remove from harvest queue
	for i = #self.harvestQueue, 1, -1 do
		if self.harvestQueue[i].resourceId == resourceInstanceId then
			table.remove(self.harvestQueue, i)
			break
		end
	end

	print("[WorldState] Unselected resource:", resourceInstanceId)
	return true
end

function WorldState:MakeResourceGlow(resourceInstanceId, shouldGlow)
	-- Make a resource glow or stop glowing
	-- Find resource in world
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj:GetAttribute("ResourceId") == resourceInstanceId then
			if shouldGlow then
				-- Add glow effect
				local selectionBox = Instance.new("SelectionBox")
				selectionBox.Name = "HarvestSelection"
				selectionBox.Adornee = obj
				selectionBox.Color3 = Color3.fromRGB(255, 255, 0) -- Yellow glow
				selectionBox.LineThickness = 0.2
				selectionBox.Transparency = 0.3
				selectionBox.Parent = obj
			else
				-- Remove glow effect
				local selectionBox = obj:FindFirstChild("HarvestSelection")
				if selectionBox then
					selectionBox:Destroy()
				end
			end
			break
		end
	end
end

function WorldState:NotifyVillagersOfNewTask()
	-- Notify villagers that there are new harvest tasks available
	if _G.NPCManager then
		_G.NPCManager:CheckForNewHarvestTasks()
	end
end

function WorldState:GetNextHarvestTask()
	-- Get the next unassigned harvest task
	for i, task in ipairs(self.harvestQueue) do
		if not task.assignedTo then
			return task, i
		end
	end
	return nil, nil
end

function WorldState:AssignHarvestTask(taskIndex, npcInstanceId)
	-- Assign a harvest task to an NPC
	if self.harvestQueue[taskIndex] then
		self.harvestQueue[taskIndex].assignedTo = npcInstanceId
		print(string.format("[WorldState] Assigned harvest task to %s", npcInstanceId))
		return self.harvestQueue[taskIndex]
	end
	return nil
end

function WorldState:CompleteHarvestTask(resourceInstanceId, npcInstanceId, harvestedAmount, resourceType)
	-- Complete a harvest task (resource was harvested)
	-- Remove from queue
	for i = #self.harvestQueue, 1, -1 do
		if self.harvestQueue[i].resourceId == resourceInstanceId then
			table.remove(self.harvestQueue, i)
			break
		end
	end

	-- Remove from selected resources and stop glowing
	self:UnselectResource(resourceInstanceId)

	print(string.format("[WorldState] %s completed harvesting %d %s", npcInstanceId, harvestedAmount, resourceType))

	return true
end

-- ========================================
-- TIME MANAGEMENT (Unchanged)
-- ========================================

function WorldState:UpdateTime()
	local currentTick = tick()
	local deltaTime = (currentTick - self.startTick) * CONFIG.TIME.TIME_SCALE
	self.elapsedTime = deltaTime

	-- Calculate current hour (0-24)
	local secondsPerHour = CONFIG.TIME.DAY_LENGTH / 24
	local totalHours = (deltaTime / secondsPerHour) + CONFIG.TIME.START_TIME

	self.currentDay = math.floor(totalHours / 24) + 1
	self.currentHour = totalHours % 24

	return self.currentHour, self.currentDay
end

function WorldState:GetTimeOfDay()
	return self.currentHour
end

function WorldState:GetFormattedTime()
	local hour = math.floor(self.currentHour)
	local minute = math.floor((self.currentHour - hour) * 60)
	return string.format("%02d:%02d", hour, minute)
end

function WorldState:GetDayNumber()
	return self.currentDay
end

function WorldState:IsNight()
	return self.currentHour < 6 or self.currentHour >= 20
end

-- ========================================
-- RESOURCE/STRUCTURE MODEL MANAGEMENT (Updated)
-- ========================================

function WorldState:RegisterResourceModel(resourceType, model)
	if model and model:IsA("Model") then
		resourceModels[resourceType] = model
		print("[WorldState] Registered model for resource " .. resourceType)
		return true
	else
		warn("[WorldState] Failed to register model for resource " .. resourceType .. " - not a valid model")
		return false
	end
end

function WorldState:GetResourceModel(resourceType)
	return resourceModels[resourceType]
end

function WorldState:GetStructureModel(structureType) -- NEW
	return structureModels[structureType]
end


-- ========================================
-- GRID CELL STATE MANAGEMENT (Updated)
-- ========================================

function WorldState:InitializeCellStates(gridCells, worldFolder) -- Added worldFolder parameter
	print("[WorldState] Initializing cell states...")

	local totalGridSize = CONFIG.GRID.GRID_SIZE + (CONFIG.GRID.BEACH_THICKNESS * 2)

	for x = 1, totalGridSize do
		self.cellStates[x] = {}
		self.resourceInstances[x] = {}

		for z = 1, totalGridSize do
			self.cellStates[x][z] = {
				occupied = false, -- Is a player here?
				resources = {}, -- Count of each resource type in this cell
				blocked = false, -- Is this cell blocked for spawning? (Used for structures)
				structureType = nil, -- Stores the type of structure blocking the cell (e.g., "TOWNHALL") (NEW)
				lastUpdate = tick(),
			}

			self.resourceInstances[x][z] = {}

			-- Initialize resource counts
			for resourceType, _ in pairs(CONFIG.RESOURCES) do
				self.cellStates[x][z].resources[resourceType] = 0
			end
		end
	end

	print("[WorldState] Cell states initialized for " .. totalGridSize .. "x" .. totalGridSize .. " grid")

	-- Place the initial structure
	self:PlaceTownHall(gridCells, worldFolder)
end

function WorldState:GetCellState(x, z)
	if self.cellStates[x] and self.cellStates[x][z] then
		return self.cellStates[x][z]
	end
	return nil
end

function WorldState:SetCellOccupied(x, z, occupied)
	if self.cellStates[x] and self.cellStates[x][z] then
		self.cellStates[x][z].occupied = occupied
		self.cellStates[x][z].lastUpdate = tick()
	end
end

function WorldState:SetCellBlocked(x, z, blocked, structureType) -- MODIFIED to accept structureType
	if self.cellStates[x] and self.cellStates[x][z] then
		self.cellStates[x][z].blocked = blocked
		-- Store the structure type if blocking, otherwise nil
		self.cellStates[x][z].structureType = blocked and structureType or nil 
	end
end

function WorldState:IsCellAvailableForSpawn(x, z)
	local state = self:GetCellState(x, z)
	if not state then return false end

	-- Check if cell is in grass area (not beach)
	local grassStartX = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndX = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE
	local grassStartZ = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndZ = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE

	if x < grassStartX or x > grassEndX or z < grassStartZ or z > grassEndZ then
		return false
	end

	-- Check if cell is occupied, blocked (by structure), or has too many resources
	if state.occupied or state.blocked then
		return false
	end

	return true
end

-- ========================================
-- STRUCTURE PLACEMENT (USING PLACEMENT MODULE)
-- ========================================

function WorldState:PlaceTownHall(gridCells, worldFolder)
	print("[WorldState] Starting TownHall placement using PlacementModule...")

	-- Debug: Check parameters
	print("[WorldState] gridCells type:", type(gridCells))
	print("[WorldState] worldFolder type:", type(worldFolder))
	if worldFolder then
		print("[WorldState] worldFolder name:", worldFolder.Name)
	end

	local structureType = "TOWNHALL"
	local townHallModel = self:GetStructureModel(structureType)
	local structureConfig = CONFIG.STRUCTURES[structureType]

	-- Debug: Check model existence
	print("[WorldState] TownHall model found:", townHallModel ~= nil)
	if townHallModel then
		print("[WorldState] TownHall model type:", townHallModel.ClassName)
		print("[WorldState] TownHall PrimaryPart:", townHallModel.PrimaryPart ~= nil)
		if townHallModel.PrimaryPart then
			print("[WorldState] PrimaryPart name:", townHallModel.PrimaryPart.Name)
		end
	end

	if not townHallModel or not townHallModel:IsA("Model") or not townHallModel.PrimaryPart then
		warn("[WorldState] TownHall model not found or has no PrimaryPart set. Skipping placement.")
		return
	end

	if not worldFolder then
		warn("[WorldState] No worldFolder provided. Cannot place TownHall.")
		return
	end

	-- Calculate structure size using PlacementModule
	local sizeX, sizeZ = self.placementModule:CalculateStructureSize(townHallModel)

	-- Define placement options for grass-only area
	local totalGridSize = CONFIG.GRID.GRID_SIZE + (CONFIG.GRID.BEACH_THICKNESS * 2)
	local grassStartX = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndX = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE
	local grassStartZ = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndZ = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE

	local placementOptions = {
		name = structureConfig.name .. "_Initial",
		structureType = structureType,
		heightOffset = 0,
		randomRotation = true,
		anchored = true,
		canCollide = true,
		makeVisible = true,
		attributes = {
			StructureType = structureType,
			Health = structureConfig.health,
		},
		gridBounds = {
			minX = grassStartX,
			maxX = grassEndX,
			minZ = grassStartZ,
			maxZ = grassEndZ,
		}
	}

	-- Use PlacementModule to place the TownHall at center
	local townHallInstance, blockedCells, placedX, placedZ = self.placementModule:PlaceAtCenter(
		townHallModel, 
		self.cellStates, 
		gridCells, 
		worldFolder, 
		placementOptions
	)

	if townHallInstance and blockedCells then
		-- Store structure instance reference
		self.structureInstances[structureType] = townHallInstance

		-- Print placement info
		print(string.format("[WorldState] TownHall placed at grid center (Cell: %d, %d) occupying %dx%d cells", 
			placedX, placedZ, sizeX, sizeZ))

		-- Print blocked cells for debugging
		for _, cell in ipairs(blockedCells) do
			print(string.format("[WorldState] Blocked cell (%d, %d) for TownHall", cell.x, cell.z))
		end

		-- Register with StructureManager to enable queue system and free Builder
		if self.structureManager then
			print("[WorldState] Registering TownHall with StructureManager...")

			-- Get the first player as owner (or use a better method to determine owner)
			local firstPlayer = game.Players:GetPlayers()[1]
			local playerName = firstPlayer and firstPlayer.Name or "Player1"

			-- Create structure stats for the TownHall with proper player assignment
			local stats = AllStats:CreateInstance("PlayerStructures", structureType, playerName)
			if not stats then
				warn("[WorldState] Failed to create TownHall stats")
			else
				-- Ensure proper team assignment
				stats.Team = "Player"
				stats.Owner = playerName

				local success = self.structureManager:OnStructurePlaced(
					townHallInstance,
					stats,
					placedX,
					placedZ,
					blockedCells
				)

				if success then
					print("[WorldState] TownHall successfully registered with StructureManager!")
					print("[WorldState] Owner:", playerName, "Team:", stats.Team)
					print("[WorldState] Free Builder should be added to queue automatically")
				else
					warn("[WorldState] Failed to register TownHall with StructureManager")
				end
			end
		else
			warn("[WorldState] StructureManager not available - TownHall queue system won't work")
		end

		print("[WorldState] TownHall placement successful!")
		return townHallInstance, placedX, placedZ
	else
		warn("[WorldState] Failed to place TownHall using PlacementModule")
		return nil
	end
end

-- ========================================
-- ADDITIONAL PLACEMENT FUNCTIONS
-- ========================================

function WorldState:PlaceStructureAt(structureType, gridX, gridZ, gridCells, worldFolder, options)
	-- Generic function to place any structure at a specific location
	local structureModel = self:GetStructureModel(structureType)
	local structureConfig = CONFIG.STRUCTURES[structureType]

	if not structureModel or not structureConfig then
		warn("[WorldState] Invalid structure type:", structureType)
		return nil
	end

	if not worldFolder then
		warn("[WorldState] No worldFolder provided. Cannot place structure.")
		return nil
	end

	-- Merge default options with provided options
	local placementOptions = options or {}
	placementOptions.name = placementOptions.name or (structureConfig.name .. "_" .. gridX .. "_" .. gridZ)
	placementOptions.structureType = structureType
	placementOptions.attributes = placementOptions.attributes or {}
	placementOptions.attributes.StructureType = structureType
	placementOptions.attributes.Health = structureConfig.health

	-- Place structure at specific location
	local structureInstance = self.placementModule:PlaceStructure(
		structureModel, 
		gridCells, 
		gridX, 
		gridZ, 
		worldFolder, 
		placementOptions
	)

	if structureInstance then
		-- Calculate and block cells
		local sizeX, sizeZ = self.placementModule:CalculateStructureSize(structureModel)
		local blockedCells = self.placementModule:BlockCells(self.cellStates, gridX, gridZ, sizeX, sizeZ, structureType)

		-- Store structure instance reference
		if not self.structureInstances[structureType] then
			self.structureInstances[structureType] = {}
		end
		if type(self.structureInstances[structureType]) == "table" then
			table.insert(self.structureInstances[structureType], structureInstance)
		else
			-- Convert single instance to table
			local oldInstance = self.structureInstances[structureType]
			self.structureInstances[structureType] = {oldInstance, structureInstance}
		end

		print(string.format("[WorldState] Placed %s at (%d, %d)", structureType, gridX, gridZ))
		return structureInstance, blockedCells
	else
		warn(string.format("[WorldState] Failed to place %s at (%d, %d)", structureType, gridX, gridZ))
		return nil
	end
end

function WorldState:PlaceStructureNear(structureType, targetX, targetZ, gridCells, worldFolder, options)
	-- Place a structure near a specific location
	local structureModel = self:GetStructureModel(structureType)
	local structureConfig = CONFIG.STRUCTURES[structureType]

	if not structureModel or not structureConfig then
		warn("[WorldState] Invalid structure type:", structureType)
		return nil
	end

	if not worldFolder then
		warn("[WorldState] No worldFolder provided. Cannot place structure.")
		return nil
	end

	-- Merge default options with provided options
	local placementOptions = options or {}
	placementOptions.structureType = structureType
	placementOptions.attributes = placementOptions.attributes or {}
	placementOptions.attributes.StructureType = structureType
	placementOptions.attributes.Health = structureConfig.health

	-- Place structure near target location
	local structureInstance, blockedCells, placedX, placedZ = self.placementModule:PlaceNearLocation(
		structureModel, 
		self.cellStates, 
		gridCells, 
		targetX, 
		targetZ, 
		worldFolder, 
		placementOptions
	)

	if structureInstance and blockedCells then
		-- Store structure instance reference
		if not self.structureInstances[structureType] then
			self.structureInstances[structureType] = {}
		end
		if type(self.structureInstances[structureType]) == "table" then
			table.insert(self.structureInstances[structureType], structureInstance)
		else
			-- Convert single instance to table
			local oldInstance = self.structureInstances[structureType]
			self.structureInstances[structureType] = {oldInstance, structureInstance}
		end

		print(string.format("[WorldState] Placed %s near (%d, %d) at (%d, %d)", 
			structureType, targetX, targetZ, placedX, placedZ))
		return structureInstance, blockedCells, placedX, placedZ
	else
		warn(string.format("[WorldState] Failed to place %s near (%d, %d)", structureType, targetX, targetZ))
		return nil
	end
end

-- ========================================
-- RESOURCE SPAWNING SYSTEM (Unchanged)
-- ========================================

function WorldState:CanSpawnResource(resourceType, x, z)
	local state = self:GetCellState(x, z)
	if not state then return false end

	local resourceConfig = CONFIG.RESOURCES[resourceType]
	if not resourceConfig then return false end

	-- Check if cell is available
	if not self:IsCellAvailableForSpawn(x, z) then
		return false
	end

	-- Check if cell already has max resources of this type
	if state.resources[resourceType] >= resourceConfig.maxPerCell then
		return false
	end

	return true
end

function WorldState:SpawnResource(resourceType, x, z, gridCells, worldFolder)
	-- Spawn a resource using AllStats data and set proper attributes
	if not AllStats:GetResourceStats(resourceType) then
		warn("[WorldState] Invalid resource type:", resourceType)
		return false
	end

	-- Check if spawn is allowed
	if not self:CanSpawnResource(resourceType, x, z) then
		return false
	end

	-- Get resource stats from AllStats
	local resourceInstance = AllStats:CreateResourceInstance(resourceType)
	if not resourceInstance then
		warn("[WorldState] Failed to create resource instance for:", resourceType)
		return false
	end

	-- Get the model name from AllStats
	local modelName = AllStats:GetResourceModelName(resourceType)
	if not modelName then
		warn("[WorldState] No model name found for resource:", resourceType)
		return false
	end

	-- Get cell position
	local cell = gridCells[x] and gridCells[x][z]
	if not cell then
		warn("[WorldState] Invalid cell coordinates:", x, z)
		return false
	end

	-- Get model from resources folder
	local resourceModel = resourceModels[resourceType]
	if not resourceModel then
		warn("[WorldState] Resource model not found for " .. resourceType .. " (looking for " .. modelName .. ")")
		return false
	end

	-- Clone the model
	local newResource = resourceModel:Clone()
	newResource.Name = resourceInstance.Name .. "_" .. resourceInstance.ResourceId

	-- Set position
	if newResource.PrimaryPart then
		local spawnPosition = cell.Position + Vector3.new(0, newResource.PrimaryPart.Size.Y/2, 0)
		newResource:SetPrimaryPartCFrame(CFrame.new(spawnPosition))

		-- Make sure all parts are anchored
		for _, part in ipairs(newResource:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	else
		warn("[WorldState] Resource model has no PrimaryPart:", resourceType)
		newResource:Destroy()
		return false
	end

	-- Set comprehensive attributes from AllStats
	newResource:SetAttribute("ResourceType", resourceInstance.Type)
	newResource:SetAttribute("ResourceId", resourceInstance.ResourceId)
	newResource:SetAttribute("ResourceName", resourceInstance.Name)
	newResource:SetAttribute("HarvestTime", resourceInstance.HarvestTime)
	newResource:SetAttribute("HarvestAmountMin", resourceInstance.HarvestAmount.min)
	newResource:SetAttribute("HarvestAmountMax", resourceInstance.HarvestAmount.max)
	newResource:SetAttribute("MaxHarvests", resourceInstance.MaxHarvests)
	newResource:SetAttribute("CurrentHarvests", resourceInstance.CurrentHarvests)
	newResource:SetAttribute("RespawnTime", resourceInstance.RespawnTime)
	newResource:SetAttribute("RequiredTool", resourceInstance.RequiredTool or "None")
	newResource:SetAttribute("StorageType", resourceInstance.StorageType)
	newResource:SetAttribute("Value", resourceInstance.Value)
	newResource:SetAttribute("IsActive", resourceInstance.IsActive)
	newResource:SetAttribute("SpawnTime", resourceInstance.SpawnTime)
	newResource:SetAttribute("LastHarvestTime", resourceInstance.LastHarvestTime)
	newResource:SetAttribute("GridX", x)
	newResource:SetAttribute("GridZ", z)
	newResource:SetAttribute("IsSelected", false) -- For selection system

	-- Optional attributes
	if resourceInstance.HarvestSound then
		newResource:SetAttribute("HarvestSound", resourceInstance.HarvestSound)
	end
	if resourceInstance.DepletedModel then
		newResource:SetAttribute("DepletedModel", resourceInstance.DepletedModel)
	end
	if resourceInstance.Description then
		newResource:SetAttribute("Description", resourceInstance.Description)
	end

	-- Parent to world
	newResource.Parent = worldFolder

	-- Update cell state
	if self.cellStates[x] and self.cellStates[x][z] then
		if not self.cellStates[x][z].resources then
			self.cellStates[x][z].resources = {}
		end
		self.cellStates[x][z].resources[resourceType] = (self.cellStates[x][z].resources[resourceType] or 0) + 1
		self.cellStates[x][z].hasResource = true
		self.cellStates[x][z].resourceType = resourceType
		self.cellStates[x][z].resourceId = resourceInstance.ResourceId
		self.cellStates[x][z].resourceInstance = newResource
	end

	-- Track the resource instance
	if not self.resourceInstances then
		self.resourceInstances = {}
	end
	if not self.resourceInstances[resourceType] then
		self.resourceInstances[resourceType] = {}
	end
	self.resourceInstances[resourceType][resourceInstance.ResourceId] = {
		instance = newResource,
		stats = resourceInstance,
		gridX = x,
		gridZ = z,
		spawnTime = tick()
	}

	-- Update counters
	if not self.totalResourcesSpawned then
		self.totalResourcesSpawned = 0
	end
	if not self.resourcesByType then
		self.resourcesByType = {}
	end
	self.totalResourcesSpawned = self.totalResourcesSpawned + 1
	if not self.resourcesByType[resourceType] then
		self.resourcesByType[resourceType] = 0
	end
	self.resourcesByType[resourceType] = self.resourcesByType[resourceType] + 1

	print(string.format("[WorldState] Spawned %s (%s) at (%d, %d) with ID: %s", 
		resourceInstance.Name, resourceType, x, z, resourceInstance.ResourceId))

	return true
end

function WorldState:CollectResource(resourceType, x, z, resourceObject, player)
	-- Remove the resource (works for both Model and Part)
	resourceObject:Destroy()

	-- Update state
	if self.cellStates[x] and self.cellStates[x][z] then
		self.cellStates[x][z].resources[resourceType] = math.max(0, self.cellStates[x][z].resources[resourceType] - 1)
	end

	-- Remove from instances table
	if self.resourceInstances[x] and self.resourceInstances[x][z] and self.resourceInstances[x][z][resourceType] then
		for i, obj in ipairs(self.resourceInstances[x][z][resourceType]) do
			if obj == resourceObject then
				table.remove(self.resourceInstances[x][z][resourceType], i)
				break
			end
		end
	end

	-- Award resource to player (you can customize this)
	local resourceConfig = CONFIG.RESOURCES[resourceType]
	print("[WorldState] " .. player.Name .. " collected " .. resourceType .. " (Value: " .. resourceConfig.value .. ")")

	-- You can add to player's inventory here
	-- Example: add to leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local resourceStat = leaderstats:FindFirstChild(resourceConfig.name)
		if not resourceStat then
			resourceStat = Instance.new("IntValue")
			resourceStat.Name = resourceConfig.name
			resourceStat.Value = 0
			resourceStat.Parent = leaderstats
		end
		resourceStat.Value = resourceStat.Value + resourceConfig.value
	end
end

function WorldState:SpawnRandomResources(gridCells, worldFolder)
	-- Spawn resources using AllStats data and spawn weights
	local currentTime = tick()

	-- Check if enough time has passed since last spawn cycle
	if not self.lastGlobalSpawnCheck then
		self.lastGlobalSpawnCheck = 0
	end

	local timeSinceLastSpawn = currentTime - self.lastGlobalSpawnCheck
	local spawnCooldown = 30 -- Spawn cycle every 30 seconds

	if timeSinceLastSpawn < spawnCooldown then
		return -- Not time to spawn yet
	end

	self.lastGlobalSpawnCheck = currentTime

	-- Get resource data from AllStats
	local resourceTypes = AllStats:GetAllResourceTypes()
	local spawnWeights = AllStats:GetResourceSpawnWeights()

	-- Calculate spawn area (grass area only)
	local grassStartX = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndX = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE
	local grassStartZ = CONFIG.GRID.BEACH_THICKNESS + 1
	local grassEndZ = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE

	-- Spawn multiple resources based on weights
	local totalSpawnAttempts = 10 -- Total spawn attempts per cycle

	for i = 1, totalSpawnAttempts do
		-- Pick weighted random resource type
		local selectedType = self:WeightedRandomChoice(resourceTypes, spawnWeights)

		-- Try to find a valid spawn location
		local attempts = 0
		local maxAttempts = 10

		while attempts < maxAttempts do
			local randomX = math.random(grassStartX, grassEndX)
			local randomZ = math.random(grassStartZ, grassEndZ)

			-- Check if we can spawn here
			if self:CanSpawnResource(selectedType, randomX, randomZ) then
				-- Apply spawn chance based on resource weight (higher weight = higher chance)
				local spawnChance = spawnWeights[selectedType] / 100 -- Convert weight to percentage
				if math.random() <= spawnChance then
					if self:SpawnResource(selectedType, randomX, randomZ, gridCells, worldFolder) then
						break -- Successfully spawned, move to next attempt
					end
				end
			end

			attempts = attempts + 1
		end
	end
end

function WorldState:WeightedRandomChoice(choices, weights)
	-- Select a random choice based on weighted probabilities
	if not choices or #choices == 0 then
		return nil
	end

	-- Calculate total weight
	local totalWeight = 0
	for _, choice in ipairs(choices) do
		totalWeight = totalWeight + (weights[choice] or 1)
	end

	-- Pick random number in range
	local randomNum = math.random() * totalWeight

	-- Find which choice this corresponds to
	local currentWeight = 0
	for _, choice in ipairs(choices) do
		currentWeight = currentWeight + (weights[choice] or 1)
		if randomNum <= currentWeight then
			return choice
		end
	end

	-- Fallback (shouldn't happen)
	return choices[1]
end

-- ========================================
-- MAIN UPDATE LOOP (Unchanged)
-- ========================================

function WorldState:StartUpdateLoop(gridCells, worldFolder)
	print("[WorldState] Starting update loop...")

	spawn(function()
		while true do
			-- Update time
			self:UpdateTime()

			-- Spawn resources if enabled
			if CONFIG.SPAWN.ENABLE_AUTO_SPAWN then
				self:SpawnRandomResources(gridCells, worldFolder)
			end

			-- Wait for next check
			wait(CONFIG.SPAWN.CHECK_INTERVAL)
		end
	end)

	print("[WorldState] Update loop started")
end

-- ========================================
-- UTILITY FUNCTIONS (Unchanged)
-- ========================================

function WorldState:GetTotalResources()
	local totals = {}
	for resourceType, _ in pairs(CONFIG.RESOURCES) do
		totals[resourceType] = 0
	end

	for x, row in pairs(self.cellStates) do
		for z, state in pairs(row) do
			for resourceType, count in pairs(state.resources) do
				totals[resourceType] = totals[resourceType] + count
			end
		end
	end

	return totals
end

function WorldState:GetConfig()
	return CONFIG
end

function WorldState:SetConfig(newConfig)
	-- Merge new config with existing
	for key, value in pairs(newConfig) do
		if CONFIG[key] then
			for subKey, subValue in pairs(value) do
				CONFIG[key][subKey] = subValue
			end
		end
	end
end

return WorldState