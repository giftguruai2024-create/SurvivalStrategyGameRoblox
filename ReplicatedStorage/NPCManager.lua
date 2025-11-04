-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- NPCManager Module
-- Handles all NPC AI behaviors, task management, pathfinding, and state control
-- Place this in ReplicatedStorage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local AllStats = require(ReplicatedStorage:WaitForChild("AllStats"))
local PathfindingModule = require(ReplicatedStorage:WaitForChild("PathfindingModule"))

local NPCManager = {}
NPCManager.__index = NPCManager

-- ========================================
-- CONFIGURATION
-- ========================================
local DEFAULT_CONFIG = {
	DEBUG_AI = true,
	UPDATE_FREQUENCY = 10, -- AI updates per second
	PATHFINDING_ENABLED = true,
	MAX_PATHFINDING_DISTANCE = 500,
	STUCK_THRESHOLD = 3, -- Seconds before considering NPC stuck
	TASK_TIMEOUT = 60, -- Seconds before abandoning a task
	COMBAT_RANGE_MULTIPLIER = 1.2, -- How much farther to detect enemies than attack range
}

-- ========================================
-- NPC AI STATES (Simplified System)
-- ========================================
local NPCStates = {
	WANDERING = "Wandering", -- Default patrol state, open to tasks
	MOVING = "Moving",       -- Moving to task location
	WORKING = "Working",     -- Harvesting/building
	RETURNING = "Returning", -- Bringing resources back
	IDLE = "Idle",          -- Brief pause before returning to wandering
	FIGHTING = "Fighting",   -- Combat with enemies
	FLEEING = "Fleeing",    -- Running to town hall when low health
	DEAD = "Dead",          -- Unit died
	STUCK = "Stuck",        -- Haven't moved in 10 seconds
}

local TaskTypes = {
	-- Core tasks
	HARVEST_RESOURCE = "HarvestResource",
	BUILD_STRUCTURE = "BuildStructure", 
	ATTACK_ENEMY = "AttackEnemy",
	FLEE_TO_BASE = "FleeToBase",
	DEPOSIT_RESOURCES = "DepositResources",
	WANDER_PATROL = "WanderPatrol",
}

-- ========================================
-- NPC MANAGER CLASS
-- ========================================

function NPCManager.new(config)
	local self = setmetatable({}, NPCManager)

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

	-- NPC tracking
	self.managedNPCs = {} -- {instanceId = npcData}
	self.npcsByState = {} -- {state = {instanceIds}}
	self.npcsByType = {} -- {npcType = {instanceIds}}
	self.npcsByOwner = {} -- {owner = {instanceIds}}

	-- Task management
	self.activeTasks = {} -- {instanceId = taskData}
	self.taskQueue = {} -- Global task queue for optimization

	-- World knowledge
	self.knownResources = {} -- {resourceId = {position, type, available}}
	self.knownBlueprints = {} -- {blueprintId = {position, type, status}}
	self.knownEnemies = {} -- {enemyId = {position, lastSeen, threat}}
	self.knownStructures = {} -- {structureId = {position, type, team}}

	-- AI update management
	self.lastUpdateTime = tick()
	self.updateConnection = nil

	-- Initialize state tracking
	for _, state in pairs(NPCStates) do
		self.npcsByState[state] = {}
	end

	print("[NPCManager] Initialized with", self.config.UPDATE_FREQUENCY, "updates per second")
	return self
end

-- ========================================
-- NPC REGISTRATION & MANAGEMENT
-- ========================================

function NPCManager:RegisterNPC(npcInstance, stats, owner)
	-- Register an NPC for AI management
	if not npcInstance or not stats then
		warn("[NPCManager] Cannot register NPC: Invalid instance or stats")
		return false
	end

	local instanceId = stats.InstanceId
	if not instanceId then
		warn("[NPCManager] Cannot register NPC: No InstanceId")
		return false
	end

	-- Create NPC data structure
	local npcData = {
		instance = npcInstance,
		stats = stats,
		owner = owner or stats.Owner,

		-- AI State
		currentState = NPCStates.WANDERING, -- Start with wandering patrol
		lastStateChange = tick(),
		stuckStartTime = 0, -- Track when NPC started being stuck

		-- Task management
		currentTask = nil,
		taskHistory = {},
		taskStartTime = 0,

		-- Movement and positioning
		targetPosition = nil,
		lastPosition = npcInstance.PrimaryPart and npcInstance.PrimaryPart.Position or Vector3.new(0, 0, 0),
		stuckTime = 0,
		currentPath = nil, -- Current pathfinding path
		pathIndex = 1, -- Current position in path
		lastMovementTime = tick(), -- Track last time NPC moved

		-- Pathfinding data
		targetGridX = nil,
		targetGridZ = nil,
		lastPathfindTime = 0,
		pathfindCooldown = 2, -- Seconds between pathfinding attempts

		-- Patrol behavior
		patrolCenter = npcInstance.PrimaryPart and npcInstance.PrimaryPart.Position or Vector3.new(0, 0, 0),
		patrolRadius = 15, -- Wander within 15 studs of spawn
		nextPatrolTarget = nil,

		-- Combat
		currentTarget = nil,
		lastAttackTime = 0,
		threatLevel = 0,

		-- Work/Resource management
		carriedResources = {},
		totalCarriedWeight = 0,
		workTarget = nil,
		workProgress = 0,

		-- Equipment (future use)
		equippedItems = {},

		-- Behavior settings
		behaviorMode = self:GetDefaultBehavior(stats.UnitType),
		customInstructions = {},

		-- Performance tracking
		lastAIUpdate = 0,
		aiUpdateInterval = 1 / self.config.UPDATE_FREQUENCY,
	}

	-- Copy default equipment
	if stats.DefaultEquipment then
		for slot, equipmentId in pairs(stats.DefaultEquipment) do
			npcData.equippedItems[slot] = equipmentId
		end
	end

	-- Register in tracking systems
	self.managedNPCs[instanceId] = npcData
	self:AddToStateTracking(instanceId, NPCStates.IDLE)
	self:AddToTypeTracking(instanceId, stats.UnitType)
	if owner then
		self:AddToOwnerTracking(instanceId, owner)
	end

	-- Set initial task
	self:AssignInitialTask(instanceId)

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] Registered %s (ID: %s) for %s", 
			stats.UnitType, instanceId, owner or "System"))
	end

	-- Start AI updates if this is the first NPC
	if not self.updateConnection then
		self:StartAIUpdates()
	end

	return true
end

function NPCManager:UnregisterNPC(instanceId, reason)
	-- Remove an NPC from AI management
	local npcData = self.managedNPCs[instanceId]
	if not npcData then
		return false
	end

	reason = reason or "Manual"

	-- Unregister NPC from WorldState cell tracking
	if npcData.instance and npcData.instance.PrimaryPart then
		local npcGridX, npcGridZ = 0, 0
		if _G.WorldToGrid then
			npcGridX, npcGridZ = _G.WorldToGrid(npcData.instance.PrimaryPart.Position)

			local worldState = _G.WorldState
			if worldState then
				worldState:UnregisterNPCFromCell(npcGridX, npcGridZ, instanceId)
			end
		end
	end

	-- Remove from tracking systems
	self:RemoveFromStateTracking(instanceId, npcData.currentState)
	self:RemoveFromTypeTracking(instanceId, npcData.stats.UnitType)
	if npcData.owner then
		self:RemoveFromOwnerTracking(instanceId, npcData.owner)
	end

	-- Cancel current task
	self:CancelTask(instanceId)

	-- Remove from main tracking
	self.managedNPCs[instanceId] = nil

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] Unregistered NPC %s (reason: %s)", instanceId, reason))
	end

	-- Stop AI updates if no NPCs remain
	if next(self.managedNPCs) == nil and self.updateConnection then
		self:StopAIUpdates()
	end

	return true
end

-- ========================================
-- AI STATE MANAGEMENT
-- ========================================

function NPCManager:ChangeNPCState(instanceId, newState)
	-- Change an NPC's AI state
	local npcData = self.managedNPCs[instanceId]
	if not npcData then
		return false
	end

	local oldState = npcData.currentState
	if oldState == newState then
		return true -- Already in desired state
	end

	-- Remove from old state tracking
	self:RemoveFromStateTracking(instanceId, oldState)

	-- Update NPC data
	npcData.currentState = newState
	npcData.lastStateChange = tick()

	-- Add to new state tracking
	self:AddToStateTracking(instanceId, newState)

	-- Update NPC model attributes
	self:UpdateNPCStateAttributes(instanceId, newState, oldState)

	-- Handle state-specific logic
	self:OnStateEnter(instanceId, newState, oldState)

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] %s changed state: %s -> %s", instanceId, oldState, newState))
	end

	return true
end

function NPCManager:UpdateNPCStateAttributes(instanceId, newState, oldState)
	-- Update NPC model attributes to reflect current state
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance then
		return
	end

	local npcInstance = npcData.instance

	-- Update state attributes
	npcInstance:SetAttribute("CurrentState", newState)
	npcInstance:SetAttribute("LastStateChange", tick())

	-- Update boolean state flags
	npcInstance:SetAttribute("IsIdle", newState == NPCStates.IDLE)
	npcInstance:SetAttribute("IsWorking", newState == NPCStates.WORKING)
	npcInstance:SetAttribute("IsMoving", newState == NPCStates.MOVING)
	npcInstance:SetAttribute("IsWandering", newState == NPCStates.WANDERING)
	npcInstance:SetAttribute("IsReturning", newState == NPCStates.RETURNING)
	npcInstance:SetAttribute("IsFighting", newState == NPCStates.FIGHTING)
	npcInstance:SetAttribute("IsFleeing", newState == NPCStates.FLEEING)
	npcInstance:SetAttribute("IsStuck", newState == NPCStates.STUCK)
	npcInstance:SetAttribute("IsDead", newState == NPCStates.DEAD)
end

function NPCManager:OnStateEnter(instanceId, newState, oldState)
	-- Handle state transition logic (simplified)
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	if newState == NPCStates.WANDERING then
		-- Start wandering patrol around spawn area
		self:StartWanderingPatrol(instanceId)

	elseif newState == NPCStates.WORKING then
		-- Initialize work progress
		npcData.workProgress = 0

	elseif newState == NPCStates.RETURNING then
		-- Find town hall to return to
		self:AssignTask(instanceId, TaskTypes.DEPOSIT_RESOURCES)

	elseif newState == NPCStates.IDLE then
		-- Start idle timer to return to wandering
		npcData.idleStartTime = tick()

	elseif newState == NPCStates.FIGHTING then
		-- Initialize combat
		npcData.lastAttackTime = 0

	elseif newState == NPCStates.FLEEING then
		-- Cancel current task and flee to town hall
		self:CancelTask(instanceId)
		self:AssignTask(instanceId, TaskTypes.FLEE_TO_BASE)

	elseif newState == NPCStates.DEAD then
		-- Handle death
		self:OnNPCDeath(instanceId)

	elseif newState == NPCStates.STUCK then
		-- Handle stuck NPC
		print(string.format("[NPCManager] %s is STUCK - hasn't moved in 10 seconds", instanceId))
		self:HandleStuckNPC(instanceId)
	end
end

-- ========================================
-- TASK MANAGEMENT SYSTEM
-- ========================================

function NPCManager:AssignTask(instanceId, taskType, taskData)
	-- Assign a specific task to an NPC
	local npcData = self.managedNPCs[instanceId]
	if not npcData then
		return false
	end

	-- Cancel current task
	self:CancelTask(instanceId)

	-- Create new task
	local task = {
		type = taskType,
		data = taskData or {},
		startTime = tick(),
		timeout = taskData and taskData.timeout or self.config.TASK_TIMEOUT,
		priority = taskData and taskData.priority or 1,
		attempts = 0,
		maxAttempts = taskData and taskData.maxAttempts or 3,
	}

	-- Assign task
	npcData.currentTask = task
	npcData.taskStartTime = tick()
	self.activeTasks[instanceId] = task

	-- Update NPC task attributes
	self:UpdateNPCTaskAttributes(instanceId, taskType, taskData)

	-- Initialize task
	self:InitializeTask(instanceId, task)

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] Assigned task %s to %s", taskType, instanceId))
	end

	return true
end

function NPCManager:UpdateNPCTaskAttributes(instanceId, taskType, taskData)
	-- Update NPC model attributes when task changes
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance then
		return
	end

	local npcInstance = npcData.instance

	-- Update task attributes
	npcInstance:SetAttribute("CurrentTask", taskType or "None")
	npcInstance:SetAttribute("TaskStartTime", tick())

	-- Add task-specific attributes
	if taskType == TaskTypes.HARVEST_RESOURCE and taskData then
		npcInstance:SetAttribute("TargetResourceType", taskData.resourceType or "Unknown")
		npcInstance:SetAttribute("TargetResourceId", taskData.resourceId or "None")
		if taskData.resourcePosition then
			npcInstance:SetAttribute("TaskTargetX", taskData.resourcePosition.X)
			npcInstance:SetAttribute("TaskTargetY", taskData.resourcePosition.Y)
			npcInstance:SetAttribute("TaskTargetZ", taskData.resourcePosition.Z)
		end
	elseif taskType == TaskTypes.BUILD_STRUCTURE and taskData then
		npcInstance:SetAttribute("TargetStructureType", taskData.structureType or "Unknown")
		npcInstance:SetAttribute("TargetBlueprintId", taskData.blueprintId or "None")
	else
		-- Clear task-specific attributes
		npcInstance:SetAttribute("TargetResourceType", "None")
		npcInstance:SetAttribute("TargetResourceId", "None")
		npcInstance:SetAttribute("TargetStructureType", "None")
		npcInstance:SetAttribute("TargetBlueprintId", "None")
		npcInstance:SetAttribute("TaskTargetX", 0)
		npcInstance:SetAttribute("TaskTargetY", 0)
		npcInstance:SetAttribute("TaskTargetZ", 0)
	end
end

function NPCManager:UpdateNPCInventoryAttributes(instanceId, resourceType, amount)
	-- Update NPC inventory attributes when resources are gained/lost
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance then
		return
	end

	local npcInstance = npcData.instance

	-- Update specific resource amounts
	local attributeName = "Carried" .. resourceType
	local currentAmount = npcInstance:GetAttribute(attributeName) or 0
	local newAmount = math.max(0, currentAmount + amount)

	npcInstance:SetAttribute(attributeName, newAmount)

	-- Update total carried weight
	local totalWeight = 0
	totalWeight = totalWeight + (npcInstance:GetAttribute("CarriedWood") or 0)
	totalWeight = totalWeight + (npcInstance:GetAttribute("CarriedStone") or 0)
	totalWeight = totalWeight + (npcInstance:GetAttribute("CarriedGold") or 0)
	totalWeight = totalWeight + (npcInstance:GetAttribute("CarriedFood") or 0)

	npcInstance:SetAttribute("CurrentCarriedWeight", totalWeight)

	-- Update capacity status
	local maxCapacity = npcInstance:GetAttribute("CarryCapacity") or 0
	local capacityPercent = maxCapacity > 0 and (totalWeight / maxCapacity) * 100 or 0
	npcInstance:SetAttribute("CapacityPercent", capacityPercent)
	npcInstance:SetAttribute("IsInventoryFull", totalWeight >= maxCapacity)

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] %s inventory: %s %+d = %d (Total: %d/%d)", 
			instanceId, resourceType, amount, newAmount, totalWeight, maxCapacity))
	end
end

function NPCManager:UpdateNPCPerformanceAttributes(instanceId, action, value)
	-- Update NPC performance tracking attributes
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance then
		return
	end

	local npcInstance = npcData.instance

	if action == "TaskCompleted" then
		local completed = npcInstance:GetAttribute("TasksCompleted") or 0
		npcInstance:SetAttribute("TasksCompleted", completed + 1)

	elseif action == "ResourceHarvested" then
		local harvested = npcInstance:GetAttribute("TotalResourcesHarvested") or 0
		npcInstance:SetAttribute("TotalResourcesHarvested", harvested + (value or 1))

	elseif action == "DistanceTraveled" then
		local distance = npcInstance:GetAttribute("TotalDistanceTraveled") or 0
		npcInstance:SetAttribute("TotalDistanceTraveled", distance + (value or 0))

	elseif action == "WorkTime" then
		local workTime = npcInstance:GetAttribute("TimeSpentWorking") or 0
		npcInstance:SetAttribute("TimeSpentWorking", workTime + (value or 0))
	end
end

function NPCManager:InitializeTask(instanceId, task)
	-- Initialize a task based on its type
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local taskType = task.type
	local taskData = task.data

	if taskType == TaskTypes.BUILD_STRUCTURE then
		self:InitializeBuildTask(instanceId, task)

	elseif taskType == TaskTypes.HARVEST_RESOURCE then
		self:InitializeHarvestTask(instanceId, task)

	elseif taskType == TaskTypes.MOVE_TO_POSITION then
		self:InitializeMoveTask(instanceId, task)

	elseif taskType == TaskTypes.ATTACK_ENEMY then
		self:InitializeCombatTask(instanceId, task)

	elseif taskType == TaskTypes.PATROL_AREA then
		self:InitializePatrolTask(instanceId, task)

	elseif taskType == TaskTypes.DEPOSIT_RESOURCES then
		self:InitializeDepositTask(instanceId, task)

	elseif taskType == TaskTypes.RETURN_TO_TOWNHALL then
		self:InitializeReturnTask(instanceId, task)

	elseif taskType == TaskTypes.WANDER_PATROL then
		self:InitializeWanderPatrolTask(instanceId, task)

	else
		warn("[NPCManager] Unknown task type:", taskType)
		self:CancelTask(instanceId)
	end
end

function NPCManager:CancelTask(instanceId)
	-- Cancel an NPC's current task
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.currentTask then
		return false
	end

	-- Add to task history
	local task = npcData.currentTask
	table.insert(npcData.taskHistory, {
		type = task.type,
		startTime = task.startTime,
		endTime = tick(),
		result = "Cancelled",
		duration = tick() - task.startTime
	})

	-- Clear task data
	npcData.currentTask = nil
	npcData.taskStartTime = 0
	npcData.workTarget = nil
	npcData.targetPosition = nil
	npcData.currentPath = nil
	self.activeTasks[instanceId] = nil

	return true
end

function NPCManager:CompleteTask(instanceId, result)
	-- Mark a task as completed
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.currentTask then
		return false
	end

	result = result or "Success"

	-- Add to task history
	local task = npcData.currentTask
	table.insert(npcData.taskHistory, {
		type = task.type,
		startTime = task.startTime,
		endTime = tick(),
		result = result,
		duration = tick() - task.startTime
	})

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] %s completed task %s (%s)", instanceId, task.type, result))
	end

	-- Clear current task
	self:CancelTask(instanceId)

	-- Change to idle state to assign next task
	self:ChangeNPCState(instanceId, NPCStates.IDLE)

	return true
end

-- ========================================
-- BEHAVIOR ASSIGNMENT
-- ========================================

function NPCManager:GetDefaultBehavior(unitType)
	-- Get default behavior for a unit type
	if unitType == "Worker" then
		-- Check if it's a builder or villager based on capabilities
		return "BUILDER_AI" -- Will be determined by capabilities in AssignInitialTask
	else
		return "AGGRESSIVE" -- For combat units
	end
end

function NPCManager:AssignInitialTask(instanceId)
	-- All NPCs start with wandering patrol
	self:ChangeNPCState(instanceId, NPCStates.WANDERING)
end

function NPCManager:AssignNextTask(instanceId)
	-- Simplified task assignment - check for urgent tasks, otherwise return to wandering
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local stats = npcData.stats

	-- Check for urgent tasks first
	if self:ShouldFlee(instanceId) then
		self:ChangeNPCState(instanceId, NPCStates.FLEEING)
		return
	end

	if self:ShouldFight(instanceId) then
		self:ChangeNPCState(instanceId, NPCStates.FIGHTING)
		return
	end

	-- Check for nearby tasks if in wandering state
	if npcData.currentState == NPCStates.WANDERING then
		local nearbyTask = self:FindNearbyTask(instanceId)
		if nearbyTask then
			self:AssignTaskFromResource(instanceId, nearbyTask)
			return
		end
	end

	-- Default: continue wandering
	self:ChangeNPCState(instanceId, NPCStates.WANDERING)
end

function NPCManager:StartWanderingPatrol(instanceId)
	-- Start wandering patrol around town hall area
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Find town hall position as patrol center
	local townHallPos = self:FindTownHallPosition(instanceId)
	if townHallPos then
		npcData.patrolCenter = townHallPos
	end

	-- Assign wandering task
	self:AssignTask(instanceId, TaskTypes.WANDER_PATROL, {
		center = npcData.patrolCenter,
		radius = npcData.patrolRadius
	})
end

function NPCManager:FindNearbyTask(instanceId)
	-- Find nearby tasks based on NPC type
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return nil end

	local stats = npcData.stats

	-- Builders look for blueprints
	if stats.CanBuild then
		return self:FindNearbyBlueprint(instanceId)
	end

	-- Villagers look for selected resources
	if stats.CanHarvest then
		return self:FindNearbySelectedResource(instanceId)
	end

	return nil
end

function NPCManager:FindTownHallPosition(instanceId)
	-- Find the town hall position for this NPC's team
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return nil end

	-- NPCs are parented to PlayerNPCs/EnemyNPCs folder, so we need to go up one more level to get the actual world folder
	local npcFolder = npcData.instance.Parent
	if not npcFolder then return nil end

	local worldFolder = npcFolder.Parent
	if not worldFolder then return nil end

	-- Look for town hall
	for _, obj in pairs(worldFolder:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("StructureType") == "Main" then
			local objTeam = obj:GetAttribute("Team")
			if objTeam == npcData.stats.Team and obj.PrimaryPart then
				return obj.PrimaryPart.Position
			end
		end
	end

	return npcData.patrolCenter -- Fallback to spawn location
end

-- ========================================
-- SPECIFIC TASK ASSIGNMENTS
-- ========================================

function NPCManager:AssignBuilderTask(instanceId)
	-- Assign a task to a builder NPC
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Check current time for work hours
	local currentHour = 12 -- You would get this from your WorldState
	local workHours = AllStats.Behaviors.BUILDER_AI.WorkHours

	if currentHour < workHours[1] or currentHour >= workHours[2] then
		-- Outside work hours, return to town hall
		self:AssignTask(instanceId, TaskTypes.RETURN_TO_TOWNHALL)
		return
	end

	-- Look for nearby blueprints
	local nearestBlueprint = self:FindNearestBlueprint(instanceId)

	if nearestBlueprint then
		self:AssignTask(instanceId, TaskTypes.BUILD_STRUCTURE, {
			blueprintId = nearestBlueprint.id,
			blueprintPosition = nearestBlueprint.position,
			structureType = nearestBlueprint.type
		})
	else
		-- No blueprints found, return to town hall
		self:AssignTask(instanceId, TaskTypes.RETURN_TO_TOWNHALL)
	end
end

function NPCManager:AssignHarvesterTask(instanceId)
	-- Assign a task to a harvester NPC (villager)
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local stats = npcData.stats

	-- Check if carrying capacity is full
	if npcData.totalCarriedWeight >= stats.CarryCapacity then
		self:AssignTask(instanceId, TaskTypes.DEPOSIT_RESOURCES)
		return
	end

	-- Find nearest harvestable resource
	local nearestResource = self:FindNearestResource(instanceId)

	if nearestResource then
		self:AssignTask(instanceId, TaskTypes.HARVEST_RESOURCE, {
			resourceId = nearestResource.id,
			resourcePosition = nearestResource.position,
			resourceType = nearestResource.type
		})
	else
		-- No resources found, patrol nearby
		self:AssignTask(instanceId, TaskTypes.PATROL_AREA, {
			center = npcData.lastPosition,
			radius = 15
		})
	end
end

function NPCManager:AssignCombatTask(instanceId)
	-- Assign a combat task to an NPC
	local nearestEnemy = self:FindNearestEnemy(instanceId)

	if nearestEnemy then
		self:AssignTask(instanceId, TaskTypes.ATTACK_ENEMY, {
			enemyId = nearestEnemy.id,
			enemyPosition = nearestEnemy.position
		})
	end
end

function NPCManager:AssignFleeTask(instanceId)
	-- Assign a flee task to an NPC
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Find safe position (away from enemies)
	local safePosition = self:FindSafePosition(instanceId)

	self:AssignTask(instanceId, TaskTypes.MOVE_TO_POSITION, {
		position = safePosition,
		priority = 10, -- High priority
		urgency = "flee"
	})

	self:ChangeNPCState(instanceId, NPCStates.FLEEING)
end

function NPCManager:AssignPatrolTask(instanceId)
	-- Assign a patrol task to an NPC
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	self:AssignTask(instanceId, TaskTypes.PATROL_AREA, {
		center = npcData.lastPosition,
		radius = 25,
		patrolPoints = self:GeneratePatrolPoints(npcData.lastPosition, 25)
	})
end

-- ========================================
-- TASK INITIALIZATION FUNCTIONS
-- ========================================

function NPCManager:InitializeBuildTask(instanceId, task)
	-- Initialize a building task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local blueprintPosition = task.data.blueprintPosition

	-- Move to blueprint if not already there
	local distance = (npcData.lastPosition - blueprintPosition).Magnitude
	if distance > npcData.stats.BuildRange then
		npcData.targetPosition = blueprintPosition
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		self:ChangeNPCState(instanceId, NPCStates.WORKING)
	end
end

function NPCManager:InitializeHarvestTask(instanceId, task)
	-- Initialize a harvesting task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local resourcePosition = task.data.resourcePosition

	-- Move to resource if not already there
	local distance = (npcData.lastPosition - resourcePosition).Magnitude
	if distance > npcData.stats.HarvestRange then
		npcData.targetPosition = resourcePosition
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		self:ChangeNPCState(instanceId, NPCStates.WORKING)
	end
end

function NPCManager:InitializeMoveTask(instanceId, task)
	-- Initialize a movement task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	npcData.targetPosition = task.data.position
	self:ChangeNPCState(instanceId, NPCStates.MOVING)
end

function NPCManager:InitializeCombatTask(instanceId, task)
	-- Initialize a combat task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local enemyPosition = task.data.enemyPosition
	npcData.currentTarget = task.data.enemyId

	-- Move to combat range if not already there
	local distance = (npcData.lastPosition - enemyPosition).Magnitude
	if distance > npcData.stats.Range then
		npcData.targetPosition = enemyPosition
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		self:ChangeNPCState(instanceId, NPCStates.FIGHTING)
	end
end

function NPCManager:InitializePatrolTask(instanceId, task)
	-- Initialize a patrol task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	local patrolPoints = task.data.patrolPoints or {task.data.center}
	task.data.currentPatrolIndex = 1
	task.data.patrolDirection = 1

	if #patrolPoints > 0 then
		npcData.targetPosition = patrolPoints[1]
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
	end
end

function NPCManager:InitializeDepositTask(instanceId, task)
	-- Initialize a resource deposit task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Find nearest deposit location (town hall, storage, etc.)
	local depositLocation = self:FindNearestDepositLocation(instanceId)

	if depositLocation then
		npcData.targetPosition = depositLocation.position
		task.data.depositId = depositLocation.id
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		-- No deposit location found
		self:CompleteTask(instanceId, "Failed - No Deposit Location")
	end
end

function NPCManager:InitializeReturnTask(instanceId, task)
	-- Initialize a return-to-base task (for Builders returning to TownHall)
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Find the TownHall or nearest base structure
	local baseLocation = self:FindNearestBase(instanceId)

	if baseLocation then
		npcData.targetPosition = baseLocation.position
		task.data.baseId = baseLocation.id
		self:ChangeNPCState(instanceId, NPCStates.MOVING)

		if self.config.DEBUG_AI then
			print(string.format("[NPCManager] %s returning to base at %s", instanceId, tostring(baseLocation.position)))
		end
	else
		-- No base found, just idle in place
		print(string.format("[NPCManager] %s cannot find base, staying idle", instanceId))
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
	end
end

function NPCManager:InitializeWanderPatrolTask(instanceId, task)
	-- Initialize a wandering patrol task
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Generate a random patrol target around the patrol center
	local angle = math.random() * math.pi * 2
	local distance = math.random() * npcData.patrolRadius
	npcData.targetPosition = npcData.patrolCenter + Vector3.new(
		math.cos(angle) * distance,
		0,
		math.sin(angle) * distance
	)

	-- Clear path to trigger pathfinding
	npcData.currentPath = nil

	-- Task is already set, state will be handled by wandering update
	-- Don't change state here, let UpdateWandering handle it
end

-- ========================================
-- AI UPDATE SYSTEM
-- ========================================

function NPCManager:StartAIUpdates()
	-- Start the main AI update loop
	if self.updateConnection then
		return -- Already running
	end

	local updateInterval = 1 / self.config.UPDATE_FREQUENCY

	self.updateConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()

		-- Only update at specified frequency
		if currentTime - self.lastUpdateTime >= updateInterval then
			self:UpdateAllNPCs(currentTime - self.lastUpdateTime)
			self.lastUpdateTime = currentTime
		end
	end)

	print("[NPCManager] Started AI updates")
end

function NPCManager:StopAIUpdates()
	-- Stop the AI update loop
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
		print("[NPCManager] Stopped AI updates")
	end
end

function NPCManager:UpdateAllNPCs(deltaTime)
	-- Update all managed NPCs
	for instanceId, npcData in pairs(self.managedNPCs) do
		-- Skip NPCs that don't need frequent updates
		if npcData.currentState == NPCStates.DEAD then
			continue
		end

		-- Stagger updates for performance
		if tick() - npcData.lastAIUpdate >= npcData.aiUpdateInterval then
			self:UpdateNPC(instanceId, deltaTime)
			npcData.lastAIUpdate = tick()
		end
	end
end

function NPCManager:UpdateNPC(instanceId, deltaTime)
	-- Update a single NPC's AI
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance or not npcData.instance.Parent then
		self:UnregisterNPC(instanceId, "Instance Destroyed")
		return
	end

	-- Update position tracking with stuck detection
	if npcData.instance.PrimaryPart then
		local newPosition = npcData.instance.PrimaryPart.Position
		local movement = (newPosition - npcData.lastPosition).Magnitude

		-- Check if NPC moved significantly (more than 0.5 studs)
		if movement > 0.5 then
			npcData.lastMovementTime = tick()
			npcData.stuckTime = 0

			if self.config.DEBUG_AI and movement > 1 then
				print(string.format("[NPCManager] %s moved %.1f studs to %.1f,%.1f,%.1f", 
					instanceId, movement, newPosition.X, newPosition.Y, newPosition.Z))
			end
		else
			-- Check if stuck for 10 seconds (but only if in moving state)
			if npcData.currentState == NPCStates.MOVING and tick() - npcData.lastMovementTime > 10 then
				if npcData.currentState ~= NPCStates.STUCK then
					print(string.format("[NPCManager] %s is STUCK - no movement for 10 seconds (pos: %.1f,%.1f,%.1f)", 
						instanceId, newPosition.X, newPosition.Y, newPosition.Z))
					self:ChangeNPCState(instanceId, NPCStates.STUCK)
				end
			end
		end

		-- Check if NPC moved to a different cell and update WorldState
		if movement > 1 then -- Only check if moved more than 1 stud
			local oldGridX, oldGridZ = 0, 0
			local newGridX, newGridZ = 0, 0

			if _G.WorldToGrid then
				oldGridX, oldGridZ = _G.WorldToGrid(npcData.lastPosition)
				newGridX, newGridZ = _G.WorldToGrid(newPosition)

				-- If moved to different cell, update WorldState tracking
				if oldGridX ~= newGridX or oldGridZ ~= newGridZ then
					local worldState = _G.WorldState
					if worldState then
						worldState:UnregisterNPCFromCell(oldGridX, oldGridZ, instanceId)
						worldState:RegisterNPCInCell(newGridX, newGridZ, instanceId)
					end
				end
			end
		end

		npcData.lastPosition = newPosition
	end

	-- Update based on current state
	if npcData.currentState == NPCStates.WANDERING then
		self:UpdateWandering(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.MOVING then
		self:UpdateMovement(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.WORKING then
		self:UpdateWork(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.RETURNING then
		self:UpdateReturning(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.IDLE then
		self:UpdateIdle(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.FIGHTING then
		self:UpdateCombat(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.FLEEING then
		self:UpdateFleeing(instanceId, deltaTime)
	elseif npcData.currentState == NPCStates.STUCK then
		-- Stuck NPCs stay stuck until manually resolved
		return
	end

	-- Check for task timeout
	if npcData.currentTask and tick() - npcData.taskStartTime > npcData.currentTask.timeout then
		self:CompleteTask(instanceId, "Timeout")
	end

	-- Check for threats (enemies nearby)
	if npcData.stats.CanFight then
		self:CheckForThreats(instanceId)
	end
end

-- ========================================
-- STATE UPDATE FUNCTIONS
-- ========================================

function NPCManager:UpdateMovement(instanceId, deltaTime)
	-- Update NPC movement AI with pathfinding
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.targetPosition then
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
		return
	end

	local distance = (npcData.lastPosition - npcData.targetPosition).Magnitude

	-- For harvest tasks, check if within harvest range (don't need to reach exact position)
	if npcData.currentTask and npcData.currentTask.type == TaskTypes.HARVEST_RESOURCE then
		if distance <= npcData.stats.HarvestRange then
			-- Within harvest range, start working immediately
			self:ChangeNPCState(instanceId, NPCStates.WORKING)
			return
		end
	end

	-- Check if reached destination
	if distance < 3 then -- Within 3 studs of target
		self:OnReachedDestination(instanceId)
		return
	end

	-- Update pathfinding if needed
	if not npcData.currentPath or self:ShouldRecalculatePath(instanceId) then
		self:CalculatePathToTarget(instanceId)
	end

	-- Follow current path
	if npcData.currentPath and #npcData.currentPath > 0 then
		self:FollowPath(instanceId)
	else
		-- No path available, try direct movement as fallback
		self:MoveTowardsTargetDirect(instanceId)
	end
end

function NPCManager:CalculatePathToTarget(instanceId)
	-- Calculate pathfinding path to target
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.targetPosition then
		return false
	end

	-- Rate limit pathfinding calculations
	local currentTime = tick()
	if currentTime - npcData.lastPathfindTime < npcData.pathfindCooldown then
		return false
	end
	npcData.lastPathfindTime = currentTime

	-- Get grid positions
	local startX, startZ = 0, 0
	local goalX, goalZ = 0, 0

	if _G.WorldToGrid then
		startX, startZ = _G.WorldToGrid(npcData.lastPosition)
		goalX, goalZ = _G.WorldToGrid(npcData.targetPosition)
	else
		warn("[NPCManager] WorldToGrid function not available for pathfinding")
		return false
	end

	-- Get WorldState for pathfinding
	local worldState = _G.WorldState
	if not worldState then
		warn("[NPCManager] WorldState not available for pathfinding")
		return false
	end

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] Calculating path for %s from (%d,%d) to (%d,%d)", 
			instanceId, startX, startZ, goalX, goalZ))
	end

	-- Calculate path using A* pathfinding
	local path = PathfindingModule:FindPath(startX, startZ, goalX, goalZ, worldState)

	if path and #path > 0 then
		-- Smooth the path for more natural movement
		npcData.currentPath = PathfindingModule:SmoothPath(path, worldState)
		npcData.pathIndex = 1
		npcData.targetGridX = goalX
		npcData.targetGridZ = goalZ

		if self.config.DEBUG_AI then
			print(string.format("[NPCManager] Path calculated for %s: %d waypoints", 
				instanceId, #npcData.currentPath))
		end

		return true
	else
		-- No path found
		if self.config.DEBUG_AI then
			print(string.format("[NPCManager] No path found for %s", instanceId))
		end

		npcData.currentPath = nil
		return false
	end
end

function NPCManager:FollowPath(instanceId)
	-- Follow the calculated pathfinding path
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.currentPath or not npcData.instance.PrimaryPart then
		return
	end

	local humanoid = npcData.instance:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	-- Get current waypoint
	local currentWaypoint = npcData.currentPath[npcData.pathIndex]
	if not currentWaypoint then
		-- Reached end of path
		npcData.currentPath = nil
		return
	end

	-- Convert grid position to world position
	local waypointWorldPos = PathfindingModule:GridToWorldPosition(currentWaypoint.x, currentWaypoint.z)

	if not waypointWorldPos then
		warn(string.format("[NPCManager] Failed to get world position for waypoint (%d, %d)", 
			currentWaypoint.x, currentWaypoint.z))
		npcData.currentPath = nil
		return
	end

	-- Check if reached current waypoint
	local distanceToWaypoint = (npcData.lastPosition - waypointWorldPos).Magnitude
	if distanceToWaypoint < 2 then
		-- Move to next waypoint
		npcData.pathIndex = npcData.pathIndex + 1

		if npcData.pathIndex > #npcData.currentPath then
			-- Reached end of path
			npcData.currentPath = nil
			print(string.format("[NPCManager] %s completed path", instanceId))
			return
		end

		-- Get next waypoint
		currentWaypoint = npcData.currentPath[npcData.pathIndex]
		if currentWaypoint then
			waypointWorldPos = PathfindingModule:GridToWorldPosition(currentWaypoint.x, currentWaypoint.z)
			if not waypointWorldPos then
				warn(string.format("[NPCManager] Failed to get world position for next waypoint (%d, %d)", 
					currentWaypoint.x, currentWaypoint.z))
				npcData.currentPath = nil
				return
			end
		end
	end

	-- Move towards current waypoint
	if waypointWorldPos then
		humanoid:MoveTo(waypointWorldPos)

		if self.config.DEBUG_AI and math.random() < 0.2 then -- Debug every ~5 updates
			print(string.format("[NPCManager] %s moving to waypoint %d/%d at grid (%d,%d) world %.1f,%.1f,%.1f", 
				instanceId, npcData.pathIndex, #npcData.currentPath, 
				currentWaypoint.x, currentWaypoint.z,
				waypointWorldPos.X, waypointWorldPos.Y, waypointWorldPos.Z))
		end
	end
end

function NPCManager:ShouldRecalculatePath(instanceId)
	-- Determine if path should be recalculated
	local npcData = self.managedNPCs[instanceId]
	if not npcData then
		return false
	end

	-- Recalculate if target has changed
	if npcData.targetPosition then
		local currentGoalX, currentGoalZ = 0, 0
		if _G.WorldToGrid then
			currentGoalX, currentGoalZ = _G.WorldToGrid(npcData.targetPosition)
		end

		if npcData.targetGridX ~= currentGoalX or npcData.targetGridZ ~= currentGoalZ then
			return true
		end
	end

	-- Recalculate if no path exists
	if not npcData.currentPath then
		return true
	end

	-- Recalculate if stuck for too long
	if tick() - npcData.lastMovementTime > 5 then
		return true
	end

	return false
end

function NPCManager:MoveTowardsTargetDirect(instanceId)
	-- Fallback direct movement when pathfinding fails
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.targetPosition or not npcData.instance.PrimaryPart then 
		return 
	end

	local humanoid = npcData.instance:FindFirstChild("Humanoid")
	if not humanoid then 
		return 
	end

	-- Direct movement towards target (fallback)
	humanoid:MoveTo(npcData.targetPosition)

	if self.config.DEBUG_AI then
		print(string.format("[NPCManager] %s using direct movement (pathfinding failed) to %.1f,%.1f,%.1f", 
			instanceId, npcData.targetPosition.X, npcData.targetPosition.Y, npcData.targetPosition.Z))
	end
end

function NPCManager:DebugNPCMovement(instanceId)
	-- Debug function to manually check NPC movement status
	local npcData = self.managedNPCs[instanceId]
	if not npcData then
		print("[NPCManager] Debug: NPC not found:", instanceId)
		return
	end

	print("=== NPC MOVEMENT DEBUG ===")
	print("Instance ID:", instanceId)
	print("Current State:", npcData.currentState)
	print("Has Instance:", npcData.instance ~= nil)
	print("Has PrimaryPart:", npcData.instance and npcData.instance.PrimaryPart ~= nil)
	print("Has Humanoid:", npcData.instance and npcData.instance:FindFirstChild("Humanoid") ~= nil)

	if npcData.instance and npcData.instance.PrimaryPart then
		local pos = npcData.instance.PrimaryPart.Position
		print("Current Position:", string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z))

		if _G.WorldToGrid then
			local gridX, gridZ = _G.WorldToGrid(pos)
			print("Grid Position:", gridX, gridZ)
		end
	end

	print("Target Position:", npcData.targetPosition and string.format("%.1f, %.1f, %.1f", 
		npcData.targetPosition.X, npcData.targetPosition.Y, npcData.targetPosition.Z) or "nil")
	print("Has Path:", npcData.currentPath ~= nil)
	if npcData.currentPath then
		print("Path Length:", #npcData.currentPath)
		print("Path Index:", npcData.pathIndex)
	end
	print("Last Movement Time:", tick() - npcData.lastMovementTime, "seconds ago")
	print("========================")
end

function NPCManager:UpdateWork(instanceId, deltaTime)
	-- Update NPC work progress
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.currentTask then
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
		return
	end

	local task = npcData.currentTask

	if task.type == TaskTypes.BUILD_STRUCTURE then
		self:UpdateBuilding(instanceId, deltaTime)
	elseif task.type == TaskTypes.HARVEST_RESOURCE then
		self:UpdateHarvesting(instanceId, deltaTime)
	end
end

function NPCManager:UpdateCombat(instanceId, deltaTime)
	-- Update NPC combat AI
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Check if target still exists and is in range
	local target = self:GetTargetInstance(npcData.currentTarget)
	if not target then
		self:CompleteTask(instanceId, "Target Lost")
		return
	end

	local distance = (npcData.lastPosition - target.PrimaryPart.Position).Magnitude

	if distance > npcData.stats.Range * 1.5 then
		-- Target too far, chase
		npcData.targetPosition = target.PrimaryPart.Position
		self:ChangeNPCState(instanceId, NPCStates.MOVING)
	else
		-- In range, attack
		self:PerformAttack(instanceId, target)
	end
end

function NPCManager:UpdateWandering(instanceId, deltaTime)
	-- Update wandering patrol behavior
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Check for nearby tasks while wandering
	local nearbyTask = self:FindNearbyTask(instanceId)
	if nearbyTask then
		self:AssignTaskFromResource(instanceId, nearbyTask)
		return
	end

	-- Continue wandering patrol
	if not npcData.targetPosition or (npcData.instance.PrimaryPart.Position - npcData.targetPosition).Magnitude < 3 then
		-- Generate new random patrol target around patrol center
		local angle = math.random() * math.pi * 2
		local distance = math.random() * npcData.patrolRadius
		npcData.targetPosition = npcData.patrolCenter + Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)

		-- Clear path to trigger pathfinding for new target
		npcData.currentPath = nil
	end

	-- Use pathfinding for wandering movement
	if not npcData.currentPath or self:ShouldRecalculatePath(instanceId) then
		self:CalculatePathToTarget(instanceId)
	end

	-- Follow path or use direct movement
	if npcData.currentPath and #npcData.currentPath > 0 then
		self:FollowPath(instanceId)
	else
		self:MoveTowardsTargetDirect(instanceId)
	end
end

function NPCManager:UpdateReturning(instanceId, deltaTime)
	-- Update NPCs returning to town hall with resources
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Check if reached town hall
	local townHallPos = self:FindTownHallPosition(instanceId)
	if townHallPos then
		local distance = (npcData.lastPosition - townHallPos).Magnitude
		if distance < 5 then
			-- Reached town hall, deposit resources
			self:DepositResources(instanceId)
			self:ChangeNPCState(instanceId, NPCStates.IDLE)
			return
		else
			-- Keep moving to town hall
			npcData.targetPosition = townHallPos

			-- Use pathfinding for returning
			if not npcData.currentPath or self:ShouldRecalculatePath(instanceId) then
				self:CalculatePathToTarget(instanceId)
			end

			if npcData.currentPath and #npcData.currentPath > 0 then
				self:FollowPath(instanceId)
			else
				self:MoveTowardsTargetDirect(instanceId)
			end
		end
	else
		-- Can't find town hall, go idle
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
	end
end

function NPCManager:UpdateIdle(instanceId, deltaTime)
	-- Update idle NPCs (3 second pause before returning to wandering)
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Initialize idle timer if not set
	if not npcData.idleStartTime then
		npcData.idleStartTime = tick()
	end

	-- Return to wandering after 3 seconds
	if tick() - npcData.idleStartTime >= 3 then
		self:ChangeNPCState(instanceId, NPCStates.WANDERING)
	end
end

function NPCManager:UpdateFleeing(instanceId, deltaTime)
	-- Update NPCs fleeing to town hall
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Find town hall and run to it
	local townHallPos = self:FindTownHallPosition(instanceId)
	if townHallPos then
		local distance = (npcData.lastPosition - townHallPos).Magnitude
		if distance < 8 then
			-- Reached safety, check health
			local humanoid = npcData.instance:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > humanoid.MaxHealth * 0.5 then
				-- Recovered enough health, return to wandering
				self:ChangeNPCState(instanceId, NPCStates.WANDERING)
			else
				-- Stay near town hall until healed
				self:ChangeNPCState(instanceId, NPCStates.IDLE)
			end
		else
			-- Keep running to town hall using pathfinding
			npcData.targetPosition = townHallPos

			-- Use pathfinding for fleeing (urgent, so allow more frequent recalculation)
			npcData.pathfindCooldown = 1 -- Faster pathfinding when fleeing
			if not npcData.currentPath or self:ShouldRecalculatePath(instanceId) then
				self:CalculatePathToTarget(instanceId)
			end

			if npcData.currentPath and #npcData.currentPath > 0 then
				self:FollowPath(instanceId)
			else
				self:MoveTowardsTargetDirect(instanceId)
			end
		end
	else
		-- Can't find town hall, just go idle
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
	end
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

function NPCManager:AddToStateTracking(instanceId, state)
	if not self.npcsByState[state] then
		self.npcsByState[state] = {}
	end
	table.insert(self.npcsByState[state], instanceId)
end

function NPCManager:RemoveFromStateTracking(instanceId, state)
	if not self.npcsByState[state] then return end
	for i, id in ipairs(self.npcsByState[state]) do
		if id == instanceId then
			table.remove(self.npcsByState[state], i)
			break
		end
	end
end

function NPCManager:AddToTypeTracking(instanceId, npcType)
	if not self.npcsByType[npcType] then
		self.npcsByType[npcType] = {}
	end
	table.insert(self.npcsByType[npcType], instanceId)
end

function NPCManager:RemoveFromTypeTracking(instanceId, npcType)
	if not self.npcsByType[npcType] then return end
	for i, id in ipairs(self.npcsByType[npcType]) do
		if id == instanceId then
			table.remove(self.npcsByType[npcType], i)
			break
		end
	end
end

function NPCManager:AddToOwnerTracking(instanceId, owner)
	if not self.npcsByOwner[owner] then
		self.npcsByOwner[owner] = {}
	end
	table.insert(self.npcsByOwner[owner], instanceId)
end

function NPCManager:RemoveFromOwnerTracking(instanceId, owner)
	if not self.npcsByOwner[owner] then return end
	for i, id in ipairs(self.npcsByOwner[owner]) do
		if id == instanceId then
			table.remove(self.npcsByOwner[owner], i)
			break
		end
	end
end

-- ========================================
-- HARVEST TASK MANAGEMENT
-- ========================================

function NPCManager:FindNearbySelectedResource(instanceId)
	-- Find nearby selected resources that need harvesting
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return nil end

	local worldState = _G.WorldState
	if not worldState then return nil end

	local npcPosition = npcData.lastPosition
	local stats = npcData.stats
	local searchRadius = 30 -- Search within 30 studs

	-- Get the next available harvest task from WorldState
	local harvestTask, taskIndex = worldState:GetNextHarvestTask()
	if harvestTask then
		local distance = (npcPosition - harvestTask.position).Magnitude
		if distance <= searchRadius then
			-- Assign this task to the NPC
			local assignedTask = worldState:AssignHarvestTask(taskIndex, instanceId)
			if assignedTask then
				return {
					resourceId = assignedTask.resourceId,
					resourceType = assignedTask.resourceType,
					position = assignedTask.position,
					taskIndex = taskIndex
				}
			end
		end
	end

	return nil
end

function NPCManager:CheckForNewHarvestTasks()
	-- Called by WorldState when new harvest tasks are available
	-- Check all wandering villagers to see if they can take on tasks
	for instanceId, npcData in pairs(self.managedNPCs) do
		if npcData.currentState == NPCStates.WANDERING and npcData.stats.CanHarvest then
			local nearbyTask = self:FindNearbySelectedResource(instanceId)
			if nearbyTask then
				self:AssignTaskFromResource(instanceId, nearbyTask)
			end
		end
	end
end

function NPCManager:AssignTaskFromResource(instanceId, resourceData)
	-- Assign a harvest task from selected resource
	self:AssignTask(instanceId, TaskTypes.HARVEST_RESOURCE, {
		resourceId = resourceData.resourceId,
		resourceType = resourceData.resourceType,
		resourcePosition = resourceData.position,
		taskIndex = resourceData.taskIndex
	})

	self:ChangeNPCState(instanceId, NPCStates.MOVING)
end

function NPCManager:DepositResources(instanceId)
	-- Deposit carried resources to town hall
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return false end

	local worldState = _G.WorldState
	if not worldState then
		warn("[NPCManager] WorldState not available for resource deposit")
		return false
	end

	local totalDeposited = 0

	-- Deposit each resource type from actual carried resources
	for resourceType, amount in pairs(npcData.carriedResources) do
		if amount > 0 then
			local deposited, newTotal = worldState:DepositResource(resourceType, amount)
			totalDeposited = totalDeposited + deposited

			if deposited > 0 then
				print(string.format("[NPCManager] %s deposited %d %s to Town Hall (new total: %d)",
					instanceId, deposited, resourceType, newTotal))

				-- Update NPC inventory attributes
				self:UpdateNPCInventoryAttributes(instanceId, resourceType, -deposited)
			end
		end
	end

	-- Clear NPC's inventory
	npcData.totalCarriedWeight = 0
	npcData.carriedResources = {}

	if totalDeposited > 0 then
		print(string.format("[NPCManager] %s deposited %d total resources", instanceId, totalDeposited))
	end

	return totalDeposited > 0
end

function NPCManager:FindNearbyBlueprint(instanceId)
	-- Find nearby blueprints that builders can construct
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return nil end

	-- TODO: Implement blueprint detection system
	-- For now, return nil since no blueprint system exists yet
	-- This will allow builders to continue wandering without crashing

	-- When blueprint system is added, this should:
	-- 1. Search for blueprint models in the world
	-- 2. Check if they're within range
	-- 3. Check if they're not already assigned to another builder
	-- 4. Return blueprint data if found

	return nil
end

function NPCManager:FindNearestDepositLocation(instanceId)
	-- Find nearest location to deposit resources (town hall, storage, etc.)
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return nil end

	-- Find town hall as deposit location
	local townHallPos = self:FindTownHallPosition(instanceId)
	if townHallPos then
		return {
			position = townHallPos,
			type = "TownHall",
			id = "main_storage"
		}
	end

	return nil
end

function NPCManager:FindNearestBase(instanceId)
	-- Find the nearest base structure (TownHall) for returning
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance or not npcData.instance.PrimaryPart then
		return nil
	end

	local npcPosition = npcData.instance.PrimaryPart.Position
	local npcTeam = npcData.stats.Team

	-- Look for TownHall or other base structures in the same world
	-- NPCs are parented to PlayerNPCs/EnemyNPCs folder, so we need to go up one more level to get the actual world folder
	local npcFolder = npcData.instance.Parent
	if not npcFolder then
		return nil
	end

	local worldFolder = npcFolder.Parent
	if not worldFolder then
		return nil
	end

	local nearestBase = nil
	local nearestDistance = math.huge

	-- Search for structures that could be bases
	for _, obj in pairs(worldFolder:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("StructureType") then
			local structureTeam = obj:GetAttribute("Team")
			local structureType = obj:GetAttribute("StructureType")

			-- Look for team structures that are bases (TownHall, etc.)
			if structureTeam == npcTeam and (structureType == "Main" or structureType == "TOWNHALL") then
				if obj.PrimaryPart then
					local distance = (npcPosition - obj.PrimaryPart.Position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestBase = {
							id = obj:GetAttribute("InstanceId") or obj.Name,
							position = obj.PrimaryPart.Position,
							instance = obj
						}
					end
				end
			end
		end
	end

	return nearestBase
end

function NPCManager:GeneratePatrolPoints(center, radius)
	-- Generate patrol points around a center position
	local points = {}
	local numPoints = 4

	for i = 1, numPoints do
		local angle = (i / numPoints) * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * radius,
			0,
			math.sin(angle) * radius
		)
		table.insert(points, center + offset)
	end

	return points
end

-- ========================================
-- PLACEHOLDER FUNCTIONS (To be implemented)
-- ========================================

function NPCManager:ShouldFlee(instanceId)
	-- Determine if an NPC should flee from danger
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return false end

	local stats = npcData.stats

	-- Builders always flee from enemies
	if stats.CanBuild and not stats.CanFight then
		return self:HasNearbyEnemies(instanceId, 15) -- Flee if enemies within 15 studs
	end

	-- Other units flee when health is low
	if npcData.instance and npcData.instance:FindFirstChild("Humanoid") then
		local humanoid = npcData.instance.Humanoid
		local healthPercent = humanoid.Health / humanoid.MaxHealth
		if healthPercent < 0.3 then -- Below 30% health
			return true
		end
	end

	return false
end

function NPCManager:ShouldFight(instanceId)
	-- Determine if an NPC should engage in combat
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return false end

	local stats = npcData.stats

	-- Can't fight if not capable
	if not stats.CanFight then
		return false
	end

	-- Fight if enemies are nearby
	return self:HasNearbyEnemies(instanceId, stats.Range * 2)
end

function NPCManager:HasNearbyEnemies(instanceId, range)
	-- Check if there are enemies within range
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.instance or not npcData.instance.PrimaryPart then
		return false
	end

	local npcPosition = npcData.instance.PrimaryPart.Position
	local npcTeam = npcData.stats.Team

	-- Check all characters in workspace for enemies
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
			-- Check if it's an enemy (different team)
			local objTeam = obj:GetAttribute("Team")
			if objTeam and objTeam ~= npcTeam then
				local distance = (npcPosition - obj.HumanoidRootPart.Position).Magnitude
				if distance <= range then
					return true
				end
			end
		end
	end

	return false
end

function NPCManager:CheckForThreats(instanceId)
	-- Check for threats and update threat level
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	if self:HasNearbyEnemies(instanceId, 20) then
		npcData.threatLevel = math.min(npcData.threatLevel + 1, 10)
	else
		npcData.threatLevel = math.max(npcData.threatLevel - 1, 0)
	end
end

function NPCManager:GetTargetInstance(targetId)
	-- Get target instance by ID
	if not targetId then return nil end

	-- Search for target in workspace
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("InstanceId") == targetId then
			return obj
		end
	end

	return nil
end

function NPCManager:PerformAttack(instanceId, target)
	-- Perform an attack on a target
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not target then return end

	local stats = npcData.stats
	local currentTime = tick()

	-- Check attack cooldown
	if currentTime - npcData.lastAttackTime < (1 / stats.AtkSpeed) then
		return
	end

	-- Deal damage to target
	local targetHumanoid = target:FindFirstChild("Humanoid")
	if targetHumanoid then
		targetHumanoid.Health = targetHumanoid.Health - stats.Attack
		npcData.lastAttackTime = currentTime

		print(string.format("[NPCManager] %s attacked target for %d damage", instanceId, stats.Attack))
	end
end

function NPCManager:OnReachedDestination(instanceId)
	-- Handle when NPC reaches their destination
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Check what task they were doing
	if npcData.currentTask then
		local task = npcData.currentTask

		if task.type == TaskTypes.MOVE_TO_POSITION then
			self:CompleteTask(instanceId, "Destination Reached")
		elseif task.type == TaskTypes.MOVE_TO_BLUEPRINT then
			self:ChangeNPCState(instanceId, NPCStates.WORKING)
		elseif task.type == TaskTypes.MOVE_TO_RESOURCE then
			self:ChangeNPCState(instanceId, NPCStates.WORKING)
		else
			-- Reached work location, start working
			self:ChangeNPCState(instanceId, NPCStates.WORKING)
		end
	else
		-- No task, go idle
		self:ChangeNPCState(instanceId, NPCStates.IDLE)
	end
end

function NPCManager:UpdatePathfinding(instanceId)
	-- Update pathfinding for an NPC
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.targetPosition then return end

	-- Simple movement towards target for now
	self:MoveTowardsTarget(instanceId)
end

-- Old MoveTowardsTarget function removed - replaced by pathfinding system
-- Use MoveTowardsTargetDirect for fallback direct movement
-- Use CalculatePathToTarget + FollowPath for pathfinding movement

function NPCManager:HandleStuckNPC(instanceId)
	-- Handle NPCs that are stuck using pathfinding
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	print(string.format("[NPCManager] %s is stuck, attempting pathfinding resolution", instanceId))

	-- Clear current path to force recalculation
	npcData.currentPath = nil
	npcData.pathIndex = 1
	npcData.lastPathfindTime = 0 -- Reset cooldown to allow immediate pathfinding

	-- Try to recalculate path
	if npcData.targetPosition then
		local pathFound = self:CalculatePathToTarget(instanceId)

		if pathFound then
			print(string.format("[NPCManager] %s found new path after being stuck", instanceId))
			self:ChangeNPCState(instanceId, NPCStates.MOVING)
			return
		end
	end

	-- If pathfinding fails, cancel current task and return to wandering
	print(string.format("[NPCManager] %s pathfinding failed, cancelling task", instanceId))
	self:CompleteTask(instanceId, "Stuck - No Path Found")
	self:ChangeNPCState(instanceId, NPCStates.WANDERING)
end

function NPCManager:UpdateBuilding(instanceId, deltaTime)
	-- Update building progress for builders
	local npcData = self.managedNPCs[instanceId]
	if not npcData then return end

	-- Simulate building progress
	npcData.workProgress = npcData.workProgress + (deltaTime * npcData.stats.BuildSpeed)

	-- Complete after some time (placeholder)
	if npcData.workProgress >= 5 then -- 5 seconds to build
		print(string.format("[NPCManager] %s completed building task", instanceId))
		self:CompleteTask(instanceId, "Building Complete")
	end
end

function NPCManager:UpdateHarvesting(instanceId, deltaTime)
	-- Update harvesting progress for villagers (with gradual damage and shrinking)
	local npcData = self.managedNPCs[instanceId]
	if not npcData or not npcData.currentTask then return end

	local task = npcData.currentTask
	local resourceId = task.data.resourceId
	local resourceType = task.data.resourceType

	-- Find the resource instance in the world
	-- NPCs are parented to PlayerNPCs/EnemyNPCs folder, so we need to go up one more level to get the actual world folder
	local npcFolder = npcData.instance.Parent
	if not npcFolder then
		self:CompleteTask(instanceId, "Failed - NPC folder not found")
		return
	end

	local worldFolder = npcFolder.Parent
	if not worldFolder then
		self:CompleteTask(instanceId, "Failed - World not found")
		return
	end

	local resourcesFolder = worldFolder:FindFirstChild("Resources")
	if not resourcesFolder then
		self:CompleteTask(instanceId, "Failed - Resources folder not found")
		return
	end

	-- Find the specific resource by ID
	local resourceInstance = nil
	for _, resource in pairs(resourcesFolder:GetChildren()) do
		if resource:GetAttribute("ResourceId") == resourceId then
			resourceInstance = resource
			break
		end
	end

	if not resourceInstance or not resourceInstance.Parent then
		-- Resource was deleted or depleted
		print(string.format("[NPCManager] %s - resource no longer exists", instanceId))
		self:CompleteTask(instanceId, "Failed - Resource Gone")
		return
	end

	-- Get health values
	local maxHealth = resourceInstance:GetAttribute("MaxHealth") or 100
	local currentHealth = resourceInstance:GetAttribute("CurrentHealth") or maxHealth

	-- Check if resource is already depleted
	if currentHealth <= 0 then
		print(string.format("[NPCManager] %s - resource is already depleted", instanceId))
		self:CompleteTask(instanceId, "Failed - Resource Depleted")
		return
	end

	-- Get harvest parameters
	local harvestTime = resourceInstance:GetAttribute("HarvestTime") or 3
	local harvestMin = resourceInstance:GetAttribute("HarvestAmountMin") or 5
	local harvestMax = resourceInstance:GetAttribute("HarvestAmountMax") or 10

	-- Calculate damage per second (total health / harvest time)
	local damagePerSecond = maxHealth / harvestTime
	local damageThisUpdate = damagePerSecond * deltaTime

	-- Deal damage to resource
	currentHealth = math.max(0, currentHealth - damageThisUpdate)
	resourceInstance:SetAttribute("CurrentHealth", currentHealth)

	-- Calculate health percentage for shrinking effect
	local healthPercent = currentHealth / maxHealth

	-- Shrink the resource based on remaining health
	if resourceInstance.PrimaryPart then
		local originalX = resourceInstance:GetAttribute("OriginalScaleX") or resourceInstance.PrimaryPart.Size.X
		local originalY = resourceInstance:GetAttribute("OriginalScaleY") or resourceInstance.PrimaryPart.Size.Y
		local originalZ = resourceInstance:GetAttribute("OriginalScaleZ") or resourceInstance.PrimaryPart.Size.Z

		-- Calculate new scale (minimum 10% of original size)
		local scaleMultiplier = math.max(0.1, healthPercent)
		local newScale = Vector3.new(
			originalX * scaleMultiplier,
			originalY * scaleMultiplier,
			originalZ * scaleMultiplier
		)

		-- Get current position to maintain it while scaling
		local currentPosition = resourceInstance.PrimaryPart.Position

		-- Apply new scale to all parts in the model
		for _, part in pairs(resourceInstance:GetDescendants()) do
			if part:IsA("BasePart") then
				local relativeScale = part.Size / resourceInstance.PrimaryPart.Size
				part.Size = Vector3.new(
					newScale.X * relativeScale.X,
					newScale.Y * relativeScale.Y,
					newScale.Z * relativeScale.Z
				)
			end
		end

		-- Restore position (scaling can sometimes shift position)
		resourceInstance.PrimaryPart.Position = currentPosition
	end

	-- Update work progress for tracking
	npcData.workProgress = npcData.workProgress + deltaTime

	-- Check if resource is fully harvested (health reached 0)
	if currentHealth <= 0 then
		-- Calculate harvested amount based on how much the NPC has been harvesting
		local harvestedAmount = math.random(harvestMin, harvestMax)

		print(string.format("[NPCManager] %s harvested %d %s - resource depleted!",
			instanceId, harvestedAmount, resourceType))

		-- Add resources to NPC inventory
		npcData.carriedResources[resourceType] = (npcData.carriedResources[resourceType] or 0) + harvestedAmount
		npcData.totalCarriedWeight = npcData.totalCarriedWeight + harvestedAmount

		-- Update NPC inventory attributes
		self:UpdateNPCInventoryAttributes(instanceId, resourceType, harvestedAmount)
		self:UpdateNPCPerformanceAttributes(instanceId, "ResourceHarvested", harvestedAmount)

		print(string.format("[NPCManager] %s now carrying: %d/%d",
			instanceId, npcData.totalCarriedWeight, npcData.stats.CarryCapacity))

		-- Destroy the depleted resource
		resourceInstance:Destroy()

		-- Notify WorldState that harvest is complete
		local worldState = _G.WorldState
		if worldState then
			worldState:CompleteHarvestTask(resourceId, instanceId, harvestedAmount, resourceType)
		end

		-- Check if inventory is full
		if npcData.totalCarriedWeight >= npcData.stats.CarryCapacity then
			print(string.format("[NPCManager] %s inventory full, returning to town hall", instanceId))
			self:CompleteTask(instanceId, "Harvesting Complete - Inventory Full")
			self:ChangeNPCState(instanceId, NPCStates.RETURNING)
		else
			-- Completed harvesting, return to idle to get next task
			self:CompleteTask(instanceId, "Harvesting Complete")
		end
	else
		-- Still harvesting, stay in WORKING state
		-- Log progress occasionally for debugging
		if self.config.DEBUG_AI and math.random() < 0.1 then
			print(string.format("[NPCManager] %s harvesting: %.1f%% complete (health: %.1f/%.1f)",
				instanceId, (1 - healthPercent) * 100, currentHealth, maxHealth))
		end
	end
end

function NPCManager:OnNPCDeath(instanceId)
	-- Handle NPC death
	print(string.format("[NPCManager] %s has died", instanceId))

	-- Clean up and remove from management
	self:UnregisterNPC(instanceId, "Death")
end

function NPCManager:FindNearestBlueprint(instanceId)
	-- Find the nearest blueprint for a builder
	-- TODO: Implement blueprint detection
	return nil
end

function NPCManager:FindNearestResource(instanceId)
	-- Find the nearest harvestable resource
	-- TODO: Implement resource detection
	return nil
end

function NPCManager:FindNearestEnemy(instanceId)
	-- Find the nearest enemy
	-- TODO: Implement enemy detection
	return nil
end

function NPCManager:FindSafePosition(instanceId)
	-- Find a safe position away from enemies
	-- TODO: Implement safe position calculation
	local npcData = self.managedNPCs[instanceId]
	return npcData and npcData.lastPosition or Vector3.new(0, 0, 0)
end

-- ========================================
-- QUERY FUNCTIONS
-- ========================================

function NPCManager:GetNPCsByState(state)
	return self.npcsByState[state] or {}
end

function NPCManager:GetNPCsByType(npcType)
	return self.npcsByType[npcType] or {}
end

function NPCManager:GetNPCsByOwner(owner)
	return self.npcsByOwner[owner] or {}
end

function NPCManager:GetNPCData(instanceId)
	return self.managedNPCs[instanceId]
end

function NPCManager:GetNPCCount()
	local count = 0
	for _ in pairs(self.managedNPCs) do
		count = count + 1
	end
	return count
end

return NPCManager