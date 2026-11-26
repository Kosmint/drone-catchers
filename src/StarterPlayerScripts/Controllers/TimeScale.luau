--!strict
-- TimeScale: world slow motion for catch celebrations (Stage 2 contract).
-- ExpeditionController multiplies the flight dt by TimeScale.get() (drone, beam, camera,
-- creatures). UI tweens and real-time timers are not affected.
--
--   TimeScale.pulse(scale, seconds)  slow the world to `scale` (0.05..1), then ease back
--                                    to 1 over the last 40% of `seconds` (real time).
--                                    A new pulse replaces a weaker one, never stacks.
--   TimeScale.get()                  current scale (1 = normal)
--   TimeScale.reset()                back to 1 at once (run end)

local TimeScale = {}

local target = 1 -- scale at the bottom of the current pulse
local total = 0 -- pulse length (real seconds)
local left = 0 -- real seconds left in the pulse
local current = 1

function TimeScale.pulse(scale: number, seconds: number)
	scale = math.clamp(scale, 0.05, 1)
	seconds = math.max(0, seconds)
	-- keep whichever pulse is stronger right now
	if left > 0 and current <= scale then return end
	target, total, left = scale, seconds, seconds
	current = scale
end

-- Call once per frame with the real (unscaled) dt.
function TimeScale.update(realDt: number)
	if left <= 0 then
		current = 1
		return
	end
	left = math.max(0, left - realDt)
	local easeWindow = total * 0.4
	if left >= easeWindow or easeWindow <= 0 then
		current = if left > 0 then target else 1
	else
		local a = 1 - left / easeWindow -- 0 -> 1 across the ease window
		current = target + (1 - target) * (a * a * (3 - 2 * a))
	end
end

function TimeScale.get(): number
	return current
end

function TimeScale.reset()
	target, total, left, current = 1, 0, 0, 1
end

return TimeScale
