--!strict
-- Net: the single place all remotes are declared.
-- * Server creates every remote at startup (Net.init()). Clients never create remotes.
-- * Every client->server handler is wrapped with a per-player token-bucket rate limit
--   and pcall, so a bad payload can never kill the handler or flood the server.
-- * Handlers must still validate their own arguments with Util.Guard.
--
-- Adding a remote = one line in DEFINITIONS.
--   kind: "event" (RemoteEvent) | "function" (RemoteFunction, client->server only)
--   rate/burst: client->server budget (requests per second / max burst)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Def = { kind: "event" | "function", rate: number?, burst: number? }

local DEFINITIONS: { [string]: Def } = {
	-- data replication (server -> client)
	DataSnapshot = { kind = "event" },
	DataChanged = { kind = "event" },
	Notify = { kind = "event" },
	-- client -> server
	RunEnded = { kind = "event" }, -- server force-ended a run (timeout) -> results
	-- client -> server
	RequestSnapshot = { kind = "event", rate = 0.5, burst = 2 },
	DebugCommand = { kind = "function", rate = 5, burst = 10 },
	RequestLaunch = { kind = "function", rate = 1, burst = 3 },
	ReportCatch = { kind = "function", rate = 8, burst = 12 },
	EndRun = { kind = "function", rate = 1, burst = 3 },
}

local FOLDER_NAME = "Remotes"
local IS_SERVER = RunService:IsServer()

local Net = {}

local remotes: { [string]: Instance } = {}

----------------------------------------------------------------------------
-- rate limiting (server only)
----------------------------------------------------------------------------
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local violations: { [Player]: number } = {}

local function allow(player: Player, name: string, def: Def): boolean
	local rate = def.rate or 10
	local burst = def.burst or 20
	local now = os.clock()
	local pb = buckets[player]
	if not pb then
		-- a request that arrives after PlayerRemoving would leak a bucket nobody clears
		if player.Parent == nil then return false end
		pb = {}
		buckets[player] = pb
	end
	local b = pb[name]
	if not b then
		b = { tokens = burst, last = now }
		pb[name] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		violations[player] = (violations[player] or 0) + 1
		if violations[player] % 100 == 1 then
			warn(string.format("[Net] rate limit: %s on %s (%d total)", player.Name, name, violations[player]))
		end
		return false
	end
	b.tokens -= 1
	return true
end

----------------------------------------------------------------------------
-- setup
----------------------------------------------------------------------------
function Net.init()
	if IS_SERVER then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if folder then folder:Destroy() end
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for name, def in DEFINITIONS do
			local r = Instance.new(if def.kind == "function" then "RemoteFunction" else "RemoteEvent")
			r.Name = name
			r.Parent = folder
			remotes[name] = r
		end
		folder.Parent = ReplicatedStorage
		Players.PlayerRemoving:Connect(function(p)
			buckets[p] = nil
			violations[p] = nil
		end)
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
		for name in DEFINITIONS do
			remotes[name] = folder:WaitForChild(name)
		end
	end
end

local function get(name: string): any
	local r = remotes[name]
	assert(r, "[Net] unknown or uninitialised remote: " .. name)
	return r
end

----------------------------------------------------------------------------
-- server API
----------------------------------------------------------------------------
-- handler(player, ...) ; for "function" remotes the handler's return value is sent back
function Net.on(name: string, handler: (...any) -> ...any)
	local def = DEFINITIONS[name]
	assert(def, "[Net] unknown remote: " .. name)
	local r = get(name)
	if IS_SERVER then
		if def.kind == "function" then
			r.OnServerInvoke = function(player: Player, ...)
				if not allow(player, name, def) then return nil end
				local results = table.pack(pcall(handler, player, ...))
				if not results[1] then
					warn("[Net] handler error in " .. name .. ": " .. tostring(results[2]))
					return nil
				end
				return table.unpack(results, 2, results.n)
			end
		else
			r.OnServerEvent:Connect(function(player: Player, ...)
				if not allow(player, name, def) then return end
				local ok, err = pcall(handler, player, ...)
				if not ok then warn("[Net] handler error in " .. name .. ": " .. tostring(err)) end
			end)
		end
	else
		assert(def.kind == "event", "[Net] client can only listen to events")
		r.OnClientEvent:Connect(handler)
	end
end

function Net.fire(target: any, name: string, ...: any)
	if IS_SERVER then
		-- Net.fire(player, name, ...)
		get(name):FireClient(target, ...)
	else
		-- Net.fire(name, ...)  (target is the name)
		get(target):FireServer(name, ...)
	end
end

function Net.fireAll(name: string, ...: any)
	assert(IS_SERVER, "fireAll is server-only")
	get(name):FireAllClients(...)
end

-- client -> server request/response
function Net.invoke(name: string, ...: any): ...any
	assert(not IS_SERVER, "invoke is client-only (never InvokeClient from the server)")
	return get(name):InvokeServer(...)
end

return Net
