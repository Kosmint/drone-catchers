--!strict
-- EpicBlink: Epic creatures blink away while being pulled (Balance.epicBlink).
-- Shared by the client (where it lands) and the server (minimum catch time).
-- Everything comes from the run seed + spawn id, so both sides get the same plan;
-- the server never takes a blink count or a position from the client.
--
-- A spot is stored RELATIVE to the drone -> creature line at the moment of the
-- blink: angle pi = behind the drone, +-pi/2 = to its left / right. That way it
-- always lands outside the beam cone and the player has to turn to re-catch it.
local Shared = script.Parent
local Balance = require(Shared.Config.Balance)

local E = Balance.epicBlink
local F = Balance.flight

export type Spot = { angle: number, dist: number }
export type BlinkPlan = { count: number, spots: { Spot } }

local SIDES = { math.pi, math.pi / 2, -math.pi / 2 } -- behind, left, right
local CONE_MARGIN = 0.15 -- rad outside the beam cone a blink spot must be

local EpicBlink = {}

function EpicBlink.applies(rarityId: string): boolean
	return rarityId == E.rarity
end

-- Deterministic: same seed + spawn id = same blinks (count, sides, distances).
function EpicBlink.plan(seed: number, spawnId: number): BlinkPlan
	local rng = Random.new(seed * 7919 + spawnId)
	local count = math.clamp(rng:NextInteger(E.minBlinks, E.maxBlinks), 0, #E.thresholds)
	local spots: { Spot } = {}
	for _ = 1, count do
		local base = SIDES[rng:NextInteger(1, #SIDES)]
		table.insert(spots, {
			angle = base + rng:NextNumber(-E.sideJitter, E.sideJitter),
			dist = rng:NextNumber(E.minDistance, E.maxDistance),
		})
	end
	return { count = count, spots = spots }
end

local function place(angle: number, dist: number, dx: number, dy: number, ux: number, uy: number,
	zoneFrom: number, zoneTo: number): (number, number)
	local c, s = math.cos(angle), math.sin(angle)
	local hw = F.halfWidth - E.edgeMargin
	local x = math.clamp(dx + (ux * c - uy * s) * dist, -hw, hw)
	local y = math.clamp(dy + (ux * s + uy * c) * dist, zoneFrom + E.edgeMargin, zoneTo - E.edgeMargin)
	return x, y
end

-- Where blink `spot` lands, in flight-plane coords. Kept inside the flight band and
-- the zone band; if clamping pushed it back into the beam cone, the mirrored side and
-- then "behind" are tried instead.
function EpicBlink.spot(spot: Spot, droneX: number, droneY: number, creatureX: number, creatureY: number,
	zoneFrom: number, zoneTo: number): (number, number)
	local ax, ay = creatureX - droneX, creatureY - droneY
	local len = math.sqrt(ax * ax + ay * ay)
	local ux, uy = 1, 0
	if len > 0.01 then ux, uy = ax / len, ay / len end
	local cosLimit = math.cos(Balance.beam.halfAngle + CONE_MARGIN)
	local x, y = 0, 0
	for _, angle in { spot.angle, -spot.angle, math.pi } do
		x, y = place(angle, spot.dist, droneX, droneY, ux, uy, zoneFrom, zoneTo)
		local vx, vy = x - droneX, y - droneY
		local d = math.sqrt(vx * vx + vy * vy)
		if d > 0.01 and (vx * ux + vy * uy) / d < cosLimit then break end
	end
	return x, y
end

-- Fastest legitimate pull of an Epic with `count` blinks: the full pull, plus the
-- progress lost at every blink, plus the re-grab delays (times the lag slack).
function EpicBlink.minCatchTime(resist: number, beamStrength: number, count: number): number
	local pull = resist / math.max(beamStrength, 1e-3)
	local lost = 0
	for i = 1, math.min(count, #E.thresholds) do
		lost += math.max(0, E.thresholds[i] - E.keepProgress)
	end
	return (pull * (1 + lost) + count * E.regrabDelay) * E.minTimeFactor
end

return EpicBlink
