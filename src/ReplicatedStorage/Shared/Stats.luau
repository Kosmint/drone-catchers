--!strict
-- Effective stats derived from player data. Used by BOTH the server (authority)
-- and the client (simulation/HUD) so they always agree. Boosts, potions and
-- research hook in here in later stages.
local Shared = script.Parent
local Upgrades = require(Shared.Config.Upgrades)
local Balance = require(Shared.Config.Balance)
local Chapters = require(Shared.Config.Chapters)
local Rarities = require(Shared.Config.Rarities)
local Modifiers = require(Shared.Config.Modifiers)
local Creatures = require(Shared.Config.Creatures)

export type DroneStats = {
	battery: number, -- seconds of idle flight
	speed: number, -- multiplier
	beamStrength: number,
	beamRange: number, -- studs
	cargo: number, -- slots
	scanner: number, -- studs
	armor: number, -- hits
}

local Stats = {}

local function levelOf(t: any, key: string, maxLevel: number): number
	local l = if typeof(t) == "table" then t[key] else nil
	if typeof(l) ~= "number" or l ~= l then return 1 end
	return math.clamp(math.floor(l), 1, maxLevel)
end

function Stats.drone(data: any): DroneStats
	local d = data and data.drone
	local out: any = {}
	for id, u in Upgrades.drone do
		out[id] = u.value(levelOf(d, id, u.maxLevel))
	end
	return out :: DroneStats
end

-- Highest chapter the player's propulsion tech allows.
function Stats.maxChapter(data: any): number
	local tech = data and data.rocket and data.rocket.tech
	for i = #Chapters.list, 1, -1 do
		if Chapters.list[i].tech == tech then return i end
	end
	return 1
end

-- Max altitude (studs in the chapter's flight column) from the engine level.
-- Engine levels belong to the player's current tech; lower chapters are fully open.
function Stats.maxAltitude(data: any, chapterId: number): number
	local range = Balance.rocket.altitude[chapterId] or Balance.rocket.altitude[1]
	if chapterId < Stats.maxChapter(data) then return range.max end
	local u = Upgrades.rocket.engine
	local engine = levelOf(data and data.rocket, "engine", u.maxLevel)
	local t = (engine - 1) / (u.maxLevel - 1)
	return range.min + (range.max - range.min) * t
end

function Stats.sizeMult(sizeId: string?): number
	for _, s in Balance.sizes.list do
		if s.id == sizeId then return s.mult end
	end
	return 1
end

-- Coin value of one creature (plan/02_CONTENT.md §5):
-- zoneBase × rarityMult × stageMult × modifier mults × size mult.
function Stats.creatureValue(creatureId: string, modifiers: { string }?, sizeId: string?, stage: number?): number
	local c = Creatures.byId[creatureId]
	if not c then return 0 end
	local zone = Chapters.zoneById[c.zone]
	local rarity = Rarities.byId[c.rarity]
	local value = (zone and zone.baseValue or 10) * (rarity and rarity.mult or 1)
	value *= Balance.economy.stageMult[stage or 1] or 1
	if modifiers then
		for _, id in modifiers do
			local m = Modifiers.byId[id]
			if m then value *= m.mult end
		end
	end
	value *= Stats.sizeMult(sizeId)
	return math.floor(value + 0.5)
end

return Stats
