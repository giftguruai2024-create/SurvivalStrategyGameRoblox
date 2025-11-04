-- @ScriptType: ModuleScript
-- NPCSpawningScript Module
-- Handles all non-structure NPC spawning (magic, events, player commands, etc.)
-- Place this in ReplicatedStorage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AllStats = require(ReplicatedStorage:WaitForChild("AllStats"))

-- Unit model references
local unitsFolder = ReplicatedStorage:WaitForChild("Units")
local playerUnitsFolder = unitsFolder:WaitForChild("Player") 
local worldAIUnitsFolder = unitsFolder:WaitForChild("WorldAI")

local NPCSpawning = {}
NPCSpawning.__index = NPCSpawning

-- ========================================
-- CONFIGURATION
-- ========================================
local DEFAULT_CONFIG = {
	DEBUG_SPAWNING = true,
	MAX_GLOBAL_NPCS = 100, -- Global limit for all non-structure NPCs
	SPAWN_HEIGHT_OFFSET = 2,
	BATCH_SPAWN_DELAY = 0.1, -- Delay between spawns in a batch
	COOLDOWN_BETWEEN_SPAWNS = 1, -- Global cooldown between spawn commands
	DEFAULT_DESPAWN_TIME = 300, -- 5 minutes default despawn time
}

-- ========================================
-- NPC SPAWNING CLASS
-- ========================================

function NPCSpawning.new(config)
	local self = setmetatable({}, NPCSpawning)

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

	-- Tracking
	self.spawnedNPCs = {} -- {instanceId = {instance, stats, spawnTime, despawnTime}}
	self.npcsByOwner = {} -- {ownerName = {instanceIds}}
	self.npcsByTeam = {Player = {}, Enemy = {}, Neutral = {}}
	self.npcsByType = {} -- {npcType = {instanceIds}}

	-- Spawn management
	self.globalNPCId = 0
	self.lastSpawnTime = 0
	self.activeSpawnEffects = {} -- Track spawn effects

	-- Batch spawning
	self.batchQueue = {} -- Queue for batch spawn operations
	self.isBatchSpawning = false

	print("[NPCSpawning] Initialized with max global NPCs:", self.config.MAX_GLOBAL_NPCS)
	return self
end

-- ========================================
-- VALIDATION & PREPARATION
-- ========================================

function NPCSpawning:CanSpawnNPC(npcType, team, owner, count)
	-- Check if NPCs can be spawned
	count = count or 1

	-- Check global NPC limit
	local totalNPCs = self:GetTotalNPCCount()
	if totalNPCs + count > self.config.MAX_GLOBAL_NPCS then
		return false, string.format("Would exceed global NPC limit (%d/%d)", 
			totalNPCs + count, self.config.MAX_GLOBAL_NPCS)
	end

	-- Check spawn cooldown
	if tick() - self.lastSpawnTime < self.config.COOLDOWN_BETWEEN_SPAWNS then
		return false, "Spawn cooldown not finished"
	end

	-- Validate NPC type
	if not AllStats:IsValidNPC(npcType, team) then
		return false, "Invalid NPC type for team"
	end

	-- Here you could add more validation:
	-- - Resource costs
	-- - Player permissions
	-- - Area restrictions

	return true, "Can spawn NPC"
end

function NPCSpawning:PrepareNPCStats(npcType, team, owner, options)
	-- Prepare NPC stats for spawning
	options = options or {}

	local stats = AllStats:CreateInstance(
		team == "Player" and "PlayerNPCs" or "EnemyNPCs",
		npcType,
		owner
	)

	if not stats then
		return nil
	end

	-- Apply any stat modifications from options
	if options.healthMultiplier then
		stats.Health = stats.Health * options.healthMultiplier
		stats.CurrentHealth = stats.Health
	end

	if options.attackMultiplier and stats.DoesAtk then
		stats.Attack = stats.Attack * options.attackMultiplier
	end

	if options.speedMultiplier then
		stats.MovementSpeed = stats.MovementSpeed * options.speedMultiplier
	end

	-- Add spawn-specific data
	stats.SpawnSource = options.spawnSource or "Manual"
	stats.SpawnMethod = options.spawnMethod or "Normal"
	stats.DespawnTime = options.despawnTime or self.config.DEFAULT_DESPAWN_TIME
	stats.CanDespawn = options.canDespawn ~= false -- Default to true

	return stats
end

-- ========================================
-- SPAWN LOCATION MANAGEMENT
-- ========================================

function NPCSpawning:FindSpawnLocation(options)
	-- Find a valid spawn location based on options
	options = options or {}

	-- Method 1: Specific position
	if options.position then
		return options.position + Vector3.new(0, self.config.SPAWN_HEIGHT_OFFSET, 0)
	end

	-- Method 2: Near a target
	if options.nearTarget and options.range then
		local target = options.nearTarget
		local range = options.range

		local randomOffset = Vector3.new(
			math.random(-range, range),
			0,
			math.random(-range, range)
		)

		return target + randomOffset + Vector3.new(0, self.config.SPAWN_HEIGHT_OFFSET, 0)
	end

	-- Method 3: Grid-based spawning (if gridCells provided)
	if options.gridCells and options.gridX and options.gridZ then
		local cell = options.gridCells[options.gridX] and options.gridCells[options.gridX][options.gridZ]
		if cell then
			return cell.Position + Vector3.new(0, self.config.SPAWN_HEIGHT_OFFSET, 0)
		end
	end

	-- Method 4: Area spawning
	if options.area then
		local area = options.area
		local randomPos = Vector3.new(
			math.random(area.minX, area.maxX),
			area.y or 0,
			math.random(area.minZ, area.maxZ)
		)
		return randomPos + Vector3.new(0, self.config.SPAWN_HEIGHT_OFFSET, 0)
	end

	-- Default: spawn at origin
	warn("[NPCSpawning] No valid spawn location method provided, using origin")
	return Vector3.new(0, self.config.SPAWN_HEIGHT_OFFSET, 0)
end

function NPCSpawning:ValidateSpawnLocation(position, options)
	-- Validate that a spawn location is safe and valid
	options = options or {}

	-- Check height (don't spawn underground)
	if position.Y < -50 then
		return false, "Position too low"
	end

	-- Check if position is inside existing structures (basic check)
	-- You could integrate with your collision system here

	-- Check spawn area restrictions
	if options.restrictToArea then
		local area = options.restrictToArea
		if position.X < area.minX or position.X > area.maxX or 
			position.Z < area.minZ or position.Z > area.maxZ then
			return false, "Position outside allowed area"
		end
	end

	return true, "Valid spawn location"
end

-- ========================================
-- CORE SPAWNING FUNCTIONS
-- ========================================

function NPCSpawning:SpawnNPC(npcType, team, owner, worldFolder, options)
	-- Spawn a single NPC
	options = options or {}

	-- Validate spawning
	local canSpawn, reason = self:CanSpawnNPC(npcType, team, owner, 1)
	if not canSpawn then
		warn("[NPCSpawning] Cannot spawn NPC:", reason)
		return nil
	end

	-- Prepare stats
	local stats = self:PrepareNPCStats(npcType, team, owner, options)
	if not stats then
		warn("[NPCSpawning] Failed to prepare NPC stats")
		return nil
	end

	-- Find spawn location
	local spawnPosition = self:FindSpawnLocation(options)
	local isValidLocation, locationError = self:ValidateSpawnLocation(spawnPosition, options)
	if not isValidLocation then
		warn("[NPCSpawning] Invalid spawn location:", locationError)
		return nil
	end

	-- Create NPC instance
	local npcInstance = self:CreateNPCInstance(stats, spawnPosition, worldFolder, options)
	if not npcInstance then
		warn("[NPCSpawning] Failed to create NPC instance")
		return nil
	end

	-- Register the NPC
	local success = self:RegisterSpawnedNPC(npcInstance, stats, options)
	if not success then
		warn("[NPCSpawning] Failed to register spawned NPC")
		npcInstance:Destroy()
		return nil
	end

	-- Create spawn effect
	if options.spawnEffect ~= false then
		self:CreateSpawnEffect(spawnPosition, options.spawnEffectType)
	end

	-- Update last spawn time
	self.lastSpawnTime = tick()

	if self.config.DEBUG_SPAWNING then
		print(string.format("[NPCSpawning] Spawned %s (ID: %s) at %s for %s", 
			npcType, stats.InstanceId, tostring(spawnPosition), owner or team))
	end

	return npcInstance, stats
end

function NPCSpawning:SpawnNPCBatch(spawnList, worldFolder, options)
	-- Spawn multiple NPCs with optional delays
	options = options or {}

	if self.isBatchSpawning then
		warn("[NPCSpawning] Batch spawn already in progress")
		return false
	end

	-- Validate total spawn count
	local totalCount = #spawnList
	local canSpawn, reason = self:CanSpawnNPC("SOLDIER", "Player", "System", totalCount)
	if not canSpawn then
		warn("[NPCSpawning] Cannot spawn batch:", reason)
		return false
	end

	-- Add to batch queue
	for _, spawnData in ipairs(spawnList) do
		table.insert(self.batchQueue, {
			npcType = spawnData.npcType,
			team = spawnData.team,
			owner = spawnData.owner,
			worldFolder = worldFolder,
			options = spawnData.options or {}
		})
	end

	-- Start batch spawning
	self:ProcessBatchQueue()

	return true
end

function NPCSpawning:ProcessBatchQueue()
	-- Process the batch spawn queue
	if self.isBatchSpawning then
		return
	end

	self.isBatchSpawning = true

	spawn(function()
		while #self.batchQueue > 0 do
			local spawnData = table.remove(self.batchQueue, 1)

			-- Spawn the NPC
			self:SpawnNPC(
				spawnData.npcType,
				spawnData.team,
				spawnData.owner,
				spawnData.worldFolder,
				spawnData.options
			)

			-- Wait before next spawn
			if #self.batchQueue > 0 then
				wait(self.config.BATCH_SPAWN_DELAY)
			end
		end

		self.isBatchSpawning = false
		print("[NPCSpawning] Batch spawning completed")
	end)
end

function NPCSpawning:CreateNPCInstance(stats, position, worldFolder, options)
	-- Create the actual NPC instance (you'll customize this for your NPC system)
	options = options or {}

	-- For now, create a simple part as placeholder
	-- You would replace this with your actual NPC creation system
	local npcInstance = Instance.new("Model")
	npcInstance.Name = stats.UnitType .. "_" .. stats.InstanceId

	-- Create main part
	local mainPart = Instance.new("Part")
	mainPart.Name = "HumanoidRootPart"
	mainPart.Size = Vector3.new(2, 5, 2)
	mainPart.Position = position
	mainPart.Anchored = false -- NPCs should be able to move
	mainPart.CanCollide = true
	mainPart.Color = stats.Team == "Player" and Color3.fromRGB(0, 0, 255) or Color3.fromRGB(255, 0, 0)
	mainPart.Parent = npcInstance

	-- Set primary part
	npcInstance.PrimaryPart = mainPart

	-- Add humanoid for movement
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.CurrentHealth
	humanoid.WalkSpeed = stats.MovementSpeed
	humanoid.Parent = npcInstance

	-- Add attributes
	npcInstance:SetAttribute("NPCType", stats.UnitType)
	npcInstance:SetAttribute("Team", stats.Team)
	npcInstance:SetAttribute("Owner", stats.Owner)
	npcInstance:SetAttribute("InstanceId", stats.InstanceId)
	npcInstance:SetAttribute("Health", stats.CurrentHealth)
	npcInstance:SetAttribute("MaxHealth", stats.Health)
	npcInstance:SetAttribute("DoesAtk", stats.DoesAtk)

	if stats.DoesAtk then
		npcInstance:SetAttribute("Range", stats.Range)
		npcInstance:SetAttribute("Attack", stats.Attack)
		npcInstance:SetAttribute("AtkSpeed", stats.AtkSpeed)
	end

	-- Parent to world
	npcInstance.Parent = worldFolder

	return npcInstance
end

function NPCSpawning:RegisterSpawnedNPC(npcInstance, stats, options)
	-- Register a spawned NPC for tracking
	local instanceId = stats.InstanceId

	-- Store NPC data
	self.spawnedNPCs[instanceId] = {
		instance = npcInstance,
		stats = stats,
		spawnTime = tick(),
		despawnTime = stats.CanDespawn and (tick() + stats.DespawnTime) or nil,
		options = options or {}
	}

	-- Track by team
	if not self.npcsByTeam[stats.Team] then
		self.npcsByTeam[stats.Team] = {}
	end
	table.insert(self.npcsByTeam[stats.Team], instanceId)

	-- Track by owner
	if stats.Owner then
		if not self.npcsByOwner[stats.Owner] then
			self.npcsByOwner[stats.Owner] = {}
		end
		table.insert(self.npcsByOwner[stats.Owner], instanceId)
	end

	-- Track by type
	local npcType = stats.UnitType or "Unknown"
	if not self.npcsByType[npcType] then
		self.npcsByType[npcType] = {}
	end
	table.insert(self.npcsByType[npcType], instanceId)

	-- Start despawn timer if applicable
	if stats.CanDespawn and stats.DespawnTime then
		self:StartDespawnTimer(instanceId)
	end

	return true
end

-- ========================================
-- SPAWN EFFECTS & VISUAL FEEDBACK
-- ========================================

function NPCSpawning:CreateSpawnEffect(position, effectType)
	-- Create visual/audio effects for spawning
	effectType = effectType or "Default"

	local effectId = tick() .. math.random(1000, 9999)

	-- Create basic spawn effect (customize for your game)
	local effect = Instance.new("Part")
	effect.Name = "SpawnEffect_" .. effectId
	effect.Size = Vector3.new(4, 0.1, 4)
	effect.Position = position
	effect.Anchored = true
	effect.CanCollide = false
	effect.Material = Enum.Material.Neon
	effect.Color = Color3.fromRGB(255, 255, 0)
	effect.Transparency = 0.5
	effect.Parent = workspace

	-- Store effect for cleanup
	self.activeSpawnEffects[effectId] = effect

	-- Animate and clean up effect
	spawn(function()
		local startTime = tick()
		local duration = 2 -- Effect duration in seconds

		while tick() - startTime < duration and effect.Parent do
			local progress = (tick() - startTime) / duration
			effect.Transparency = 0.5 + (progress * 0.5)
			effect.Size = Vector3.new(4 - (progress * 2), 0.1, 4 - (progress * 2))
			wait(0.1)
		end

		-- Clean up
		if effect.Parent then
			effect:Destroy()
		end
		self.activeSpawnEffects[effectId] = nil
	end)

	return effectId
end

-- ========================================
-- NPC MANAGEMENT & CLEANUP
-- ========================================

function NPCSpawning:StartDespawnTimer(instanceId)
	-- Start automatic despawn timer for an NPC
	local npcData = self.spawnedNPCs[instanceId]
	if not npcData or not npcData.despawnTime then
		return
	end

	spawn(function()
		local timeUntilDespawn = npcData.despawnTime - tick()

		if timeUntilDespawn > 0 then
			wait(timeUntilDespawn)
		end

		-- Check if NPC still exists and should be despawned
		if self.spawnedNPCs[instanceId] and npcData.stats.CanDespawn then
			self:DespawnNPC(instanceId, "Timer")
		end
	end)
end

function NPCSpawning:DespawnNPC(instanceId, reason)
	-- Remove an NPC from the world
	local npcData = self.spawnedNPCs[instanceId]
	if not npcData then
		return false
	end

	reason = reason or "Manual"

	-- Create despawn effect
	if npcData.instance and npcData.instance.PrimaryPart then
		self:CreateSpawnEffect(npcData.instance.PrimaryPart.Position, "Despawn")
	end

	-- Remove from tracking
	self:UnregisterNPC(instanceId)

	-- Destroy instance
	if npcData.instance and npcData.instance.Parent then
		npcData.instance:Destroy()
	end

	if self.config.DEBUG_SPAWNING then
		print(string.format("[NPCSpawning] Despawned NPC %s (reason: %s)", instanceId, reason))
	end

	return true
end

function NPCSpawning:UnregisterNPC(instanceId)
	-- Remove NPC from all tracking systems
	local npcData = self.spawnedNPCs[instanceId]
	if not npcData then
		return false
	end

	local stats = npcData.stats

	-- Remove from team tracking
	if self.npcsByTeam[stats.Team] then
		for i, id in ipairs(self.npcsByTeam[stats.Team]) do
			if id == instanceId then
				table.remove(self.npcsByTeam[stats.Team], i)
				break
			end
		end
	end

	-- Remove from owner tracking
	if stats.Owner and self.npcsByOwner[stats.Owner] then
		for i, id in ipairs(self.npcsByOwner[stats.Owner]) do
			if id == instanceId then
				table.remove(self.npcsByOwner[stats.Owner], i)
				break
			end
		end
	end

	-- Remove from type tracking
	local npcType = stats.UnitType or "Unknown"
	if self.npcsByType[npcType] then
		for i, id in ipairs(self.npcsByType[npcType]) do
			if id == instanceId then
				table.remove(self.npcsByType[npcType], i)
				break
			end
		end
	end

	-- Remove from main tracking
	self.spawnedNPCs[instanceId] = nil

	return true
end

-- ========================================
-- QUERY & UTILITY FUNCTIONS
-- ========================================

function NPCSpawning:GetNPCsByOwner(owner)
	-- Get all NPCs owned by a specific player
	return self.npcsByOwner[owner] or {}
end

function NPCSpawning:GetNPCsByTeam(team)
	-- Get all NPCs for a team
	return self.npcsByTeam[team] or {}
end

function NPCSpawning:GetNPCsByType(npcType)
	-- Get all NPCs of a specific type
	return self.npcsByType[npcType] or {}
end

function NPCSpawning:GetNPCData(instanceId)
	-- Get complete data for an NPC
	return self.spawnedNPCs[instanceId]
end

function NPCSpawning:GetTotalNPCCount()
	-- Get total count of all spawned NPCs
	local count = 0
	for _ in pairs(self.spawnedNPCs) do
		count = count + 1
	end
	return count
end

function NPCSpawning:GetNPCCount(team, npcType)
	-- Get count of NPCs for a team/type
	local count = 0

	if npcType then
		-- Count specific type
		for _, instanceId in ipairs(self:GetNPCsByType(npcType)) do
			local data = self.spawnedNPCs[instanceId]
			if data and data.stats.Team == team then
				count = count + 1
			end
		end
	else
		-- Count all for team
		count = #(self.npcsByTeam[team] or {})
	end

	return count
end

function NPCSpawning:ClearAllNPCs(team, reason)
	-- Clear all NPCs for a team (or all teams if team is nil)
	reason = reason or "Clear All"

	local instanceIds = {}

	if team then
		-- Clear specific team
		instanceIds = self:GetNPCsByTeam(team)
	else
		-- Clear all NPCs
		for instanceId in pairs(self.spawnedNPCs) do
			table.insert(instanceIds, instanceId)
		end
	end

	-- Despawn all collected NPCs
	local count = 0
	for _, instanceId in ipairs(instanceIds) do
		if self:DespawnNPC(instanceId, reason) then
			count = count + 1
		end
	end

	print(string.format("[NPCSpawning] Cleared %d NPCs (team: %s, reason: %s)", 
		count, team or "All", reason))

	return count
end

-- ========================================
-- PRESET SPAWN FUNCTIONS
-- ========================================

function NPCSpawning:SpawnWave(waveData, worldFolder, options)
	-- Spawn a wave of enemies
	options = options or {}

	local spawnList = {}

	for _, unit in ipairs(waveData.units) do
		for i = 1, unit.count do
			table.insert(spawnList, {
				npcType = unit.type,
				team = waveData.team or "Enemy",
				owner = waveData.owner or "AI",
				options = {
					spawnSource = "Wave",
					spawnMethod = "Batch",
					position = waveData.spawnPosition,
					range = waveData.spawnRange or 5,
					nearTarget = waveData.spawnPosition,
					despawnTime = options.waveDespawnTime or 120,
				}
			})
		end
	end

	return self:SpawnNPCBatch(spawnList, worldFolder, options)
end

function NPCSpawning:SpawnAroundPosition(npcType, team, owner, position, count, radius, worldFolder, options)
	-- Spawn multiple NPCs around a position
	options = options or {}

	local spawnList = {}

	for i = 1, count do
		-- Calculate random position in circle
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local distance = math.random() * radius

		local offsetPosition = position + Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)

		table.insert(spawnList, {
			npcType = npcType,
			team = team,
			owner = owner,
			options = {
				position = offsetPosition,
				spawnSource = "Circle",
				spawnMethod = "Batch",
			}
		})
	end

	return self:SpawnNPCBatch(spawnList, worldFolder, options)
end

-- ========================================
-- UNIT MODEL UTILITIES
-- ========================================

function NPCSpawning:GetUnitModel(npcType, team)
	-- Get the 3D model for a specific unit type and team
	local folder = team == "Player" and playerUnitsFolder or worldAIUnitsFolder

	local model = folder:FindFirstChild(npcType)
	if not model then
		warn("[NPCSpawning] Unit model not found:", npcType, "for team:", team)
		return nil
	end

	if not model:IsA("Model") then
		warn("[NPCSpawning] Found object is not a model:", npcType)
		return nil
	end

	return model
end

return NPCSpawning