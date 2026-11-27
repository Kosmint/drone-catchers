--!strict
-- Unit tests for Shared/SpawnWindow (pure Luau, no Roblox).
-- Run from the repo root:  lune run scripts/tests/SpawnWindow.spec.luau
-- Exits with code 1 if a test fails.

local SpawnWindow = require("../../src/ReplicatedStorage/Shared/SpawnWindow")

local SWARM_MIN, SWARM_MAX = 3, 5 -- Balance.spawns
local failures = 0

local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

type Entry = { index: number, group: number }

-- tiny seeded RNG (lune has no Roblox Random)
type Rng = { NextNumber: (Rng) -> number, NextInteger: (Rng, number, number) -> number, state: number }
local function newRng(seed: number): Rng
	local r = { state = seed } :: any
	function r.NextNumber(self: Rng): number
		self.state = (self.state * 48271) % 2147483647 -- MINSTD, exact in doubles
		return (self.state - 1) / 2147483646
	end
	function r.NextInteger(self: Rng, lo: number, hi: number): number
		return lo + math.floor(self:NextNumber() * (hi - lo + 1))
	end
	return r
end

-- queue like SpawnGen: singles and swarms of 3-5 in a row, `swarmShare` = chance of a swarm
local function makeQueue(rng: Rng, length: number, swarmShare: number): { Entry }
	local q: { Entry } = {}
	local group = 0
	while #q < length do
		group += 1
		local count = if rng:NextNumber() < swarmShare then rng:NextInteger(SWARM_MIN, SWARM_MAX) else 1
		for _ = 1, count do
			table.insert(q, { index = #q + 1, group = group })
		end
	end
	return q
end

-- advance / initial on a fixed queue: groups 1(single) 2(x3) 3(single) 4(x5) 5(single)
do
	local groups = { 1, 2, 2, 2, 3, 4, 4, 4, 4, 4, 5 }
	local q: { Entry } = {}
	for i, g in groups do q[i] = { index = i, group = g } end
	check(SpawnWindow.advance(q, 1) == 2, "single advances by 1")
	check(SpawnWindow.advance(q, 2) == 5, "swarm of 3 advances by 3")
	check(SpawnWindow.advance(q, 6) == 11, "swarm of 5 advances by 5")
	check(SpawnWindow.advance(q, 11) == 12, "last entry")
	check(SpawnWindow.advance(q, 12) == 12, "used-up queue stays")
	check(SpawnWindow.initial(q, 3) == 5, "initial: swarm straddling the limit comes in whole")
	check(SpawnWindow.initial(q, 5) == 6, "initial: exact boundary")
	check(SpawnWindow.initial(q, 50) == 12, "initial: queue shorter than active")
end

-- simulated runs: the client activates/catches like CreatureSimClient, the server
-- checks like ExpeditionService. No client-active spawn may ever fall outside the window.
do
	local rng = newRng(71)
	local oldRuleFailed = false
	for run = 1, 300 do
		local active = rng:NextInteger(4, 30)
		local q = makeQueue(rng, active * 4, if run % 3 == 0 then 1 else 0.5)
		-- client
		local clientNext = SpawnWindow.initial(q, active)
		local live: { number } = {}
		for i = 1, clientNext - 1 do table.insert(live, i) end
		-- server
		local serverNext = SpawnWindow.initial(q, active)
		local caught = 0
		while #live > 0 do
			local pick = rng:NextInteger(1, #live)
			local index = live[pick]
			check(SpawnWindow.allows(index, serverNext, SWARM_MAX),
				("run %d: active spawn %d rejected (window next %d)"):format(run, index, serverNext))
			-- the old rule (index <= active + caught + swarmMax) for comparison
			if index > active + caught + SWARM_MAX then oldRuleFailed = true end
			-- every spawn the client has out must be inside the window, not just the caught one
			for _, other in live do
				check(SpawnWindow.allows(other, serverNext, SWARM_MAX),
					("run %d: live spawn %d outside window (next %d)"):format(run, other, serverNext))
			end
			-- accepted: both sides advance one whole group
			caught += 1
			serverNext = SpawnWindow.advance(q, serverNext)
			table.remove(live, pick)
			local from = clientNext
			clientNext = SpawnWindow.advance(q, clientNext)
			for i = from, clientNext - 1 do table.insert(live, i) end
			check(serverNext == clientNext, ("run %d: client/server next differ"):format(run))
		end
	end
	check(oldRuleFailed, "the old per-catch rule should fail these runs (bug #71 reproduced)")
end

-- jumps far ahead are still rejected
do
	check(not SpawnWindow.allows(20 + SWARM_MAX, 20, SWARM_MAX), "next + slack rejected")
	check(SpawnWindow.allows(20 + SWARM_MAX - 1, 20, SWARM_MAX), "inside slack accepted")
	check(not SpawnWindow.allows(500, 20, SWARM_MAX), "far jump rejected")
	check(not SpawnWindow.allows(0, 20, SWARM_MAX), "index 0 rejected")
end

if failures > 0 then
	print(("%d test(s) failed"):format(failures))
	local process = require("@lune/process")
	process.exit(1)
end
print("SpawnWindow: all tests passed")
