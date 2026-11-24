--!strict
-- Global tunables. Flight numbers come from the approved browser demo
-- (plan/PROGRESS.md "Approved movement numbers"), converted at 0.1 studs per
-- demo unit: the demo showed 620 units vertically, the Roblox flight camera
-- shows `flight.viewHeight` (62) studs, so the feel and proportions match.
return {
	flight = {
		origin = Vector3.new(20000, 100, 0), -- world position of altitude 0 on the flight plane (Z = origin.Z)
		accel = 125, -- studs/s^2
		drag = 2.6, -- v *= exp(-drag*dt)
		maxSpeed = 43, -- studs/s (x speed upgrade)
		thinAirAltitude = 400, -- Edge of Space starts here
		thinAirAccelMult = 0.85,
		bobAmplitude = 0.6,
		bobFrequency = 1.3,
		tiltPerSpeed = 0.013, -- rad per stud/s
		maxTilt = 0.45,
		tiltSmoothing = 8,
		halfWidth = 180, -- horizontal flight band (soft wall beyond)
		edgePush = 90,
		floor = 18, -- soft floor above the ground
		floorSpring = 10,
		ceilingSpring = 14, -- rocket limit spring
		deployAltitude = 30,
		deploySpeed = 18,
		-- camera
		fov = 35,
		viewHeight = 62, -- studs visible vertically on the flight plane
		cameraLeadX = 0.35,
		cameraLeadY = 0.25,
		cameraSmoothing = 3.5,
	},
	beam = {
		halfAngle = 0.38, -- rad
		decayPerSecond = 0.55, -- progress lost per second off-beam
		struggleRate = 2.2, -- jerks per second for Rare+
		struggleMinRank = 3, -- Rare
		pullSpeed = 4, -- studs/s toward the drone at full progress
		batteryDrainMult = 1.6,
		swarmMultiPull = 3, -- max creatures of one swarm pulled at once
	},
	battery = {
		lowThreshold = 0.25,
		criticalThreshold = 0.10,
	},
	spawns = {
		perHundredStuds = 12, -- active creatures per 100 studs of altitude (demo had 7; felt empty in 3D)
		queueFactor = 4, -- spawn list length = active * this (catches activate the next one)
		swarmMin = 3,
		swarmMax = 5,
		skittishRadius = 17,
		skittishTriggerSpeed = 12, -- drone faster than this scares Skittish creatures
		skittishDartSpeed = 20,
	},
	rocket = {
		-- max altitude (studs in the chapter's flight column) at engine level 1 and max
		altitude = {
			[1] = { min = 260, max = 600 },
			[2] = { min = 260, max = 600 },
		},
	},
	expedition = {
		deployGrace = 8, -- seconds between launch and battery start (deploy, camera)
		batteryGrace = 6, -- extra seconds before the server assumes the battery died
		timeoutExtra = 60, -- server force-ends a run this long after the battery must be empty
		minCatchGap = 0.25,
		resistGapFactor = 0.5, -- min seconds between catches >= resist / beamStrength * this
	},
	sizes = {
		enabled = true, -- size roll (plan/02_CONTENT.md §1d) — confirm with user in Stage 6
		list = {
			{ id = "Tiny", mult = 0.8, weight = 15 },
			{ id = "Normal", mult = 1, weight = 67.9 },
			{ id = "Big", mult = 1.3, weight = 15 },
			{ id = "Huge", mult = 1.8, weight = 2 },
			{ id = "Colossal", mult = 3, weight = 0.1 },
		},
	},
	economy = {
		incomeDivisor = 600, -- income/sec = value / 600
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
