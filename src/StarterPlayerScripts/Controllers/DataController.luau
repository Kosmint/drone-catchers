--!strict
-- DataController: the client's read-only copy of its own profile.
-- UI reads from here and listens to Changed; it never edits data (server decides).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataController = {}
DataController.Loaded = Signal.new()   -- (data)
DataController.Changed = Signal.new()  -- (key, value)

local data: any = nil

function DataController.get(): any
	return data
end

-- yields until the first snapshot arrives
function DataController.wait(): any
	while not data do DataController.Loaded:Wait() end
	return data
end

function DataController.init()
	Net.on("DataSnapshot", function(snapshot)
		local first = data == nil
		data = snapshot
		if first then
			DataController.Loaded:Fire(data)
		else
			for key, value in snapshot do DataController.Changed:Fire(key, value) end
		end
	end)
	Net.on("DataChanged", function(key, value)
		if not data then return end
		data[key] = value
		DataController.Changed:Fire(key, value)
	end)
end

function DataController.start()
	-- in case the snapshot was sent before our listener connected
	task.delay(5, function()
		if not data then Net.fire("RequestSnapshot") end
	end)
end

return DataController
