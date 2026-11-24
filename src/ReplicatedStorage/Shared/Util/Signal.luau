--!strict
-- Lightweight signal. Handlers run in their own thread (task.spawn) so one erroring
-- handler never breaks the others.
local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: any)
	if not self.Connected then return end
	self.Connected = false
	local handlers = self._signal._handlers
	local i = table.find(handlers, self)
	if i then table.remove(handlers, i) end
end

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local conn = setmetatable({ Connected = true, _signal = self, _fn = fn }, Connection)
	table.insert(self._handlers, conn)
	return conn :: any
end

function Signal.Once(self: any, fn: (...any) -> ()): Connection
	local conn
	conn = Signal.Connect(self, function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: any, ...: any)
	-- iterate a snapshot so handlers may disconnect while firing
	for _, conn in table.clone(self._handlers) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: any)
	for _, conn in self._handlers do conn.Connected = false end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
