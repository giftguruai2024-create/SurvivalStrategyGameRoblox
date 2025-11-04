-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- StructureManager Module
-- Interfaces with AllStats and handles structure placement, management, and logic
-- Called by PlacementModule when placing structures

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AllStats = require(ReplicatedStorage:WaitForChild("AllStats"))

-- Unit model references
local unitsFolder = ReplicatedStorage:WaitForChild("Units")
local playerUnitsFolder = unitsFolder:WaitForChild("Player")
local worldAIUnitsFolder = unitsFolder:WaitForChild("WorldAI")

local StructureManager = {}
StructureManager.__index = StructureManager

-- ========================================
-- STRUCTURE MANAGER CLASS
-- ========================================

function StructureManager.new()
	local self = setmetatable({}, StructureManager)

	-- Track all placed structures
	self.placedStructures = {} -- {instanceId = {instance, stats, gridX, gridZ, blockedCells}}
	self.structuresByTeam = {Player = {}, Enemy = {}}
	self.structuresByOwner = {} -- {ownerName = {instanceIds}}
	self.structuresByType = {} -- {structureType = {instanceIds}}

	-- Queue management
	self.spawnQueues = {} -- {instanceId = {queue = {}, lastSpawnTime = 0, isPaused = false}}
	self.globalQueueId = 0 -- For unique queue entry IDs

	print("[StructureManager] Initialized with queue management")
	return self
end

-- ========================================
-- STRUCTURE VALIDATION & STATS
-- ========================================

function StructureManager:GetStructureStats(structureType, team, owner)
	-- Get structure stats from AllStats with owner information
	team = team or "Player"

	local stats = AllStats:GetStructureStats(structureType, team)
	if not stats then
		warn("[StructureManager] Invalid structure type:", structureType, "for team:", team)
		return nil
	end

	-- Create instance with owner
	local instanceStats = AllStats:CreateInstance(
		team == "Player" and "PlayerStructures" or "EnemyStructures",
		structureType,
		owner
	)

	return instanceStats
end

function StructureManager:CanPlaceStructure(structureType, team, owner, resources)
	-- Check if a structure can be placed (permissions, resources, etc.)
	local stats = self:GetStructureStats(structureType, team, owner)
	if not stats then
		return false, "Invalid structure type"
	end

	-- Check if player has required resources (if provided)
	if resources and stats.Cost then
		for resourceType, cost in pairs(stats.Cost) do
			if not resources[resourceType] or resources[resourceType] < cost then
				return false, "Insufficient " .. resourceType .. " (need " .. cost .. ", have " .. (resources[resourceType] or 0) .. ")"
			end
		end
	end

	-- Check team permissions (could add more logic here)
	if team == "Player" and not owner then
		return false, "Player structures require an owner"
	end

	return true, "Can place structure"
end

function StructureManager:GetStructureCost(structureType, team)
	-- Get the resource cost for building a structure
	local stats = AllStats:GetStructureStats(structureType, team)
	return stats and stats.Cost or {}
end

function StructureManager:GetBuildTime(structureType, team)
	-- Get the build time for a structure
	local stats = AllStats:GetStructureStats(structureType, team)
	return stats and stats.BuildTime or 0
end

-- ========================================
-- STRUCTURE PLACEMENT INTEGRATION
-- ========================================

function StructureManager:PrepareStructureForPlacement(structureType, team, owner, gridX, gridZ, options)
	-- Prepare structure data before placement (called by PlacementModule)
	options = options or {}

	-- Get structure stats
	local stats = self:GetStructureStats(structureType, team, owner)
	if not stats then
		return nil, "Invalid structure"
	end

	-- Create placement options with structure-specific attributes
	local placementOptions = {
		name = options.name or (stats.StructureType .. "_" .. structureType .. "_" .. gridX .. "_" .. gridZ),
		structureType = structureType,
		heightOffset = options.heightOffset or 0,
		randomRotation = options.randomRotation or false,
		anchored = true,
		canCollide = true,
		makeVisible = true,
		attributes = {
			StructureType = structureType,
			Team = stats.Team,
			Owner = stats.Owner,
			Health = stats.Health,
			MaxHealth = stats.Health,
			DoesAtk = stats.DoesAtk,
			InstanceId = stats.InstanceId,
			PlacedTime = tick(),
		}
	}

	-- Add attack-specific attributes
	if stats.DoesAtk then
		placementOptions.attributes.Range = stats.Range
		placementOptions.attributes.Attack = stats.Attack
		placementOptions.attributes.AtkSpeed = stats.AtkSpeed
	end

	-- Add spawner-specific attributes
	if stats.Spawner then
		placementOptions.attributes.Spawner = true
		if stats.SpawnTypes then
			placementOptions.attributes.SpawnTypes = table.concat(stats.SpawnTypes, ",")
		end
		if stats.SpawnRate then
			placementOptions.attributes.SpawnRate = stats.SpawnRate
		end
	end

	-- Add resource generation attributes
	if stats.ResourceGeneration then
		for resourceType, rate in pairs(stats.ResourceGeneration) do
			placementOptions.attributes["Generate" .. resourceType] = rate
		end
	end

	return stats, placementOptions
end

function StructureManager:OnStructurePlaced(structureInstance, stats, gridX, gridZ, blockedCells)
	-- Called after a structure is successfully placed
	if not structureInstance or not stats then
		warn("[StructureManager] Invalid structure placement data")
		return false
	end

	local instanceId = stats.InstanceId

	-- Store structure data
	self.placedStructures[instanceId] = {
		instance = structureInstance,
		stats = stats,
		gridX = gridX,
		gridZ = gridZ,
		blockedCells = blockedCells,
		placedTime = tick()
	}

	-- Track by team
	if not self.structuresByTeam[stats.Team] then
		self.structuresByTeam[stats.Team] = {}
	end
	table.insert(self.structuresByTeam[stats.Team], instanceId)

	-- Track by owner
	if stats.Owner then
		if not self.structuresByOwner[stats.Owner] then
			self.structuresByOwner[stats.Owner] = {}
		end
		table.insert(self.structuresByOwner[stats.Owner], instanceId)
	end

	-- Track by type
	local structureType = stats.StructureType or "Unknown"
	if not self.structuresByType[structureType] then
		self.structuresByType[structureType] = {}
	end
	table.insert(self.structuresByType[structureType], instanceId)

	print(string.format("[StructureManager] Registered %s structure (ID: %s) at (%d, %d) for %s", 
		structureType, instanceId, gridX, gridZ, stats.Owner or stats.Team))

	-- Initialize structure behavior (spawning, resource generation, etc.)
	self:InitializeStructureBehavior(instanceId)

	-- Special handling for Town Hall - add free starting Villager
	-- Check for TownHall by its unique properties: Main type + can spawn VILLAGER
	if stats.StructureType == "Main" and stats.Spawner and stats.SpawnTypes then
		for _, spawnType in ipairs(stats.SpawnTypes) do
			if spawnType == "VILLAGER" and stats.Team == "Player" then
				print("[StructureManager] Detected Player TownHall - adding free Villager")
				self:AddFreeStartingVillager(instanceId)
				break
			end
		end
	end

	return true
end

-- ========================================
-- QUEUE MANAGEMENT SYSTEM
-- ========================================

function StructureManager:InitializeQueue(instanceId)
	-- Initialize spawn queue for a spawner structure
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.Spawner then
		return false
	end

	self.spawnQueues[instanceId] = {
		queue = {}, -- Array of spawn orders
		lastSpawnTime = 0,
		isPaused = false,
		lastAutoQueueTime = 0,
	}

	print(string.format("[StructureManager] Initialized spawn queue for %s", instanceId))
	return true
end

function StructureManager:AddToQueue(instanceId, npcType, priority, customSpawnTime)
	-- Add an NPC to the spawn queue
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.Spawner then
		warn("[StructureManager] Cannot add to queue: Structure is not a spawner")
		return false
	end

	local stats = structureData.stats
	local queue = self.spawnQueues[instanceId]

	if not queue then
		warn("[StructureManager] Queue not initialized for structure:", instanceId)
		return false
	end

	-- Check if queue is full
	if #queue.queue >= stats.MaxQueue then
		if stats.PauseWhenFull then
			warn("[StructureManager] Queue is full, cannot add more units")
			return false
		else
			-- Remove oldest item if queue is full and not set to pause
			table.remove(queue.queue, 1)
			print("[StructureManager] Queue full, removed oldest entry")
		end
	end

	-- Validate NPC type
	if not self:CanSpawnNPCType(instanceId, npcType) then
		warn("[StructureManager] Cannot spawn NPC type:", npcType)
		return false
	end

	-- Get base spawn time from NPC stats
	local npcStats = AllStats:GetNPCStats(npcType, stats.Team)
	if not npcStats then
		warn("[StructureManager] Invalid NPC type:", npcType)
		return false
	end

	-- Calculate actual spawn time with multiplier
	local baseSpawnTime = customSpawnTime or npcStats.SpawnTime or 5
	local actualSpawnTime = baseSpawnTime * stats.SpawnTimeMultiplier

	-- Create queue entry
	self.globalQueueId = self.globalQueueId + 1
	local queueEntry = {
		queueId = self.globalQueueId,
		npcType = npcType,
		spawnTimeRemaining = actualSpawnTime,
		totalSpawnTime = actualSpawnTime,
		priority = priority or 1,
		addedTime = tick(),
		owner = stats.Owner,
		team = stats.Team,
		cost = npcStats.Cost or {},
		paid = false, -- Track if cost has been paid
	}

	-- Insert based on priority (higher priority = earlier in queue)
	local inserted = false
	for i, entry in ipairs(queue.queue) do
		if queueEntry.priority > entry.priority then
			table.insert(queue.queue, i, queueEntry)
			inserted = true
			break
		end
	end

	if not inserted then
		table.insert(queue.queue, queueEntry)
	end

	-- Handle cost payment
	if stats.QueueCost == "Upfront" then
		-- Here you would integrate with your resource system
		-- For now, just mark as paid
		queueEntry.paid = true
		print(string.format("[StructureManager] Upfront cost paid for %s: %s", npcType, self:FormatCost(queueEntry.cost)))
	end

	print(string.format("[StructureManager] Added %s to queue (ID: %d, spawn time: %.1fs, priority: %d)", 
		npcType, queueEntry.queueId, actualSpawnTime, queueEntry.priority))

	return queueEntry.queueId
end

function StructureManager:RemoveFromQueue(instanceId, queueId)
	-- Remove a specific entry from the queue
	local queue = self.spawnQueues[instanceId]
	if not queue then
		return false
	end

	for i, entry in ipairs(queue.queue) do
		if entry.queueId == queueId then
			-- Refund cost if paid upfront
			if entry.paid then
				print(string.format("[StructureManager] Refunding cost for %s: %s", entry.npcType, self:FormatCost(entry.cost)))
				-- Here you would integrate with your resource system to refund
			end

			table.remove(queue.queue, i)
			print(string.format("[StructureManager] Removed %s from queue (ID: %d)", entry.npcType, queueId))
			return true
		end
	end

	return false
end

function StructureManager:PauseQueue(instanceId, paused)
	-- Pause or unpause the spawn queue
	local queue = self.spawnQueues[instanceId]
	if not queue then
		return false
	end

	queue.isPaused = paused
	print(string.format("[StructureManager] Queue %s for %s", paused and "paused" or "unpaused", instanceId))
	return true
end

function StructureManager:ClearQueue(instanceId)
	-- Clear all entries from the queue
	local queue = self.spawnQueues[instanceId]
	if not queue then
		return false
	end

	-- Refund costs for upfront payments
	local structureData = self.placedStructures[instanceId]
	if structureData and structureData.stats.QueueCost == "Upfront" then
		for _, entry in ipairs(queue.queue) do
			if entry.paid then
				print(string.format("[StructureManager] Refunding cost for %s: %s", entry.npcType, self:FormatCost(entry.cost)))
				-- Here you would integrate with your resource system to refund
			end
		end
	end

	queue.queue = {}
	print(string.format("[StructureManager] Cleared queue for %s", instanceId))
	return true
end

function StructureManager:GetQueueInfo(instanceId)
	-- Get information about the current queue
	local queue = self.spawnQueues[instanceId]
	if not queue then
		return nil
	end

	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return nil
	end

	return {
		queueLength = #queue.queue,
		maxQueue = structureData.stats.MaxQueue,
		isPaused = queue.isPaused,
		queue = queue.queue,
		nextSpawnTime = queue.queue[1] and queue.queue[1].spawnTimeRemaining or 0,
	}
end

function StructureManager:CanSpawnNPCType(instanceId, npcType)
	-- Check if a structure can spawn a specific NPC type
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.Spawner then
		return false
	end

	local spawnTypes = structureData.stats.SpawnTypes
	if not spawnTypes then
		return false
	end

	for _, allowedType in ipairs(spawnTypes) do
		if allowedType == npcType then
			return true
		end
	end

	return false
end

function StructureManager:ProcessQueue(instanceId, deltaTime)
	-- Process the spawn queue (called every frame/tick)
	local queue = self.spawnQueues[instanceId]
	if not queue or queue.isPaused or #queue.queue == 0 then
		return
	end

	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return
	end

	-- Check if structure still exists and has health
	local currentHealth = structureData.instance:GetAttribute("Health") or 0
	if currentHealth <= 0 then
		return
	end

	-- Process first item in queue
	local firstEntry = queue.queue[1]
	if firstEntry then
		firstEntry.spawnTimeRemaining = firstEntry.spawnTimeRemaining - deltaTime

		-- Update spawn time attribute for external systems
		structureData.instance:SetAttribute("NextSpawnTime", firstEntry.spawnTimeRemaining)

		-- Ready to spawn?
		if firstEntry.spawnTimeRemaining <= 0 then
			self:SpawnFromQueue(instanceId)
		end
	end
end

function StructureManager:SpawnFromQueue(instanceId)
	-- Spawn the first NPC in the queue
	local queue = self.spawnQueues[instanceId]
	if not queue or #queue.queue == 0 then
		return false
	end

	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return false
	end

	local firstEntry = queue.queue[1]
	local stats = structureData.stats

	-- Handle cost payment if not paid upfront
	if stats.QueueCost == "OnSpawn" and not firstEntry.paid then
		-- Here you would integrate with your resource system
		-- For now, just mark as paid
		firstEntry.paid = true
		print(string.format("[StructureManager] OnSpawn cost paid for %s: %s", firstEntry.npcType, self:FormatCost(firstEntry.cost)))
	end

	-- Actually spawn the NPC (you'll integrate this with your NPC spawning system)
	local success = self:ExecuteSpawn(instanceId, firstEntry)

	if success then
		-- Remove from queue
		table.remove(queue.queue, 1)
		queue.lastSpawnTime = tick()

		print(string.format("[StructureManager] Successfully spawned %s from %s", firstEntry.npcType, instanceId))
		return true
	else
		warn(string.format("[StructureManager] Failed to spawn %s from %s", firstEntry.npcType, instanceId))
		return false
	end
end

function StructureManager:ExecuteSpawn(instanceId, queueEntry)
	-- Execute the actual spawning of an NPC
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return false
	end

	print(string.format("[StructureManager] Executing spawn: %s for owner %s", 
		queueEntry.npcType, queueEntry.owner))

	-- Get the unit model
	local unitModel = self:GetUnitModel(queueEntry.npcType, queueEntry.team)
	if not unitModel then
		warn("[StructureManager] Could not find unit model for:", queueEntry.npcType)
		return false
	end

	-- Find a nearby available cell for spawning
	local spawnCell = self:FindNearbySpawnCell(instanceId)
	if not spawnCell then
		warn("[StructureManager] No available spawn cells near structure")
		return false
	end

	-- Create NPC stats instance
	local npcStats = AllStats:CreateInstance(
		queueEntry.team == "Player" and "PlayerNPCs" or "EnemyNPCs",
		queueEntry.npcType,
		queueEntry.owner
	)

	if not npcStats then
		warn("[StructureManager] Could not create NPC stats")
		return false
	end

	-- Clone the unit model
	local npcInstance = unitModel:Clone()
	npcInstance.Name = queueEntry.npcType .. "_" .. npcStats.InstanceId

	-- Position the NPC at the spawn cell
	local spawnPosition = spawnCell.Position + Vector3.new(0, 5, 0) -- 5 studs above cell
	if npcInstance.PrimaryPart then
		npcInstance.PrimaryPart.CFrame = CFrame.new(spawnPosition)
	else
		warn("[StructureManager] NPC model has no PrimaryPart set")
		npcInstance:Destroy()
		return false
	end

	-- Set NPC attributes
	npcInstance:SetAttribute("NPCType", queueEntry.npcType)
	npcInstance:SetAttribute("Team", queueEntry.team)
	npcInstance:SetAttribute("Owner", queueEntry.owner)
	npcInstance:SetAttribute("InstanceId", npcStats.InstanceId)
	npcInstance:SetAttribute("Health", npcStats.Health)
	npcInstance:SetAttribute("MaxHealth", npcStats.Health)

	-- Find proper world subfolder
	local worldFolder = self:FindWorldFolder()
	local targetFolder = self:GetOrCreateNPCFolder(worldFolder, queueEntry.team)
	if not targetFolder then
		warn("[StructureManager] Could not find/create NPC folder for spawning")
		npcInstance:Destroy()
		return false
	end

	-- Parent to appropriate folder
	npcInstance.Parent = targetFolder

	-- Add comprehensive NPC attributes for easy game tracking
	self:InitializeNPCAttributes(npcInstance, npcStats, queueEntry.owner)

	-- Register NPC position in WorldState for cell tracking
	local npcGridX, npcGridZ = 0, 0
	if _G.WorldToGrid then
		npcGridX, npcGridZ = _G.WorldToGrid(spawnPosition)

		local worldState = _G.WorldState
		if worldState then
			worldState:RegisterNPCInCell(npcGridX, npcGridZ, npcStats.InstanceId)
		end
	end

	-- Initialize NPCManager if available (for AI)
	if _G.NPCManager then
		local success = _G.NPCManager:RegisterNPC(npcInstance, npcStats, queueEntry.owner)
		if success then
			print(string.format("[StructureManager] NPC %s registered with NPCManager for AI", npcStats.InstanceId))
		else
			warn("[StructureManager] Failed to register NPC with NPCManager")
		end
	else
		print("[StructureManager] NPCManager not available - NPC will not have AI")
	end

	print(string.format("[StructureManager] Successfully spawned %s (ID: %s) at %s", 
		queueEntry.npcType, npcStats.InstanceId, tostring(spawnPosition)))

	return true
end

function StructureManager:InitializeNPCAttributes(npcInstance, npcStats, owner)
	-- Add comprehensive attributes to NPC for easy game tracking
	if not npcInstance or not npcStats then
		return
	end

	-- Basic NPC Info
	npcInstance:SetAttribute("NPCId", npcStats.InstanceId)
	npcInstance:SetAttribute("NPCType", npcStats.UnitType) -- "Worker", "Combat", etc.
	npcInstance:SetAttribute("NPCName", npcStats.UnitType) -- "VILLAGER", "BUILDER", etc.
	npcInstance:SetAttribute("Team", npcStats.Team)
	npcInstance:SetAttribute("Owner", owner or "System")
	npcInstance:SetAttribute("SpawnTime", tick())

	-- Health & Combat
	npcInstance:SetAttribute("Health", npcStats.Health)
	npcInstance:SetAttribute("MaxHealth", npcStats.Health)
	npcInstance:SetAttribute("Attack", npcStats.Attack or 0)
	npcInstance:SetAttribute("AttackSpeed", npcStats.AtkSpeed or 1.0)
	npcInstance:SetAttribute("Range", npcStats.Range or 4)
	npcInstance:SetAttribute("CanFight", npcStats.CanFight or false)

	-- Movement & Stats
	npcInstance:SetAttribute("MovementSpeed", npcStats.MovementSpeed or 8)
	npcInstance:SetAttribute("Level", 1) -- Could be expanded later
	npcInstance:SetAttribute("Experience", 0)

	-- Work Capabilities
	npcInstance:SetAttribute("CanBuild", npcStats.CanBuild or false)
	npcInstance:SetAttribute("CanHarvest", npcStats.CanHarvest or false)
	npcInstance:SetAttribute("BuildSpeed", npcStats.BuildSpeed or 1.0)
	npcInstance:SetAttribute("HarvestSpeed", npcStats.HarvestSpeed or 1.0)
	npcInstance:SetAttribute("HarvestRange", npcStats.HarvestRange or 6)

	-- Inventory & Capacity
	npcInstance:SetAttribute("CarryCapacity", npcStats.CarryCapacity or 0)
	npcInstance:SetAttribute("CurrentCarriedWeight", 0)
	npcInstance:SetAttribute("CarriedWood", 0)
	npcInstance:SetAttribute("CarriedStone", 0)
	npcInstance:SetAttribute("CarriedGold", 0)
	npcInstance:SetAttribute("CarriedFood", 0)

	-- AI State & Task Tracking
	npcInstance:SetAttribute("CurrentState", "Wandering") -- Will be updated by NPCManager
	npcInstance:SetAttribute("CurrentTask", "None") -- Will be updated when tasks assigned
	npcInstance:SetAttribute("TaskStartTime", 0)
	npcInstance:SetAttribute("LastStateChange", tick())
	npcInstance:SetAttribute("IsIdle", false)
	npcInstance:SetAttribute("IsWorking", false)
	npcInstance:SetAttribute("IsMoving", false)

	-- Position & Grid Tracking
	if npcInstance.PrimaryPart then
		local pos = npcInstance.PrimaryPart.Position
		npcInstance:SetAttribute("WorldX", pos.X)
		npcInstance:SetAttribute("WorldY", pos.Y)
		npcInstance:SetAttribute("WorldZ", pos.Z)

		if _G.WorldToGrid then
			local gridX, gridZ = _G.WorldToGrid(pos)
			npcInstance:SetAttribute("GridX", gridX)
			npcInstance:SetAttribute("GridZ", gridZ)
		end
	end

	-- Equipment Slots (for future expansion)
	npcInstance:SetAttribute("EquippedTool", "None")
	npcInstance:SetAttribute("EquippedWeapon", "None")
	npcInstance:SetAttribute("EquippedArmor", "None")

	-- Performance Tracking
	npcInstance:SetAttribute("TasksCompleted", 0)
	npcInstance:SetAttribute("TotalResourcesHarvested", 0)
	npcInstance:SetAttribute("TotalDistanceTraveled", 0)
	npcInstance:SetAttribute("TimeSpentWorking", 0)

	print(string.format("[StructureManager] Added comprehensive attributes to NPC %s (%s)", 
		npcStats.InstanceId, npcStats.UnitType))
end

function StructureManager:GetOrCreateNPCFolder(worldFolder, team)
	-- Get or create the appropriate NPC folder based on team
	if not worldFolder then
		return nil
	end

	local folderName = team == "Player" and "PlayerNPCs" or "EnemyNPCs"
	local folder = worldFolder:FindFirstChild(folderName)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = worldFolder
		print(string.format("[StructureManager] Created %s folder", folderName))
	end

	return folder
end

function StructureManager:GetOrCreateStructureFolder(worldFolder, team)
	-- Get or create the appropriate structure folder based on team
	if not worldFolder then
		return nil
	end

	local folderName = team == "Player" and "PlayerStructures" or "EnemyStructures"
	local folder = worldFolder:FindFirstChild(folderName)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = worldFolder
		print(string.format("[StructureManager] Created %s folder", folderName))
	end

	return folder
end

function StructureManager:GetOrCreateResourceFolder(worldFolder)
	-- Get or create the resource folder
	if not worldFolder then
		return nil
	end

	local folder = worldFolder:FindFirstChild("Resources")

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Resources"
		folder.Parent = worldFolder
		print("[StructureManager] Created Resources folder")
	end

	return folder
end

function StructureManager:FindNearbySpawnCell(instanceId)
	-- Find an available cell near the structure for spawning using WorldState
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return nil
	end

	local structurePos = structureData.instance.PrimaryPart.Position

	-- Get grid position of structure using global helper function
	local structureGridX, structureGridZ = 0, 0
	if _G.WorldToGrid then
		structureGridX, structureGridZ = _G.WorldToGrid(structurePos)
	else
		warn("[StructureManager] WorldToGrid function not available")
		return nil
	end

	-- Get WorldState for cell checking
	local worldState = _G.WorldState
	if not worldState then
		warn("[StructureManager] WorldState not available for cell checking")
		return nil
	end

	print(string.format("[StructureManager] Searching for spawn cell near structure at (%d, %d)", structureGridX, structureGridZ))

	-- Search in expanding circles around the structure
	for radius = 1, 10 do -- Increased search radius
		for dx = -radius, radius do
			for dz = -radius, radius do
				-- Only check cells at the current radius (not inside)
				if math.abs(dx) == radius or math.abs(dz) == radius then
					local checkX = structureGridX + dx
					local checkZ = structureGridZ + dz

					-- Check if cell is available using WorldState
					if worldState:IsCellAvailableForSpawn(checkX, checkZ) then
						-- Get the actual cell part
						local cell = nil
						if _G.GetCell then
							cell = _G.GetCell(checkX, checkZ)
						end

						if cell then
							print(string.format("[StructureManager] Found spawn cell at (%d, %d)", checkX, checkZ))
							-- Mark cell as temporarily occupied in WorldState
							worldState:SetCellOccupied(checkX, checkZ, true)
							return cell
						end
					end
				end
			end
		end
	end

	warn("[StructureManager] No available spawn cells found within 10 cell radius")
	return nil
end

function StructureManager:IsCellAvailableForSpawn(gridX, gridZ)
	-- Use WorldState for cell availability checking instead of local tracking
	local worldState = _G.WorldState
	if worldState then
		return worldState:IsCellAvailableForSpawn(gridX, gridZ)
	else
		warn("[StructureManager] WorldState not available, using fallback method")
		return self:FallbackCellCheck(gridX, gridZ)
	end
end

function StructureManager:FallbackCellCheck(gridX, gridZ)
	-- Fallback method if WorldState is not available
	-- Check against our own blocked cells
	for instanceId, structureData in pairs(self.placedStructures) do
		if structureData.blockedCells then
			for _, blockedCell in pairs(structureData.blockedCells) do
				if blockedCell.x == gridX and blockedCell.z == gridZ then
					return false -- Cell is blocked by a structure
				end
			end
		end
	end

	-- Check if cell is in valid spawn area (grass area, not beach)
	local totalGridSize = 30 + (2 * 2) -- GRID_SIZE + (BEACH_THICKNESS * 2) 
	local grassStartX = 2 + 1  -- BEACH_THICKNESS + 1
	local grassEndX = 2 + 30   -- BEACH_THICKNESS + GRID_SIZE
	local grassStartZ = 2 + 1
	local grassEndZ = 2 + 30

	if gridX < grassStartX or gridX > grassEndX or gridZ < grassStartZ or gridZ > grassEndZ then
		return false -- Outside valid spawn area
	end

	return true -- Cell is available
end

function StructureManager:FindWorldFolder()
	-- Find the world folder for placing NPCs
	-- Look for folders ending with "_World"
	for _, child in pairs(workspace:GetChildren()) do
		if child:IsA("Folder") and string.find(child.Name, "_World$") then
			return child
		end
	end

	-- Fallback: create a default world folder
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "Default_World"
	worldFolder.Parent = workspace
	return worldFolder
end

function StructureManager:HandleAutoQueue(instanceId)
	-- Handle automatic queuing for AI structures
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.AutoSpawn then
		return
	end

	local stats = structureData.stats
	local queue = self.spawnQueues[instanceId]

	if not queue then
		return
	end

	-- Check if enough time has passed since last auto-queue
	local currentTime = tick()
	if currentTime - queue.lastAutoQueueTime < stats.AutoQueueInterval then
		return
	end

	-- Check if queue has space
	if #queue.queue >= stats.MaxQueue then
		return
	end

	-- Choose what to spawn (prefer PreferredSpawn if set)
	local npcType = stats.PreferredSpawn
	if not npcType or not self:CanSpawnNPCType(instanceId, npcType) then
		-- Choose random from available types
		local spawnTypes = stats.SpawnTypes
		if spawnTypes and #spawnTypes > 0 then
			npcType = spawnTypes[math.random(1, #spawnTypes)]
		end
	end

	if npcType then
		local priority = 1 -- Default priority for auto-queue
		local queueId = self:AddToQueue(instanceId, npcType, priority)

		if queueId then
			queue.lastAutoQueueTime = currentTime
			print(string.format("[StructureManager] Auto-queued %s for %s", npcType, instanceId))
		end
	end
end

function StructureManager:FormatCost(cost)
	-- Helper function to format cost for display
	if not cost or type(cost) ~= "table" then
		return "Free"
	end

	local costStrings = {}
	for resource, amount in pairs(cost) do
		table.insert(costStrings, amount .. " " .. resource)
	end

	return table.concat(costStrings, ", ")
end

-- ========================================
-- SPECIAL STRUCTURE FUNCTIONS
-- ========================================

function StructureManager:AddFreeStartingVillager(instanceId)
	-- Add a free Villager to Town Hall queue when first placed
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.Spawner then
		return false
	end

	local stats = structureData.stats

	-- Verify this structure can spawn villagers
	if not self:CanSpawnNPCType(instanceId, "VILLAGER") then
		warn("[StructureManager] Town Hall cannot spawn VILLAGER units")
		return false
	end

	-- Initialize queue if not already done
	if not self.spawnQueues[instanceId] then
		self:InitializeQueue(instanceId)
	end

	-- Create a special free villager queue entry
	self.globalQueueId = self.globalQueueId + 1
	local npcStats = AllStats:GetNPCStats("VILLAGER", stats.Team)
	if not npcStats then
		warn("[StructureManager] Could not get Villager stats")
		return false
	end

	-- Calculate spawn time with multiplier
	local baseSpawnTime = npcStats.SpawnTime or 4 -- Villagers spawn faster than builders
	local actualSpawnTime = baseSpawnTime * stats.SpawnTimeMultiplier

	local freeVillagerEntry = {
		queueId = self.globalQueueId,
		npcType = "VILLAGER",
		spawnTimeRemaining = actualSpawnTime,
		totalSpawnTime = actualSpawnTime,
		priority = 5, -- High priority for starting unit
		addedTime = tick(),
		owner = stats.Owner,
		team = stats.Team,
		cost = {}, -- No cost for starting villager
		paid = true, -- Mark as already paid (free)
		isStartingUnit = true, -- Special flag
	}

	-- Add directly to front of queue due to high priority
	local queue = self.spawnQueues[instanceId]
	table.insert(queue.queue, 1, freeVillagerEntry)

	-- Update structure attribute to show next spawn time
	if structureData.instance then
		structureData.instance:SetAttribute("NextSpawnTime", actualSpawnTime)
		structureData.instance:SetAttribute("QueueLength", #queue.queue)
	end

	print(string.format("[StructureManager] Added free starting Villager to Town Hall %s (spawn time: %.1fs)", 
		instanceId, actualSpawnTime))

	return true
end

-- ========================================
-- STRUCTURE BEHAVIOR & LOGIC (Updated)
-- ========================================

function StructureManager:InitializeStructureBehavior(instanceId)
	-- Initialize special behaviors for structures (spawning, resource generation, etc.)
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return
	end

	local stats = structureData.stats

	-- Initialize spawner behavior
	if stats.Spawner and stats.SpawnTypes then
		self:InitializeSpawner(instanceId)
	end

	-- Initialize resource generation
	if stats.ResourceGeneration then
		self:InitializeResourceGeneration(instanceId)
	end

	-- Initialize attack behavior
	if stats.DoesAtk then
		self:InitializeDefensiveBehavior(instanceId)
	end
end

function StructureManager:InitializeSpawner(instanceId)
	-- Initialize spawning behavior for structures that can spawn units
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return
	end

	local stats = structureData.stats

	print(string.format("[StructureManager] Initializing spawner with queue system for %s (max queue: %d)", 
		instanceId, stats.MaxQueue))

	-- Initialize the queue
	self:InitializeQueue(instanceId)

	-- Create main spawning coroutine
	spawn(function()
		local lastFrameTime = tick()

		while structureData.instance and structureData.instance.Parent do
			local currentTime = tick()
			local deltaTime = currentTime - lastFrameTime
			lastFrameTime = currentTime

			-- Check if structure still exists and has health
			local currentHealth = structureData.instance:GetAttribute("Health") or 0
			if currentHealth <= 0 then
				break
			end

			-- Process the spawn queue
			self:ProcessQueue(instanceId, deltaTime)

			-- Handle auto-queuing for AI structures
			self:HandleAutoQueue(instanceId)

			wait(0.1) -- Update 10 times per second
		end

		-- Clean up queue when structure is destroyed
		self.spawnQueues[instanceId] = nil
		print(string.format("[StructureManager] Cleaned up spawn queue for destroyed structure %s", instanceId))
	end)
end

function StructureManager:InitializeResourceGeneration(instanceId)
	-- Initialize resource generation behavior
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return
	end

	local stats = structureData.stats

	print(string.format("[StructureManager] Initializing resource generation for %s", instanceId))

	-- Create resource generation coroutine
	spawn(function()
		while structureData.instance and structureData.instance.Parent do
			wait(1) -- Generate resources every second

			-- Check if structure still exists and has health
			local currentHealth = structureData.instance:GetAttribute("Health") or 0
			if currentHealth <= 0 then
				break
			end

			-- Generate resources for owner
			self:GenerateResources(instanceId)
		end
	end)
end

function StructureManager:InitializeDefensiveBehavior(instanceId)
	-- Initialize defensive/attacking behavior for structures
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return
	end

	local stats = structureData.stats

	print(string.format("[StructureManager] Initializing defensive behavior for %s (range: %d, attack: %d)", 
		instanceId, stats.Range or 0, stats.Attack or 0))

	-- Create defensive behavior coroutine
	spawn(function()
		local attackCooldown = 1 / (stats.AtkSpeed or 1) -- Convert attacks per second to cooldown
		local lastAttackTime = 0

		while structureData.instance and structureData.instance.Parent do
			wait(0.5) -- Check for enemies every 0.5 seconds

			-- Check if structure still exists and has health
			local currentHealth = structureData.instance:GetAttribute("Health") or 0
			if currentHealth <= 0 then
				break
			end

			-- Check if enough time has passed since last attack
			if tick() - lastAttackTime >= attackCooldown then
				-- Look for enemies in range and attack
				if self:FindAndAttackEnemies(instanceId) then
					lastAttackTime = tick()
				end
			end
		end
	end)
end

-- ========================================
-- STRUCTURE ACTIONS
-- ========================================

function StructureManager:AttemptSpawn(instanceId)
	-- Attempt to spawn a unit from a spawner structure
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.Spawner then
		return false
	end

	local stats = structureData.stats
	local spawnTypes = stats.SpawnTypes

	if not spawnTypes or #spawnTypes == 0 then
		return false
	end

	-- Choose random spawn type
	local spawnType = spawnTypes[math.random(1, #spawnTypes)]

	print(string.format("[StructureManager] %s attempting to spawn %s", instanceId, spawnType))

	-- Here you would integrate with your unit spawning system
	-- For now, just log the attempt

	return true
end

function StructureManager:GenerateResources(instanceId)
	-- Generate resources for the structure owner
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.ResourceGeneration then
		return
	end

	local stats = structureData.stats
	local owner = stats.Owner

	if not owner then
		return
	end

	-- Here you would integrate with your resource system
	-- For now, just log the generation
	for resourceType, rate in pairs(stats.ResourceGeneration) do
		print(string.format("[StructureManager] %s generated %d %s for %s", 
			instanceId, rate, resourceType, owner))
	end
end

function StructureManager:FindAndAttackEnemies(instanceId)
	-- Find enemies in range and attack them
	local structureData = self.placedStructures[instanceId]
	if not structureData or not structureData.stats.DoesAtk then
		return false
	end

	local stats = structureData.stats
	local range = stats.Range or 0
	local attack = stats.Attack or 0

	-- Here you would integrate with your combat system
	-- For now, just log the attack attempt
	print(string.format("[StructureManager] %s scanning for enemies (range: %d, attack: %d)", 
		instanceId, range, attack))

	return false -- No enemies found/attacked
end

-- ========================================
-- STRUCTURE QUERIES & MANAGEMENT
-- ========================================

function StructureManager:GetStructuresByOwner(owner)
	-- Get all structures owned by a specific player
	return self.structuresByOwner[owner] or {}
end

function StructureManager:GetStructuresByTeam(team)
	-- Get all structures for a team
	return self.structuresByTeam[team] or {}
end

function StructureManager:GetStructuresByType(structureType)
	-- Get all structures of a specific type
	return self.structuresByType[structureType] or {}
end

function StructureManager:GetStructureData(instanceId)
	-- Get complete data for a structure
	return self.placedStructures[instanceId]
end

function StructureManager:RemoveStructure(instanceId, placementModule, cellStates)
	-- Remove a structure (when destroyed, sold, etc.)
	local structureData = self.placedStructures[instanceId]
	if not structureData then
		return false
	end

	-- Unblock cells if placementModule provided
	if placementModule and cellStates and structureData.blockedCells then
		placementModule:UnblockCells(cellStates, structureData.blockedCells)
	end

	-- Remove from tracking arrays
	local stats = structureData.stats

	-- Remove from team tracking
	if self.structuresByTeam[stats.Team] then
		for i, id in ipairs(self.structuresByTeam[stats.Team]) do
			if id == instanceId then
				table.remove(self.structuresByTeam[stats.Team], i)
				break
			end
		end
	end

	-- Remove from owner tracking
	if stats.Owner and self.structuresByOwner[stats.Owner] then
		for i, id in ipairs(self.structuresByOwner[stats.Owner]) do
			if id == instanceId then
				table.remove(self.structuresByOwner[stats.Owner], i)
				break
			end
		end
	end

	-- Remove from type tracking
	local structureType = stats.StructureType or "Unknown"
	if self.structuresByType[structureType] then
		for i, id in ipairs(self.structuresByType[structureType]) do
			if id == instanceId then
				table.remove(self.structuresByType[structureType], i)
				break
			end
		end
	end

	-- Destroy the instance
	if structureData.instance and structureData.instance.Parent then
		structureData.instance:Destroy()
	end

	-- Remove from main tracking
	self.placedStructures[instanceId] = nil

	print(string.format("[StructureManager] Removed structure %s", instanceId))
	return true
end

function StructureManager:GetStructureCount(team, structureType)
	-- Get count of structures for a team/type
	local count = 0

	if structureType then
		-- Count specific type
		for _, instanceId in ipairs(self:GetStructuresByType(structureType)) do
			local data = self.placedStructures[instanceId]
			if data and data.stats.Team == team then
				count = count + 1
			end
		end
	else
		-- Count all for team
		count = #(self.structuresByTeam[team] or {})
	end

	return count
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

function StructureManager:GetUnitModel(npcType, team)
	-- Get the 3D model for a specific unit type and team
	local folder = team == "Player" and playerUnitsFolder or worldAIUnitsFolder

	local model = folder:FindFirstChild(npcType)
	if not model then
		warn("[StructureManager] Unit model not found:", npcType, "for team:", team)
		return nil
	end

	if not model:IsA("Model") then
		warn("[StructureManager] Found object is not a model:", npcType)
		return nil
	end

	return model
end

return StructureManager