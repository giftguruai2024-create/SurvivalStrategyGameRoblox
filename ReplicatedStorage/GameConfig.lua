-- @ScriptType: ModuleScript
-- GameConfig
-- Centralized configuration for grid, placement, time, spawning, and camera defaults

local GameConfig = {}

local function deepCopy(source)
	if typeof(source) ~= "table" then
		return source
	end

	local copy = {}
	for key, value in pairs(source) do
		copy[key] = deepCopy(value)
	end
	return copy
end

local GRID = {
	GRID_SIZE = 30,
	CELL_SIZE = 3,
	BEACH_THICKNESS = 2,
	MIN_SPAWN_DISTANCE = 10,
}

local PLACEMENT = {
	CELL_SIZE = GRID.CELL_SIZE,
	PLACEMENT_HEIGHT_OFFSET = 0,
	DEBUG_PLACEMENT = true,
}

local TIME = {
	DAY_LENGTH = 600,
	START_TIME = 6,
	TIME_SCALE = 1,
}

local SPAWN = {
	CHECK_INTERVAL = 5,
	RESOURCE_HEIGHT_OFFSET = 2,
	ENABLE_AUTO_SPAWN = true,
	MAX_PER_CELL = 1,
}

local CAMERA = {
	INITIAL_HEIGHT = 50,
	MIN_ZOOM = 20,
	MAX_ZOOM = 100,
	CAMERA_SPEED = 0.5,
	ZOOM_SPEED = 2,
	ROTATION_SPEED = 1,
}

function GameConfig.GetGrid()
	return deepCopy(GRID)
end

function GameConfig.GetPlacement()
	return deepCopy(PLACEMENT)
end

function GameConfig.GetTime()
	return deepCopy(TIME)
end

function GameConfig.GetSpawn()
	return deepCopy(SPAWN)
end

function GameConfig.GetCamera()
	return deepCopy(CAMERA)
end

return GameConfig
