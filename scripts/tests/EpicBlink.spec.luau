--!strict
-- Unit tests for Shared/EpicBlink (run with lune).
-- Run from the repo root:  lune run scripts/tests/EpicBlink.spec.luau
-- Exits with code 1 if a test fails.

local process = require("@lune/process")
local MockShared = require("./lib/MockShared")

local mock = MockShared.create()
local Shared = mock.Shared
local Balance = mock.require(Shared.Config.Balance)
local EpicBlink = mock.require(Shared.EpicBlink)
local E = Balance.epicBlink
local F = Balance.flight

local failures = 0

local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- applies is true only for Epic
do
	check(EpicBlink.applies("Epic"), "applies: true for Epic")
	for _, id in { "Common", "Uncommon", "Rare", "Legendary", "Mythic", "Celestial", "Null", "epic", "" } do
		check(not EpicBlink.applies(id), ("applies: false for %q"):format(id))
	end
end

-- plan(seed, id) is deterministic: same input, same output
do
	local cases = {
		{ seed = 0, id = 0 },
		{ seed = 1, id = 1 },
		{ seed = 42, id = 7 },
		{ seed = 123456, id = 99 },
		{ seed = 987654321, id = 13 },
		{ seed = -17, id = 5 },
	}
	for _, c in cases do
		local a = EpicBlink.plan(c.seed, c.id)
		local b = EpicBlink.plan(c.seed, c.id)
		check(a.count == b.count, ("deterministic count for (%d, %d)"):format(c.seed, c.id))
		check(#a.spots == #b.spots and #a.spots == a.count,
			("deterministic spot count for (%d, %d)"):format(c.seed, c.id))
		for i = 1, #a.spots do
			check(a.spots[i].angle == b.spots[i].angle and a.spots[i].dist == b.spots[i].dist,
				("deterministic spot %d for (%d, %d)"):format(i, c.seed, c.id))
		end
	end
end

-- blink count stays within configured min/max over many seeds
do
	local maxAllowed = math.min(E.maxBlinks, #E.thresholds)
	local minAllowed = math.clamp(E.minBlinks, 0, maxAllowed)
	local sawMin = false
	local sawMax = false
	for seed = 1, 250 do
		for spawnId = 1, 4 do
			local p = EpicBlink.plan(seed, spawnId)
			check(p.count >= minAllowed and p.count <= maxAllowed,
				("seed %d spawn %d: count %d outside [%d, %d]"):format(seed, spawnId, p.count, minAllowed, maxAllowed))
			check(#p.spots == p.count,
				("seed %d spawn %d: #spots (%d) ~= count (%d)"):format(seed, spawnId, #p.spots, p.count))
			if p.count == minAllowed then sawMin = true end
			if p.count == maxAllowed then sawMax = true end
			for i, sp in p.spots do
				check(sp.dist >= E.minDistance and sp.dist <= E.maxDistance,
					("seed %d spawn %d spot %d: dist %.3f outside [%.3f, %.3f]"):format(
						seed, spawnId, i, sp.dist, E.minDistance, E.maxDistance))
			end
		end
	end
	if minAllowed < maxAllowed then
		check(sawMin, "observed minBlinks across seeds")
		check(sawMax, "observed maxBlinks across seeds")
	end
end

-- minCatchTime grows with blink count and never falls below plain pull time
do
	local pairsToTest = {
		{ resist = 3.5, strength = 1.0 },
		{ resist = 3.5, strength = 1.5 },
		{ resist = 3.5, strength = 2.92 },
		{ resist = 5.0, strength = 1.0 },
		{ resist = 10.0, strength = 2.0 },
	}
	for _, tc in pairsToTest do
		local plainPull = tc.resist / tc.strength
		local prev = EpicBlink.minCatchTime(tc.resist, tc.strength, 0)
		local expectedZero = plainPull * E.minTimeFactor
		check(math.abs(prev - expectedZero) < 1e-9,
			("count 0 minCatchTime matches plainPull * minTimeFactor (resist=%.2f, strength=%.2f)"):format(
				tc.resist, tc.strength))
		for count = 1, #E.thresholds do
			local t = EpicBlink.minCatchTime(tc.resist, tc.strength, count)
			check(t > prev,
				("minCatchTime grows at count %d (%.4f <= %.4f)"):format(count, t, prev))
			check(t >= plainPull,
				("minCatchTime at count %d (%.4f) below plain pull time (%.4f)"):format(count, t, plainPull))
			prev = t
		end
	end
	local clamped = EpicBlink.minCatchTime(3.5, 0, 1)
	check(clamped == clamped and clamped < math.huge and clamped > 0, "minCatchTime clamps zero beamStrength")
end

-- spot stays inside flight-band and zone-band bounds and lands outside the beam cone
do
	local hw = F.halfWidth - E.edgeMargin
	local zoneFrom, zoneTo = 200, 400
	local cosLimit = math.cos(Balance.beam.halfAngle + 0.15)
	local p = EpicBlink.plan(7, 1)
	for i, sp in p.spots do
		local x, y = EpicBlink.spot(sp, 0, 300, 10, 300, zoneFrom, zoneTo)
		check(x >= -hw and x <= hw, ("open spot %d x in flight band"):format(i))
		check(y >= zoneFrom + E.edgeMargin and y <= zoneTo - E.edgeMargin,
			("open spot %d y in zone band"):format(i))
		local vx, vy = x - 0, y - 300
		local d = math.sqrt(vx * vx + vy * vy)
		check(d > 0.01 and (vx / d) < cosLimit, ("open spot %d lands outside beam cone"):format(i))
	end
	for _, pos in {
		{ dx = hw, dy = zoneTo - E.edgeMargin, cx = hw - 5, cy = zoneTo - E.edgeMargin - 2 },
		{ dx = -hw, dy = zoneFrom + E.edgeMargin, cx = -hw + 5, cy = zoneFrom + E.edgeMargin + 2 },
	} do
		local x, y = EpicBlink.spot({ angle = math.pi / 2, dist = E.maxDistance },
			pos.dx, pos.dy, pos.cx, pos.cy, zoneFrom, zoneTo)
		check(x >= -hw and x <= hw, "corner spot x stays in flight band")
		check(y >= zoneFrom + E.edgeMargin and y <= zoneTo - E.edgeMargin, "corner spot y stays in zone band")
	end
end

if failures > 0 then
	print(("%d test(s) failed"):format(failures))
	process.exit(1)
end
print("EpicBlink: all tests passed")
