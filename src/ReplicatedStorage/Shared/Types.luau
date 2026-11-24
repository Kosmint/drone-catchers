--!strict
-- Shared types + the default player profile (plan/01_ARCHITECTURE.md §5).
-- DEFAULT_PROFILE is deep-copied for new players and used to fill in fields that
-- older saves are missing (reconcile), so adding a field never breaks old data.

export type OwnedCreature = {
	id: string,
	stage: number,
	caughtAt: number,
	modifiers: { string },
	size: string,
}

export type PlayerData = {
	version: number,
	coins: number,
	stats: { [string]: number },
	rocket: { [string]: any },
	drone: { [string]: number },
	creatures: { [string]: OwnedCreature },
	habitat: { slots: number, placed: { string } },
	collection: { [string]: any },
	base: { unlockedStations: { [string]: boolean }, expansions: { [string]: boolean } },
	upgrades: { [string]: number },
	research: { active: any, done: { [string]: boolean } },
	lab: { evolutions: { any }, fusions: { any } },
	potions: { owned: { [string]: number }, active: { [string]: number } },
	achievements: { [string]: any },
	quests: { [string]: any },
	skins: { owned: { [string]: boolean }, equipped: { rocket: string, drone: string } },
	rifts: { seen: { [string]: number }, best: string? },
	purchases: { processedReceiptIds: { [string]: number } },
	retention: { [string]: any },
	tutorial: { step: number, done: boolean },
	settings: { musicVolume: number, sfxVolume: number, shake: boolean },
	lastOnline: number,
}

local DEFAULT_PROFILE: PlayerData = {
	version = 1,
	coins = 0,
	stats = { totalRuns = 0, totalCatches = 0, bestAltitude = 0, perfectLaunches = 0, playTime = 0, coinsEarned = 0 },
	rocket = { engine = 1, fuel = 1, heatShield = 0, gravityShield = 0, tech = "Chemical" },
	drone = { battery = 1, speed = 1, beamStrength = 1, beamRange = 1, cargo = 1, scanner = 1, armor = 1 },
	creatures = {},
	habitat = { slots = 2, placed = {} },
	collection = {},
	base = { unlockedStations = { LaunchPad = true, Hangar = true, Habitat = true, Market = true, Storage = true }, expansions = {} },
	upgrades = { luckReactor = 0, modifierInfuser = 0, storage = 0 },
	research = { active = false, done = {} },
	lab = { evolutions = {}, fusions = {} },
	potions = { owned = {}, active = {} },
	achievements = {},
	quests = {},
	skins = { owned = { Default = true }, equipped = { rocket = "Default", drone = "Default" } },
	rifts = { seen = {}, best = nil },
	purchases = { processedReceiptIds = {} },
	retention = { loginStreak = 0, lastLoginDay = 0, redeemedCodes = {}, groupRewardClaimed = false },
	tutorial = { step = 0, done = false },
	settings = { musicVolume = 0.7, sfxVolume = 0.8, shake = true },
	lastOnline = 0,
}

local function deepCopy<T>(t: T): T
	if typeof(t) ~= "table" then return t end
	local out = {}
	for k, v in t :: any do
		out[k] = deepCopy(v)
	end
	return out :: any
end

-- Fill in keys that exist in `template` but are missing in `data` (recursively).
-- Never overwrites existing values. Only recurses into dictionary-style tables.
local function reconcile(data: any, template: any)
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(data[k], v)
		end
	end
end

return {
	DEFAULT_PROFILE = DEFAULT_PROFILE,
	deepCopy = deepCopy,
	reconcile = reconcile,
}
