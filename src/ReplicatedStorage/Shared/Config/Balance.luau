--!strict
-- Global tunables. Flight numbers come from the approved browser demo
-- (plan/PROGRESS.md "Approved movement numbers") and may be retuned for Roblox scale.
return {
	flight = {
		accel = 1250,
		drag = 2.6,
		maxSpeed = 430,
		thinAirAccelMult = 0.85,
		tiltPerSpeed = 0.0013,
		maxTilt = 0.45,
		tiltSmoothing = 8,
		cameraLeadX = 0.35,
		cameraLeadY = 0.25,
		cameraSmoothing = 3.5,
		ceilingSpring = 14,
	},
	beam = {
		baseRange = 230,
		halfAngle = 0.38,
		decayPerSecond = 0.55,
		struggleRate = 2.2,
		batteryDrainMult = 1.6,
	},
	battery = {
		lowThreshold = 0.25,
		criticalThreshold = 0.10,
	},
	economy = {
		incomeDivisor = 600,      -- income/sec = value / 600
		boostSlotIncomeMult = 2,
		offlineRate = 0.5,
		offlineCapSeconds = 2 * 3600,
		towFee = 0.15,
		explodeKeepFraction = 0.5,
		stageMult = { 1, 2.5, 6, 14 },
		startingCoins = 0,
	},
	launch = {
		cooldownSeconds = 20,
		perfectAltitudeBonus = 0.10,
		badAltitudePenalty = 0.10,
	},
	luck = {
		cap = 50,
	},
	data = {
		autosaveSeconds = 90,
	},
}
