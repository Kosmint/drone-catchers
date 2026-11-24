--!strict
-- Smoothing helpers used for camera, drone and UI motion.
-- `damp` is frame-rate independent exponential smoothing (same math as the approved
-- browser demo: value = lerp(value, target, 1 - exp(-k*dt))).
-- `Spring` is a spring for bouncy UI / camera punches.
local Spring = {}
Spring.__index = Spring

function Spring.damp(current: number, target: number, k: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-k * dt))
end

function Spring.dampVector(current: Vector3, target: Vector3, k: number, dt: number): Vector3
	return current:Lerp(target, 1 - math.exp(-k * dt))
end

-- Spring: x'' = -stiffness*(x-target) - damping*x'
function Spring.new(initial: any, stiffness: number?, damping: number?)
	return setmetatable({
		position = initial,
		velocity = initial * 0,
		target = initial,
		stiffness = stiffness or 170,
		damping = damping or 26,
	}, Spring)
end

function Spring.step(self: any, dt: number)
	-- sub-step for stability at low frame rates
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		local accel = (self.target - self.position) * self.stiffness - self.velocity * self.damping
		self.velocity += accel * h
		self.position += self.velocity * h
	end
	return self.position
end

function Spring.impulse(self: any, v: any)
	self.velocity += v
end

return Spring
