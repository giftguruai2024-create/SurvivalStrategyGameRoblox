-- @ScriptType: ModuleScript
-- GameCatalog
-- Provides authoritative access to stats definitions and asset models

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameCatalog = {}

local AllStats = require(ReplicatedStorage:WaitForChild("AllStats"))

local function getFolder(name)
	local folder = ReplicatedStorage:FindFirstChild(name)
	if not folder then
		warn(string.format("[GameCatalog] Folder '%s' not found in ReplicatedStorage", tostring(name)))
	end
	return folder
end

local function cloneTable(source)
	if typeof(source) ~= "table" then
		return source
	end

	local copy = {}
	for key, value in pairs(source) do
		copy[key] = cloneTable(value)
	end
	return copy
end

function GameCatalog.GetStructureDefinition(structureId, team)
	team = team or "Player"
	local stats = AllStats:GetStructureStats(structureId, team)
	return stats and cloneTable(stats) or nil
end

function GameCatalog.GetNPCDefinition(npcType, team)
	team = team or "Player"
	local stats = AllStats:GetNPCStats(npcType, team)
	return stats and cloneTable(stats) or nil
end

function GameCatalog.GetResourceDefinition(resourceType)
	local stats = AllStats:GetResourceStats(resourceType)
	return stats and cloneTable(stats) or nil
end

function GameCatalog.CreateInstance(category, id, owner)
	return AllStats:CreateInstance(category, id, owner)
end

function GameCatalog.GetStructureModel(structureId)
	local structuresFolder = getFolder("Structures")
	return structuresFolder and structuresFolder:FindFirstChild(structureId) or nil
end

function GameCatalog.GetUnitModel(team, npcType)
	local unitsFolder = getFolder("Units")
	if not unitsFolder then
		return nil
	end

	local teamFolder = unitsFolder:FindFirstChild(team)
	if not teamFolder then
		warn(string.format("[GameCatalog] Team folder '%s' missing under Units", tostring(team)))
		return nil
	end

	local model = teamFolder:FindFirstChild(npcType)
	if not model then
		warn(string.format("[GameCatalog] Unit model '%s' missing under Units/%s", tostring(npcType), tostring(team)))
	end
	return model
end

function GameCatalog.GetResourceModel(resourceType)
	local resourcesFolder = getFolder("Resources")
	if not resourcesFolder then
		return nil
	end

	local model = resourcesFolder:FindFirstChild(resourceType)
	if not model then
		warn(string.format("[GameCatalog] Resource model '%s' missing under Resources", tostring(resourceType)))
	end
	return model
end

function GameCatalog.GetAllStatsModule()
	return AllStats
end

return GameCatalog

