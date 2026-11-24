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
}

local list: { Creature } = {
	-- Low Sky
	{ id = "CloudPuff", name = "Cloud Puff", zone = "LowSky", rarity = "Common", behavior = "Drifter",
		boost = { family = "Money", stat = "income", amount = 0.02 }, lore = "Soft as a cloud and twice as lazy." },
	{ id = "BreezeFin", name = "Breeze Fin", zone = "LowSky", rarity = "Common", behavior = "Swarm",
		boost = { family = "Speed", stat = "droneSpeed", amount = 0.02 }, lore = "Schools of them ride the morning wind." },
	{ id = "SkySkipper", name = "Sky Skipper", zone = "LowSky", rarity = "Uncommon", behavior = "Skittish",
		boost = { family = "Speed", stat = "launchCooldown", amount = 0.03 }, lore = "Darts away the moment it notices you." },
	{ id = "DewWing", name = "Dew Wing", zone = "LowSky", rarity = "Uncommon", behavior = "Drifter",
		boost = { family = "Time", stat = "offlineCap", amount = 0.05 }, lore = "Its wings collect morning dew." },
	{ id = "HaloGlider", name = "Halo Glider", zone = "LowSky", rarity = "Rare", behavior = "Skittish",
		boost = { family = "Luck", stat = "luck", amount = 0.02 }, lore = "A ring of light follows it everywhere." },
	-- Storm Layer
	{ id = "StaticMote", name = "Static Mote", zone = "StormLayer", rarity = "Common", behavior = "Swarm",
		boost = { family = "Protection", stat = "armor", amount = 0.03 }, lore = "Tiny sparks that buzz in clusters." },
	{ id = "ThunderEel", name = "Thunder Eel", zone = "StormLayer", rarity = "Uncommon", behavior = "Phaser",
		boost = { family = "Protection", stat = "batteryOnCatch", amount = 0.01 }, lore = "Blinks between clouds like lightning." },
	{ id = "RainRay", name = "Rain Ray", zone = "StormLayer", rarity = "Rare", behavior = "Conditional", condition = "Thunderstorm",
		boost = { family = "Money", stat = "sellPrice", amount = 0.05 }, lore = "Only surfaces when the storm is loudest." },
	{ id = "StormHound", name = "Storm Hound", zone = "StormLayer", rarity = "Epic", behavior = "Aggressive",
		boost = { family = "Protection", stat = "lightningShield", amount = 1 }, lore = "Hunts anything that glows." },
	-- Edge of Space
	{ id = "AuroraWisp", name = "Aurora Wisp", zone = "EdgeOfSpace", rarity = "Rare", behavior = "Hidden",
		boost = { family = "Luck", stat = "scannerRange", amount = 0.05 }, lore = "Invisible until the aurora touches it." },
	{ id = "FrostDrifter", name = "Frost Drifter", zone = "EdgeOfSpace", rarity = "Epic", behavior = "Heavy",
		boost = { family = "Time", stat = "evolveTime", amount = 0.05 }, lore = "Slow, cold, and incredibly heavy." },
	{ id = "Skyhorn", name = "Skyhorn", zone = "EdgeOfSpace", rarity = "Legendary", behavior = "Phaser",
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
