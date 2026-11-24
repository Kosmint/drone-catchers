--!strict
-- Full rarity ladder (plan/02_CONTENT.md §1). Order = rank (higher index = rarer).
-- resist = seconds to pull at beam strength 1. mult = value multiplier.
-- tier = catch celebration tier (T0..T10, see §1b). rift = only from that rift.
export type Rarity = {
	id: string,
	name: string,
	rank: number,
	color: Color3,
	color2: Color3?, -- second gradient color for fancy rarities
	resist: number,
	mult: number,
	tier: number,
	chapter: number?, -- first chapter it appears in
	rift: string?,
}

local list: { Rarity } = {}
local byId: { [string]: Rarity } = {}

local function add(id: string, name: string, color: Color3, color2: Color3?, resist: number, mult: number, tier: number, chapter: number?, rift: string?)
	local r: Rarity = {
		id = id, name = name, rank = #list + 1, color = color, color2 = color2,
		resist = resist, mult = mult, tier = tier, chapter = chapter, rift = rift,
	}
	table.insert(list, r)
	byId[id] = r
end

local rgb = Color3.fromRGB
-- normal ladder
add("Common", "Common", rgb(216, 224, 234), nil, 0.35, 1, 0, 1)
add("Uncommon", "Uncommon", rgb(111, 219, 130), nil, 0.8, 3, 1, 1)
add("Rare", "Rare", rgb(85, 174, 255), nil, 2, 10, 2, 1)
add("Epic", "Epic", rgb(184, 107, 255), nil, 3.5, 35, 3, 1)
add("Legendary", "Legendary", rgb(255, 192, 77), rgb(255, 236, 160), 5, 150, 4, 1)
add("Mythic", "Mythic", rgb(255, 74, 107), rgb(255, 160, 120), 6, 600, 5, 2)
add("Celestial", "Celestial", rgb(170, 240, 255), rgb(255, 255, 255), 7, 2000, 5, 2)
add("Cosmic", "Cosmic", rgb(40, 60, 190), rgb(150, 90, 255), 8, 6000, 6, 3)
add("Astral", "Astral", rgb(200, 190, 255), rgb(240, 240, 255), 8.5, 15000, 6, 3)
add("Galactic", "Galactic", rgb(160, 70, 230), rgb(255, 120, 200), 9, 40000, 6, 4)
add("Supernova", "Supernova", rgb(255, 150, 60), rgb(255, 250, 230), 9.5, 1e5, 7, 4)
add("Eclipse", "Eclipse", rgb(25, 20, 30), rgb(255, 200, 90), 10, 2.5e5, 7, 4)
add("Quantum", "Quantum", rgb(40, 220, 200), rgb(180, 255, 245), 10.5, 6e5, 7, 5)
add("Interdimensional", "Interdimensional", rgb(255, 90, 200), rgb(90, 220, 255), 11, 1.5e6, 8, 5)
add("Singularity", "Singularity", rgb(10, 10, 15), rgb(255, 170, 80), 12, 4e6, 8, 6)
add("Void", "Void", rgb(8, 6, 14), rgb(140, 70, 255), 12.5, 1e7, 8, 6)
add("Transcendent", "Transcendent", rgb(255, 245, 215), rgb(255, 215, 120), 13, 3e7, 9, 6)
add("Apex", "Apex", rgb(255, 80, 80), rgb(80, 200, 255), 14, 1e8, 9, 6)
add("Secret", "Secret", rgb(30, 30, 30), rgb(255, 255, 255), 15, 2.5e8, 9, 1)
-- rift ladder (above everything; Null is the highest in the game)
add("Anomalous", "Anomalous", rgb(120, 255, 170), rgb(255, 90, 210), 5, 3000, 5, nil, "Anomaly")
add("Flickering", "Flickering", rgb(255, 255, 200), rgb(120, 120, 140), 6, 12000, 6, nil, "Flicker")
add("Static", "Static", rgb(200, 200, 210), rgb(60, 60, 70), 7, 50000, 6, nil, "Static")
add("Echo", "Echo", rgb(140, 200, 255), rgb(255, 255, 255), 8, 2.5e5, 7, nil, "Echo")
add("Mirage", "Mirage", rgb(255, 200, 120), rgb(120, 200, 255), 9, 1e6, 7, nil, "Mirage")
add("Prismatic", "Prismatic", rgb(255, 120, 120), rgb(120, 255, 200), 10, 5e6, 8, nil, "Prism")
add("Abyssal", "Abyssal", rgb(10, 20, 50), rgb(60, 220, 255), 12, 5e7, 9, nil, "Abyssal")
add("Hollow", "Hollow", rgb(240, 240, 245), rgb(20, 20, 25), 13, 3e8, 9, nil, "Hollow")
add("Null", "Null", rgb(0, 0, 0), rgb(255, 255, 255), 15, 2e9, 10, nil, "Null")

-- spawn weights for normal flight (rarities above Legendary come from chapter configs)
local SPAWN_WEIGHTS: { [string]: number } = {
	Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 0.9, Mythic = 0.1,
}

return {
	list = list,
	byId = byId,
	spawnWeights = SPAWN_WEIGHTS,
	get = function(id: string): Rarity
		local r = byId[id]
		assert(r, "Unknown rarity: " .. tostring(id))
		return r
	end,
}
