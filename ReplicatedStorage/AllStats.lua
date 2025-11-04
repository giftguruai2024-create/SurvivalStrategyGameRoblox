-- @ScriptType: ModuleScript
-- AllStats Module
-- Place this in ReplicatedStorage and name it "AllStats"
-- Stores all statistics for NPCs and Structures for both Player and Enemy teams

local AllStats = {}

-- ========================================
-- STAT ARRAYS
-- ========================================

-- Player controlled units
AllStats.PlayerNPCs = {
	BUILDER = {
		Team = "Player",
		Owner = nil, -- Will be set when spawned
		Health = 80,
		DoesAtk = false, -- Builders don't fight
		MovementSpeed = 10, -- Fast for getting around
		UnitType = "Worker",
		Cost = {Wood = 15, Food = 5},
		SpawnTime = 4,
		-- Builder-specific properties
		CanBuild = true,
		BuildSpeed = 1.0, -- Speed multiplier for building
		BuildRange = 8, -- How close to blueprints they need to be
		CarryCapacity = 0, -- Builders don't carry resources
		-- Equipment system preparation
		EquipmentSlots = {"Tool"}, -- Only tools for builders
		DefaultEquipment = {
			Tool = "BASIC_HAMMER"
		},
		MaxEquipmentWeight = 10,
	},

	VILLAGER = {
		Team = "Player",
		Owner = nil,
		Health = 100,
		DoesAtk = true,
		Range = 4, -- Melee range when fighting
		Attack = 20, -- Base attack without equipment
		AtkSpeed = 1.2,
		MovementSpeed = 8,
		UnitType = "Worker",
		Cost = {Wood = 10, Food = 8},
		SpawnTime = 5,
		-- Villager-specific properties
		CanHarvest = true,
		HarvestSpeed = 1.0, -- Speed multiplier for resource gathering
		HarvestRange = 6, -- How close to resources they need to be
		CarryCapacity = 50, -- How many resources they can carry
		CanFight = true,
		-- Equipment system
		EquipmentSlots = {"Helm", "Chest", "Boots", "Weapon", "Tool"},
		DefaultEquipment = {
			Tool = "BASIC_PICKAXE",
			Weapon = "BASIC_SWORD"
		},
		MaxEquipmentWeight = 25,
		-- Resource preferences (what they prioritize harvesting)
		HarvestPreferences = {"Wood", "Stone", "Food", "Gold"},
	},
}

-- Player controlled structures/buildings
AllStats.PlayerStructures = {
	TOWNHALL = {
		Team = "Player",
		Owner = nil,
		Health = 500,
		DoesAtk = false,
		Spawner = true,
		SpawnTypes = {"VILLAGER", "BUILDER"}, -- Villager first for free spawn
		MaxQueue = 4,
		SpawnTimeMultiplier = 1.0,
		QueueCost = "Upfront", -- Players pay upfront
		AutoSpawn = false,
		PauseWhenFull = true,
		StructureType = "Main",
		Cost = {Wood = 100, Stone = 50},
		BuildTime = 60,
		CanBeAttacked = true,
	},

	BARRACKS = {
		Team = "Player",
		Owner = nil,
		Health = 300,
		DoesAtk = false,
		Spawner = true,
		SpawnTypes = {"VILLAGER"}, -- Only villagers for now, military units later
		MaxQueue = 5,
		SpawnTimeMultiplier = 1.0,
		QueueCost = "Upfront",
		AutoSpawn = false,
		PauseWhenFull = true,
		StructureType = "Military",
		Cost = {Wood = 80, Stone = 30},
		BuildTime = 45,
		CanBeAttacked = true,
	},

	TOWER = {
		Team = "Player",
		Owner = nil,
		Health = 250,
		DoesAtk = true,
		Range = 15,
		Attack = 40,
		AtkSpeed = 2.0,
		Spawner = false,
		StructureType = "Defense",
		Cost = {Wood = 60, Stone = 40, Gold = 10},
		BuildTime = 30,
		CanBeAttacked = true,
	},

	WALL = {
		Team = "Player",
		Owner = nil,
		Health = 150,
		DoesAtk = false,
		Spawner = false,
		StructureType = "Defense",
		Cost = {Stone = 20},
		BuildTime = 15,
		CanBeAttacked = true,
	},

	FARM = {
		Team = "Player",
		Owner = nil,
		Health = 100,
		DoesAtk = false,
		Spawner = false,
		ResourceGeneration = {Food = 2}, -- Per second
		StructureType = "Economy",
		Cost = {Wood = 40},
		BuildTime = 25,
		CanBeAttacked = true,
	},
}

-- Enemy controlled units
AllStats.EnemyNPCs = {
	GOBLIN = {
		Team = "Enemy",
		Owner = "AI",
		Health = 60,
		DoesAtk = true,
		Range = 4,
		Attack = 15,
		AtkSpeed = 1.8,
		MovementSpeed = 10,
		UnitType = "Infantry",
		SpawnTime = 2,
		AIBehavior = "Aggressive",
	},

	ORC_WARRIOR = {
		Team = "Enemy",
		Owner = "AI",
		Health = 150,
		DoesAtk = true,
		Range = 3,
		Attack = 35,
		AtkSpeed = 1.0,
		MovementSpeed = 6,
		UnitType = "Heavy",
		SpawnTime = 5,
		AIBehavior = "Defensive",
	},

	SKELETON_ARCHER = {
		Team = "Enemy",
		Owner = "AI",
		Health = 50,
		DoesAtk = true,
		Range = 10,
		Attack = 20,
		AtkSpeed = 1.5,
		MovementSpeed = 7,
		UnitType = "Ranged",
		SpawnTime = 3,
		AIBehavior = "Support",
	},
}

-- Enemy controlled structures
AllStats.EnemyStructures = {
	ENEMY_CAMP = {
		Team = "Enemy",
		Owner = "AI",
		Health = 400,
		DoesAtk = false,
		Spawner = true,
		SpawnTypes = {"GOBLIN", "ORC_WARRIOR"},
		MaxQueue = 3,
		SpawnTimeMultiplier = 0.8, -- AI spawns 20% faster
		QueueCost = "OnSpawn", -- AI doesn't pay upfront
		AutoSpawn = true, -- AI auto-queues units
		PauseWhenFull = false, -- AI doesn't pause
		AutoQueueInterval = 8, -- Auto-queue every 8 seconds
		PreferredSpawn = "GOBLIN", -- AI prefers this unit type
		StructureType = "Main",
		BuildTime = 45,
		CanBeAttacked = true,
		AIBehavior = "Spawner",
	},

	DARK_TOWER = {
		Team = "Enemy",
		Owner = "AI",
		Health = 200,
		DoesAtk = true,
		Range = 12,
		Attack = 30,
		AtkSpeed = 1.5,
		Spawner = false,
		StructureType = "Defense",
		BuildTime = 30,
		CanBeAttacked = true,
		AIBehavior = "Aggressive",
	},

	GOBLIN_HUT = {
		Team = "Enemy",
		Owner = "AI",
		Health = 120,
		DoesAtk = false,
		Spawner = true,
		SpawnTypes = {"GOBLIN"},
		MaxQueue = 2,
		SpawnTimeMultiplier = 1.2, -- Slower spawning
		QueueCost = "OnSpawn",
		AutoSpawn = true,
		PauseWhenFull = false,
		AutoQueueInterval = 12,
		PreferredSpawn = "GOBLIN",
		StructureType = "Military",
		BuildTime = 20,
		CanBeAttacked = true,
		AIBehavior = "Spawner",
	},
}

-- ========================================
-- RESOURCE SYSTEM DATA
-- ========================================

-- Resource definitions with harvest stats
AllStats.Resources = {
	WOOD = {
		Name = "Wood",
		Type = "WOOD",
		ModelName = "Tree", -- Name in ReplicatedStorage.Resources
		HarvestTime = 3, -- Seconds to harvest
		HarvestAmount = {min = 8, max = 15}, -- Amount gained per harvest
		MaxHarvests = 3, -- How many times can be harvested before depleting
		RespawnTime = 120, -- Seconds to respawn after depletion (2 minutes)
		SpawnWeight = 35, -- Relative spawn frequency
		RequiredTool = "Pickaxe", -- What tool is needed (optional)
		HarvestSound = "ChopWood", -- Sound to play when harvesting
		DepletedModel = "TreeStump", -- Model to show when depleted (optional)
		StorageType = "Wood", -- How it's stored in town hall
		Description = "Basic building material from trees",
		Value = 1, -- Base value for trading
	},

	STONE = {
		Name = "Stone", 
		Type = "STONE",
		ModelName = "Rock",
		HarvestTime = 4, -- Takes longer to mine
		HarvestAmount = {min = 5, max = 12},
		MaxHarvests = 4, -- Rocks last longer
		RespawnTime = 180, -- 3 minutes
		SpawnWeight = 25,
		RequiredTool = "Pickaxe",
		HarvestSound = "MineStone",
		DepletedModel = "RockRubble",
		StorageType = "Stone",
		Description = "Durable material for construction",
		Value = 2,
	},

	FOOD = {
		Name = "Food",
		Type = "FOOD", 
		ModelName = "Food",
		HarvestTime = 2, -- Quick to gather
		HarvestAmount = {min = 3, max = 8},
		MaxHarvests = 2, -- Food sources deplete quickly
		RespawnTime = 90, -- 1.5 minutes - food respawns fast
		SpawnWeight = 30,
		RequiredTool = nil, -- No tool needed
		HarvestSound = "GatherFood",
		DepletedModel = nil, -- Just disappears
		StorageType = "Food",
		Description = "Sustains your population",
		Value = 1,
	},

	GOLD = {
		Name = "Gold",
		Type = "GOLD",
		ModelName = "Gold", 
		HarvestTime = 5, -- Takes time to extract
		HarvestAmount = {min = 2, max = 6},
		MaxHarvests = 5, -- Gold veins last long
		RespawnTime = 300, -- 5 minutes - rare resource
		SpawnWeight = 10, -- Rare spawn
		RequiredTool = "Pickaxe",
		HarvestSound = "MineGold",
		DepletedModel = "GoldVeinEmpty",
		StorageType = "Gold",
		Description = "Precious metal for advanced upgrades",
		Value = 5,
	},
}

-- ========================================
-- EQUIPMENT SYSTEM DATA
-- ========================================

-- Equipment definitions
AllStats.Equipment = {
	-- Tools
	BASIC_HAMMER = {
		Name = "Basic Hammer",
		Type = "Tool",
		Slot = "Tool",
		Weight = 3,
		Effects = {
			BuildSpeed = 1.0, -- No bonus
		},
		RequiredLevel = 1,
		Durability = 100,
		Value = 10,
	},

	IRON_HAMMER = {
		Name = "Iron Hammer",
		Type = "Tool",
		Slot = "Tool", 
		Weight = 5,
		Effects = {
			BuildSpeed = 1.5, -- 50% faster building
		},
		RequiredLevel = 3,
		Durability = 200,
		Value = 30,
	},

	BASIC_PICKAXE = {
		Name = "Basic Pickaxe",
		Type = "Tool",
		Slot = "Tool",
		Weight = 4,
		Effects = {
			HarvestSpeed = 1.0, -- No bonus
			HarvestBonus = 0, -- No extra resources
		},
		RequiredLevel = 1,
		Durability = 80,
		Value = 15,
	},

	IRON_PICKAXE = {
		Name = "Iron Pickaxe", 
		Type = "Tool",
		Slot = "Tool",
		Weight = 6,
		Effects = {
			HarvestSpeed = 1.3, -- 30% faster harvesting
			HarvestBonus = 1, -- +1 extra resource per harvest
		},
		RequiredLevel = 2,
		Durability = 150,
		Value = 40,
	},

	-- Weapons
	BASIC_SWORD = {
		Name = "Basic Sword",
		Type = "Weapon",
		Slot = "Weapon",
		Weight = 5,
		Effects = {
			Attack = 15, -- Base attack bonus
			AtkSpeed = 1.0, -- No speed bonus
			Range = 4, -- Melee range
		},
		RequiredLevel = 1,
		Durability = 120,
		Value = 25,
	},

	IRON_SWORD = {
		Name = "Iron Sword",
		Type = "Weapon",
		Slot = "Weapon",
		Weight = 7,
		Effects = {
			Attack = 25,
			AtkSpeed = 1.1,
			Range = 4,
		},
		RequiredLevel = 3,
		Durability = 200,
		Value = 60,
	},

	-- Armor - Helms
	LEATHER_HELM = {
		Name = "Leather Helm",
		Type = "Armor",
		Slot = "Helm",
		Weight = 2,
		Effects = {
			Defense = 5, -- Damage reduction
			Health = 10, -- Health bonus
		},
		RequiredLevel = 1,
		Durability = 80,
		Value = 20,
	},

	IRON_HELM = {
		Name = "Iron Helm",
		Type = "Armor",
		Slot = "Helm",
		Weight = 4,
		Effects = {
			Defense = 12,
			Health = 20,
		},
		RequiredLevel = 4,
		Durability = 150,
		Value = 50,
	},

	-- Armor - Chest
	LEATHER_CHEST = {
		Name = "Leather Chestplate",
		Type = "Armor",
		Slot = "Chest",
		Weight = 6,
		Effects = {
			Defense = 15,
			Health = 25,
		},
		RequiredLevel = 1,
		Durability = 100,
		Value = 40,
	},

	IRON_CHEST = {
		Name = "Iron Chestplate",
		Type = "Armor",
		Slot = "Chest",
		Weight = 10,
		Effects = {
			Defense = 30,
			Health = 50,
		},
		RequiredLevel = 4,
		Durability = 200,
		Value = 100,
	},

	-- Armor - Boots
	LEATHER_BOOTS = {
		Name = "Leather Boots",
		Type = "Armor",
		Slot = "Boots",
		Weight = 3,
		Effects = {
			Defense = 8,
			MovementSpeed = 1, -- +1 speed bonus
		},
		RequiredLevel = 1,
		Durability = 90,
		Value = 25,
	},

	IRON_BOOTS = {
		Name = "Iron Boots",
		Type = "Armor",
		Slot = "Boots",
		Weight = 5,
		Effects = {
			Defense = 18,
			MovementSpeed = 0, -- No speed bonus due to weight
		},
		RequiredLevel = 4,
		Durability = 180,
		Value = 65,
	},
}

-- ========================================
-- BEHAVIOR DEFINITIONS (Future Implementation)
-- ========================================

-- AI Behavior templates for future use
AllStats.Behaviors = {
	BUILDER_AI = {
		Priority = "BuildBlueprints", -- Main goal
		SearchRadius = 50, -- How far to look for blueprints
		IdleBehavior = "ReturnToTownHall", -- What to do when no blueprints
		AvoidCombat = true, -- Builders run from enemies
		WorkHours = {6, 18}, -- Only work during day hours (6 AM to 6 PM)
	},

	VILLAGER_HARVEST = {
		Priority = "HarvestResources",
		SearchRadius = 30,
		IdleBehavior = "PatrolNearby",
		AvoidCombat = false, -- Villagers will fight if needed
		ReturnWhenFull = true, -- Return to drop off resources when carry is full
		FightWhenAttacked = true,
	},

	VILLAGER_GUARD = {
		Priority = "DefendArea",
		SearchRadius = 20,
		IdleBehavior = "PatrolArea",
		AvoidCombat = false,
		AggroRange = 15, -- How close enemies need to be to attack
		ChaseRange = 25, -- How far to chase enemies
	},
}

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

function AllStats:GetStatsByType(category, statType)
	-- Get stats for a specific unit/structure type
	-- category: "PlayerNPCs", "PlayerStructures", "EnemyNPCs", "EnemyStructures"
	-- statType: The specific type (e.g., "BUILDER", "TOWNHALL")

	if not self[category] then
		warn("[AllStats] Invalid category:", category)
		return nil
	end

	if not self[category][statType] then
		warn("[AllStats] Invalid stat type '" .. statType .. "' in category '" .. category .. "'")
		return nil
	end

	-- Return a deep copy to prevent accidental modification
	local stats = {}
	for key, value in pairs(self[category][statType]) do
		stats[key] = value
	end

	return stats
end

function AllStats:GetAllByCategory(category)
	-- Get all stats in a category
	if not self[category] then
		warn("[AllStats] Invalid category:", category)
		return nil
	end

	return self[category]
end

function AllStats:GetStructureStats(structureType, team)
	-- Get structure stats by type and team
	team = team or "Player"

	local category = team == "Player" and "PlayerStructures" or "EnemyStructures"
	return self:GetStatsByType(category, structureType)
end

function AllStats:GetNPCStats(npcType, team)
	-- Get NPC stats by type and team
	team = team or "Player"

	local category = team == "Player" and "PlayerNPCs" or "EnemyNPCs"
	return self:GetStatsByType(category, npcType)
end

function AllStats:IsValidStructure(structureType, team)
	-- Check if a structure type exists for the given team
	team = team or "Player"
	local category = team == "Player" and "PlayerStructures" or "EnemyStructures"

	return self[category] and self[category][structureType] ~= nil
end

function AllStats:IsValidNPC(npcType, team)
	-- Check if an NPC type exists for the given team
	team = team or "Player"
	local category = team == "Player" and "PlayerNPCs" or "EnemyNPCs"

	return self[category] and self[category][npcType] ~= nil
end

function AllStats:CanStructureSpawn(structureType, team)
	-- Check if a structure can spawn units
	local stats = self:GetStructureStats(structureType, team)
	return stats and stats.Spawner == true
end

function AllStats:GetSpawnableUnits(structureType, team)
	-- Get list of units a structure can spawn
	local stats = self:GetStructureStats(structureType, team)
	if stats and stats.Spawner and stats.SpawnTypes then
		return stats.SpawnTypes
	end
	return {}
end

function AllStats:CreateInstance(category, statType, owner)
	-- Create an instance with stats (useful for spawning)
	local baseStats = self:GetStatsByType(category, statType)
	if not baseStats then
		return nil
	end

	-- Set owner if provided
	if owner then
		baseStats.Owner = owner
	end

	-- Add instance-specific data
	baseStats.InstanceId = tick() .. math.random(1000, 9999) -- Unique ID
	baseStats.CurrentHealth = baseStats.Health -- Track current health separately
	baseStats.SpawnTime = tick() -- When this instance was created

	return baseStats
end

function AllStats:GetTeamStructures(team)
	-- Get all structures for a specific team
	local category = team == "Player" and "PlayerStructures" or "EnemyStructures"
	return self:GetAllByCategory(category)
end

function AllStats:GetTeamNPCs(team)
	-- Get all NPCs for a specific team
	local category = team == "Player" and "PlayerNPCs" or "EnemyNPCs"
	return self:GetAllByCategory(category)
end

-- ========================================
-- EQUIPMENT UTILITY FUNCTIONS
-- ========================================

function AllStats:GetEquipmentBySlot(slot)
	-- Get all equipment that can be equipped in a specific slot
	local equipment = {}

	for equipId, equipData in pairs(self.Equipment) do
		if equipData.Slot == slot then
			equipment[equipId] = equipData
		end
	end

	return equipment
end

function AllStats:GetEquipmentByType(equipType)
	-- Get all equipment of a specific type (Tool, Weapon, Armor)
	local equipment = {}

	for equipId, equipData in pairs(self.Equipment) do
		if equipData.Type == equipType then
			equipment[equipId] = equipData
		end
	end

	return equipment
end

function AllStats:IsValidEquipment(equipmentId)
	-- Check if equipment exists
	return self.Equipment[equipmentId] ~= nil
end

function AllStats:GetEquipmentEffects(equipmentId)
	-- Get the effects of a specific piece of equipment
	local equipment = self.Equipment[equipmentId]
	return equipment and equipment.Effects or {}
end

function AllStats:CalculateEquipmentWeight(equippedItems)
	-- Calculate total weight of equipped items
	local totalWeight = 0

	for _, equipmentId in pairs(equippedItems) do
		local equipment = self.Equipment[equipmentId]
		if equipment then
			totalWeight = totalWeight + equipment.Weight
		end
	end

	return totalWeight
end

function AllStats:CanEquipItem(npcType, team, equipmentId, currentEquipment)
	-- Check if an NPC can equip a specific item
	local npcStats = self:GetNPCStats(npcType, team)
	local equipment = self.Equipment[equipmentId]

	if not npcStats or not equipment then
		return false, "Invalid NPC or equipment"
	end

	-- Check if NPC has the required slot
	local hasSlot = false
	for _, slot in ipairs(npcStats.EquipmentSlots) do
		if slot == equipment.Slot then
			hasSlot = true
			break
		end
	end

	if not hasSlot then
		return false, "NPC cannot equip items in " .. equipment.Slot .. " slot"
	end

	-- Check weight limit
	currentEquipment = currentEquipment or {}
	local currentWeight = self:CalculateEquipmentWeight(currentEquipment)
	local newWeight = currentWeight + equipment.Weight

	-- Subtract weight of item being replaced
	if currentEquipment[equipment.Slot] then
		local oldEquipment = self.Equipment[currentEquipment[equipment.Slot]]
		if oldEquipment then
			newWeight = newWeight - oldEquipment.Weight
		end
	end

	if newWeight > npcStats.MaxEquipmentWeight then
		return false, "Would exceed weight limit"
	end

	return true, "Can equip item"
end

function AllStats:PrintAllStats()
	-- Debug function to print all stats
	print("=== ALL STATS ===")
	for category, data in pairs(self) do
		if type(data) == "table" and category ~= "PrintAllStats" then
			print("\n" .. category .. ":")
			for statType, stats in pairs(data) do
				print("  " .. statType .. ":")
				for key, value in pairs(stats) do
					print("    " .. key .. ": " .. tostring(value))
				end
			end
		end
	end
	print("==================")
end

-- ========================================
-- RESOURCE UTILITY FUNCTIONS
-- ========================================

function AllStats:GetResourceStats(resourceType)
	-- Get stats for a specific resource type
	if not self.Resources[resourceType] then
		warn("[AllStats] Invalid resource type:", resourceType)
		return nil
	end

	-- Return a deep copy to prevent accidental modification
	local stats = {}
	for key, value in pairs(self.Resources[resourceType]) do
		if type(value) == "table" then
			stats[key] = {}
			for k, v in pairs(value) do
				stats[key][k] = v
			end
		else
			stats[key] = value
		end
	end

	return stats
end

function AllStats:CreateResourceInstance(resourceType)
	-- Create a resource instance with unique ID and current state
	local baseStats = self:GetResourceStats(resourceType)
	if not baseStats then
		return nil
	end

	-- Add instance-specific data
	baseStats.ResourceId = tick() .. math.random(1000, 9999) -- Unique ID
	baseStats.CurrentHarvests = 0 -- How many times harvested
	baseStats.IsActive = true -- Can be harvested
	baseStats.SpawnTime = tick() -- When this instance was created
	baseStats.LastHarvestTime = 0 -- When last harvested

	return baseStats
end

function AllStats:GetResourceModelName(resourceType)
	-- Get the model name for a resource type
	local stats = self.Resources[resourceType]
	return stats and stats.ModelName or nil
end

function AllStats:GetAllResourceTypes()
	-- Get list of all available resource types
	local types = {}
	for resourceType, _ in pairs(self.Resources) do
		table.insert(types, resourceType)
	end
	return types
end

function AllStats:GetResourceSpawnWeights()
	-- Get spawn weights for all resources (for random spawning)
	local weights = {}
	for resourceType, stats in pairs(self.Resources) do
		weights[resourceType] = stats.SpawnWeight or 1
	end
	return weights
end

function AllStats:CalculateHarvestAmount(resourceType, toolBonus)
	-- Calculate harvest amount with randomness and tool bonuses
	local stats = self.Resources[resourceType]
	if not stats then
		return 0
	end

	toolBonus = toolBonus or 0
	local baseAmount = math.random(stats.HarvestAmount.min, stats.HarvestAmount.max)
	return baseAmount + toolBonus
end

function AllStats:IsResourceDepleted(resourceInstance)
	-- Check if a resource instance is depleted
	if not resourceInstance then
		return true
	end

	return resourceInstance.CurrentHarvests >= resourceInstance.MaxHarvests
end

function AllStats:CanRespawnResource(resourceInstance)
	-- Check if a depleted resource can respawn
	if not resourceInstance or resourceInstance.IsActive then
		return false
	end

	local timeSinceDepletion = tick() - (resourceInstance.DepletionTime or 0)
	return timeSinceDepletion >= resourceInstance.RespawnTime
end

return AllStats