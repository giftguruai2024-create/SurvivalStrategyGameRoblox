-- @ScriptType: ModuleScript
-- WorldStateScript Module
-- Place this in ReplicatedStorage or ServerStorage
-- Manages world time, grid cell states, and resource spawning

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldState = {}
WorldState.__index = WorldState

-- ========================================
-- RESOURCE MODEL REFERENCES
-- ========================================
local resourcesFolder = ReplicatedStorage:WaitForChild("Resources")
local resourceModels = {
	WOOD = resourcesFolder:WaitForChild("Tree"),
	STONE = resourcesFolder:WaitForChild("Rock"),
	FOOD = resourcesFolder:WaitForChild("Food"),
	GOLD = resourcesFolder:WaitForChild("Gold"),
	-- Add more mappings as you create models
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
			modelName = "Tree", -- Name of model in Resources folder
			spawnChance = 0.5, -- 15% chance per spawn cycle
			maxPerCell = 1, -- Maximum resources of this type per cell
			spawnCooldown = 30, -- Seconds between spawn attempts
			value = 10, -- Resource value (for collection)
			heightOffset = 0, -- Additional height offset (if needed)
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
			modelName = nil, -- No model yet (will use generic part)
			spawnChance = 0.5,
			maxPerCell = 1,
			spawnCooldown = 20,
			value = 5,
			heightOffset = 0,
			-- Fallback properties for generic parts
			color = Color3.fromRGB(255, 100, 100),
			size = Vector3.new(1.5, 1.5, 1.5),
		},
		GOLD = {
			name = "Gold",
			modelName = nil, -- No model yet (will use generic part)
			spawnChance = 0.1, -- Rare
			maxPerCell = 1,
			spawnCooldown = 120, -- 2 minutes
			value = 50,
			heightOffset = 0,
			-- Fallback properties for generic parts
			color = Color3.fromRGB(255, 215, 0),
			size = Vector3.new(1, 2, 1),
		},
	},

	-- Grid configuration (should match your main script)
	GRID = {
		GRID_SIZE = 30,
		CELL_SIZE = 3,
		BEACH_THICKNESS = 2,
	},

	-- Spawning behavior
	SPAWN = {
		CHECK_INTERVAL = 5, -- How often to check for new spawns (seconds)
		RESOURCE_HEIGHT_OFFSET = 2, -- Height above cell to spawn resources
		ENABLE_AUTO_SPAWN = true, -- Enable automatic spawning
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

	-- Resource spawn tracking
	self.lastSpawnCheck = {} -- Track last spawn time for each resource type

	-- Initialize spawn timers
	for resourceType, _ in pairs(CONFIG.RESOURCES) do
		self.lastSpawnCheck[resourceType] = 0
	end

	print("[WorldState] Initialized")
	return self
end

-- ========================================
-- TIME MANAGEMENT
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
-- RESOURCE MODEL MANAGEMENT
-- ========================================

function WorldState:RegisterResourceModel(resourceType, model)
	if model and model:IsA("Model") then
		resourceModels[resourceType] = model
		print("[WorldState] Registered model for " .. resourceType)
		return true
	else
		warn("[WorldState] Failed to register model for " .. resourceType .. " - not a valid model")
		return false
	end
end

function WorldState:GetResourceModel(resourceType)
	return resourceModels[resourceType]
end

-- ========================================
-- GRID CELL STATE MANAGEMENT
-- ========================================

function WorldState:InitializeCellStates(gridCells)
	print("[WorldState] Initializing cell states...")

	local totalGridSize = CONFIG.GRID.GRID_SIZE + (CONFIG.GRID.BEACH_THICKNESS * 2)

	for x = 1, totalGridSize do
		self.cellStates[x] = {}
		self.resourceInstances[x] = {}

		for z = 1, totalGridSize do
			self.cellStates[x][z] = {
				occupied = false, -- Is a player here?
				resources = {}, -- Count of each resource type in this cell
				blocked = false, -- Is this cell blocked for spawning?
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

function WorldState:SetCellBlocked(x, z, blocked)
	if self.cellStates[x] and self.cellStates[x][z] then
		self.cellStates[x][z].blocked = blocked
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

	-- Check if cell is occupied, blocked, or has too many resources
	if state.occupied or state.blocked then
		return false
	end

	return true
end

-- ========================================
-- RESOURCE SPAWNING SYSTEM
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
	if not self:CanSpawnResource(resourceType, x, z) then
		return false
	end

	local resourceConfig = CONFIG.RESOURCES[resourceType]
	local cell = gridCells[x] and gridCells[x][z]

	if not cell then
		warn("[WorldState] Cell not found at (" .. x .. ", " .. z .. ")")
		return false
	end

	local resource
	local clickDetectorParent

	-- Check if we have a model for this resource type
	local model = resourceModels[resourceType]

	if model and model:IsA("Model") then
		-- Clone the model from ReplicatedStorage
		resource = model:Clone()
		resource.Name = resourceConfig.name .. "_" .. x .. "_" .. z

		-- Make sure the model has a PrimaryPart
		if not resource.PrimaryPart then
			warn("[WorldState] Model '" .. model.Name .. "' has no PrimaryPart set! Using first part.")
			-- Try to set a primary part automatically
			for _, part in ipairs(resource:GetDescendants()) do
				if part:IsA("BasePart") then
					resource.PrimaryPart = part
					break
				end
			end
		end

		if resource.PrimaryPart then
			-- Calculate spawn position
			local spawnPosition = cell.Position + Vector3.new(0, CONFIG.SPAWN.RESOURCE_HEIGHT_OFFSET + resourceConfig.heightOffset, 0)

			-- Position the model using PrimaryPart
			resource:SetPrimaryPartCFrame(CFrame.new(spawnPosition))

			-- Set all parts to anchored
			for _, part in ipairs(resource:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end

			clickDetectorParent = resource.PrimaryPart
		else
			warn("[WorldState] Could not set PrimaryPart for " .. resourceType .. " model")
			resource:Destroy()
			return false
		end

	else
		-- Fallback: Create a generic part if no model exists
		warn("[WorldState] No model found for " .. resourceType .. ", using generic part")
		resource = Instance.new("Part")
		resource.Name = resourceConfig.name .. "_" .. x .. "_" .. z
		resource.Size = resourceConfig.size or Vector3.new(2, 2, 2)
		resource.Color = resourceConfig.color or Color3.fromRGB(200, 200, 200)
		resource.Material = Enum.Material.SmoothPlastic
		resource.Anchored = true
		resource.CanCollide = true

		-- Position above the cell
		local spawnPosition = cell.Position + Vector3.new(0, CONFIG.SPAWN.RESOURCE_HEIGHT_OFFSET + resourceConfig.heightOffset, 0)
		resource.Position = spawnPosition

		clickDetectorParent = resource
	end

	-- Add identifier attributes to the main object (Model or Part)
	resource:SetAttribute("ResourceType", resourceType)
	resource:SetAttribute("ResourceValue", resourceConfig.value)
	resource:SetAttribute("GridX", x)
	resource:SetAttribute("GridZ", z)

	-- Parent to world folder
	resource.Parent = worldFolder

	-- Update state
	self.cellStates[x][z].resources[resourceType] = self.cellStates[x][z].resources[resourceType] + 1

	-- Store instance reference
	if not self.resourceInstances[x][z][resourceType] then
		self.resourceInstances[x][z][resourceType] = {}
	end
	table.insert(self.resourceInstances[x][z][resourceType], resource)

	-- Setup collection detection (ClickDetector on PrimaryPart or main Part)
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 10
	clickDetector.Parent = clickDetectorParent

	clickDetector.MouseClick:Connect(function(player)
		self:CollectResource(resourceType, x, z, resource, player)
	end)

	print("[WorldState] Spawned " .. resourceType .. " at (" .. x .. ", " .. z .. ")")
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
	local currentTime = tick()

	for resourceType, resourceConfig in pairs(CONFIG.RESOURCES) do
		-- Check if cooldown has passed
		local timeSinceLastSpawn = currentTime - self.lastSpawnCheck[resourceType]

		if timeSinceLastSpawn >= resourceConfig.spawnCooldown then
			self.lastSpawnCheck[resourceType] = currentTime

			-- Attempt to spawn resources
			local grassStartX = CONFIG.GRID.BEACH_THICKNESS + 1
			local grassEndX = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE
			local grassStartZ = CONFIG.GRID.BEACH_THICKNESS + 1
			local grassEndZ = CONFIG.GRID.BEACH_THICKNESS + CONFIG.GRID.GRID_SIZE

			-- Try to spawn in random cells
			local spawnAttempts = 5 -- Try 5 random cells per resource type
			for i = 1, spawnAttempts do
				local randomX = math.random(grassStartX, grassEndX)
				local randomZ = math.random(grassStartZ, grassEndZ)

				-- Check spawn chance
				if math.random() <= resourceConfig.spawnChance then
					self:SpawnResource(resourceType, randomX, randomZ, gridCells, worldFolder)
				end
			end
		end
	end
end

-- ========================================
-- MAIN UPDATE LOOP
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
-- UTILITY FUNCTIONS
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