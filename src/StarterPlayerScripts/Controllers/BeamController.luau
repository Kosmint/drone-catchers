--!strict
-- BeamController: the suction beam. Aim (mouse / right stick / touch auto-aim),
-- cone targeting, pull progress (beamStrength / resistance), Rare+ struggle,
-- swarm multi-pull, catch requests to the server (which rolls modifier + size).
-- Stage 1 visuals: a camera-facing light wedge + tether + progress tag.
-- Stage 2 replaces them with the final beam VFX and catch celebrations.

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
local wedge: Beam? = nil
local tether: Beam? = nil
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

	local w = Instance.new("Beam")
	w.Name = "Wedge"
	w.Attachment0 = nozzle
	w.Attachment1 = ea
	w.FaceCamera = true
	w.LightEmission = 1
	w.LightInfluence = 0
	w.Segments = 1
	w.Width0 = 0.6
	w.Width1 = 18
	w.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	w.Enabled = false
	w.Parent = e
	wedge = w

	local th = Instance.new("Beam")
	th.Name = "Tether"
	th.Attachment0 = nozzle
	th.Attachment1 = ta
	th.FaceCamera = true
	th.LightEmission = 1
	th.LightInfluence = 0
	th.Segments = 12
	th.Width0 = 0.5
	th.Width1 = 1.6
	th.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.45),
	})
	th.Enabled = false
	th.Parent = tp
	tether = th

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
			CreatureSimClient.rejectCatch(l)
			if ok and typeof(res) == "table" and res.reason == "full" then
				BeamController.CargoFull:Fire()
			end
		end
	end)
end

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
	if wedge and endPart then
		wedge.Enabled = active
		if active then
			local tip = Vector3.new(nozzle.X + aimDir.X * range, nozzle.Y + aimDir.Y * range, ORIGIN.Z)
			endPart.CFrame = CFrame.new(tip)
			wedge.Width1 = 2 * range * math.tan(B.halfAngle)
			wedge.Color = ColorSequence.new(color)
			local pulse = 0.08 * math.sin(t * 9)
			wedge.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3 + pulse),
				NumberSequenceKeypoint.new(0.7, 0.72 + pulse),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
	if tether and tetherPart and tag and tagFill and tagLabel then
		local show = best ~= nil
		tether.Enabled = show
		tag.Enabled = show
		if best then
			tetherPart.CFrame = CFrame.new(ORIGIN.X + best.x, ORIGIN.Y + best.y, ORIGIN.Z)
			tether.Color = ColorSequence.new(color)
			tether.CurveSize0 = math.sin(t * 17) * 1.2
			tether.CurveSize1 = math.cos(t * 13) * 1.2
			tagFill.Size = UDim2.fromScale(math.clamp(best.progress, 0, 1), 1)
			tagFill.BackgroundColor3 = color
			tagLabel.Text = best.def.name
			tagLabel.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		end
	end
	if nozzleLight then
		nozzleLight.Color = color
		nozzleLight.Brightness = if active then 2.5 else 0
	end
	return active
end

return BeamController
