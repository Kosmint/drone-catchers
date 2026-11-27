--!strict
-- Unit tests for Shared/EpicBlink (run with lune).
-- Run from the repo root:  lune run scripts/tests/EpicBlink.spec.luau
-- Exits with code 1 if a test fails.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SHARED_DIR = if fs.isDir("src/ReplicatedStorage/Shared")
	then "src/ReplicatedStorage/Shared"
	elseif fs.isDir("../../src/ReplicatedStorage/Shared")
	then "../../src/ReplicatedStorage/Shared"
	else error("Cannot locate src/ReplicatedStorage/Shared from cwd: " .. process.cwd)

-- Deterministic Random.new(seed) shim (Lune has no Roblox Random).
type FakeRng = {
	_state: number,
	NextInteger: (self: FakeRng, lo: number, hi: number) -> number,
	NextNumber: (self: FakeRng, lo: number?, hi: number?) -> number,
}

local function nextU32(rng: FakeRng): number
	local x = rng._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	rng._state = x
	return x
end

local FakeRandom = {}
function FakeRandom.new(seed: number?): FakeRng
	local s = bit32.bxor(math.floor(seed or 1) % 0x100000000, 0x9E3779B9)
	if s == 0 then
		s = 0x6D2B79F5
	end
	local rng: FakeRng = {
		_state = s,
		NextInteger = function(self: FakeRng, lo: number, hi: number): number
			if lo > hi then
				lo, hi = hi, lo
			end
			return lo + (nextU32(self) % (hi - lo + 1))
		end,
		NextNumber = function(self: FakeRng, lo: number?, hi: number?): number
			local u = nextU32(self) / 4294967296
			if lo ~= nil and hi ~= nil then
				return lo + u * (hi - lo)
			end
			return u
		end,
	}
	nextU32(rng)
	nextU32(rng)
	nextU32(rng)
	return rng
end

-- Minimal Roblox ModuleScript loader for src/ReplicatedStorage/Shared without editing src/.
type Node = {
	_path: string,
	Parent: Node?,
}

local nodes: { [string]: Node } = {}
local cache: { [string]: any } = {}
local loadModule: (target: any) -> any

local function getNode(path: string, parent: Node?): Node
	if nodes[path] then
		return nodes[path]
	end
	local node: any = { _path = path, Parent = parent }
	setmetatable(node, {
		__index = function(self: Node, key: string)
			local childBase = self._path .. "/" .. key
			if fs.isFile(childBase .. ".luau") then
				return getNode(childBase .. ".luau", self)
			elseif fs.isDir(childBase) then
				return getNode(childBase, self)
			end
			error("Mock instance child not found: " .. childBase)
		end,
	})
	nodes[path] = node
	return node
end

local function makeEnv(scriptNode: Node): { [string]: any }
	return {
		assert = assert,
		error = error,
		getmetatable = getmetatable,
		ipairs = ipairs,
		next = next,
		pairs = pairs,
		pcall = pcall,
		print = print,
		rawequal = rawequal,
		rawget = rawget,
		rawlen = rawlen,
		rawset = rawset,
		select = select,
		setmetatable = setmetatable,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		typeof = typeof,
		unpack = unpack,
		xpcall = xpcall,
		bit32 = bit32,
		buffer = buffer,
		coroutine = coroutine,
		math = math,
		os = os,
		string = string,
		table = table,
		utf8 = utf8,
		_VERSION = _VERSION,
		script = scriptNode,
		require = function(target: any)
			return loadModule(target)
		end,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		Random = FakeRandom,
	}
end

loadModule = function(target: any): any
	assert(type(target) == "table" and type(target._path) == "string", "Expected mock module node")
	local path = target._path
	if cache[path] ~= nil then
		return cache[path]
	end
	local source = fs.readFile(path)
	local bytecode = luau.compile(source)
	local chunk = luau.load(bytecode, {
		debugName = path,
		environment = makeEnv(target),
		injectGlobals = false,
	})
	local result = chunk()
	cache[path] = result
	return result
end

local Shared: any = getNode(SHARED_DIR, nil)
local Balance = loadModule(Shared.Config.Balance)
local EpicBlink = loadModule(Shared.EpicBlink)
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
