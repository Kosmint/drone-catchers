--!strict
-- CreatureSimClient: simulates and renders the run's creatures from the shared
-- deterministic spawn plan. Behaviours in Stage 1: Drifter, Skittish (darts away
-- from a fast-approaching drone, like a fish), Swarm (schools; members orbit a
-- moving centre). Others fall back to Drifter until Stage 3.
-- Models are pooled per creature id and only exist near the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local SpawnGen = require(Shared.SpawnGen)

local F = Balance.flight
local S = Balance.spawns
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
	progress: number, -- beam pull 0..1
	beamed: boolean, -- in the beam this frame
	pending: boolean, -- catch request in flight
	caught: boolean,
	intake: number, -- 0..1 intake animation after a confirmed catch
	intakeFrom: Vector2,
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
local YAW_RIGHT = math.rad(0) -- placeholder already faces +X turned toward camera
local HIDDEN = CFrame.new(0, -10000, 0)

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
		yaw = 0,
		progress = 0, beamed = false, pending = false, caught = false,
		intake = 0, intakeFrom = Vector2.zero,
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

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------
function CreatureSimClient.begin(plan: SpawnGen.Plan)
	CreatureSimClient.finish()
	local f = Instance.new("Folder")
	f.Name = "Creatures"
	f.Parent = workspace:FindFirstChild("FlightSpace") or workspace
	folder = f
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
	-- pooled models were parented to nil; drop them so a new run rebuilds cleanly
	for _, pool in pools do
		for _, m in pool do m:Destroy() end
	end
	table.clear(pools)
end

function CreatureSimClient.list(): { Live }
	return live
end

-- server confirmed the catch: play the intake and replace it in the sky
function CreatureSimClient.confirmCatch(l: Live)
	l.caught = true
	l.pending = false
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
	local i = 1
	while i <= #live do
		local l = live[i]
		if l.caught then
			-- intake: spiral toward the nozzle, shrink, vanish
			l.intake = math.min(1, l.intake + dt / 0.35)
			local t = l.intake * l.intake
			local nx, ny = nozzle.X - ORIGIN.X, nozzle.Y - ORIGIN.Y
			local spin = (1 - t) * 2.5
			local ox = (l.intakeFrom.X - nx) * (1 - t)
			local oy = (l.intakeFrom.Y - ny) * (1 - t)
			l.x = nx + ox * math.cos(spin * t * 6) - oy * math.sin(spin * t * 6)
			l.y = ny + ox * math.sin(spin * t * 6) + oy * math.cos(spin * t * 6)
			if l.intake >= 1 then
				l.done = true
			end
		elseif not l.pending then
			stepBehaviour(l, dt, droneX, droneY, droneSpeed)
		end

		if l.done then
			release(l)
			live[i] = live[#live]
			live[#live] = nil
			continue
		end

		-- render only near the camera
		local near = math.abs(l.x - camX) < VIEW_X and math.abs(l.y - camY) < VIEW_Y
		if near and not l.model then acquire(l) elseif not near and l.model then release(l) end
		local root = l.root
		if root then
			local targetYaw = if l.facing >= 0 then YAW_RIGHT else math.pi - YAW_RIGHT
			-- face the drone while being pulled (it "looks back" as it struggles)
			if l.beamed or l.pending then targetYaw = if droneX >= l.x then YAW_RIGHT else math.pi - YAW_RIGHT end
			l.yaw += (targetYaw - l.yaw) * (1 - math.exp(-6 * dt))
			local bob = math.sin(l.ph * 2.2) * 0.25
			local roll = math.sin(l.ph * 1.6) * 0.06
			local shrink = if l.caught then 1 - l.intake * l.intake * 0.9 else 1
			local wobble = if l.beamed then math.sin(l.ph * 30) * 0.08 * l.progress else 0
			local cf = CFrame.new(ORIGIN.X + l.x, ORIGIN.Y + l.y + bob, ORIGIN.Z)
				* CAM_PITCH
				* CFrame.Angles(0, l.yaw, roll + wobble)
			root.CFrame = cf
			if shrink < 0.999 then
				-- intake shrink (one creature for 0.35 s; scale is restored on release)
				(l.model :: Model):ScaleTo(math.max(0.05, l.scale * shrink))
			end
			if l.light then
				l.light.Brightness = (0.6 + l.rarity.rank * 0.35) * (0.75 + 0.25 * math.sin(l.ph * 3)) * (1 + l.progress)
			end
		end
		i += 1
	end
end

return CreatureSimClient
