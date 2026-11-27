--!strict
-- SkyController: the flight sky, ported 1:1 from the approved Stage 0.5 demo (flat low-poly style).
--   * sky gradient that shifts with altitude (blue/peach -> violet/orange -> navy -> black)
--   * sun glow (fades out by ~35 km), twinkling stars, ringed planet, moon and the Earth curve
--     with its blue rim near the Edge of Space. These are "screen" layers: locked to the camera,
--     placed in demo screen units with the demo's tiny parallax.
--   * 80 flat faceted 2D clouds at five parallax depths (0.4 .. 1.25, the nearest pass in front
--     of the drone at half opacity) and the far blue mountain range (depth 0.3). These sit at
--     real 3D depths chosen so perspective gives exactly the demo's parallax.
-- Everything here is client-only and rebuilt per flight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local SkyArt = require(Shared.Config.SkyArt)

local F = Balance.flight
local ORIGIN = F.origin
local VIEW_UNITS = 620 -- the demo canvas height in units
local UNIT = F.viewHeight / VIEW_UNITS -- studs per demo unit on the flight plane
local TAN = math.tan(math.rad(F.fov / 2))
local CAM_DIST = (F.viewHeight / 2) / TAN

local SkyController = {}

local folder: Folder? = nil
local rng = Random.new(7)
local clock = 0

-- screen layers ---------------------------------------------------------------
type ScreenCard = { part: BasePart, gui: SurfaceGui, depth: number }
local gradientCard: ScreenCard? = nil
local gradient: UIGradient? = nil
local starCard: ScreenCard? = nil
type Star = { frame: Frame, x: number, y: number, s: number, tw: number }
local stars: { Star } = {}
local sunCard: ScreenCard? = nil
local sunLabel: ImageLabel? = nil
local planetCard: ScreenCard? = nil
local planetLabel: ImageLabel? = nil
local moonCard: ScreenCard? = nil
local moonLabel: ImageLabel? = nil
local earthCard: ScreenCard? = nil
local earthLabels: { ImageLabel } = {} -- left + right tile

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function sky(a: number): (Color3, Color3)
	local keys = SkyArt.sky
	a = math.clamp(a, 0, 6000)
	for i = 1, #keys - 1 do
		local k, n = keys[i], keys[i + 1]
		if a <= n.a then
			local t = (a - k.a) / (n.a - k.a)
			return k.top:Lerp(n.top, t), k.bot:Lerp(n.bot, t)
		end
	end
	local last = keys[#keys]
	return last.top, last.bot
end

local function newPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = folder
	return p
end

local function newGui(part: BasePart, canvas: Vector2): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Back -- the camera looks down -Z, so it sees the +Z (Back) face
	g.LightInfluence = 0
	g.Brightness = 1
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = canvas
	g.ClipsDescendants = true
	g.Parent = part
	return g
end

local function newImage(parent: Instance, image: string): ImageLabel
	local l = Instance.new("ImageLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Image = image
	l.ScaleType = Enum.ScaleType.Stretch
	l.Parent = parent
	return l
end

-- depth = distance from the camera (studs); all screen cards are thin and face the camera
local function screenCard(name: string, depth: number, canvas: Vector2): ScreenCard
	local p = newPart(name, Vector3.new(1, 1, 0.05))
	return { part = p, gui = newGui(p, canvas), depth = depth }
end

-- per-frame camera numbers
local camCF = CFrame.identity
local aspect = 16 / 9
local wUnits = VIEW_UNITS * aspect

-- place a screen card: centre at demo screen point (sx, sy) (units from the top-left), size in units
local function placeScreen(c: ScreenCard, sx: number, sy: number, w: number, h: number)
	local unit = 2 * TAN * c.depth / VIEW_UNITS
	c.part.Size = Vector3.new(math.min(w * unit, 2040), math.min(h * unit, 2040), 0.05)
	c.part.CFrame = camCF * CFrame.new((sx - wUnits / 2) * unit, (VIEW_UNITS / 2 - sy) * unit, -c.depth)
end

-- world layers ------------------------------------------------------------------
-- a layer with demo parallax factor d sits where perspective scrolls it at d x the flight plane
local function planeZ(d: number): number
	if d == 1 then return -1 end -- just behind the drone so it never hides the drone or creatures
	return CAM_DIST - CAM_DIST / d
end

local function buildClouds()
	local depths = { 0.4, 0.6, 0.85, 1, 1.25 }
	local tone = SkyArt.cloudBaseTone
	for i = 0, 79 do
		local d = depths[i % 5 + 1]
		local alt = rng:NextNumber(300, 4300) -- demo units
		local x = rng:NextNumber(-2800, 2800) -- demo units at the flight plane
		local art = SkyArt.clouds[rng:NextInteger(1, #SkyArt.clouds)]
		local scale = rng:NextNumber(0.75, 1.1) * (0.55 + 0.45 * d) / d * UNIT
		local w, h = art.unitsW * scale, art.unitsH * scale
		local ox = ORIGIN.X + x * UNIT
		local oy = ORIGIN.Y + alt * UNIT
		local p = newPart("Cloud", Vector3.new(w, h, 0.05))
		p.CFrame = CFrame.new(ox + (0.5 - art.originU) * w, oy + (art.originV - 0.5) * h, ORIGIN.Z + planeZ(d))
		local g = newGui(p, Vector2.new(512, 512 * art.unitsH / art.unitsW))
		g.Brightness = 1.12 -- tone mapping greys pure white; lift clouds back to the demo white
		local img = newImage(g, art.image)
		-- demo: base = mix(white, sky(alt).bot, .28); images hold that base at grey `tone`
		local _, bot = sky(alt)
		local base = Color3.new(1, 1, 1):Lerp(bot, 0.28)
		img.ImageColor3 = Color3.new(math.min(1, base.R / tone), math.min(1, base.G / tone), math.min(1, base.B / tone))
		img.ImageTransparency = if d > 1.1 then 0.5 else 0
	end
end

local function buildMountains()
	local m = SkyArt.mountains
	local d = m.depth
	local k = UNIT / d
	for i, image in m.images do
		local x0 = m.x0 + (i - 1) * m.tileW
		local w = m.tileW * k
		local h = (m.top - m.bottom) * k
		local p = newPart("Mountains", Vector3.new(w + 0.2, h, 0.05))
		p.CFrame = CFrame.new(ORIGIN.X + (x0 + m.tileW / 2) * k, ORIGIN.Y + (m.top + m.bottom) / 2 * k, ORIGIN.Z + planeZ(d))
		newImage(newGui(p, Vector2.new(1024, 1024 * (m.top - m.bottom) / m.tileW)), image)
	end
end

local function buildScreenLayers()
	-- sky gradient (farthest)
	local gc = screenCard("SkyGradient", 1200, Vector2.new(64, 64))
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Parent = gc.gui
	local ug = Instance.new("UIGradient")
	ug.Rotation = 90
	ug.Parent = frame
	gradientCard, gradient = gc, ug

	-- stars: 180 twinkling dots on a camera-locked card (demo: 0.03 parallax, wrap around)
	local sc = screenCard("Stars", 1150, Vector2.new(1240 * 2.4, 1240))
	starCard = sc
	local srng = Random.new(3)
	for _ = 1, 180 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = srng:NextNumber(0.6, 1.8)
		f.Size = UDim2.fromOffset(s * 2.6, s * 2.6)
		f.Parent = sc.gui
		table.insert(stars, { frame = f, x = srng:NextNumber(), y = srng:NextNumber(), s = s, tw = srng:NextNumber(0, 6) })
	end

	local sun = screenCard("SunGlow", 1100, Vector2.new(256, 256))
	sunCard, sunLabel = sun, newImage(sun.gui, SkyArt.sunGlow)

	local mc = screenCard("Moon", 1000, Vector2.new(240, 240))
	moonCard, moonLabel = mc, newImage(mc.gui, SkyArt.moon.image)

	local pc = screenCard("Planet", 950, Vector2.new(512, 300))
	planetCard, planetLabel = pc, newImage(pc.gui, SkyArt.planet.image)

	-- Earth: two tiles side by side on one card (each under Roblox's 1024 px limit, crisp limb)
	local art = SkyArt.earth
	local ec = screenCard("Earth", 600, Vector2.new(art.pxW, art.pxH))
	earthCard, earthLabels = ec, {}
	for i, image in art.images do
		local l = newImage(ec.gui, image)
		l.Size = UDim2.fromScale(1 / #art.images, 1)
		l.Position = UDim2.fromScale((i - 1) / #art.images, 0)
		table.insert(earthLabels, l)
	end
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function SkyController.begin()
	SkyController.finish()
	local space = workspace:FindFirstChild("FlightSpace") or workspace
	local f = Instance.new("Folder")
	f.Name = "DemoSky"
	folder = f
	rng = Random.new(7)
	clock = 0
	buildScreenLayers()
	buildClouds()
	buildMountains()
	f.Parent = space
	SkyController.update(0)
end

function SkyController.finish()
	if folder then folder:Destroy() end
	folder = nil
	table.clear(stars)
	gradientCard, gradient, starCard = nil, nil, nil
	sunCard, sunLabel, planetCard, planetLabel = nil, nil, nil, nil
	moonCard, moonLabel, earthCard = nil, nil, nil
	earthLabels = {}
end

-- call after the camera moved this frame
function SkyController.update(dt: number)
	if not folder then return end
	clock += dt
	local cam = workspace.CurrentCamera
	camCF = cam.CFrame
	local vp = cam.ViewportSize
	aspect = if vp.Y > 0 then vp.X / vp.Y else 16 / 9
	wUnits = VIEW_UNITS * aspect
	local camPos = camCF.Position
	local alt = (camPos.Y - ORIGIN.Y) / UNIT -- camera altitude in demo units
	local cx = (camPos.X - ORIGIN.X) / UNIT

	-- gradient: top = sky(alt + 330).top, bottom = sky(alt - 330).bot (demo drawSky)
	if gradientCard and gradient then
		local top = sky(alt + 330)
		local _, bot = sky(alt - 330)
		gradient.Color = ColorSequence.new(top, bot)
		placeScreen(gradientCard, wUnits / 2, VIEW_UNITS / 2, wUnits + 40, VIEW_UNITS + 40)
	end

	-- stars
	local sa = clamp01((alt - 2900) / 1600)
	if starCard then
		starCard.gui.Enabled = sa > 0
		if sa > 0 then
			local canvasW = math.floor(1240 * aspect)
			if starCard.gui.CanvasSize.X ~= canvasW then
				starCard.gui.CanvasSize = Vector2.new(canvasW, 1240) -- keep the dots square
			end
			placeScreen(starCard, wUnits / 2, VIEW_UNITS / 2, wUnits, VIEW_UNITS)
			for _, s in stars do
				local x = ((s.x * wUnits - cx * 0.03) % wUnits) / wUnits
				local y = ((s.y * VIEW_UNITS + alt * 0.03) % VIEW_UNITS) / VIEW_UNITS
				s.frame.Position = UDim2.fromScale(x, y)
				s.frame.BackgroundTransparency = 1 - sa * (0.55 + 0.45 * math.sin(clock * 1.5 + s.tw))
			end
		end
	end

	-- sun glow (upper right, gone by ~35 km)
	local sunA = clamp01(1 - alt / 3500)
	if sunCard and sunLabel then
		sunCard.gui.Enabled = sunA > 0
		if sunA > 0 then
			sunLabel.ImageTransparency = 1 - sunA
			placeScreen(sunCard, wUnits * 0.8, VIEW_UNITS * 0.18, 340, 340)
		end
	end

	-- moon (upper left)
	local ma = clamp01((alt - 3000) / 1200)
	if moonCard and moonLabel then
		moonCard.gui.Enabled = ma > 0
		if ma > 0 then
			moonLabel.ImageTransparency = 1 - ma
			local r = 26
			local size = SkyArt.moon.pxW / SkyArt.moon.radiusPx * r
			placeScreen(moonCard, wUnits * 0.2 - cx * 0.015, VIEW_UNITS * 0.2 + (alt - 4300) * 0.015, size, size)
		end
	end

	-- ringed planet
	local pa = clamp01((alt - 2600) / 1400)
	if planetCard and planetLabel then
		planetCard.gui.Enabled = pa > 0
		if pa > 0 then
			planetLabel.ImageTransparency = 1 - pa
			local pl = SkyArt.planet
			local k = 70 / pl.radiusPx
			placeScreen(planetCard, wUnits * 0.78 - cx * 0.02, VIEW_UNITS * 0.26 + (alt - 4500) * 0.02, pl.pxW * k, pl.pxH * k)
		end
	end

	-- Earth curve with its blue rim: sinks and shrinks slightly as the drone climbs
	local ea = clamp01((alt - 3700) / 900)
	if earthCard and #earthLabels > 0 then
		earthCard.gui.Enabled = ea > 0
		if ea > 0 then
			for _, l in earthLabels do l.ImageTransparency = 1 - ea end
			local e = SkyArt.earth
			local t = clamp01((alt - e.altStart) / (e.altEnd - e.altStart))
			local scale = e.scaleStart + (e.scaleEnd - e.scaleStart) * t
			local fill = e.fillStart + (e.fillEnd - e.fillStart) * t
			local curveTop = VIEW_UNITS * (1 - fill)
			local ecx = wUnits / 2 - cx * 0.05
			local top = curveTop - e.topU * scale
			local h = e.unitsH * scale
			placeScreen(earthCard, ecx, top + h / 2, e.unitsW * scale, h)
		end
	end
end

return SkyController
