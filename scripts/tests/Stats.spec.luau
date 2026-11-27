--!strict
-- Unit tests for Shared/Stats (run with lune).
-- Run from the repo root:  lune run scripts/tests/Stats.spec.luau
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
local Upgrades = loadModule(Shared.Config.Upgrades)
local Creatures = loadModule(Shared.Config.Creatures)
local Stats = loadModule(Shared.Stats)

local failures = 0

local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- drone stats: defaults, clamping, floor, NaN safety, monotonic scaling
do
	local dNil = Stats.drone(nil)
	local dEmpty = Stats.drone({})
	for id, u in Upgrades.drone do
		local lvl1 = u.value(1)
		check(dNil[id] == lvl1, ("drone(nil).%s == level 1"):format(id))
		check(dEmpty[id] == lvl1, ("drone({}).%s == level 1"):format(id))
		local prev = lvl1
		for lvl = 2, u.maxLevel do
			local cur = Stats.drone({ drone = { [id] = lvl } })[id]
			check(cur >= prev, ("drone.%s non-decreasing at level %d"):format(id, lvl))
			prev = cur
		end
		check(prev > lvl1, ("drone.%s grows by maxLevel"):format(id))
	end

	local clamped = Stats.drone({
		drone = {
			battery = 0,
			speed = -5,
			beamStrength = 0 / 0,
			beamRange = "bad",
			cargo = 2.9,
			scanner = 999,
			armor = 4,
		},
	})
	check(clamped.battery == Upgrades.drone.battery.value(1), "battery 0 clamped to level 1")
	check(clamped.speed == Upgrades.drone.speed.value(1), "negative speed clamped to level 1")
	check(clamped.beamStrength == Upgrades.drone.beamStrength.value(1), "NaN beamStrength falls back to level 1")
	check(clamped.beamRange == Upgrades.drone.beamRange.value(1), "non-number beamRange falls back to level 1")
	check(clamped.cargo == Upgrades.drone.cargo.value(2), "fractional cargo 2.9 floored to level 2")
	check(clamped.scanner == Upgrades.drone.scanner.value(Upgrades.drone.scanner.maxLevel),
		"scanner 999 clamped to maxLevel")
	check(clamped.armor == 2, "armor at level 4 == 2")
end

-- maxChapter
do
	check(Stats.maxChapter(nil) == 1, "maxChapter(nil) == 1")
	check(Stats.maxChapter({}) == 1, "maxChapter({}) == 1")
	check(Stats.maxChapter({ rocket = { tech = "Unknown" } }) == 1, "maxChapter unknown tech == 1")
	check(Stats.maxChapter({ rocket = { tech = "Chemical" } }) == 1, "maxChapter Chemical == 1")
	check(Stats.maxChapter({ rocket = { tech = "OrbitalBooster" } }) == 2, "maxChapter OrbitalBooster == 2")
end

-- maxAltitude
do
	local r1 = Balance.rocket.altitude[1]
	local r2 = Balance.rocket.altitude[2]
	local maxEngine = Upgrades.rocket.engine.maxLevel

	check(Stats.maxAltitude(nil, 1) == r1.min, "maxAltitude(nil, 1) == min")
	check(Stats.maxAltitude({ rocket = { engine = 1, tech = "Chemical" } }, 1) == r1.min,
		"maxAltitude engine 1 == min")
	check(Stats.maxAltitude({ rocket = { engine = maxEngine, tech = "Chemical" } }, 1) == r1.max,
		"maxAltitude max engine == max")
	check(Stats.maxAltitude({ rocket = { engine = 999, tech = "Chemical" } }, 1) == r1.max,
		"maxAltitude clamps above maxLevel")
	check(Stats.maxAltitude({ rocket = { engine = -5, tech = "Chemical" } }, 1) == r1.min,
		"maxAltitude clamps negative engine")
	check(Stats.maxAltitude({ rocket = { engine = 0 / 0, tech = "Chemical" } }, 1) == r1.min,
		"maxAltitude handles NaN engine")

	local prevAlt = Stats.maxAltitude({ rocket = { engine = 1, tech = "Chemical" } }, 1)
	for lvl = 2, maxEngine do
		local alt = Stats.maxAltitude({ rocket = { engine = lvl, tech = "Chemical" } }, 1)
		check(alt > prevAlt, ("maxAltitude strictly increases at engine %d"):format(lvl))
		prevAlt = alt
	end

	-- lower chapters are fully open once higher propulsion tech is reached
	local ch2Data = { rocket = { engine = 1, tech = "OrbitalBooster" } }
	check(Stats.maxAltitude(ch2Data, 1) == r1.max, "lower chapter fully open at ch2 tech")
	check(Stats.maxAltitude(ch2Data, 2) == r2.min, "current chapter still starts at engine 1 min")
end

-- sizeMult
do
	for _, s in Balance.sizes.list do
		check(Stats.sizeMult(s.id) == s.mult, ("sizeMult(%q) == %.2f"):format(s.id, s.mult))
	end
	check(Stats.sizeMult(nil) == 1, "sizeMult(nil) == 1")
	check(Stats.sizeMult("NotASize") == 1, "sizeMult unknown == 1")
end

-- creatureValue
do
	check(Stats.creatureValue("DoesNotExist") == 0, "unknown creature value == 0")
	check(Stats.creatureValue("CloudPuff") == 10, "CloudPuff base value == 10")
	check(Stats.creatureValue("DuskManta") == 875, "DuskManta base value == 875")
	check(Stats.creatureValue("Skyhorn") == 9000, "Skyhorn base value == 9000")

	check(Stats.creatureValue("CloudPuff", nil, nil, 1) == 10, "CloudPuff stage 1 == 10")
	check(Stats.creatureValue("CloudPuff", nil, nil, 2) == 25, "CloudPuff stage 2 == 25")
	check(Stats.creatureValue("CloudPuff", nil, nil, 3) == 60, "CloudPuff stage 3 == 60")
	check(Stats.creatureValue("CloudPuff", nil, nil, 4) == 140, "CloudPuff stage 4 == 140")

	check(Stats.creatureValue("CloudPuff", { "Glossy" }) == 15, "CloudPuff Glossy == 15")
	check(Stats.creatureValue("CloudPuff", { "Glossy", "Frosted" }) == 30, "CloudPuff Glossy+Frosted == 30")
	check(Stats.creatureValue("CloudPuff", { "Glossy", "FakeMod" }) == 15, "unknown modifier ignored")

	check(Stats.creatureValue("CloudPuff", nil, "Tiny") == 8, "CloudPuff Tiny == 8")
	check(Stats.creatureValue("CloudPuff", nil, "Big") == 13, "CloudPuff Big == 13")
	check(Stats.creatureValue("CloudPuff", nil, "Colossal") == 30, "CloudPuff Colossal == 30")

	-- 10 * 2.5 * 1.5 * 1.3 = 48.75 -> rounded to 49
	check(Stats.creatureValue("CloudPuff", { "Glossy" }, "Big", 2) == 49, "combined stage+modifier+size rounds to 49")

	for _, c in Creatures.list do
		local v = Stats.creatureValue(c.id)
		check(v > 0 and v == math.floor(v), ("creature %s has positive integer value"):format(c.id))
	end
end

if failures > 0 then
	print(("%d test(s) failed"):format(failures))
	process.exit(1)
end
print("Stats: all tests passed")
