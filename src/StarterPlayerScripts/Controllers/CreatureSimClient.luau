--!strict
-- CreatureSimClient: simulates and renders the run's creatures from the shared
-- deterministic spawn plan. Behaviours in Stage 1: Drifter, Skittish (darts away
-- from a fast-approaching drone, like a fish), Swarm (schools; members orbit a
-- moving centre). Others fall back to Drifter until Stage 3.
-- Epic creatures blink away while being pulled (Shared/EpicBlink, Balance.epicBlink).
-- Models are pooled per creature id and only exist near the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local SpawnGen = require(Shared.SpawnGen)
local EpicBlink = require(Shared.EpicBlink)
local CatchEvents = require(script.Parent.CatchEvents)

local F = Balance.flight
local S = Balance.spawns
local EB = Balance.epicBlink
local ORIGIN = F.origin
local TWO_PI = math.pi * 2

local CreatureSimClient = {}

export type Live = {
	spawn: SpawnGen.Spawn,
	def: Creatures.Creature,
	rarity: Rarities.Rarity,
	zoneFrom: number,
	zoneTo: number,
	x: number,
	y: number,
	vx: number, -- wander drift
	dartX: number, -- skittish escape velocity
	dartY: number,
	ph: number,
	facing: number, -- 1 right, -1 left
	yaw: number, -- smoothed render yaw
	pitch: number, -- smoothed nose up/down
	px: number, -- previous position (for the real velocity)
	py: number,
	svx: number, -- smoothed velocity
	svy: number,
	progress: number, -- beam pull 0..1
	beamed: boolean, -- in the beam this frame
	pending: boolean, -- catch request in flight
	caught: boolean,
	intake: number, -- 0..1 intake animation after a confirmed catch
	intakeFrom: Vector2,
	catchInfo: CatchEvents.CatchInfo?, -- set on a confirmed catch; Landed fires with it
	revealed: boolean, -- false = a Hidden creature the scanner hasn't found (not drawn, not beamable)
	blink: EpicBlink.BlinkPlan?, -- Epic only: deterministic blink plan
	blinksDone: number,
	regrab: number, -- seconds left before the beam can grab it again after a blink
	vanish: number, -- seconds left of the shrink-out before it jumps
	appear: number, -- 0..1 pop-in after the jump (1 = normal)
	blinkToX: number,
	blinkToY: number,
	blinkScaled: boolean, -- model is currently scaled by the blink effect
	scale: number,
	model: Model?,
	root: BasePart?,
	light: PointLight?,
	done: boolean,
}

type Group = { cx: number, cy: number, vx: number, ph: number, members: number }

local live: { Live } = {}
local groups: { [number]: Group } = {}
local zoneQueues: { [string]: { queue: { SpawnGen.Spawn }, nextIndex: number, from: number, to: number } } = {}
local pools: { [string]: { Model } } = {}
local folder: Folder? = nil

local VIEW_X = 75 -- studs from camera centre where models exist
local VIEW_Y = 48
local CAM_PITCH = CFrame.Angles(math.rad(10), 0, 0)
-- heading: model faces +X; turning to -X goes through -pi/2 (facing the camera)
local YAW_RIGHT = math.rad(-12) -- slight 3/4 turn toward the camera
local YAW_LEFT = -math.pi + math.rad(12)
local MAX_PITCH = math.rad(55)
local HIDDEN = CFrame.new(0, -10000, 0)
local INTAKE_TIME = 0.45 -- seconds from confirmed catch to swallowed
local FLASH_TIME = 0.22

-- intake flash: one part per run (light + sparkles), reused for every catch
local flash: BasePart? = nil
local flashLight: PointLight? = nil
local flashEmitter: ParticleEmitter? = nil
local flashLeft = 0

-- blink effects: two parts per run (vanish spot, appear spot), reused for every blink
type BlinkFx = { part: BasePart, light: PointLight, emitter: ParticleEmitter, left: number }
local blinkFx: { BlinkFx } = {}
local BLINK_FX_TIME = 0.3
local runSeed = 0

----------------------------------------------------------------------------
-- models (pooled)
----------------------------------------------------------------------------
local TINT_PARTS = { Body = true, Rear = true, Tuft1 = true, Tuft2 = true, Tuft3 = true, Tuft4 = true }
local FIN_PARTS = { Fin = true, TailTop = true, TailBot = true }

local function buildModel(def: Creatures.Creature, rarity: Rarities.Rarity, scale: number): Model
	local tpl = ReplicatedStorage.Assets.Creatures:FindFirstChild(def.id)
		or ReplicatedStorage.Assets.Creatures:FindFirstChild("Placeholder")
	assert(tpl and tpl:IsA("Model"), "[CreatureSimClient] missing creature template")
	local m = tpl:Clone()
	m.Name = def.id
	if tpl.Name == "Placeholder" then
		-- greybox tint (final models arrive in Stage 6)
		local fin = def.color:Lerp(Color3.new(0, 0, 0), 0.25)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				if TINT_PARTS[p.Name] then p.Color = def.color
				elseif FIN_PARTS[p.Name] then p.Color = fin; p.Transparency = 0.1
				elseif p.Name == "Belly" then p.Color = def.color:Lerp(Color3.new(1, 1, 1), 0.5) end
			end
		end
		local hl = m:FindFirstChildOfClass("Highlight")
		if hl then hl.OutlineColor = def.color:Lerp(Color3.new(0, 0, 0), 0.45) end
	end
	m:ScaleTo(scale)
	local root = m.PrimaryPart :: BasePart
	if rarity.rank >= 2 then
		-- rarity glow (Uncommon+): soft light in the rarity colour
		local light = Instance.new("PointLight")
		light.Name = "RarityGlow"
		light.Color = rarity.color
		light.Range = 6 + rarity.rank * 2
		light.Brightness = 0.6 + rarity.rank * 0.35
		light.Shadows = false
		light.Parent = root
		local hl = m:FindFirstChildOfClass("Highlight")
		if hl and rarity.rank >= 3 then
			hl.OutlineColor = rarity.color
			hl.OutlineTransparency = 0.25
		end
	end
	return m
end

local function acquire(l: Live)
	local pool = pools[l.def.id]
	local m = if pool and #pool > 0 then table.remove(pool) else nil
	if not m then m = buildModel(l.def, l.rarity, l.scale) end
	m.Parent = folder
	l.model = m
	l.root = m.PrimaryPart
	l.light = (m.PrimaryPart :: BasePart):FindFirstChild("RarityGlow") :: PointLight?
end

local function release(l: Live)
	local m = l.model
	if not m then return end
	if l.root then l.root.CFrame = HIDDEN end
	if math.abs(m:GetScale() - l.scale) > 1e-3 then m:ScaleTo(l.scale) end -- undo intake shrink
	m.Parent = nil
	pools[l.def.id] = pools[l.def.id] or {}
	table.insert(pools[l.def.id], m)
	l.model, l.root, l.light = nil, nil, nil
end

----------------------------------------------------------------------------
-- spawning
----------------------------------------------------------------------------
local function scaleFor(r: Rarities.Rarity): number
	return 0.72 + (r.rank - 1) * 0.06 -- placeholder ~5.7 studs (≈ drone size); rarer = slightly bigger
end

local function activate(s: SpawnGen.Spawn)
	local def = Creatures.byId[s.creature]
	local rarity = Rarities.byId[def.rarity]
	local zq = zoneQueues[s.zone]
	local l: Live = {
		spawn = s, def = def, rarity = rarity,
		zoneFrom = zq.from, zoneTo = zq.to,
		x = s.x, y = s.y,
		vx = (math.sin(s.phase * 3.1) * 3),
		dartX = 0, dartY = 0,
		ph = s.phase,
		facing = if math.sin(s.phase * 3.1) >= 0 then 1 else -1,
		yaw = if math.sin(s.phase * 3.1) >= 0 then YAW_RIGHT else YAW_LEFT,
		pitch = 0, px = s.x, py = s.y, svx = 0, svy = 0,
		progress = 0, beamed = false, pending = false, caught = false,
		intake = 0, intakeFrom = Vector2.zero,
		catchInfo = nil,
		blink = if EpicBlink.applies(rarity.id) then EpicBlink.plan(runSeed, s.id) else nil,
		blinksDone = 0, regrab = 0, vanish = 0, appear = 1, blinkToX = 0, blinkToY = 0, blinkScaled = false,
		revealed = not (def.behavior == "Hidden" and Balance.scanner.hideHidden),
		scale = scaleFor(rarity),
		model = nil, root = nil, light = nil, done = false,
	}
	if def.behavior == "Swarm" then
		local g = groups[s.group]
		if not g then
			g = { cx = s.x, cy = s.y, vx = math.sin(s.phase * 2.3) * 3, ph = s.phase, members = 0 }
			groups[s.group] = g
		end
		g.members += 1
		l.x = g.cx + math.cos(s.slot * 1.9) * 4
		l.y = g.cy + math.sin(s.slot * 1.9) * 2.5
	end
	l.px, l.py = l.x, l.y
	table.insert(live, l)
end

-- activate the next queued spawn in a zone (whole swarm groups at once)
local function activateNext(zoneId: string)
	local zq = zoneQueues[zoneId]
	if not zq then return end
	local s = zq.queue[zq.nextIndex]
	if not s then return end
	local group = s.group
	repeat
		activate(s)
		zq.nextIndex += 1
		s = zq.queue[zq.nextIndex]
	until not s or s.group ~= group
end

local function buildBlinkFx(parent: Instance): BlinkFx
	local p = Instance.new("Part")
	p.Name = "BlinkFx"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.5
	p.CFrame = HIDDEN
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = p
	local em = Instance.new("ParticleEmitter")
	em.Enabled = false
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.25, 0.45)
	em.Speed = NumberRange.new(6, 14)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Drag = 4
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	em.LightEmission = 1
	em.Parent = p
	p.Parent = parent
	return { part = p, light = light, emitter = em, left = 0 }
end

local function playBlinkFx(fx: BlinkFx?, x: number, y: number, color: Color3)
	if not fx then return end
	fx.part.CFrame = CFrame.new(ORIGIN.X + x, ORIGIN.Y + y, ORIGIN.Z)
	fx.light.Color = color
	fx.light.Brightness = 4
	fx.left = BLINK_FX_TIME
	fx.emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	fx.emitter:Emit(12)
end

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------
function CreatureSimClient.begin(plan: SpawnGen.Plan)
	CreatureSimClient.finish()
	runSeed = plan.seed
	local f = Instance.new("Folder")
	f.Name = "Creatures"
	f.Parent = workspace:FindFirstChild("FlightSpace") or workspace
	folder = f
	local fp = Instance.new("Part")
	fp.Name = "IntakeFlash"
	fp.Anchored, fp.CanCollide, fp.CanQuery, fp.CanTouch, fp.CastShadow = true, false, false, false, false
	fp.Transparency = 1
	fp.Size = Vector3.one * 0.5
	fp.CFrame = HIDDEN
	local fl = Instance.new("PointLight")
	fl.Color = Color3.fromRGB(255, 244, 200)
	fl.Range = 16
	fl.Brightness = 0
	fl.Shadows = false
	fl.Parent = fp
	local em = Instance.new("ParticleEmitter")
	em.Enabled = false
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.2, 0.35)
	em.Speed = NumberRange.new(10, 18)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(Color3.fromRGB(255, 252, 225), Color3.fromRGB(255, 214, 120))
	em.LightEmission = 1
	em.Parent = fp
	fp.Parent = f
	flash, flashLight, flashEmitter, flashLeft = fp, fl, em, 0
	blinkFx = { buildBlinkFx(f), buildBlinkFx(f) }
	for _, zp in plan.zones do
		zoneQueues[zp.zone] = { queue = zp.queue, nextIndex = 1, from = zp.from, to = zp.to }
		-- activate exactly `active` entries (a swarm straddling the limit comes in whole)
		while zoneQueues[zp.zone].nextIndex <= zp.active do
			activateNext(zp.zone)
		end
	end
end

function CreatureSimClient.finish()
	for _, l in live do release(l) end
	table.clear(live)
	table.clear(groups)
	table.clear(zoneQueues)
	if folder then folder:Destroy() end
	folder = nil
	flash, flashLight, flashEmitter, flashLeft = nil, nil, nil, 0
	table.clear(blinkFx) -- parts die with the folder
	-- pooled models were parented to nil; drop them so a new run rebuilds cleanly
	for _, pool in pools do
		for _, m in pool do m:Destroy() end
	end
	table.clear(pools)
end

function CreatureSimClient.list(): { Live }
	return live
end

-- Can the beam (and auto-aim) target it right now?
function CreatureSimClient.isTargetable(l: Live): boolean
	return l.revealed and not l.caught and not l.pending and l.regrab <= 0
end

-- Called by the beam after it adds progress. An Epic that crosses its next blink
-- threshold blinks: the link breaks (progress drops, not targetable for
-- regrabDelay) and it jumps behind / left / right of the beam origin (bx, by).
-- Returns true if it blinked.
function CreatureSimClient.tryBlink(l: Live, bx: number, by: number): boolean
	local plan = l.blink
	if not plan or l.blinksDone >= plan.count or l.pending or l.caught then return false end
	if l.progress < EB.thresholds[l.blinksDone + 1] then return false end
	l.blinksDone += 1
	l.blinkToX, l.blinkToY = EpicBlink.spot(plan.spots[l.blinksDone], bx, by, l.x, l.y, l.zoneFrom, l.zoneTo)
	l.progress = EB.keepProgress
	l.beamed = false
	l.regrab = EB.regrabDelay
	l.vanish = EB.vanishTime
	l.dartX, l.dartY = 0, 0
	playBlinkFx(blinkFx[1], l.x, l.y, l.rarity.color)
	return true
end

-- Scanner found a Hidden creature: draw it and let the beam target it.
function CreatureSimClient.reveal(l: Live)
	l.revealed = true
end

-- server confirmed the catch: play the intake (fires CatchEvents.Landed when it ends)
-- and replace it in the sky
function CreatureSimClient.confirmCatch(l: Live, info: CatchEvents.CatchInfo)
	l.caught = true
	l.pending = false
	l.revealed = true
	l.catchInfo = info
	l.intake = 0
	l.intakeFrom = Vector2.new(l.x, l.y)
	local g = groups[l.spawn.group]
	if g then g.members -= 1 end
	activateNext(l.spawn.zone)
end

-- server refused (or cargo full): let it go again
function CreatureSimClient.rejectCatch(l: Live)
	l.pending = false
	l.progress = 0.55
end

----------------------------------------------------------------------------
-- simulation
----------------------------------------------------------------------------
local function stepBehaviour(l: Live, dt: number, droneX: number, droneY: number, droneSpeed: number)
	local b = l.def.behavior
	l.ph += dt
	if b == "Swarm" then
		local g = groups[l.spawn.group]
		if g then
			local n = math.max(1, g.members)
			local a = g.ph * 1.2 + l.spawn.slot * TWO_PI / n
			local tx = g.cx + math.cos(a) * (3 + n * 0.6)
			local ty = g.cy + math.sin(a) * (2 + n * 0.35)
			local k = 1 - math.exp(-3 * dt)
			if not l.beamed then
				l.x += (tx - l.x) * k
				l.y += (ty - l.y) * k
			end
			l.facing = if g.vx >= 0 then 1 else -1
		end
	else
		-- Drifter (and fallback): lazy wander
		l.x += (l.vx + math.cos(l.ph * 0.7) * 2.2) * dt
		l.y += math.sin(l.ph * 1.1) * 1.8 * dt
		if math.abs(l.vx) > 0.3 then l.facing = if l.vx > 0 then 1 else -1 end
	end

	if b == "Skittish" and l.progress < 0.05 and not l.pending then
		local dx, dy = l.x - droneX, l.y - droneY
		local d = math.sqrt(dx * dx + dy * dy)
		if d < S.skittishRadius and d > 0.01 and droneSpeed > S.skittishTriggerSpeed then
			l.dartX = dx / d * S.skittishDartSpeed
			l.dartY = dy / d * S.skittishDartSpeed * 0.75
			l.facing = if dx > 0 then 1 else -1
		end
	end
	if l.dartX ~= 0 or l.dartY ~= 0 then
		l.x += l.dartX * dt
		l.y += l.dartY * dt
		local decay = math.exp(-2.2 * dt)
		l.dartX *= decay
		l.dartY *= decay
		if math.abs(l.dartX) + math.abs(l.dartY) < 0.3 then l.dartX, l.dartY = 0, 0 end
	end

	-- stay in the zone band and the flight width
	local hw = F.halfWidth + 10
	if l.x > hw then l.vx = -math.abs(l.vx); l.x -= (l.x - hw) * dt
	elseif l.x < -hw then l.vx = math.abs(l.vx); l.x += (-hw - l.x) * dt end
	if l.y > l.zoneTo then l.y -= (l.y - l.zoneTo) * 2 * dt
	elseif l.y < l.zoneFrom then l.y += (l.zoneFrom - l.y) * 2 * dt end
end

local function stepGroups(dt: number)
	for _, g in groups do
		g.ph += dt
		g.cx += (g.vx + math.cos(g.ph * 0.5) * 2) * dt
		g.cy += math.sin(g.ph * 0.8) * 2 * dt
		local hw = F.halfWidth
		if g.cx > hw then g.vx = -math.abs(g.vx) elseif g.cx < -hw then g.vx = math.abs(g.vx) end
	end
end

-- droneX/Y: flight-plane coords; nozzle: world position; camX/Y: camera centre (flight coords)
function CreatureSimClient.update(dt: number, droneX: number, droneY: number, droneSpeed: number, nozzle: Vector3, camX: number, camY: number)
	stepGroups(dt)
	-- intake flash decay
	if flashLeft > 0 and flashLight then
		flashLeft = math.max(0, flashLeft - dt)
		local k = flashLeft / FLASH_TIME
		flashLight.Brightness = 6 * k * k
	end
	for _, fx in blinkFx do
		if fx.left > 0 then
			fx.left = math.max(0, fx.left - dt)
			local k = fx.left / BLINK_FX_TIME
			fx.light.Brightness = 4 * k * k
		end
	end
	local i = 1
	while i <= #live do
		local l = live[i]
		if l.regrab > 0 then l.regrab = math.max(0, l.regrab - dt) end
		if l.vanish > 0 then
			-- shrinking out at the old spot; then jump and pop in at the new one
			l.vanish -= dt
			if l.vanish <= 0 then
				l.vanish = 0
				l.x, l.y = l.blinkToX, l.blinkToY
				l.px, l.py = l.x, l.y -- no velocity spike from the jump
				l.svx, l.svy = 0, 0
				l.appear = 0
				playBlinkFx(blinkFx[2], l.x, l.y, l.rarity.color)
			end
		elseif l.appear < 1 then
			l.appear = math.min(1, l.appear + dt / EB.appearTime)
		end
		if l.caught then
			-- intake: corkscrew along the beam line to the nozzle (accelerating), then swallowed
			l.intake = math.min(1, l.intake + dt / INTAKE_TIME)
			local t = l.intake * l.intake
			local nx, ny = nozzle.X - ORIGIN.X, nozzle.Y - ORIGIN.Y
			local dx, dy = l.intakeFrom.X - nx, l.intakeFrom.Y - ny
			-- centre travels the straight beam line; the offset swings around it and shrinks
			local ang = l.intake * 9
			local rad = math.sin(l.intake * math.pi) * 2.5 * (1 - l.intake)
			local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
			local px, py = -dy / len, dx / len -- perpendicular to the beam
			l.x = nx + dx * (1 - t) + px * rad * math.cos(ang)
			l.y = ny + dy * (1 - t) + py * rad * math.sin(ang)
			if l.intake >= 1 then
				l.done = true
				if flash and flashLight and flashEmitter then
					flash.CFrame = CFrame.new(nozzle)
					flashLight.Brightness = 6
					flashLeft = FLASH_TIME
					flashEmitter:Emit(8)
				end
				local info = l.catchInfo
				if info then CatchEvents.Landed:Fire(info) end
			end
		elseif not l.pending and l.vanish <= 0 then
			stepBehaviour(l, dt, droneX, droneY, droneSpeed)
		end

		if l.done then
			release(l)
			live[i] = live[#live]
			live[#live] = nil
			continue
		end

		-- render only near the camera
		local near = l.revealed and math.abs(l.x - camX) < VIEW_X and math.abs(l.y - camY) < VIEW_Y
		if near and not l.model then acquire(l) elseif not near and l.model then release(l) end
		-- 3D heading from the actual motion (behaviour + beam pull), smoothed
		if dt > 0 then
			local k = 1 - math.exp(-6 * dt)
			l.svx += ((l.x - l.px) / dt - l.svx) * k
			l.svy += ((l.y - l.py) / dt - l.svy) * k
		end
		l.px, l.py = l.x, l.y

		local root = l.root
		if root then
			-- facing: follow horizontal motion (hysteresis); while pulled it strains AWAY from the drone
			if l.beamed or l.pending then
				l.facing = if droneX >= l.x then -1 else 1
			elseif l.svx > 0.6 then
				l.facing = 1
			elseif l.svx < -0.6 then
				l.facing = -1
			end
			-- yaw passes through the camera side (-pi/2) when turning, so it turns toward us
			local targetYaw = if l.facing >= 0 then YAW_RIGHT else YAW_LEFT
			l.yaw += (targetYaw - l.yaw) * (1 - math.exp(-5 * dt))
			-- pitch: nose up when rising, down when sinking (beam pull = straining away)
			local vx, vy = math.abs(l.svx), l.svy
			if l.beamed or l.pending then vy = -vy end
			local targetPitch = math.clamp(math.atan2(vy, math.max(vx, 2)), -MAX_PITCH, MAX_PITCH)
			l.pitch += (targetPitch - l.pitch) * (1 - math.exp(-5 * dt))
			-- bank into turns (fast yaw change) + gentle idle roll
			local bob = math.sin(l.ph * 2.2) * 0.25
			local roll = math.sin(l.ph * 1.6) * 0.06 + math.clamp((targetYaw - l.yaw) * 0.25, -0.35, 0.35)
			-- squash & stretch: bulge back first, stretch while flying in, squash at the intake
			local shrink = 1
			local stretchPitch, stretchRoll = 0, 0
			if l.caught then
				local u = l.intake
				if u < 0.2 then
					shrink = 1 + 0.18 * math.sin(u / 0.2 * math.pi * 0.5) -- wind-up bulge
				else
					local v = (u - 0.2) / 0.8
					shrink = 1.18 * (1 - v * v) * (1 + 0.12 * math.sin(v * math.pi * 3)) + 0.05 * v * v
				end
				-- lean into the pull and tumble
				stretchPitch = math.sin(u * math.pi) * 0.5
				stretchRoll = u * u * 5
			end
			-- beamed: faster, bigger wobble as the pull locks in + a small lean toward the drone
			local wobble = 0
			if l.beamed then
				local pr = math.clamp(l.progress, 0, 1)
				local lean = math.clamp(math.atan2(droneY - l.y, math.max(math.abs(droneX - l.x), 2)), -0.6, 0.6)
				wobble = math.sin(l.ph * (30 + 25 * pr)) * (0.04 + 0.08 * pr) * pr + lean * 0.25 * pr
			end
			local cf = CFrame.new(ORIGIN.X + l.x, ORIGIN.Y + l.y + bob, ORIGIN.Z)
				* CAM_PITCH
				* CFrame.Angles(0, l.yaw, 0)
				* CFrame.Angles(roll + stretchRoll, 0, l.pitch + wobble + stretchPitch)
			root.CFrame = cf
			if l.caught then
				-- intake pulse (scale is restored on release)
				(l.model :: Model):ScaleTo(math.max(0.05, l.scale * shrink))
			elseif l.vanish > 0 or l.appear < 1 then
				-- blink: shrink out, then pop back in with a small overshoot
				local a = l.appear
				local b = if l.vanish > 0 then l.vanish / EB.vanishTime
					else 1 - (1 - a) ^ 3 + 0.3 * math.sin(a * math.pi) * (1 - a)
				local m = l.model :: Model
				m:ScaleTo(math.max(0.05, l.scale * b))
				l.blinkScaled = true
			elseif l.blinkScaled then
				local m = l.model :: Model
				m:ScaleTo(l.scale)
				l.blinkScaled = false
			end
			if l.light then
				l.light.Brightness = (0.6 + l.rarity.rank * 0.35) * (0.75 + 0.25 * math.sin(l.ph * 3)) * (1 + l.progress)
			end
		end
		i += 1
	end
end

return CreatureSimClient
