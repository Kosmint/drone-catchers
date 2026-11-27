--!strict
-- ScannerController: flight scanner (Stage 2, #29, plan/00_GAME_DESIGN.md §4).
--   - Thin Mission Control range ring + gentle sweep pulse around the drone.
--   - Rarity rings on revealed creatures inside scanner range.
--   - Neutral "?" edge blips pointing to off-screen creatures within 2x range
--     (max 8, nearest first; avoids HUD panels on desktop and phone).
--   - Reveals Hidden creatures (e.g. Aurora Wisp) when they enter scanner range
--     with a short 3D + 2D shimmer.
-- All UI elements and 3D shimmer parts are pooled (no per-frame Instance.new)
-- and cleaned up automatically when the flight HUD hides at run end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local CreatureSimClient = require(script.Parent.CreatureSimClient)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)

local ORIGIN = Balance.flight.origin
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

local MAX_BLIPS = 8
local MAX_RARITY_RINGS = 28
local MAX_SHIMMER_UI = 6
local MAX_SHIMMER_3D = 4
local SHIMMER_TIME = 0.45
local SWEEP_PERIOD = 2.8

local C_CYAN = Color3.fromRGB(57, 213, 255)
local C_PANEL = Color3.fromRGB(11, 18, 32)
local C_NEUTRAL = Color3.fromRGB(214, 226, 244)
local C_NEUTRAL_DIM = Color3.fromRGB(142, 164, 200)
local FONT = Enum.Font.GothamBold

local ScannerController = {}

type BlipUI = {
	root: Frame,
	bg: Frame,
	stroke: UIStroke,
	label: TextLabel,
	arrowHolder: Frame,
	armTop: Frame,
	armBot: Frame,
}

type RarityRingUI = {
	frame: Frame,
	stroke: UIStroke,
}

type ShimmerUI = {
	frame: Frame,
	stroke: UIStroke,
	x: number,
	y: number,
	color: Color3,
	left: number,
}

type Shimmer3D = {
	part: BasePart,
	light: PointLight,
	emitter: ParticleEmitter,
	left: number,
}

type BlipSlot = {
	dist: number,
	lx: number,
	ly: number,
}

local layer: Frame? = nil
local ringFrame: Frame? = nil
local sweepFrame: Frame? = nil
local sweepStroke: UIStroke? = nil

local blips: { BlipUI } = {}
local rarityRings: { RarityRingUI } = {}
local shimmerUIs: { ShimmerUI } = {}
local shimmer3Ds: { Shimmer3D } = {}
local fxFolder: Folder? = nil
local nextShimmerUI = 1
local nextShimmer3D = 1

-- Pre-allocated top-K candidate slots for edge blips (zero per-frame allocations)
local blipCandidates: { BlipSlot } = {}
for i = 1, MAX_BLIPS do
	blipCandidates[i] = { dist = math.huge, lx = 0, ly = 0 }
end

local sweepT = 0
local pulseT = 0
local activeRunId: any = nil

----------------------------------------------------------------------------
-- UI pool builders (called once in init)
----------------------------------------------------------------------------
local function makeCorner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, transp: number, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transp
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function buildDroneRing(parent: Frame)
	local rf = Instance.new("Frame")
	rf.Name = "RangeRing"
	rf.AnchorPoint = Vector2.new(0.5, 0.5)
	rf.BackgroundTransparency = 1
	rf.Visible = false
	rf.ZIndex = 1
	rf.Parent = parent
	makeCorner(rf, UDim.new(1, 0))
	makeStroke(rf, C_CYAN, 0.72, 1.3)

	-- 4 subtle cardinal reticle ticks (N/S/E/W)
	local ticks: { { pos: UDim2, size: UDim2 } } = {
		{ pos = UDim2.new(0.5, 0, 0, -4), size = UDim2.fromOffset(2, 8) },
		{ pos = UDim2.new(0.5, 0, 1, 4), size = UDim2.fromOffset(2, 8) },
		{ pos = UDim2.new(0, -4, 0.5, 0), size = UDim2.fromOffset(8, 2) },
		{ pos = UDim2.new(1, 4, 0.5, 0), size = UDim2.fromOffset(8, 2) },
	}
	for _, tk in ticks do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = tk.pos
		f.Size = tk.size
		f.BackgroundColor3 = C_CYAN
		f.BackgroundTransparency = 0.55
		f.BorderSizePixel = 0
		f.ZIndex = 1
		f.Parent = rf
	end

	-- Inner expanding radar sweep pulse
	local sf = Instance.new("Frame")
	sf.Name = "Sweep"
	sf.AnchorPoint = Vector2.new(0.5, 0.5)
	sf.Position = UDim2.fromScale(0.5, 0.5)
	sf.Size = UDim2.fromScale(0.1, 0.1)
	sf.BackgroundTransparency = 1
	sf.Visible = false
	sf.ZIndex = 1
	sf.Parent = rf
	makeCorner(sf, UDim.new(1, 0))
	local ss = makeStroke(sf, C_CYAN, 0.85, 1.2)

	ringFrame = rf
	sweepFrame = sf
	sweepStroke = ss
end

local function buildBlip(parent: Frame, idx: number): BlipUI
	local root = Instance.new("Frame")
	root.Name = "Blip" .. tostring(idx)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(28, 28)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 4
	root.Parent = parent

	local bg = Instance.new("Frame")
	bg.Name = "Pill"
	bg.AnchorPoint = Vector2.new(0.5, 0.5)
	bg.Position = UDim2.fromScale(0.5, 0.5)
	bg.Size = UDim2.fromOffset(26, 26)
	bg.BackgroundColor3 = C_PANEL
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.ZIndex = 4
	bg.Parent = root
	makeCorner(bg, UDim.new(1, 0))
	local st = makeStroke(bg, C_NEUTRAL_DIM, 0.3, 1.4)

	-- TextSize 16 -> >= 10.4 px even at 0.65 mobile UIScale
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Mark"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = FONT
	lbl.Text = "?"
	lbl.TextSize = 16
	lbl.TextColor3 = C_NEUTRAL
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.ZIndex = 5
	lbl.Parent = bg

	-- Directional pointer chevron orbiting the pill
	local arrowHolder = Instance.new("Frame")
	arrowHolder.Name = "Arrow"
	arrowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowHolder.Position = UDim2.fromScale(0.5, 0.5)
	arrowHolder.Size = UDim2.fromOffset(10, 10)
	arrowHolder.BackgroundTransparency = 1
	arrowHolder.ZIndex = 5
	arrowHolder.Parent = root

	local armTop = Instance.new("Frame")
	armTop.AnchorPoint = Vector2.new(0.5, 0.5)
	armTop.Position = UDim2.fromOffset(5, 3)
	armTop.Size = UDim2.fromOffset(7, 2)
	armTop.Rotation = 45
	armTop.BackgroundColor3 = C_NEUTRAL
	armTop.BorderSizePixel = 0
	armTop.ZIndex = 5
	armTop.Parent = arrowHolder

	local armBot = Instance.new("Frame")
	armBot.AnchorPoint = Vector2.new(0.5, 0.5)
	armBot.Position = UDim2.fromOffset(5, 7)
	armBot.Size = UDim2.fromOffset(7, 2)
	armBot.Rotation = -45
	armBot.BackgroundColor3 = C_NEUTRAL
	armBot.BorderSizePixel = 0
	armBot.ZIndex = 5
	armBot.Parent = arrowHolder

	return {
		root = root,
		bg = bg,
		stroke = st,
		label = lbl,
		arrowHolder = arrowHolder,
		armTop = armTop,
		armBot = armBot,
	}
end

local function buildRarityRing(parent: Frame, idx: number): RarityRingUI
	local f = Instance.new("Frame")
	f.Name = "RarityRing" .. tostring(idx)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(44, 44)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.ZIndex = 2
	f.Parent = parent
	makeCorner(f, UDim.new(1, 0))
	local st = makeStroke(f, C_NEUTRAL, 0.4, 1.6)
	return { frame = f, stroke = st }
end

local function buildShimmerUI(parent: Frame, idx: number): ShimmerUI
	local f = Instance.new("Frame")
	f.Name = "ShimmerRing" .. tostring(idx)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(30, 30)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.ZIndex = 3
	f.Parent = parent
	makeCorner(f, UDim.new(1, 0))
	local st = makeStroke(f, C_CYAN, 0.1, 2.2)
	return { frame = f, stroke = st, x = 0, y = 0, color = C_CYAN, left = 0 }
end

----------------------------------------------------------------------------
-- 3D shimmer pool (built once per run, destroyed on cleanup)
----------------------------------------------------------------------------
local function ensureShimmer3D()
	if fxFolder and fxFolder.Parent then return end
	local f = Instance.new("Folder")
	f.Name = "ScannerFx"
	f.Parent = workspace:FindFirstChild("FlightSpace") or workspace
	fxFolder = f
	table.clear(shimmer3Ds)
	for i = 1, MAX_SHIMMER_3D do
		local p = Instance.new("Part")
		p.Name = "RevealShimmer" .. tostring(i)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(0.5, 0.5, 0.5)
		p.CFrame = CFrame.new(0, -10000, 0)

		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 0
		light.Shadows = false
		light.Parent = p

		local em = Instance.new("ParticleEmitter")
		em.Enabled = false
		em.Rate = 0
		em.Texture = SPARKLE_TEX
		em.Lifetime = NumberRange.new(0.3, 0.5)
		em.Speed = NumberRange.new(5, 13)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Drag = 3.5
		em.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		em.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		em.LightEmission = 1
		em.LightInfluence = 0
		em.Parent = p
		p.Parent = f

		table.insert(shimmer3Ds, { part = p, light = light, emitter = em, left = 0 })
	end
end

local function triggerShimmer(x: number, y: number, color: Color3)
	-- 3D sparkle burst + flash at the creature's world position
	ensureShimmer3D()
	local fx = shimmer3Ds[nextShimmer3D]
	nextShimmer3D = (nextShimmer3D % #shimmer3Ds) + 1
	if fx then
		fx.part.CFrame = CFrame.new(ORIGIN.X + x, ORIGIN.Y + y, ORIGIN.Z)
		fx.light.Color = color
		fx.light.Brightness = 4.5
		fx.left = SHIMMER_TIME
		fx.emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		fx.emitter:Emit(14)
	end

	-- 2D expanding shimmer ring on the scanner HUD layer
	local ui = shimmerUIs[nextShimmerUI]
	nextShimmerUI = (nextShimmerUI % #shimmerUIs) + 1
	if ui then
		ui.x = x
		ui.y = y
		ui.color = color
		ui.left = SHIMMER_TIME
	end
end

----------------------------------------------------------------------------
-- Cleanup (run end)
----------------------------------------------------------------------------
local function hideVisuals()
	if ringFrame then ringFrame.Visible = false end
	if sweepFrame then sweepFrame.Visible = false end
	for _, b in blips do
		b.root.Visible = false
	end
	for _, r in rarityRings do
		r.frame.Visible = false
	end
	for _, s in shimmerUIs do
		s.left = 0
		s.frame.Visible = false
	end
end

local function cleanup()
	hideVisuals()
	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
	table.clear(shimmer3Ds)
	sweepT = 0
	pulseT = 0
	activeRunId = nil
end

----------------------------------------------------------------------------
-- HUD avoidance for edge blips (desktop + phone)
----------------------------------------------------------------------------
local function avoidRect(bx: number, by: number, rx1: number, ry1: number, rx2: number, ry2: number, minX: number, maxX: number, minY: number, maxY: number): (number, number)
	if bx < rx1 or bx > rx2 or by < ry1 or by > ry2 then
		return bx, by
	end
	-- Push to the nearest clear side of the rect that stays inside the safe box
	local bestX, bestY = bx, by
	local bestD = math.huge
	if rx1 >= minX then
		local d = bx - rx1
		if d < bestD then bestD, bestX, bestY = d, rx1, by end
	end
	if rx2 <= maxX then
		local d = rx2 - bx
		if d < bestD then bestD, bestX, bestY = d, rx2, by end
	end
	if ry1 >= minY then
		local d = by - ry1
		if d < bestD then bestD, bestX, bestY = d, bx, ry1 end
	end
	if ry2 <= maxY then
		local d = ry2 - by
		if d < bestD then bestD, bestX, bestY = d, bx, ry2 end
	end
	return bestX, bestY
end

----------------------------------------------------------------------------
-- Per-frame update (called from ExpeditionController.stepFlight)
----------------------------------------------------------------------------
function ScannerController.update(dt: number, fs: any, run: any)
	if not layer then return end
	if not run or not fs or not fs.active then
		if activeRunId ~= nil then cleanup() end
		return
	end

	if activeRunId ~= run.runId then
		cleanup()
		activeRunId = run.runId
	end

	local cam = workspace.CurrentCamera
	if not cam then return end

	local fPos = layer.AbsolutePosition
	local fSize = layer.AbsoluteSize
	if fSize.X < 1 or fSize.Y < 1 then return end

	local vp = cam.ViewportSize
	local uiScale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.65, 1.25)
	local range: number = if run.stats and typeof(run.stats.scanner) == "number" then run.stats.scanner else 60
	local maxBlipDist = range * 2

	-- Decay 3D shimmer lights
	for _, fx in shimmer3Ds do
		if fx.left > 0 then
			fx.left = math.max(0, fx.left - dt)
			local k = fx.left / SHIMMER_TIME
			fx.light.Brightness = 4.5 * k * k
		end
	end

	-- Hide scanner visuals while diving back to base
	if fs.diving then
		hideVisuals()
		return
	end

	pulseT += dt
	sweepT = (sweepT + dt) % SWEEP_PERIOD

	-- 1) Subtle Mission Control scanner ring around the drone
	local droneWorld = Vector3.new(ORIGIN.X + fs.x, ORIGIN.Y + fs.y, ORIGIN.Z)
	local dronePt = cam:WorldToScreenPoint(droneWorld)
	local droneLx = dronePt.X - fPos.X
	local droneLy = dronePt.Y - fPos.Y

	if ringFrame and sweepFrame and sweepStroke then
		if dronePt.Z > 0 then
			-- Keep the ring nicely visible in the free screen center; grows slightly with scanner upgrades
			local upgradeFrac = math.clamp((range - 60) / 144, 0, 1)
			local logicalH = fSize.Y / uiScale
			local ringRadius = logicalH * (0.26 + 0.07 * upgradeFrac)
			local ringDiam = math.floor(ringRadius * 2 + 0.5)
			ringFrame.Size = UDim2.fromOffset(ringDiam, ringDiam)
			ringFrame.Position = UDim2.fromScale(droneLx / fSize.X, droneLy / fSize.Y)
			ringFrame.Visible = true

			local u = sweepT / SWEEP_PERIOD
			local ease = 1 - (1 - u) * (1 - u)
			local sFrac = 0.14 + 0.86 * ease
			sweepFrame.Size = UDim2.fromScale(sFrac, sFrac)
			sweepStroke.Transparency = 0.68 + 0.32 * u
			sweepFrame.Visible = true
		else
			ringFrame.Visible = false
			sweepFrame.Visible = false
		end
	end

	-- 2) Scan all live creatures: Hidden reveal, in-range rarity rings, off-screen blip candidates
	local creatures = CreatureSimClient.list()
	local ringUsed = 0
	local candCount = 0

	for _, l in creatures do
		if l.caught or l.done then continue end
		local dx = l.x - fs.x
		local dy = l.y - fs.y
		local dist = math.sqrt(dx * dx + dy * dy)

		-- Hidden reveal: when a Hidden creature enters scanner range, reveal it + shimmer
		if not l.revealed then
			if dist <= range then
				CreatureSimClient.reveal(l)
				triggerShimmer(l.x, l.y, l.rarity.color)
			else
				-- Unrevealed Hidden creatures stay completely invisible (no blip, no ring)
				continue
			end
		end

		if dist > maxBlipDist then continue end

		local cWorld = Vector3.new(ORIGIN.X + l.x, ORIGIN.Y + l.y, ORIGIN.Z)
		local cPt = cam:WorldToScreenPoint(cWorld)
		local lx = cPt.X - fPos.X
		local ly = cPt.Y - fPos.Y
		local onScreen = cPt.Z > 0 and lx >= 0 and lx <= fSize.X and ly >= 0 and ly <= fSize.Y

		if dist <= range and onScreen and l.vanish <= 0 then
			-- Inside scanner range and visible: show rarity ring
			if ringUsed < MAX_RARITY_RINGS then
				ringUsed += 1
				local rr = rarityRings[ringUsed]
				local rank = l.rarity.rank
				local baseDiam = 40 + math.min(rank, 6) * 5
				local breath = if rank >= 3 then 1 + 0.06 * math.sin(pulseT * 5 + l.ph) else 1
				local diam = math.floor(baseDiam * breath + 0.5)
				rr.frame.Size = UDim2.fromOffset(diam, diam)
				rr.frame.Position = UDim2.fromScale(lx / fSize.X, ly / fSize.Y)
				rr.stroke.Color = l.rarity.color
				-- Soft fade near the outer 15% of scanner range; rarer creatures read crisper
				local edgeFade = math.clamp((range - dist) / (range * 0.15), 0, 1)
				local baseTransp = math.clamp(0.65 - (rank - 1) * 0.12, 0.18, 0.65)
				rr.stroke.Transparency = 1 - (1 - baseTransp) * edgeFade
				rr.frame.Visible = true
			end
		elseif not onScreen then
			-- Off screen and within 2x scanner range: insert into top-K nearest edge blips
			local targetLx, targetLy = lx, ly
			if cPt.Z < 0 then
				targetLx = fSize.X - lx
				targetLy = fSize.Y - ly
			end
			if candCount < MAX_BLIPS then
				candCount += 1
				local slot = blipCandidates[candCount]
				slot.dist = dist
				slot.lx = targetLx
				slot.ly = targetLy
				-- Insertion sort to keep nearest first
				local j = candCount
				while j > 1 and blipCandidates[j].dist < blipCandidates[j - 1].dist do
					blipCandidates[j], blipCandidates[j - 1] = blipCandidates[j - 1], blipCandidates[j]
					j -= 1
				end
			elseif dist < blipCandidates[MAX_BLIPS].dist then
				local slot = blipCandidates[MAX_BLIPS]
				slot.dist = dist
				slot.lx = targetLx
				slot.ly = targetLy
				local j = MAX_BLIPS
				while j > 1 and blipCandidates[j].dist < blipCandidates[j - 1].dist do
					blipCandidates[j], blipCandidates[j - 1] = blipCandidates[j - 1], blipCandidates[j]
					j -= 1
				end
			end
		end
	end

	-- Hide unused rarity rings
	for i = ringUsed + 1, MAX_RARITY_RINGS do
		rarityRings[i].frame.Visible = false
	end

	-- 3) Position edge blips along the safe screen perimeter, avoiding HUD panels
	local cx = fSize.X * 0.5
	local cy = fSize.Y * 0.5
	local minX = 28 * uiScale
	local maxX = fSize.X - 28 * uiScale
	local minY = 28 * uiScale
	-- Bottom margin clears CargoBay (70 logical px) and Recall (80 logical px)
	local maxY = fSize.Y - 98 * uiScale
	local isTouch = InputController.device() == "touch"

	for i = 1, MAX_BLIPS do
		local b = blips[i]
		if i > candCount then
			b.root.Visible = false
			continue
		end
		local cand = blipCandidates[i]
		local vx = cand.lx - cx
		local vy = cand.ly - cy
		local t = math.huge
		if vx > 1e-4 then
			t = math.min(t, (maxX - cx) / vx)
		elseif vx < -1e-4 then
			t = math.min(t, (minX - cx) / vx)
		end
		if vy > 1e-4 then
			t = math.min(t, (maxY - cy) / vy)
		elseif vy < -1e-4 then
			t = math.min(t, (minY - cy) / vy)
		end
		if t == math.huge then t = 0 end

		local bx = math.clamp(cx + vx * t, minX, maxX)
		local by = math.clamp(cy + vy * t, minY, maxY)

		-- Avoid Top-Left Status panel (16..292, 12..106) and Altimeter (16..204, 114..344)
		bx, by = avoidRect(bx, by, 0, 0, 312 * uiScale, 126 * uiScale, minX, maxX, minY, maxY)
		bx, by = avoidRect(bx, by, 0, 108 * uiScale, 224 * uiScale, 364 * uiScale, minX, maxX, minY, maxY)
		-- Avoid Touch Beam button on phones (bottom-right above Recall)
		if isTouch then
			bx, by = avoidRect(bx, by, fSize.X - 150 * uiScale, fSize.Y - 216 * uiScale, fSize.X, fSize.Y, minX, maxX, minY, maxY)
		end

		local ang = math.atan2(cand.ly - by, cand.lx - bx)
		local deg = math.deg(ang)
		b.root.Position = UDim2.fromScale(bx / fSize.X, by / fSize.Y)
		b.arrowHolder.Position = UDim2.new(0.5, math.cos(ang) * 19, 0.5, math.sin(ang) * 19)
		b.arrowHolder.Rotation = deg

		-- Faintness scales with distance (clearer near scanner range, fainter near 2x range)
		local distFrac = math.clamp((cand.dist - range) / math.max(1, range), 0, 1)
		local fade = 0.15 + 0.45 * distFrac
		b.bg.BackgroundTransparency = math.clamp(0.25 + 0.45 * distFrac, 0, 0.9)
		b.stroke.Transparency = math.clamp(0.25 + 0.5 * distFrac, 0, 0.92)
		b.label.TextTransparency = fade
		b.armTop.BackgroundTransparency = fade
		b.armBot.BackgroundTransparency = fade
		b.root.Visible = true
	end

	-- 4) Update 2D reveal shimmer rings
	for _, s in shimmerUIs do
		if s.left > 0 then
			s.left = math.max(0, s.left - dt)
			if s.left <= 0 then
				s.frame.Visible = false
			else
				local u = 1 - s.left / SHIMMER_TIME
				local pt = cam:WorldToScreenPoint(Vector3.new(ORIGIN.X + s.x, ORIGIN.Y + s.y, ORIGIN.Z))
				if pt.Z > 0 then
					local diam = math.floor(24 + 84 * (1 - (1 - u) * (1 - u)) + 0.5)
					s.frame.Size = UDim2.fromOffset(diam, diam)
					s.frame.Position = UDim2.fromScale((pt.X - fPos.X) / fSize.X, (pt.Y - fPos.Y) / fSize.Y)
					s.stroke.Color = s.color:Lerp(Color3.new(1, 1, 1), (1 - u) * 0.5)
					s.stroke.Transparency = u * u
					s.frame.Visible = true
				else
					s.frame.Visible = false
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Lifecycle (ClientMain runs HUDController.init before ScannerController.init)
----------------------------------------------------------------------------
function ScannerController.init()
	local l = HUDController.scannerLayer()
	layer = l
	buildDroneRing(l)
	for i = 1, MAX_BLIPS do
		table.insert(blips, buildBlip(l, i))
	end
	for i = 1, MAX_RARITY_RINGS do
		table.insert(rarityRings, buildRarityRing(l, i))
	end
	for i = 1, MAX_SHIMMER_UI do
		table.insert(shimmerUIs, buildShimmerUI(l, i))
	end

	-- Clean up automatically when the flight HUD hides at run end
	local parentFrame = l.Parent
	if parentFrame and parentFrame:IsA("GuiObject") then
		parentFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if not parentFrame.Visible then
				cleanup()
			end
		end)
	end
end

return ScannerController
