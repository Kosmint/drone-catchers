--!strict
-- ClientMain: THE client entry point. Same two-phase pattern as ServerMain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"DataController",
	"InputController",
	"CameraController",
	"FlightController",
	"CreatureSimClient",
	"BeamController",
	"HUDController",
	"ExpeditionController",
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
		warn("[ClientMain] failed to load " .. module.Name .. ": " .. tostring(mod))
	end
end

for _, name in ORDER do
	local m = Controllers:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then load(m) end
end
local rest = Controllers:GetChildren()
table.sort(rest, function(a, b) return a.Name < b.Name end)
for _, m in rest do
	if m:IsA("ModuleScript") then load(m) end
end

for _, c in loaded do
	if typeof(c.mod.init) == "function" then
		local ok, err = pcall(c.mod.init)
		if not ok then warn("[ClientMain] " .. c.name .. ".init failed: " .. tostring(err)) end
	end
end
for _, c in loaded do
	if typeof(c.mod.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(c.mod.start)
			if not ok then warn("[ClientMain] " .. c.name .. ".start failed: " .. tostring(err)) end
		end)
	end
end

print(string.format("[ClientMain] %d controllers started", #loaded))
