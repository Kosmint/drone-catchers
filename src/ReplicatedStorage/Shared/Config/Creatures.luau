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
	-- Storm Layer
	{ id = "StaticMote", color = rgb(255, 238, 150), name = "Static Mote", zone = "StormLayer", rarity = "Common", behavior = "Swarm",
		boost = { family = "Protection", stat = "armor", amount = 0.03 }, lore = "Tiny sparks that buzz in clusters." },
	{ id = "ThunderEel", color = rgb(143, 168, 255), name = "Thunder Eel", zone = "StormLayer", rarity = "Uncommon", behavior = "Phaser",
		boost = { family = "Protection", stat = "batteryOnCatch", amount = 0.01 }, lore = "Blinks between clouds like lightning." },
	{ id = "RainRay", color = rgb(127, 180, 217), name = "Rain Ray", zone = "StormLayer", rarity = "Rare", behavior = "Conditional", condition = "Thunderstorm",
		boost = { family = "Money", stat = "sellPrice", amount = 0.05 }, lore = "Only surfaces when the storm is loudest." },
	{ id = "StormHound", color = rgb(120, 112, 170), name = "Storm Hound", zone = "StormLayer", rarity = "Epic", behavior = "Aggressive",
		boost = { family = "Protection", stat = "lightningShield", amount = 1 }, lore = "Hunts anything that glows." },
	-- Edge of Space
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
