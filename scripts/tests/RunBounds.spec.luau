--!strict
-- Unit tests for Shared/RunBounds (run with lune).
-- Run from the repo root:  lune run scripts/tests/RunBounds.spec.luau
-- Exits with code 1 if a test fails.

local process = require("@lune/process")
local MockShared = require("./lib/MockShared")

local mock = MockShared.create()
local Shared = mock.Shared
local Balance = mock.require(Shared.Config.Balance)
local Upgrades = mock.require(Shared.Config.Upgrades)
local Rarities = mock.require(Shared.Config.Rarities)
local RunBounds = mock.require(Shared.RunBounds)
local F = Balance.flight
local E = Balance.expedition

local failures = 0

local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local speed = Upgrades.drone.speed
local range = Upgrades.drone.beamRange
local strength = Upgrades.drone.beamStrength
local EDGE_FROM, SUNSET_FROM = 400 + 6, 200 + 6 -- SpawnGen zone plan `from` (zone.from + 6)

-- legit flight: the same integration as FlightController.update, full throttle up,
-- from deploy. The real drone can never be above this curve.
local function simulateClimb(speedMult: number, seconds: number, dt: number): { number }
	local y, vy, t = F.deployAltitude, F.deploySpeed, 0
	local heights = {}
	local steps = math.floor(seconds / dt + 0.5)
	for i = 1, steps do
		t += dt
		local thin = if y > F.thinAirAltitude then F.thinAirAccelMult else 1
		vy += F.accel * speedMult * thin * dt
		vy *= math.exp(-F.drag * dt)
		vy += math.sin(t * F.bobFrequency) * F.bobAmplitude * dt
		local maxV = F.maxSpeed * speedMult
		if vy > maxV then vy = maxV end
		y += vy * dt
		heights[i] = y
	end
	return heights
end

-- the bound is never below a real full-speed climb (any speed level, any frame rate)
do
	for _, lvl in { 1, 10, speed.maxLevel } do
		local mult = speed.value(lvl)
		for _, dt in { 1 / 240, 1 / 60, 1 / 20 } do
			local heights = simulateClimb(mult, 60, dt)
			for i, y in heights do
				local t = i * dt
				if y > RunBounds.maxReach(t, mult) then
					check(false, ("speed %d dt %.3f: real climb %.1f above bound %.1f at %.2f s"):format(lvl, dt, y, RunBounds.maxReach(t, mult), t))
					break
				end
			end
		end
	end
end

-- a real flight to the bottom of Edge of Space is accepted the moment the beam can reach it
do
	for _, sl in { 1, speed.maxLevel } do
		for _, rl in { 1, range.maxLevel } do
			local mult, r = speed.value(sl), range.value(rl)
			local dt = 1 / 60
			local heights = simulateClimb(mult, 60, dt)
			for i, y in heights do
				if y + r >= EDGE_FROM then
					check(RunBounds.canReachZone(EDGE_FROM, i * dt, mult, r),
						("speed %d range %d: legit Edge catch at %.2f s rejected"):format(sl, rl, i * dt))
					break
				end
			end
		end
	end
end

-- the old hole: Edge of Space 1 s after launch is rejected, even at max speed + range
do
	local mult, r = speed.value(speed.maxLevel), range.value(range.maxLevel)
	check(not RunBounds.canReachZone(EDGE_FROM, 1, mult, r), "Edge catch 1 s after launch rejected (max stats)")
	check(not RunBounds.canReachZone(EDGE_FROM, 3, speed.value(1), range.value(1)), "Edge catch 3 s after launch rejected (base stats)")
	check(not RunBounds.canReachZone(EDGE_FROM, 0, mult, r), "Edge catch at t=0 rejected")
	-- Low Sky and Sunset Heights start inside deploy reach
	check(RunBounds.canReachZone(6, 1, speed.value(1), range.value(1)), "Low Sky reachable at once")
	check(RunBounds.canReachZone(SUNSET_FROM, 1, speed.value(1), range.value(1)), "Sunset Heights reachable after 1 s")
	-- long after launch everything is reachable
	check(RunBounds.canReachZone(EDGE_FROM, 30, speed.value(1), range.value(1)), "Edge reachable after 30 s")
	-- negative time (clock oddities) behaves like 0
	check(RunBounds.maxReach(-5, 1) == RunBounds.maxReach(0, 1), "negative elapsed = 0")
end

-- peak altitude: capped by reach and by the rocket limit, never negative
do
	local mult = speed.value(1)
	check(RunBounds.clampPeak(600, 1, mult, 600) == RunBounds.maxReach(1, mult), "faked peak 1 s in -> reach cap")
	check(RunBounds.clampPeak(600, 60, mult, 450) == 450, "peak capped by rocket limit")
	check(RunBounds.clampPeak(300, 60, mult, 600) == 300, "legit peak kept")
	check(RunBounds.clampPeak(-10, 60, mult, 600) == 0, "negative peak -> 0")
	-- a real climb's peak is never cut
	local dt = 1 / 60
	local heights = simulateClimb(mult, 20, dt)
	for i, y in heights do
		local peak = math.min(y, 600)
		if RunBounds.clampPeak(peak, i * dt, mult, 600) < peak then
			check(false, ("legit peak %.1f cut at %.2f s"):format(peak, i * dt))
			break
		end
	end
end

-- catch gap: the fastest legit pull (max beam strength) is never rejected
do
	local maxStrength = strength.value(strength.maxLevel)
	for _, rarity in Rarities.list or {} do
		local pull = rarity.resist / maxStrength
		local gap = RunBounds.minCatchGap(rarity.resist, maxStrength)
		check(gap <= math.max(E.minCatchGap, pull), ("%s: gap %.3f above legit pull %.3f"):format(rarity.id, gap, pull))
		check(gap >= pull * 0.8 or gap == E.minCatchGap, ("%s: gap %.3f too loose vs pull %.3f"):format(rarity.id, gap, pull))
	end
	check(E.resistGapFactor >= 0.8 and E.resistGapFactor < 1, "resistGapFactor in [0.8, 1)")
	-- a script pulling twice as fast is rejected (Rare at base strength: pull 2 s)
	check(1.0 < RunBounds.minCatchGap(2, 1), "Rare in half the pull time rejected")
	check(RunBounds.minCatchGap(0.01, 3) == E.minCatchGap, "floor at minCatchGap")
end

if failures > 0 then
	print(("%d test(s) failed"):format(failures))
	process.exit(1)
end
print("RunBounds: all tests passed")
