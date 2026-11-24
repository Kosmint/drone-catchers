--!strict
-- DataService: the ONLY module that touches player DataStores.
-- Gameplay reads/writes the in-memory profile via DataService.get / DataService.set.
--
-- Safety (plan/01_ARCHITECTURE.md §5, roblox-datastores skill):
--  * UpdateAsync everywhere (never Get+Set), retries with exponential backoff.
--  * Session lock: { job, time } written on load; another server's fresh lock blocks
--    loading (player is kicked with a friendly message instead of risking dupes).
--  * Saves abort if our lock was taken over (never overwrite another server's data).
--  * Autosave (staggered), save on leave, save all on BindToClose.
--  * Schema version + migrations + reconcile (fills new default fields).
--  * A failed load NEVER falls back to a fresh profile; the player is kicked.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Balance = require(Shared.Config.Balance)

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = if IS_STUDIO then "PlayerData_v1_studio" else "PlayerData_v1"
local CURRENT_VERSION = 1
local AUTOSAVE = Balance.data.autosaveSeconds
local LOCK_STALE_SECONDS = AUTOSAVE * 2 + 30
local LOCK_RETRIES = 5
local LOCK_RETRY_WAIT = 3

-- JobId is "" in Studio; use a random id so locks still work there
local SERVER_ID = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local MIGRATIONS: { [number]: (any) -> any } = {
	-- [1] = function(data) ... return data end, -- v1 -> v2
}

type Profile = {
	data: Types.PlayerData,
	key: string,
	loadedAt: number,
	released: boolean,
	saving: boolean,
	nextSave: number,
}

local DataService = {}
DataService.Loaded = Signal.new() -- (player, data)
DataService.Releasing = Signal.new() -- (player, data) fired just before the final save

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function withRetry(attempts: number, label: string, fn: () -> any): (boolean, any)
	local waitTime = 1
	local lastErr: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		warn(string.format("[DataService] %s attempt %d/%d failed: %s", label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(waitTime)
			waitTime = math.min(waitTime * 2, 16)
		end
	end
	return false, lastErr
end

local function migrate(data: any): any
	if typeof(data.version) ~= "number" then data.version = 1 end
	while data.version < CURRENT_VERSION do
		local step = MIGRATIONS[data.version]
		if not step then error("missing migration from v" .. data.version) end
		data = step(data)
		data.version += 1
	end
	return data
end

-- strip server-only fields before sending to the client
local function clientView(data: any): any
	local copy = table.clone(data)
	copy.purchases = nil
	return copy
end

----------------------------------------------------------------------------
-- load
----------------------------------------------------------------------------
type LoadResult = "ok" | "locked" | "error"

local function tryLoad(key: string): (LoadResult, any)
	local lockedElsewhere = false
	local loaded: any = nil
	local ok, err = withRetry(4, "load " .. key, function()
		lockedElsewhere = false
		loaded = nil
		;(store :: DataStore):UpdateAsync(key, function(old: any)
			local now = os.time()
			if old ~= nil then
				local lock = old.lock
				-- Studio only (separate store): a lock left by an earlier Studio playtest is
				-- never live, because stopping a playtest can cut the final save short.
				local studioLeftover = IS_STUDIO and typeof(lock) == "table" and typeof(lock.job) == "string"
					and string.sub(lock.job, 1, 7) == "studio-"
				if typeof(lock) == "table" and lock.job ~= SERVER_ID and not studioLeftover and now - (lock.time or 0) < LOCK_STALE_SECONDS then
					lockedElsewhere = true
					return nil -- abort write
				end
			else
				old = Types.deepCopy(Types.DEFAULT_PROFILE)
				old.coins = Balance.economy.startingCoins
			end
			local data = migrate(old)
			Types.reconcile(data, Types.DEFAULT_PROFILE)
			data.lock = { job = SERVER_ID, time = now }
			loaded = data
			return data
		end)
	end)
	if not ok then return "error", err end
	if lockedElsewhere then return "locked", nil end
	return "ok", loaded
end

local function onPlayerAdded(player: Player)
	if not store then
		player:Kick("Saving is unavailable right now. Please rejoin in a moment.")
		return
	end
	local key = keyFor(player.UserId)
	local result, data
	for attempt = 1, LOCK_RETRIES do
		result, data = tryLoad(key)
		if result ~= "locked" then break end
		-- another server may be finishing its final save; give it time
		if attempt < LOCK_RETRIES then task.wait(LOCK_RETRY_WAIT) end
		if not player.Parent then return end
	end
	if not player.Parent then
		-- left while loading: release the lock we may have taken
		if result == "ok" then
			pcall(function()
				(store :: DataStore):UpdateAsync(key, function(old: any)
					if old and old.lock and old.lock.job == SERVER_ID then old.lock = nil; return old end
					return nil
				end)
			end)
		end
		return
	end
	if result == "locked" then
		player:Kick("Your progress is still being saved on another server. Please rejoin in a few seconds.")
		return
	elseif result == "error" then
		player:Kick("Your data couldn't be loaded (Roblox servers may be busy). Please rejoin.")
		return
	end

	data.lock = nil -- lock lives only in the stored copy
	-- random first offset staggers autosaves across players
	profiles[player] = {
		data = data, key = key, loadedAt = os.time(), released = false, saving = false,
		nextSave = os.clock() + AUTOSAVE * (0.5 + math.random() * 0.5),
	}
	Net.fire(player, "DataSnapshot", clientView(data))
	DataService.Loaded:Fire(player, data)
end

----------------------------------------------------------------------------
-- save
----------------------------------------------------------------------------
-- release = true clears the lock (player leaving / server closing)
local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or profile.released or not store then return false end
	-- wait for an in-flight save so we never interleave writes
	local waited = 0
	while profile.saving and waited < 30 do
		task.wait(0.25)
		waited += 0.25
	end
	if profile.released then return false end
	profile.saving = true
	if release then profile.released = true end

	local now = os.time()
	profile.data.lastOnline = now
	local stats = profile.data.stats
	stats.playTime = (stats.playTime or 0) + (now - profile.loadedAt)
	profile.loadedAt = now

	local stolen = false
	local ok = withRetry(if release then 5 else 3, "save " .. profile.key, function()
		stolen = false
		;(store :: DataStore):UpdateAsync(profile.key, function(old: any)
			if old and typeof(old.lock) == "table" and old.lock.job ~= SERVER_ID then
				stolen = true
				return nil -- someone else owns this profile now; don't overwrite
			end
			local out = Types.deepCopy(profile.data) :: any
			out.lock = if release then nil else { job = SERVER_ID, time = now }
			return out
		end)
	end)
	profile.saving = false
	if stolen then
		warn("[DataService] lock for " .. profile.key .. " is held by another server; save skipped")
		profile.released = true
		if player.Parent then
			player:Kick("You joined from another server. Please rejoin.")
		end
		return false
	end
	return ok
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then return end
	DataService.Releasing:Fire(player, profile.data)
	save(player, true)
	profiles[player] = nil
end

----------------------------------------------------------------------------
-- public API
----------------------------------------------------------------------------
function DataService.get(player: Player): Types.PlayerData?
	local p = profiles[player]
	return if p and not p.released then p.data else nil
end

-- yields until the player's data is loaded (or they leave). Returns nil if they left.
function DataService.waitFor(player: Player, timeout: number?): Types.PlayerData?
	local start = os.clock()
	while player.Parent and not profiles[player] do
		if timeout and os.clock() - start > timeout then return nil end
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Tell the client a top-level key changed (call after mutating data[key]).
function DataService.changed(player: Player, key: string)
	local data = DataService.get(player)
	if not data or key == "purchases" then return end
	Net.fire(player, "DataChanged", key, (data :: any)[key])
end

-- Convenience: set a top-level key and replicate it.
function DataService.set(player: Player, key: string, value: any)
	local data = DataService.get(player)
	if not data then return end
	(data :: any)[key] = value
	DataService.changed(player, key)
end

-- Add coins (negative to spend). Returns false if it would go below zero.
function DataService.addCoins(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data or amount ~= amount or math.abs(amount) == math.huge then return false end
	if data.coins + amount < 0 then return false end
	data.coins += amount
	if amount > 0 then data.stats.coinsEarned = (data.stats.coinsEarned or 0) + amount end
	DataService.changed(player, "coins")
	DataService.changed(player, "stats")
	return true
end

-- Debug/QA only: replace the profile with a fresh default (keeps the lock owner).
function DataService.resetForDebug(player: Player)
	local profile = profiles[player]
	if not profile then return end
	profile.data = Types.deepCopy(Types.DEFAULT_PROFILE)
	Net.fire(player, "DataSnapshot", clientView(profile.data))
end

function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable: " .. tostring(result))
	end

	Net.on("RequestSnapshot", function(player: Player)
		local data = DataService.get(player)
		if data then Net.fire(player, "DataSnapshot", clientView(data)) end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.Releasing:Fire(player, profiles[player] and profiles[player].data)
				save(player, true)
				pending -= 1
			end)
		end
		local limit = if IS_STUDIO then 5 else 25
		local start = os.clock()
		while pending > 0 and os.clock() - start < limit do task.wait(0.1) end
	end)
end

function DataService.start()
	-- staggered autosave: each player saves on their own offset within the interval
	while true do
		task.wait(1)
		local now = os.clock()
		for player, profile in profiles do
			if not profile.released and not profile.saving and now >= profile.nextSave then
				profile.nextSave = now + AUTOSAVE
				task.spawn(save, player, false)
			end
		end
	end
end

return DataService
