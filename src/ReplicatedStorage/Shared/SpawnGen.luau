--!strict
-- Deterministic creature spawn plan for one expedition.
-- Server and client both call SpawnGen.build(seed, chapterId, maxAltitude) and
-- get identical lists (Random is deterministic for a given seed).
--
-- Each reachable zone has a QUEUE of spawns. The first `active` entries are in the
-- sky at deploy; every catch in a zone activates the next queued entry, so the
-- sky never empties. The server uses the queue index to check that a reported
-- catch could really have been in the sky (index <= active + caughtInZone + slack).
local Shared = script.Parent
local Balance = require(Shared.Config.Balance)
local Chapters = require(Shared.Config.Chapters)
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local WeightedRandom = require(Shared.Util.WeightedRandom)

export type Spawn = {
	id: number,
	creature: string,
	zone: string,
	index: number, -- position in its zone queue (1-based)
	group: number, -- swarm members share a group
	slot: number, -- member number inside the group
	x: number, -- spawn position (studs on the flight plane, relative to origin)
	y: number,
	phase: number,
}

export type ZonePlan = {
	zone: string,
	from: number,
	to: number,
	active: number,
	queue: { Spawn },
}

export type Plan = {
	zones: { ZonePlan },
	byId: { [number]: Spawn },
}

local SpawnGen = {}

function SpawnGen.build(seed: number, chapterId: number, maxAltitude: number, eventId: string?): Plan
	local rng = Random.new(seed)
	local cfg = Balance.spawns
	local halfWidth = Balance.flight.halfWidth - 10
	local plan: Plan = { zones = {}, byId = {} }
	local nextId = 1
	local group = 0

	for _, z in Chapters.get(chapterId).zones do
		if z.from >= maxAltitude then break end
		local lo = math.max(z.from, Balance.flight.floor) + 6
		local hi = math.min(z.to, maxAltitude) - 6
		if hi - lo < 20 then continue end

		-- weighted pool (Creatures.byZone keeps config order -> deterministic)
		local entries = {}
		for _, c in Creatures.byZone[z.id] or {} do
			if c.condition == nil or c.condition == eventId then
				local w = Rarities.spawnWeights[c.rarity] or 0
				if w > 0 then table.insert(entries, { item = c, weight = w }) end
			end
		end
		if #entries == 0 then continue end

		local active = math.max(4, math.floor((hi - lo) / 100 * cfg.perHundredStuds + 0.5))
		local zp: ZonePlan = { zone = z.id, from = lo, to = hi, active = active, queue = {} }
		local total = active * cfg.queueFactor
		while #zp.queue < total do
			local c = WeightedRandom.pick(rng, entries)
			if not c then break end
			local count = if c.behavior == "Swarm" then rng:NextInteger(cfg.swarmMin, cfg.swarmMax) else 1
			group += 1
			local gx = rng:NextNumber(-halfWidth, halfWidth)
			local gy = rng:NextNumber(lo, hi)
			for slot = 1, count do
				local s: Spawn = {
					id = nextId,
					creature = c.id,
					zone = z.id,
					index = #zp.queue + 1,
					group = group,
					slot = slot,
					x = gx,
					y = gy,
					phase = rng:NextNumber(0, math.pi * 2),
				}
				nextId += 1
				table.insert(zp.queue, s)
				plan.byId[s.id] = s
			end
		end
		table.insert(plan.zones, zp)
	end
	return plan
end

return SpawnGen
