--!strict
-- ServerMain: THE server entry point. Everything else is a ModuleScript.
-- Two-phase startup: every service's init() runs (in ORDER) before any start().
-- A failing service is reported but does not stop the others from starting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local Services = script.Parent:WaitForChild("Services")

-- Explicit order: services listed here init first, in this order; any other
-- service module found in the folder inits afterwards (alphabetically).
local ORDER = {
	"DataService",
	"DebugService",
}

Net.init()

local loaded: { { name: string, mod: any } } = {}
local seen: { [string]: boolean } = {}

local function load(module: ModuleScript)
	if seen[module.Name] then return end
	seen[module.Name] = true
	local ok, mod = pcall(require, module)
	if ok then
		table.insert(loaded, { name = module.Name, mod = mod })
	else
		warn("[ServerMain] failed to load " .. module.Name .. ": " .. tostring(mod))
	end
end

for _, name in ORDER do
	local m = Services:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then load(m) end
end
local rest = Services:GetChildren()
table.sort(rest, function(a, b) return a.Name < b.Name end)
for _, m in rest do
	if m:IsA("ModuleScript") then load(m) end
end

for _, s in loaded do
	if typeof(s.mod.init) == "function" then
		local ok, err = pcall(s.mod.init)
		if not ok then warn("[ServerMain] " .. s.name .. ".init failed: " .. tostring(err)) end
	end
end
for _, s in loaded do
	if typeof(s.mod.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(s.mod.start)
			if not ok then warn("[ServerMain] " .. s.name .. ".start failed: " .. tostring(err)) end
		end)
	end
end

print(string.format("[ServerMain] %d services started", #loaded))
