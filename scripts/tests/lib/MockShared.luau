--!strict
-- Shared Roblox ModuleScript loader for Lune specs testing src/ReplicatedStorage/Shared.
-- Walks Shared eagerly with @lune/fs in normal code (no metatables, no fs calls in require)
-- so Lune's async fs functions never cross a metamethod or module chunk call boundary.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- Deterministic Random.new(seed) shim (Lune has no Roblox Random).
export type FakeRng = {
	_state: number,
	NextInteger: (self: FakeRng, lo: number, hi: number) -> number,
	NextNumber: (self: FakeRng, lo: number?, hi: number?) -> number,
}

export type Node = { [string]: any }

export type Context = {
	Shared: Node,
	require: (target: any) -> any,
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

local function findSharedDir(): string
	if fs.isDir("src/ReplicatedStorage/Shared") then
		return "src/ReplicatedStorage/Shared"
	elseif fs.isDir("../../src/ReplicatedStorage/Shared") then
		return "../../src/ReplicatedStorage/Shared"
	end
	error("Cannot locate src/ReplicatedStorage/Shared from cwd: " .. process.cwd)
end

local function walkDir(dirPath: string, parent: Node?): Node
	local node: Node = {
		_path = dirPath,
		Parent = parent,
	}
	for _, entry in fs.readDir(dirPath) do
		local fullPath = dirPath .. "/" .. entry
		if fs.isDir(fullPath) then
			node[entry] = walkDir(fullPath, node)
		elseif fs.isFile(fullPath) and #entry > 5 and string.sub(entry, -5) == ".luau" then
			local name = string.sub(entry, 1, -6)
			local source = fs.readFile(fullPath)
			if name == "init" then
				node._path = fullPath
				node._source = source
			else
				node[name] = {
					_path = fullPath,
					_source = source,
					Parent = node,
				}
			end
		end
	end
	return node
end

local MockShared = {}

function MockShared.create(): Context
	local sharedDir = findSharedDir()
	local sharedRoot = walkDir(sharedDir, nil)
	local cache: { [string]: any } = {}
	local loadModule: (target: any) -> any

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
			warn = warn,
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
		assert(type(target) == "table" and type(target._path) == "string",
			"Expected mock module node, got: " .. tostring(target))
		assert(type(target._source) == "string",
			"Mock node is not a module (no source): " .. target._path)
		local path = target._path
		if cache[path] ~= nil then
			return cache[path]
		end
		local bytecode = luau.compile(target._source)
		local chunk = luau.load(bytecode, {
			debugName = path,
			environment = makeEnv(target),
			injectGlobals = false,
		})
		local result = chunk()
		cache[path] = result
		return result
	end

	return {
		Shared = sharedRoot,
		require = loadModule,
	}
end

return MockShared
