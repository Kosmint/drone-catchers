--!strict
-- ExpeditionService: server authority over a run (plan/01_ARCHITECTURE.md §3).
--  RequestLaunch(chapterId)        -> run { runId, seed, chapter, maxAltitude, stats }
--  ReportCatch(runId, spawnId)     -> { modifiers, size, value } (server rolls both)
--  EndRun(runId, reason, peakAlt)  -> results; cargo moves into the inventory
-- The client simulates flight; the server validates every catch against the same
-- deterministic spawn plan (SpawnGen) and plausible timings.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Guard = require(Shared.Util.Guard)
local WeightedRandom = require(Shared.Util.WeightedRandom)
local Balance = require(Shared.Config.Balance)
local Chapters = require(Shared.Config.Chapters)
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local Modifiers = require(Shared.Config.Modifiers)
local Stats = require(Shared.Stats)
local SpawnGen = require(Shared.SpawnGen)
local SpawnWindow = require(Shared.SpawnWindow)
local EpicBlink = require(Shared.EpicBlink)
local DataService = require(script.Parent.DataService)
local DebugService = require(script.Parent.DebugService)

type CargoItem = { spawnId: number, creature: string, modifiers: { string }, size: string, value: number }

type Run = {
	id: number,
	seed: number,
	chapter: number,
	maxAltitude: number,
	stats: Stats.DroneStats,
	plan: SpawnGen.Plan,
	startedAt: number,
	caught: { [number]: boolean },
	nextIndex: { [string]: number }, -- per zone: first queue index the client hasn't activated (SpawnWindow)
	cargo: { CargoItem },
	lastCatchAt: number,
	lastGroup: number,
	burstStart: number, -- first catch of the current same-group burst (swarm multi-pull)
	burstCount: number, -- catches in that burst
}

local ExpeditionService = {}

local runs: { [Player]: Run } = {}
local lastLaunch: { [Player]: number } = {}
local rng = Random.new()
local nextRunId = 0
-- swarm members pulled together by one beam finish within this many seconds of each other
local SWARM_BURST_WINDOW = 0.3

----------------------------------------------------------------------------
-- rolls (server RNG only)
----------------------------------------------------------------------------
local function rollModifiers(chapter: number): { string }
	-- TODO(Stage 6): Modifier Infuser, potions, events, luck raise the chance
	if rng:NextNumber() >= math.min(Modifiers.BASE_CHANCE, Modifiers.MAX_CHANCE) then return {} end
	local entries = {}
	for _, m in Modifiers.list do
		if m.riftOnly == nil and (m.minChapter == nil or m.minChapter <= chapter) then
			table.insert(entries, { item = m.id, weight = m.weight })
		end
	end
	local id = WeightedRandom.pick(rng, entries)
	return if id then { id } else {}
end

local function rollSize(): string
	if not Balance.sizes.enabled then return "Normal" end
	local entries = {}
	for _, s in Balance.sizes.list do table.insert(entries, { item = s.id, weight = s.weight }) end
	return WeightedRandom.pick(rng, entries) or "Normal"
end

----------------------------------------------------------------------------
-- run lifecycle
----------------------------------------------------------------------------
local function zonePlan(run: Run, zoneId: string): SpawnGen.ZonePlan?
	for _, zp in run.plan.zones do
		if zp.zone == zoneId then return zp end
	end
	return nil
end

export type Results = {
	runId: number,
	reason: string,
	towed: boolean,
	cargo: { CargoItem },
	total: number,
	fee: number,
}

-- Moves cargo into the inventory and closes the run. Generous by design:
-- leaving or timing out still keeps every creature (plan: "never lose everything").
local function finalize(player: Player, reason: string, peakAltitude: number?): Results?
	local run = runs[player]
	if not run then return nil end
	runs[player] = nil

	local elapsed = os.clock() - run.startedAt
	local batteryLimit = run.stats.battery + Balance.expedition.deployGrace + Balance.expedition.batteryGrace
	local towed = reason == "battery" or reason == "timeout" or elapsed > batteryLimit

	local total = 0
	for _, item in run.cargo do total += item.value end
	local fee = if towed then math.floor(total * Balance.economy.towFee) else 0

	local data = DataService.get(player)
	if data then
		local now = os.time()
		for _, item in run.cargo do
			local uid = HttpService:GenerateGUID(false)
			data.creatures[uid] = { id = item.creature, stage = 1, caughtAt = now, modifiers = item.modifiers, size = item.size }
			local entry = data.collection[item.creature]
			if typeof(entry) ~= "table" then
				entry = { caught = 0, maxStage = 1, firstCaughtAt = now }
				data.collection[item.creature] = entry
			end
			entry.caught += 1
		end
		local st = data.stats
		st.totalRuns = (st.totalRuns or 0) + 1
		st.totalCatches = (st.totalCatches or 0) + #run.cargo
		if Guard.number(peakAltitude, 0, 1e6) then
			local km = Chapters.toKm(run.chapter, math.min(peakAltitude :: number, run.maxAltitude))
			st.bestAltitude = math.max(st.bestAltitude or 0, math.floor(km * 10) / 10)
		end
		if fee > 0 then
			fee = math.min(fee, data.coins) -- never push coins below zero
			if fee > 0 then DataService.addCoins(player, -fee) end
		end
		DataService.changed(player, "creatures")
		DataService.changed(player, "collection")
		DataService.changed(player, "stats")
	end

	return { runId = run.id, reason = reason, towed = towed, cargo = run.cargo, total = total, fee = fee }
end

local function onRequestLaunch(player: Player, chapterId: unknown)
	local data = DataService.get(player)
	if not data then return { ok = false, reason = "loading" } end
	if runs[player] then
		-- a stale run (client lost it) is closed generously before a new one starts
		local r = runs[player]
		if os.clock() - r.startedAt < r.stats.battery + Balance.expedition.deployGrace then
			return { ok = false, reason = "inflight" }
		end
		finalize(player, "timeout")
	end
	if not Guard.int(chapterId, 1, #Chapters.list) then return { ok = false, reason = "bad chapter" } end
	local chapter = chapterId :: number
	if chapter > Stats.maxChapter(data) then return { ok = false, reason = "locked" } end

	local since = os.clock() - (lastLaunch[player] or -math.huge)
	local cooldown = Balance.launch.cooldownSeconds
	if since < cooldown then
		return { ok = false, reason = "cooldown", wait = math.ceil(cooldown - since) }
	end

	nextRunId += 1
	local seed = rng:NextInteger(1, 2 ^ 31 - 2)
	local stats = Stats.drone(data)
	local maxAltitude = Stats.maxAltitude(data, chapter)
	local plan = SpawnGen.build(seed, chapter, maxAltitude)
	local nextIndex: { [string]: number } = {}
	for _, zp in plan.zones do
		-- same deploy activation as CreatureSimClient.begin
		nextIndex[zp.zone] = SpawnWindow.initial(zp.queue, zp.active)
	end
	local run: Run = {
		id = nextRunId,
		seed = seed,
		chapter = chapter,
		maxAltitude = maxAltitude,
		stats = stats,
		plan = plan,
		startedAt = os.clock(),
		caught = {},
		nextIndex = nextIndex,
		cargo = {},
		lastCatchAt = -math.huge,
		lastGroup = -1,
		burstStart = -math.huge,
		burstCount = 0,
	}
	runs[player] = run
	lastLaunch[player] = os.clock()
	return { ok = true, runId = run.id, seed = seed, chapter = chapter, maxAltitude = maxAltitude, stats = stats }
end

local function onReportCatch(player: Player, runId: unknown, spawnId: unknown)
	local run = runs[player]
	if not run or runId ~= run.id then return { ok = false, reason = "norun" } end
	if not Guard.int(spawnId, 1, 100000) then return { ok = false, reason = "bad" } end
	local spawn = run.plan.byId[spawnId :: number]
	if not spawn or run.caught[spawn.id] then return { ok = false, reason = "gone" } end
	if #run.cargo >= run.stats.cargo then return { ok = false, reason = "full" } end

	-- could this creature really be in the sky yet? (the client activates whole groups,
	-- one group per catch in the zone; swarmMax = slack for timing)
	local zp = zonePlan(run, spawn.zone)
	local nextIndex = run.nextIndex[spawn.zone]
	if not zp or not nextIndex or not SpawnWindow.allows(spawn.index, nextIndex, Balance.spawns.swarmMax) then
		return { ok = false, reason = "inactive" }
	end

	-- plausible timing: pulling takes resist / beamStrength seconds
	local now = os.clock()
	local creature = Creatures.byId[spawn.creature]
	local rarity = Rarities.byId[creature.rarity]
	if now - run.startedAt < 1 then return { ok = false, reason = "early" } end
	local gap = math.max(Balance.expedition.minCatchGap, rarity.resist / run.stats.beamStrength * Balance.expedition.resistGapFactor)
	-- swarm multi-pull: up to swarmMultiPull members of one group, pulled by the same beam,
	-- finish together; they need no gap within SWARM_BURST_WINDOW of the burst's first catch
	local inBurst = spawn.group == run.lastGroup
		and run.burstCount < Balance.beam.swarmMultiPull
		and now - run.burstStart <= SWARM_BURST_WINDOW
	if inBurst then gap = 0 end
	if now - run.lastCatchAt < gap then return { ok = false, reason = "fast" } end
	if EpicBlink.applies(rarity.id) then
		-- Epics blink away while pulled (count from the run seed, never from the client):
		-- the pull can't be shorter than the full pull + lost progress + re-grab delays,
		-- counted from the last catch and from the launch.
		local blinks = EpicBlink.plan(run.seed, spawn.id).count
		local need = EpicBlink.minCatchTime(rarity.resist, run.stats.beamStrength, blinks)
		if math.min(now - run.lastCatchAt, now - run.startedAt) < need then
			return { ok = false, reason = "fast" }
		end
	end

	run.caught[spawn.id] = true
	run.nextIndex[spawn.zone] = SpawnWindow.advance(zp.queue, nextIndex) -- mirrors CreatureSimClient.activateNext
	run.lastCatchAt = now
	run.lastGroup = spawn.group
	if inBurst then
		run.burstCount += 1
	else
		run.burstStart, run.burstCount = now, 1
	end

	local modifiers = rollModifiers(run.chapter)
	local size = rollSize()
	local value = Stats.creatureValue(spawn.creature, modifiers, size, 1)
	table.insert(run.cargo, { spawnId = spawn.id, creature = spawn.creature, modifiers = modifiers, size = size, value = value })
	return { ok = true, modifiers = modifiers, size = size, value = value }
end

local function onEndRun(player: Player, runId: unknown, reason: unknown, peakAltitude: unknown)
	local run = runs[player]
	if not run or runId ~= run.id then return nil end
	local why = if reason == "battery" then "battery" else "recall"
	return finalize(player, why, if Guard.number(peakAltitude, 0, 1e6) then peakAltitude :: number else nil)
end

----------------------------------------------------------------------------
-- debug (Studio / owner only, gated by DebugService)
----------------------------------------------------------------------------
local function registerDebug()
	local cmds = DebugService.commands
	cmds.engine = function(player, level)
		local data = DataService.get(player)
		if not data or not Guard.int(level, 1, 30) then return "usage: engine <1-30>" end
		data.rocket.engine = level
		DataService.changed(player, "rocket")
		return "engine = " .. tostring(level) .. " (max altitude " .. tostring(Stats.maxAltitude(data, 1)) .. ")"
	end
	-- "drone battery 5"  ->  arg = "battery 5"
	cmds.drone = function(player, arg)
		local data = DataService.get(player)
		if not data or not Guard.string(arg, 32) then return "usage: drone '<stat> <level>'" end
		local stat, lvl = string.match(arg :: string, "^(%a+)%s+(%d+)$")
		if not stat or data.drone[stat] == nil then return "unknown stat" end
		data.drone[stat] = math.clamp(tonumber(lvl) or 1, 1, 25)
		DataService.changed(player, "drone")
		return stat .. " = " .. tostring(data.drone[stat])
	end
	cmds.cooldown = function(player)
		lastLaunch[player] = nil
		return "launch cooldown cleared"
	end
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function ExpeditionService.init()
	Net.on("RequestLaunch", onRequestLaunch)
	Net.on("ReportCatch", onReportCatch)
	Net.on("EndRun", onEndRun)
	registerDebug()

	-- leaving mid-run: cargo is kept (finalize before the final save)
	DataService.Releasing:Connect(function(player: Player)
		if runs[player] then finalize(player, "left") end
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- connection order vs DataService is not guaranteed: finalize here too
		if runs[player] then finalize(player, "left") end
		lastLaunch[player] = nil
	end)
end

function ExpeditionService.start()
	-- safety net: close runs whose battery must be long empty
	while true do
		task.wait(5)
		local now = os.clock()
		for player, run in runs do
			if now - run.startedAt > run.stats.battery + Balance.expedition.deployGrace + Balance.expedition.timeoutExtra then
				local results = finalize(player, "timeout")
				if results and player.Parent then Net.fire(player, "RunEnded", results) end
			end
		end
	end
end

function ExpeditionService.hasRun(player: Player): boolean
	return runs[player] ~= nil
end

return ExpeditionService
