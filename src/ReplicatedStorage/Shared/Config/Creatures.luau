--!strict
-- Creature roster (plan/02_CONTENT.md §3). Chapter 1 now; others added per stage.
-- boost = { family, stat, amount } — amount is a fraction (0.02 = +2%).
export type Boost = { family: string, stat: string, amount: number }
export type Creature = {
	id: string,
	name: string,
	zone: string,
	rarity: string,
	behavior: string,
	boost: Boost,
	condition: string?, -- sky event required to spawn
	lore: string,
	color: Color3, -- body tint (placeholder visuals, UI accents)
}

local rgb = Color3.fromRGB
local list: { Creature } = {
	-- Low Sky
	{ id = "CloudPuff", color = rgb(243, 246, 251), name = "Cloud Puff", zone = "LowSky", rarity = "Common", behavior = "Drifter",
		boost = { family = "Money", stat = "income", amount = 0.02 }, lore = "Soft as a cloud and twice as lazy." },
	{ id = "BreezeFin", color = rgb(159, 227, 224), name = "Breeze Fin", zone = "LowSky", rarity = "Common", behavior = "Swarm",
		boost = { family = "Speed", stat = "droneSpeed", amount = 0.02 }, lore = "Schools of them ride the morning wind." },
	{ id = "SkySkipper", color = rgb(255, 210, 122), name = "Sky Skipper", zone = "LowSky", rarity = "Uncommon", behavior = "Skittish",
		boost = { family = "Speed", stat = "launchCooldown", amount = 0.03 }, lore = "Darts away the moment it notices you." },
	{ id = "DewWing", color = rgb(189, 240, 214), name = "Dew Wing", zone = "LowSky", rarity = "Uncommon", behavior = "Drifter",
		boost = { family = "Time", stat = "offlineCap", amount = 0.05 }, lore = "Its wings collect morning dew." },
	{ id = "HaloGlider", color = rgb(191, 224, 255), name = "Halo Glider", zone = "LowSky", rarity = "Rare", behavior = "Skittish",
		boost = { family = "Luck", stat = "luck", amount = 0.02 }, lore = "A ring of light follows it everywhere." },
	-- Sunset Heights (from the approved demo)
	{ id = "DuskMoth", color = rgb(231, 179, 217), name = "Dusk Moth", zone = "SunsetHeights", rarity = "Common", behavior = "Drifter",
		boost = { family = "Protection", stat = "armor", amount = 0.03 }, lore = "Follows the last warm light of the day." },
	{ id = "EmberRay", color = rgb(255, 154, 122), name = "Ember Ray", zone = "SunsetHeights", rarity = "Uncommon", behavior = "Drifter",
		boost = { family = "Protection", stat = "batteryOnCatch", amount = 0.01 }, lore = "Glides on the heat rising off sunset clouds." },
	{ id = "AmberKite", color = rgb(255, 196, 138), name = "Amber Kite", zone = "SunsetHeights", rarity = "Rare", behavior = "Skittish",
		boost = { family = "Money", stat = "sellPrice", amount = 0.05 }, lore = "Rides the golden edge of the clouds." },
	{ id = "DuskManta", color = rgb(143, 111, 214), name = "Dusk Manta", zone = "SunsetHeights", rarity = "Epic", behavior = "Skittish",
		boost = { family = "Luck", stat = "luck", amount = 0.03 }, lore = "A shadow with wings, seen only at dusk." },
	-- Edge of Space
	{ id = "StarKrill", color = rgb(201, 210, 255), name = "Star Krill", zone = "EdgeOfSpace", rarity = "Common", behavior = "Swarm",
		boost = { family = "Speed", stat = "droneSpeed", amount = 0.02 }, lore = "Tiny lights that swarm like a galaxy." },
	{ id = "AuroraWisp", color = rgb(143, 240, 200), name = "Aurora Wisp", zone = "EdgeOfSpace", rarity = "Rare", behavior = "Hidden",
		boost = { family = "Luck", stat = "scannerRange", amount = 0.05 }, lore = "Invisible until the aurora touches it." },
	{ id = "FrostDrifter", color = rgb(207, 234, 255), name = "Frost Drifter", zone = "EdgeOfSpace", rarity = "Epic", behavior = "Heavy",
		boost = { family = "Time", stat = "evolveTime", amount = 0.05 }, lore = "Slow, cold, and incredibly heavy." },
	{ id = "Skyhorn", color = rgb(255, 241, 194), name = "Skyhorn", zone = "EdgeOfSpace", rarity = "Legendary", behavior = "Phaser",
		boost = { family = "Money", stat = "income", amount = 0.10 }, lore = "Its call can be heard for a hundred kilometers." },
}

local byId: { [string]: Creature } = {}
local byZone: { [string]: { Creature } } = {}
for _, c in list do
	byId[c.id] = c
	byZone[c.zone] = byZone[c.zone] or {}
	table.insert(byZone[c.zone], c)
end

return {
	list = list,
	byId = byId,
	byZone = byZone,
}
