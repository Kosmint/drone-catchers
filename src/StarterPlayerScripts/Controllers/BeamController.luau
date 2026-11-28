--!strict
-- BeamController: the suction beam. Aim (mouse / right stick / touch auto-aim),
-- cone targeting, pull progress (beamStrength / resistance), Rare+ struggle,
-- swarm multi-pull, catch requests to the server (which rolls modifier + size).
-- Visuals (built once per run): rarity-tinted glow + core wedge, energy tether with
-- flowing particles, progress tag, struggle kick and catch-snap flash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)
local Signal = require(Shared.Util.Signal)
local CreatureSimClient = require(script.Parent.CreatureSimClient)
local CatchEvents = require(script.Parent.CatchEvents)

local B = Balance.beam
local ORIGIN = Balance.flight.origin
local BEAM_CYAN = Color3.fromRGB(79, 216, 255)
local BEAM_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local KICK_TIME = 0.15
local FLASH_TIME = 0.2

local BeamController = {}
-- A confirmed catch fires CatchEvents.Caught(info, live) (see CatchEvents).
BeamController.CargoFull = Signal.new()
BeamController.Struggle = Signal.new() -- (live)

local run: any = nil
local runToken = 0
local cargoCount = 0
local pendingCount = 0
local fullWarned = false
local aimDir = Vector2.new(1, 0)
local rng = Random.new()
local t = 0

-- visuals
local folder: Folder? = nil
local endPart: BasePart? = nil
local tetherPart: BasePart? = nil
local wedge: Beam? = nil -- outer glow
local core: Beam? = nil
local tether: Beam? = nil
local tetherCore: Beam? = nil
local flow: ParticleEmitter? = nil
local flashPart: BasePart? = nil
local flashEmitter: ParticleEmitter? = nil
local flashT = 0 -- remaining catch-flash time
local kickT = 0 -- remaining struggle-kick time
local smoothProg = 0
local tag: BillboardGui? = nil
local tagFill: Frame? = nil
local tagLabel: TextLabel? = nil
local nozzleLight: PointLight? = nil

local function anchorPart(name: string, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function buildVisuals(nozzle: Attachment?)
	local f = Instance.new("Folder")
	f.Name = "Beam"
	f.Parent = workspace:FindFirstChild("FlightSpace") or workspace
	folder = f
	local e = anchorPart("BeamEnd", f)
	local ea = Instance.new("Attachment"); ea.Parent = e
	local tp = anchorPart("Tether", f)
	local ta = Instance.new("Attachment"); ta.Parent = tp
	endPart, tetherPart = e, tp

	-- outer glow: wide, saturated, only partly additive so it still shows over white clouds
	local w = Instance.new("Beam")
	w.Name = "Glow"
	w.Attachment0 = nozzle
	w.Attachment1 = ea
	w.FaceCamera = true
	w.LightEmission = 0.4
	w.LightInfluence = 0
	w.Segments = 1
	w.Width0 = 0.9
	w.Width1 = 18
	w.Enabled = false
	w.Parent = e
	wedge = w

	-- bright core: narrow, fully additive, scrolling sparkle texture
	local c = Instance.new("Beam")
	c.Name = "Core"
	c.Attachment0 = nozzle
	c.Attachment1 = ea
	c.FaceCamera = true
	c.LightEmission = 1
	c.LightInfluence = 0
	c.Segments = 1
	c.Texture = BEAM_TEXTURE
	c.TextureMode = Enum.TextureMode.Wrap
	c.TextureLength = 4
	c.Width0 = 0.4
	c.Width1 = 5
	c.Enabled = false
	c.Parent = e
	core = c

	-- tether: curvy energy line to the target (outer + inner so it reads on any background)
	local th = Instance.new("Beam")
	th.Name = "Tether"
	th.Attachment0 = nozzle
	th.Attachment1 = ta
	th.FaceCamera = true
	th.LightEmission = 0.5
	th.LightInfluence = 0
	th.Segments = 24
	th.Width0 = 0.5
	th.Width1 = 1.6
	th.Enabled = false
	th.Parent = tp
	tether = th

	local ti = Instance.new("Beam")
	ti.Name = "TetherCore"
	ti.Attachment0 = nozzle
	ti.Attachment1 = ta
	ti.FaceCamera = true
	ti.LightEmission = 1
	ti.LightInfluence = 0
	ti.Segments = 24
	ti.Texture = BEAM_TEXTURE
	ti.TextureMode = Enum.TextureMode.Wrap
	ti.TextureLength = 2
	ti.Width0 = 0.2
	ti.Width1 = 0.7
	ti.Enabled = false
	ti.Parent = tp
	tetherCore = ti

	-- particles flowing from the creature toward the nozzle (part is oriented toward the nozzle)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Flow"
	pe.Texture = BEAM_TEXTURE
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Lifetime = NumberRange.new(0.5)
	pe.Speed = NumberRange.new(20)
	pe.Rate = 0
	pe.Enabled = false
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = tp
	flow = pe

	-- catch flash at the nozzle (Emit on Caught)
	local fp = anchorPart("Flash", f)
	local fe = Instance.new("ParticleEmitter")
	fe.Name = "Snap"
	fe.Texture = BEAM_TEXTURE
	fe.Rate = 0
	fe.Lifetime = NumberRange.new(0.25)
	fe.Speed = NumberRange.new(0)
	fe.LightEmission = 1
	fe.LightInfluence = 0
	fe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 7),
	})
	fe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fe.Parent = fp
	flashPart, flashEmitter = fp, fe

	-- progress tag above the creature being pulled
	local bb = Instance.new("BillboardGui")
	bb.Name = "PullTag"
	bb.Size = UDim2.fromOffset(96, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Adornee = tp
	bb.Parent = tp
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = bb
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(13, 19, 36)
	bar.BackgroundTransparency = 0.25
	bar.Position = UDim2.fromOffset(8, 17)
	bar.Size = UDim2.new(1, -16, 0, 8)
	bar.Parent = bb
	local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(1, 0); c1.Parent = bar
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(1, 0); c2.Parent = fill
	tag, tagFill, tagLabel = bb, fill, label

	nozzleLight = if nozzle then nozzle:FindFirstChildOfClass("PointLight") else nil
end

----------------------------------------------------------------------------
-- catching
----------------------------------------------------------------------------
local function requestCatch(l: CreatureSimClient.Live)
	l.pending = true
	l.beamed = false
	pendingCount += 1
	local token = runToken
	local runId = run.runId
	task.spawn(function()
		local ok, res = pcall(Net.invoke, "ReportCatch", runId, l.spawn.id)
		if token ~= runToken then return end -- run already over
		pendingCount -= 1
		if ok and typeof(res) == "table" and res.ok then
			cargoCount += 1
			local info = CatchEvents.info(l.def, l.rarity, res, cargoCount, run.stats.cargo,
				Vector3.new(ORIGIN.X + l.x, ORIGIN.Y + l.y, ORIGIN.Z))
			CreatureSimClient.confirmCatch(l, info)
			CatchEvents.Caught:Fire(info, l)
		else
			local reason = if ok and typeof(res) == "table" and typeof(res.reason) == "string" then res.reason else nil
			CreatureSimClient.rejectCatch(l, reason)
			if reason == "full" then
				BeamController.CargoFull:Fire()
			end
		end
	end)
end

BeamController.Struggle:Connect(function()
	kickT = KICK_TIME
end)

CatchEvents.Caught:Connect(function()
	if flashEmitter then
		flashEmitter.Color = ColorSequence.new(Color3.new(1, 1, 1), BEAM_CYAN)
		flashEmitter:Emit(2)
		flashT = FLASH_TIME
	end
end)

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------
function BeamController.begin(r: any, nozzle: Attachment?)
	BeamController.finish()
	run = r
	runToken += 1
	cargoCount, pendingCount = 0, 0
	fullWarned = false
	aimDir = Vector2.new(1, 0)
	buildVisuals(nozzle)
end

function BeamController.finish()
	runToken += 1
	run = nil
	if folder then folder:Destroy() end
	folder, endPart, tetherPart, wedge, tether, tag, tagFill, tagLabel = nil, nil, nil, nil, nil, nil, nil, nil
	core, tetherCore, flow, flashPart, flashEmitter = nil, nil, nil, nil, nil
	flashT, kickT, smoothProg = 0, 0, 0
	if nozzleLight then nozzleLight.Brightness = 0 end
	nozzleLight = nil
end

function BeamController.cargoCount(): number
	return cargoCount
end

-- held: beam button down; aimPoint: world point or nil (auto-aim)
-- flight: FlightController.state; nozzle: world position of the beam nozzle
function BeamController.update(dt: number, held: boolean, aimPoint: Vector3?, flight: any, nozzle: Vector3): boolean
	if not run then return false end
	t += dt
	local stats = run.stats
	local range = stats.beamRange
	local full = cargoCount + pendingCount >= stats.cargo
	local wantBeam = held and not flight.locked
	if wantBeam and full and not fullWarned and pendingCount == 0 then
		fullWarned = true
		BeamController.CargoFull:Fire()
	end
	local active = wantBeam and not full
	flight.beaming = active

	local nx, ny = nozzle.X - ORIGIN.X, nozzle.Y - ORIGIN.Y
	local creatures = CreatureSimClient.list()

	-- aim direction
	local desired: Vector2? = nil
	if aimPoint then
		local v = Vector2.new(aimPoint.X - nozzle.X, aimPoint.Y - nozzle.Y)
		if v.Magnitude > 0.5 then desired = v.Unit end
	else
		-- auto-aim: nearest creature in reach (touch, or gamepad without right stick)
		local bestD = range * 1.15
		for _, l in creatures do
			if CreatureSimClient.isTargetable(l) then
				local dx, dy = l.x - nx, l.y - ny
				local d = math.sqrt(dx * dx + dy * dy)
				if d < bestD and d > 0.01 then
					bestD = d
					desired = Vector2.new(dx / d, dy / d)
				end
			end
		end
	end
	if desired then
		local k = 1 - math.exp(-18 * dt)
		local v = aimDir:Lerp(desired, k)
		aimDir = if v.Magnitude > 1e-3 then v.Unit else desired
	end

	-- targeting
	local cosHalf = math.cos(B.halfAngle)
	local best: CreatureSimClient.Live? = nil
	local bestD = math.huge
	if active then
		for _, l in creatures do
			if CreatureSimClient.isTargetable(l) then
				local dx, dy = l.x - nx, l.y - ny
				local d = math.sqrt(dx * dx + dy * dy)
				if d < range and d > 0.01 and (dx * aimDir.X + dy * aimDir.Y) / d > cosHalf and d < bestD then
					bestD = d
					best = l
				end
			end
		end
	end

	local swarmGroup = if best and best.def.behavior == "Swarm" then best.spawn.group else -1
	local swarmPulled = 0
	for _, l in creatures do
		if not CreatureSimClient.isTargetable(l) then
			l.beamed = false
			continue
		end
		local inBeam = l == best
		if not inBeam and swarmGroup ~= -1 and l.spawn.group == swarmGroup and swarmPulled < B.swarmMultiPull - 1 then
			local dx, dy = l.x - nx, l.y - ny
			local d = math.sqrt(dx * dx + dy * dy)
			if d < range and d > 0.01 and (dx * aimDir.X + dy * aimDir.Y) / d > cosHalf then
				inBeam = true
				swarmPulled += 1
			end
		end
		l.beamed = inBeam
		if inBeam then
			l.progress += dt * stats.beamStrength / l.rarity.resist
			local dx, dy = nx - l.x, ny - l.y
			local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
			local pull = B.pullSpeed * l.progress * dt
			l.x += dx / d * pull
			l.y += dy / d * pull
			if l.rarity.rank >= B.struggleMinRank and rng:NextNumber() < dt * B.struggleRate then
				-- struggle: jerk away, lose some progress
				l.x -= dx / d * rng:NextNumber(2.5, 5.5)
				l.y -= dy / d * rng:NextNumber(1, 4)
				l.progress = math.max(0, l.progress - 0.06)
				BeamController.Struggle:Fire(l)
			end
			-- Epic blink: link breaks, it jumps out of the cone (CreatureSimClient.tryBlink)
			if CreatureSimClient.tryBlink(l, nx, ny) then
				if l == best then best = nil end
				continue
			end
			if l.progress >= 1 then
				l.progress = 1
				requestCatch(l)
			end
		else
			l.progress = math.max(0, l.progress - dt * B.decayPerSecond)
		end
	end

	-- visuals
	local color = if best then best.rarity.color else BEAM_CYAN
	local prog = if best then math.clamp(best.progress, 0, 1) else 0
	smoothProg += (prog - smoothProg) * (1 - math.exp(-10 * dt))
	kickT = math.max(0, kickT - dt)
	flashT = math.max(0, flashT - dt)
	local kick = kickT / KICK_TIME -- 1 -> 0
	-- struggle: random flicker + wider kick; locked-in look grows with progress
	local flicker = if kick > 0 then rng:NextNumber(0, 0.6) * kick else 0
	local lock = smoothProg
	if wedge and core and endPart then
		wedge.Enabled = active
		core.Enabled = active
		if active then
			local tip = Vector3.new(nozzle.X + aimDir.X * range, nozzle.Y + aimDir.Y * range, ORIGIN.Z)
			endPart.CFrame = CFrame.new(tip)
			local fullW = 2 * range * math.tan(B.halfAngle)
			local pulse = 0.06 * math.sin(t * 9)
			wedge.Width1 = fullW * (1 + 0.25 * kick)
			wedge.Color = ColorSequence.new(color)
			wedge.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.2 * lock + pulse + flicker, 0, 1)),
				NumberSequenceKeypoint.new(0.75, math.clamp(0.8 - 0.2 * lock + pulse + flicker * 0.5, 0, 1)),
				NumberSequenceKeypoint.new(1, 1),
			})
			-- core: narrow wedge, wider and brighter as the pull locks in
			core.Width0 = 0.4 + 0.5 * lock
			core.Width1 = fullW * (0.12 + 0.2 * lock)
			core.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35 + 0.4 * lock))
			core.TextureSpeed = 2 + 8 * lock
			core.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.clamp(0.15 - 0.1 * lock + flicker, 0, 1)),
				NumberSequenceKeypoint.new(0.8, math.clamp(0.7 - 0.3 * lock + flicker, 0, 1)),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
	if tether and tetherCore and tetherPart and tag and tagFill and tagLabel and flow then
		local show = best ~= nil
		tether.Enabled = show
		tetherCore.Enabled = show
		tag.Enabled = show
		flow.Enabled = show
		if best then
			local target = Vector3.new(ORIGIN.X + best.x, ORIGIN.Y + best.y, ORIGIN.Z)
			local toNozzle = nozzle - target
			local dist = toNozzle.Magnitude
			if dist > 0.05 then
				tetherPart.CFrame = CFrame.lookAt(target, nozzle)
				flow.Speed = NumberRange.new(dist / 0.5)
				flow.Rate = 10 + 40 * lock
			else
				tetherPart.CFrame = CFrame.new(target)
				flow.Rate = 0
			end
			local amp = (1 + 1.5 * lock) * (1 + 2 * kick)
			local speed = 1 + 1.2 * lock
			tether.Color = ColorSequence.new(color)
			tether.Width0 = 0.5 + 0.4 * lock
			tether.Width1 = 1.6 + 0.8 * lock
			tether.Transparency = NumberSequence.new(math.clamp(0.35 - 0.25 * lock + flicker, 0, 1))
			tether.CurveSize0 = math.sin(t * 17 * speed) * 1.2 * amp
			tether.CurveSize1 = math.cos(t * 13 * speed) * 1.2 * amp
			tetherCore.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5 + 0.3 * lock))
			tetherCore.Width0 = 0.2 + 0.2 * lock
			tetherCore.Width1 = 0.7 + 0.5 * lock
			tetherCore.TextureSpeed = 3 + 9 * lock
			tetherCore.Transparency = NumberSequence.new(math.clamp(0.1 + flicker, 0, 1))
			tetherCore.CurveSize0 = tether.CurveSize0
			tetherCore.CurveSize1 = tether.CurveSize1
			tagFill.Size = UDim2.fromScale(prog, 1)
			tagFill.BackgroundColor3 = color
			tagLabel.Text = best.def.name
			tagLabel.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		end
	end
	if flashPart then
		flashPart.CFrame = CFrame.new(nozzle)
	end
	if nozzleLight then
		nozzleLight.Color = if flashT > 0 then Color3.new(1, 1, 1) else color
		nozzleLight.Brightness = (if active then 2.5 + 2 * lock else 0) + flashT / FLASH_TIME * 6
	end
	return active
end

return BeamController
