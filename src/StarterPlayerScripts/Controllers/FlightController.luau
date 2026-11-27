--!strict
-- FlightController: the drone simulation on the X/Y flight plane (client-owned
-- for zero-latency feel), the drone model, virtual altitude -> zone detection,
-- per-zone lighting blend, battery and the rocket-limit ceiling.
-- Numbers: plan/PROGRESS.md "Approved movement numbers" (via Balance.flight).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local Chapters = require(Shared.Config.Chapters)
local ZoneLighting = require(Shared.Config.ZoneLighting)
local Signal = require(Shared.Util.Signal)

local F = Balance.flight
local ORIGIN = F.origin

local FlightController = {}
FlightController.ZoneChanged = Signal.new() -- (zone, isFirst)
FlightController.BatteryEmpty = Signal.new()
FlightController.CeilingHit = Signal.new()

export type State = {
	active: boolean,
	x: number,
	y: number,
	vx: number,
	vy: number,
	tilt: number,
	t: number,
	battery: number, -- seconds left
	batteryMax: number,
	beaming: boolean,
	peak: number,
	maxAltitude: number,
	chapter: number,
	speedMult: number,
	zoneId: string,
	locked: boolean, -- no player control (deploy / return)
	diving: boolean, -- return trip
	ceilingWarned: boolean,
	batteryFired: boolean,
	bounce: number,
}

local state: State = {
	active = false, x = 0, y = 0, vx = 0, vy = 0, tilt = 0, t = 0,
	battery = 1, batteryMax = 1, beaming = false, peak = 0, maxAltitude = 600, chapter = 1,
	speedMult = 1, zoneId = "", locked = false, diving = false, ceilingWarned = false,
	batteryFired = false, bounce = 0,
}
FlightController.state = state

-- drone model ---------------------------------------------------------------
type Rotor = { motor: Motor6D, base: CFrame, axis: Vector3, dir: number }
local model: Model? = nil
local root: BasePart? = nil
local nozzle: Attachment? = nil
local rotors: { Rotor } = {}
local rotorAngle = 0

local POSE = CFrame.Angles(math.rad(14), 0, 0) * CFrame.Angles(0, math.rad(-20), 0) -- tilted toward the camera

-- lighting ------------------------------------------------------------------
local atmosphere: Atmosphere? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local sunRays: SunRaysEffect? = nil
local savedLighting: { [Instance]: { [string]: any } } = {}
local lightingTimer = 0

local LIGHT_PROPS = { "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient" }
local ATMOS_PROPS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local CC_PROPS = { "Saturation", "Contrast", "Brightness", "TintColor" }

local function snapshot(inst: Instance?, props: { string })
	if not inst then return end
	local t = {}
	for _, p in props do t[p] = (inst :: any)[p] end
	savedLighting[inst] = t
end

local function restoreLighting()
	for inst, props in savedLighting do
		for p, v in props do (inst :: any)[p] = v end
	end
	table.clear(savedLighting)
end

local function lerpPreset(a: ZoneLighting.Preset, b: ZoneLighting.Preset, t: number): ZoneLighting.Preset
	local out: any = {}
	for k, va in a :: any do
		local vb = (b :: any)[k]
		if typeof(va) == "number" then
			out[k] = va + (vb - va) * t
		else
			out[k] = (va :: Color3):Lerp(vb, t)
		end
	end
	return out
end

local function presetAt(chapterId: number, y: number): ZoneLighting.Preset
	local zones = Chapters.get(chapterId).zones
	local band = ZoneLighting.blendBand
	local presets = ZoneLighting.presets
	local function get(z: Chapters.Zone): ZoneLighting.Preset
		return presets[z.id] or presets.LowSky
	end
	for i = 1, #zones - 1 do
		local boundary = zones[i].to
		if y < boundary - band then return get(zones[i]) end
		if y <= boundary + band then
			return lerpPreset(get(zones[i]), get(zones[i + 1]), (y - (boundary - band)) / (2 * band))
		end
	end
	return get(zones[#zones])
end

-- particle layers in FlightSpace (stars, rain...) tagged with attribute FxLayer
type FxEmitter = { emitter: ParticleEmitter, field: string, baseRate: number }
local fxEmitters: { FxEmitter } = {}
-- Parallax rig for painted sky layers and stars (camera never rotates, so flat cards work).
-- Attributes on a BasePart: SkyLockY (offset from the camera eye at the anchor altitude),
-- SkyLockZ (depth offset from the flight plane), ParallaxX/ParallaxY (0 = locked to the camera
-- = infinitely far, 1 = fixed in the world), AnchorAlt, SkyLockRoll (degrees).
type SkyLock = { part: BasePart, y: number, z: number, roll: number, kx: number, ky: number, anchorY: number }
local skyLocks: { SkyLock } = {}
-- painted images faded per zone: ImageLabels with attribute FxLayer (e.g. "skyLow" -> preset fxSkyLow)
type FxImage = { label: ImageLabel, field: string, base: number }
local fxImages: { FxImage } = {}
-- scrolling textures (drifting mist): ImageLabels with attribute ScrollSpeed (studs/s); label is one tile wider than its card
type Scroller = { label: ImageLabel, perSec: number, period: number }
local scrollers: { Scroller } = {}
local scrollT = 0

local function fxField(layer: string): string
	return "fx" .. string.upper(string.sub(layer, 1, 1)) .. string.sub(layer, 2)
end

local function collectFx()
	table.clear(fxEmitters)
	table.clear(skyLocks)
	table.clear(fxImages)
	table.clear(scrollers)
	local space = workspace:FindFirstChild("FlightSpace")
	if not space then return end
	for _, d in space:GetDescendants() do
		if d:IsA("BasePart") and typeof(d:GetAttribute("SkyLockY")) == "number" then
			table.insert(skyLocks, {
				part = d,
				y = d:GetAttribute("SkyLockY") :: number,
				z = (d:GetAttribute("SkyLockZ") or -500) :: number,
				roll = math.rad((d:GetAttribute("SkyLockRoll") or 0) :: number),
				kx = (d:GetAttribute("ParallaxX") or 0) :: number,
				ky = (d:GetAttribute("ParallaxY") or 0) :: number,
				anchorY = ORIGIN.Y + ((d:GetAttribute("AnchorAlt") or 0) :: number),
			})
		elseif d:IsA("ImageLabel") and typeof(d:GetAttribute("FxLayer")) == "string" then
			-- remember the authored transparency (see-through foreground clouds keep it when faded in)
			local base = d:GetAttribute("BaseTransparency")
			if typeof(base) ~= "number" then
				base = d.ImageTransparency
				d:SetAttribute("BaseTransparency", base)
			end
			table.insert(fxImages, { label = d, field = fxField(d:GetAttribute("FxLayer") :: string), base = base :: number })
			local speed = d:GetAttribute("ScrollSpeed")
			local card = d:FindFirstAncestorWhichIsA("BasePart")
			if typeof(speed) == "number" and card then
				table.insert(scrollers, { label = d, perSec = speed / card.Size.X, period = d.Size.X.Scale - 1 })
			end
		end
		if d:IsA("ParticleEmitter") then
			local layer = d:GetAttribute("FxLayer")
			local base = d:GetAttribute("BaseRate")
			if typeof(layer) == "string" and typeof(base) == "number" then
				table.insert(fxEmitters, { emitter = d, field = fxField(layer), baseRate = base })
			end
		end
	end
end

local lastPreset: any = nil

-- current blended value of a preset field (e.g. "fxSkyStorm" = how much of the storm set is in view)
function FlightController.weight(field: string): number
	local v = lastPreset and lastPreset[field]
	return if typeof(v) == "number" then v else 0
end

local function applyLighting(p: ZoneLighting.Preset)
	lastPreset = p
	for _, fx in fxEmitters do
		local w = (p :: any)[fx.field]
		fx.emitter.Rate = fx.baseRate * (if typeof(w) == "number" then w else 0)
	end
	for _, fi in fxImages do
		local w = (p :: any)[fi.field]
		local wc = math.clamp(if typeof(w) == "number" then w else 0, 0, 1)
		fi.label.ImageTransparency = 1 - wc * (1 - fi.base)
	end
	Lighting.GeographicLatitude = p.latitude
	Lighting.ClockTime = p.clockTime
	Lighting.Brightness = p.brightness
	Lighting.Ambient = p.ambient
	Lighting.OutdoorAmbient = p.outdoorAmbient
	if atmosphere then
		atmosphere.Density = p.atmosDensity
		atmosphere.Offset = p.atmosOffset
		atmosphere.Color = p.atmosColor
		atmosphere.Decay = p.atmosDecay
		atmosphere.Glare = p.atmosGlare
		atmosphere.Haze = p.atmosHaze
	end
	if sunRays then
		sunRays.Intensity = p.sunRays
	end
	if colorCorrection then
		colorCorrection.Saturation = p.ccSaturation
		colorCorrection.Contrast = p.ccContrast
		colorCorrection.Brightness = p.ccBrightness
		colorCorrection.TintColor = p.ccTint
	end
end

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
function FlightController.toWorld(x: number, y: number): Vector3
	return Vector3.new(ORIGIN.X + x, ORIGIN.Y + y, ORIGIN.Z)
end

function FlightController.dronePosition(): Vector3
	return FlightController.toWorld(state.x, state.y)
end

function FlightController.nozzleWorld(): Vector3
	if nozzle then return nozzle.WorldPosition end
	return FlightController.dronePosition()
end

function FlightController.nozzleAttachment(): Attachment?
	return nozzle
end

function FlightController.bounce()
	state.bounce = 1
end

local function spawnModel()
	local tpl = ReplicatedStorage.Assets.Drones:FindFirstChild("Tier1") :: Model?
	assert(tpl, "[FlightController] missing Assets.Drones.Tier1")
	local m = tpl:Clone()
	m.Name = "Drone"
	root = m.PrimaryPart
	nozzle = (root :: BasePart):FindFirstChild("Nozzle") :: Attachment?
	table.clear(rotors)
	local i = 0
	for _, r in (m:FindFirstChild("Rotors") :: Instance):GetChildren() do
		local hub = r:FindFirstChild("Hub")
		local motor = hub and hub:FindFirstChild("Spin") :: Motor6D?
		if hub and motor then
			i += 1
			local axis = hub:GetAttribute("SpinAxis")
			table.insert(rotors, {
				motor = motor, base = motor.C0,
				axis = if typeof(axis) == "Vector3" then axis else Vector3.yAxis,
				dir = if i % 2 == 0 then 1 else -1,
			})
		end
	end
	m.Parent = workspace:FindFirstChild("FlightSpace") or workspace
	model = m
end

local function updateModel(dt: number)
	if not root then return end
	state.bounce = math.max(0, state.bounce - dt * 3.2)
	-- gulp: quick dip as it swallows, then a hop up with a nose-up tilt that settles
	local e = 1 - state.bounce -- 0..1 since the catch
	local bounceY, bounceTilt = 0, 0
	if state.bounce > 0 then
		local dip = -math.sin(math.clamp(e / 0.25, 0, 1) * math.pi) * 0.35
		local hop = math.sin(math.clamp((e - 0.15) / 0.85, 0, 1) * math.pi) * 0.9
		bounceY = dip + hop
		bounceTilt = math.sin(e * math.pi * 2) * 0.16 * state.bounce
	end
	local cf = CFrame.new(FlightController.dronePosition() + Vector3.new(0, bounceY, 0))
		* CFrame.Angles(0, 0, -state.tilt + bounceTilt)
		* POSE
	root.CFrame = cf
	-- rotors: faster when moving
	local speed = math.sqrt(state.vx * state.vx + state.vy * state.vy)
	rotorAngle = (rotorAngle + dt * (32 + speed * 0.5)) % (math.pi * 2)
	for _, r in rotors do
		r.motor.C0 = r.base * CFrame.fromAxisAngle(r.axis, rotorAngle * r.dir)
	end
end

----------------------------------------------------------------------------
-- run lifecycle
----------------------------------------------------------------------------
-- run = server launch reply { chapter, maxAltitude, stats }
function FlightController.begin(run: any)
	state.active = true
	state.chapter = run.chapter
	state.maxAltitude = run.maxAltitude
	state.speedMult = run.stats.speed
	state.batteryMax = run.stats.battery
	state.battery = run.stats.battery
	state.x, state.y = 0, F.deployAltitude
	state.vx, state.vy = 0, F.deploySpeed
	state.tilt, state.t, state.peak = 0, 0, state.y
	state.beaming, state.locked, state.diving = false, false, false
	state.ceilingWarned, state.batteryFired = false, false
	state.zoneId = ""
	state.bounce = 0

	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	snapshot(Lighting, LIGHT_PROPS)
	snapshot(atmosphere, ATMOS_PROPS)
	snapshot(colorCorrection, CC_PROPS)
	snapshot(sunRays, { "Intensity" })
	collectFx()
	applyLighting(presetAt(state.chapter, state.y))
	lightingTimer = 0

	spawnModel()
	updateModel(0)
end

function FlightController.finish()
	state.active = false
	if model then model:Destroy() end
	model, root, nozzle = nil, nil, nil
	table.clear(rotors)
	for _, fx in fxEmitters do
		fx.emitter.Rate = 0
		fx.emitter:Clear()
	end
	table.clear(fxEmitters)
	table.clear(fxImages)
	table.clear(skyLocks)
	restoreLighting()
end

-- Return trip (basic, Stage 3 makes the real re-entry): controls off, dive down.
function FlightController.startDive()
	state.locked = true
	state.diving = true
end

function FlightController.update(dt: number, input: Vector2)
	if not state.active then return end
	state.t += dt
	local ix, iy = input.X, input.Y
	if state.locked then ix, iy = 0, 0 end

	-- thrust + exponential drag (demo feel)
	local thin = if state.y > F.thinAirAltitude then F.thinAirAccelMult else 1
	local accel = F.accel * state.speedMult * thin
	state.vx += ix * accel * dt
	state.vy += iy * accel * dt
	local drag = math.exp(-F.drag * dt)
	state.vx *= drag
	state.vy *= drag
	state.vy += math.sin(state.t * F.bobFrequency) * F.bobAmplitude * dt

	if state.diving then
		state.vx += (0 - state.vx) * math.min(1, dt * 3)
		state.vy += (-70 - state.vy) * math.min(1, dt * 2.5)
	else
		local maxSpeed = F.maxSpeed * state.speedMult
		local sp = math.sqrt(state.vx * state.vx + state.vy * state.vy)
		if sp > maxSpeed then
			state.vx *= maxSpeed / sp
			state.vy *= maxSpeed / sp
		end
	end

	state.x += state.vx * dt
	state.y += state.vy * dt

	if not state.diving then
		-- soft side walls, rocket ceiling, ground floor
		if math.abs(state.x) > F.halfWidth then
			state.vx -= math.sign(state.x) * F.edgePush * dt
		end
		if state.y > state.maxAltitude then
			state.vy -= (state.y - state.maxAltitude) * F.ceilingSpring * dt
			if not state.ceilingWarned then
				state.ceilingWarned = true
				FlightController.CeilingHit:Fire()
			end
		end
		if state.y < F.floor then
			state.vy += (F.floor - state.y) * F.floorSpring * dt
		end
	end

	-- tilt leans into horizontal speed
	local targetTilt = math.clamp(state.vx * F.tiltPerSpeed, -F.maxTilt, F.maxTilt)
	state.tilt += (targetTilt - state.tilt) * (1 - math.exp(-F.tiltSmoothing * dt))

	-- battery
	if not state.diving then
		state.battery -= dt * (if state.beaming then Balance.beam.batteryDrainMult else 1)
		if state.battery <= 0 then
			state.battery = 0
			if not state.batteryFired then
				state.batteryFired = true
				FlightController.BatteryEmpty:Fire()
			end
		end
	end

	state.peak = math.max(state.peak, state.y)

	-- zone detection
	local zone = Chapters.zoneAt(state.chapter, math.max(0, state.y))
	if zone.id ~= state.zoneId then
		local first = state.zoneId == ""
		state.zoneId = zone.id
		FlightController.ZoneChanged:Fire(zone, first)
	end

	-- lighting at 10 Hz (property writes are not free)
	lightingTimer -= dt
	if lightingTimer <= 0 then
		lightingTimer = 0.1
		applyLighting(presetAt(state.chapter, math.max(0, state.y)))
	end

	updateModel(dt)
end

-- call after the camera moved this frame
function FlightController.updateSky()
	scrollT = state.t
	for _, s in scrollers do
		if s.period > 0 then
			s.label.Position = UDim2.fromScale(-((scrollT * s.perSec) % s.period), 0)
		end
	end
	if #skyLocks == 0 then return end
	local cam = workspace.CurrentCamera.CFrame.Position
	for _, s in skyLocks do
		local x = cam.X + (ORIGIN.X - cam.X) * s.kx
		local y = cam.Y + s.y + (s.anchorY - cam.Y) * s.ky
		s.part.CFrame = CFrame.new(x, y, ORIGIN.Z + s.z) * CFrame.Angles(0, 0, s.roll)
	end
end

-- camera target: drone + velocity lead
function FlightController.cameraTarget(): Vector3
	local p = FlightController.dronePosition()
	if state.diving then return p end
	return p + Vector3.new(state.vx * F.cameraLeadX, state.vy * F.cameraLeadY, 0)
end

return FlightController
