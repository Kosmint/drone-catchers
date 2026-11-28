--!strict
-- RunBounds: server plausibility bounds for a run (pure, no Roblox APIs).
-- ExpeditionService uses them to reject catches that come too fast or from zones
-- the drone can't have reached yet, and to cap the reported peak altitude.
-- Unit tests: scripts/tests/RunBounds.spec.luau (run with lune).
--
-- Reachability: the drone starts at `flight.deployAltitude` and its speed is capped
-- at `flight.maxSpeed * speedMult` (FlightController.update), so after `elapsed`
-- seconds it can't be higher than deployAltitude + maxSpeed * speedMult * elapsed.
-- `elapsed` is server time since RequestLaunch, which is always >= the client's
-- flight time (the flight starts after the launch reply), so the bound only errs
-- in the player's favour. Slack covers bobbing and frame steps.
local Balance = require(script.Parent.Config.Balance)

local F = Balance.flight
local E = Balance.expedition

local RunBounds = {}

-- Highest altitude (studs) the drone can have reached `elapsed` seconds after launch.
function RunBounds.maxReach(elapsed: number, speedMult: number): number
	local t = math.max(0, elapsed)
	return F.deployAltitude + F.maxSpeed * speedMult * E.reachSpeedSlack * t + E.reachSlackStuds
end

-- Could the beam reach a creature living at or above `zoneFrom` by now?
-- The beam reaches `beamRange` studs above the drone.
function RunBounds.canReachZone(zoneFrom: number, elapsed: number, speedMult: number, beamRange: number): boolean
	return zoneFrom <= RunBounds.maxReach(elapsed, speedMult) + beamRange
end

-- Reported peak altitude, capped by what is reachable and by the rocket limit.
function RunBounds.clampPeak(peak: number, elapsed: number, speedMult: number, maxAltitude: number): number
	return math.clamp(peak, 0, math.min(maxAltitude, RunBounds.maxReach(elapsed, speedMult)))
end

-- Minimum seconds between two separate catches: a pull takes resist / beamStrength
-- seconds; `resistGapFactor` (< 1) is lag slack.
function RunBounds.minCatchGap(resist: number, beamStrength: number): number
	return math.max(E.minCatchGap, resist / beamStrength * E.resistGapFactor)
end

return RunBounds
