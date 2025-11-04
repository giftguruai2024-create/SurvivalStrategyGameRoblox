-- @ScriptType: ModuleScript
-- EventBus
-- Centralized RemoteEvent/RemoteFunction creation and access

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = {}

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local functionsFolder = ReplicatedStorage:FindFirstChild("Functions")
if not functionsFolder then
	functionsFolder = Instance.new("Folder")
	functionsFolder.Name = "Functions"
	functionsFolder.Parent = ReplicatedStorage
end

local VALID_CLASSES = {
	RemoteEvent = true,
	RemoteFunction = true,
}

local function getOrCreateSignal(name, className)
	className = className or "RemoteEvent"
	assert(VALID_CLASSES[className], string.format("Unsupported remote class: %s", tostring(className)))

	local container = className == "RemoteFunction" and functionsFolder or eventsFolder
	local existing = container:FindFirstChild(name)
	if existing then
		return existing
	end

	local signal = Instance.new(className)
	signal.Name = name
	signal.Parent = container
	return signal
end

function EventBus.Initialize(definitions)
	for name, className in pairs(definitions) do
		getOrCreateSignal(name, className)
	end
end

function EventBus.GetRemote(name)
	return getOrCreateSignal(name, "RemoteEvent")
end

function EventBus.GetFunction(name)
	return getOrCreateSignal(name, "RemoteFunction")
end

function EventBus.GetEventsFolder()
	return eventsFolder
end

function EventBus.GetFunctionsFolder()
	return functionsFolder
end

return EventBus

