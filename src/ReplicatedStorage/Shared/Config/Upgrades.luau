--!strict
-- Upgrade tables and cost formulas (plan/02_CONTENT.md §4).
-- cost(level) = price to go FROM `level` TO `level + 1`.
export type Upgrade = {
	id: string,
	name: string,
	maxLevel: number,
	baseCost: number,
	growth: number,
	value: (level: number) -> number, -- stat value at a given level
	unit: string?,
}

local function cost(u: Upgrade, level: number): number
	return math.floor(u.baseCost * u.growth ^ (level - 1))
end

local drone: { [string]: Upgrade } = {
	battery = { id = "battery", name = "Battery", maxLevel = 25, baseCost = 50, growth = 1.35,
		value = function(l) return 60 + (l - 1) * 6 end, unit = "s" },
	speed = { id = "speed", name = "Speed", maxLevel = 25, baseCost = 60, growth = 1.35,
		value = function(l) return 1 + (l - 1) * 0.025 end, unit = "x" },
	beamStrength = { id = "beamStrength", name = "Beam Strength", maxLevel = 25, baseCost = 80, growth = 1.35,
		value = function(l) return 1 + (l - 1) * 0.08 end, unit = "x" },
	beamRange = { id = "beamRange", name = "Beam Range", maxLevel = 25, baseCost = 70, growth = 1.35,
		value = function(l) return 30 + (l - 1) * 2 end, unit = "studs" },
	cargo = { id = "cargo", name = "Cargo", maxLevel = 25, baseCost = 100, growth = 1.35,
		value = function(l) return 5 + (l - 1) end, unit = "slots" },
	scanner = { id = "scanner", name = "Scanner", maxLevel = 25, baseCost = 90, growth = 1.35,
		value = function(l) return 60 + (l - 1) * 6 end, unit = "studs" },
	armor = { id = "armor", name = "Hull", maxLevel = 25, baseCost = 120, growth = 1.35,
		value = function(l) return 1 + math.floor((l - 1) / 3) end, unit = "hits" },
}

local rocket: { [string]: Upgrade } = {
	engine = { id = "engine", name = "Engine", maxLevel = 30, baseCost = 100, growth = 1.4,
		value = function(l) return l end },
	fuel = { id = "fuel", name = "Fuel", maxLevel = 10, baseCost = 150, growth = 1.5,
		value = function(l) return l end },
	heatShield = { id = "heatShield", name = "Heat Shield", maxLevel = 10, baseCost = 500, growth = 1.6,
		value = function(l) return l end },
}

local base: { [string]: Upgrade } = {
	luckReactor = { id = "luckReactor", name = "Luck Reactor", maxLevel = 50, baseCost = 500, growth = 1.45,
		value = function(l) return 1 + l * 0.05 end, unit = "x" },
	modifierInfuser = { id = "modifierInfuser", name = "Modifier Infuser", maxLevel = 40, baseCost = 800, growth = 1.5,
		value = function(l) return 1.04 ^ l end, unit = "x" },
	storage = { id = "storage", name = "Storage", maxLevel = 30, baseCost = 300, growth = 1.4,
		value = function(l) return 50 + l * 15 end, unit = "slots" },
}

return {
	drone = drone,
	rocket = rocket,
	base = base,
	cost = cost,
}
