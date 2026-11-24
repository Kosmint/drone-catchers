--!strict
-- Minimal state machine used by Mood, Expedition and Tutorial.
-- states = { Name = { enter = fn?, exit = fn?, update = fn(dt)? } }
local Signal = require(script.Parent.Signal)

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(states: { [string]: any }, initial: string)
	local self = setmetatable({
		states = states,
		current = initial,
		timeInState = 0,
		Changed = Signal.new(),
	}, StateMachine)
	local s = states[initial]
	if s and s.enter then s.enter(nil) end
	return self
end

function StateMachine.set(self: any, name: string, ...: any)
	if name == self.current then return end
	assert(self.states[name], "Unknown state: " .. name)
	local prev = self.current
	local old = self.states[prev]
	if old and old.exit then old.exit(name) end
	self.current = name
	self.timeInState = 0
	local new = self.states[name]
	if new.enter then new.enter(prev, ...) end
	self.Changed:Fire(name, prev)
end

function StateMachine.update(self: any, dt: number)
	self.timeInState += dt
	local s = self.states[self.current]
	if s and s.update then s.update(dt) end
end

function StateMachine.is(self: any, name: string): boolean
	return self.current == name
end

return StateMachine
