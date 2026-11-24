--!strict
-- Trove: collects things that need cleanup (connections, instances, functions,
-- threads, objects with :Destroy) and cleans them all at once. Every controller
-- owns a Trove so nothing leaks between runs.
local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({ _items = {} :: { any } }, Trove)
end

function Trove.Add<T>(self: any, item: T): T
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: any, signal: any, fn: (...any) -> ())
	return Trove.Add(self, signal:Connect(fn))
end

function Trove.Extend(self: any)
	return Trove.Add(self, Trove.new())
end

local function cleanup(item: any)
	local t = typeof(item)
	if t == "RBXScriptConnection" then
		item:Disconnect()
	elseif t == "Instance" then
		item:Destroy()
	elseif t == "function" then
		item()
	elseif t == "thread" then
		pcall(task.cancel, item)
	elseif t == "table" then
		if typeof(item.Destroy) == "function" then
			item:Destroy()
		elseif typeof(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.Clean(self: any)
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		local ok, err = pcall(cleanup, items[i])
		if not ok then warn("[Trove] cleanup failed:", err) end
	end
end

Trove.Destroy = Trove.Clean

return Trove
