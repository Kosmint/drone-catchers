--!strict
-- Weighted picks driven by an explicit Random object, so client and server can
-- produce identical spawn lists from the same seed.
local WeightedRandom = {}

export type Entry<T> = { item: T, weight: number }

function WeightedRandom.pick<T>(rng: Random, entries: { Entry<T> }): T?
	local total = 0
	for _, e in entries do
		if e.weight > 0 then total += e.weight end
	end
	if total <= 0 then return nil end
	local roll = rng:NextNumber() * total
	for _, e in entries do
		if e.weight > 0 then
			roll -= e.weight
			if roll <= 0 then return e.item end
		end
	end
	return entries[#entries].item -- float edge case
end

-- Picks from a map { [item] = weight }. Keys are sorted first so the result is
-- deterministic for a given seed (map iteration order is not guaranteed).
function WeightedRandom.pickMap(rng: Random, map: { [string]: number }): string?
	local keys = {}
	for k in map do table.insert(keys, k) end
	table.sort(keys)
	local entries = {}
	for _, k in keys do table.insert(entries, { item = k, weight = map[k] }) end
	return WeightedRandom.pick(rng, entries)
end

-- "1 in N" roll with a luck multiplier: chance = luck / N (capped at 1).
function WeightedRandom.oneIn(rng: Random, n: number, luck: number?): boolean
	local chance = math.min(1, (luck or 1) / n)
	return rng:NextNumber() < chance
end

return WeightedRandom
