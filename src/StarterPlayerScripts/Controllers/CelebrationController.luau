--!strict
-- CelebrationController: plays the rarity celebration when a catch lands (T0..T5,
-- Config/Celebrations, plan/02_CONTENT.md §1b).
-- Input: CatchEvents.Landed. Outputs: CatchEvents.CardRequested, HUDController.toast,
-- CameraController.shake, TimeScale.pulse. Sounds: tier.sound slots stay empty (Stage 3).
--
-- T0 pop | T1 pop + sparkles | T2 ring burst + flash | T3 burst + purple edge glow + camera punch
-- T4 slow-mo + golden rays + flash | T5 slow-mo + color-grade shift + particle storm.
-- World VFX are short-lived parts (Debris). Screen VFX use one ScreenGui and one
-- ColorCorrectionEffect created once and reused; Lighting is restored after every effect
-- (overlapping catches use a generation counter) and on run end.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Celebrations = require(Shared.Config.Celebrations)
local Modifiers = require(Shared.Config.Modifiers)

local Controllers = script.Parent
local CatchEvents = require(Controllers.CatchEvents)
local CameraController = require(Controllers.CameraController)
local HUDController = require(Controllers.HUDController)
local TimeScale = require(Controllers.TimeScale)
local FlightController = require(Controllers.FlightController)

local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local rng = Random.new()

local CelebrationController = {}

local gui: ScreenGui? = nil
local flashFrame: Frame? = nil
local glowFrames: { Frame } = {}
local grade: ColorCorrectionEffect? = nil
local gradeGen = 0 -- bumped by every color-grade effect; only the latest one restores
local glowGen = 0
local lastCardTier = -1

----------------------------------------------------------------------------
-- Screen layer (created once)
----------------------------------------------------------------------------
local function ensureScreen(): ScreenGui
	if gui and gui.Parent then return gui end
	local g = Instance.new("ScreenGui")
	g.Name = "Celebration"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 20
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g

	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = g
	flashFrame = f

	-- screen-edge glow: four edge strips fading toward the centre
	glowFrames = {}
	local edges = {
		{ UDim2.new(1, 0, 0.3, 0), UDim2.fromScale(0, 0), 90 }, -- top
		{ UDim2.new(1, 0, 0.3, 0), UDim2.fromScale(0, 0.7), 270 }, -- bottom
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, -- left
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0.82, 0), 180 }, -- right
	}
	for _, e in edges do
		local fr = Instance.new("Frame")
		fr.Name = "Glow"
		fr.Size = e[1]
		fr.Position = e[2]
		fr.BackgroundColor3 = Color3.new(1, 1, 1)
		fr.BackgroundTransparency = 1
		fr.BorderSizePixel = 0
		fr.Parent = g
		local grad = Instance.new("UIGradient")
		grad.Rotation = e[3]
		-- Transparency here is the shape: opaque at the screen edge, clear toward the centre
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		grad.Parent = fr
		table.insert(glowFrames, fr)
	end
	return g
end

local function ensureGrade(): ColorCorrectionEffect
	if grade and grade.Parent then return grade end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CelebrationGrade"
	cc.Enabled = false
	cc.Parent = Lighting
	grade = cc
	return cc
end

local function resetGrade()
	gradeGen += 1
	local cc = grade
	if cc and cc.Parent then
		cc.Enabled = false
		cc.Saturation, cc.Contrast, cc.Brightness = 0, 0, 0
		cc.TintColor = Color3.new(1, 1, 1)
	end
end

local function resetScreen()
	glowGen += 1
	if flashFrame then flashFrame.BackgroundTransparency = 1 end
	for _, fr in glowFrames do fr.BackgroundTransparency = 1 end
	resetGrade()
end

local function screenFlash(color: Color3, strength: number, seconds: number)
	ensureScreen()
	local f = flashFrame :: Frame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - math.clamp(strength * 0.6, 0, 1) * 0.85
	TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function edgeGlow(color: Color3, strength: number, seconds: number)
	ensureScreen()
	glowGen += 1
	local mine = glowGen
	for _, fr in glowFrames do
		fr.BackgroundColor3 = color
		fr.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
		TweenService:Create(fr, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end
	task.delay(seconds + 0.1, function()
		if mine == glowGen then resetScreen() end
	end)
end

-- Temporary color-grade shift: tint + saturation/contrast, eased back after `seconds`.
local function colorGrade(tint: Color3, seconds: number)
	local cc = ensureGrade()
	gradeGen += 1
	local mine = gradeGen
	cc.Enabled = true
	cc.TintColor = tint
	cc.Saturation, cc.Contrast, cc.Brightness = 0.2, 0.1, 0
	TweenService:Create(cc, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0,
	}):Play()
	task.delay(seconds + 0.05, function()
		if mine == gradeGen then resetGrade() end -- a newer grade owns the effect otherwise
	end)
end

-- Rotating golden light rays centred on the drone's screen position.
local function lightRays(worldPos: Vector3, color: Color3, seconds: number)
	local g = ensureScreen()
	local cam = workspace.CurrentCamera
	local v = cam:WorldToViewportPoint(worldPos)
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(v.X, v.Y)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.Parent = g
	local count = 12
	for i = 1, count do
		local ray = Instance.new("Frame")
		ray.BackgroundColor3 = color
		ray.BorderSizePixel = 0
		ray.AnchorPoint = Vector2.new(0.5, 1)
		ray.Size = UDim2.fromOffset(20, 1400)
		ray.Rotation = (i - 1) * (360 / count)
		ray.Position = UDim2.fromOffset(0, 0)
		ray.BackgroundTransparency = 0.7
		ray.Parent = holder
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		grad.Parent = ray
		-- rays are thin wedges: scale width up to feel like beams
		TweenService:Create(ray, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(60, 1400), BackgroundTransparency = 1,
		}):Play()
	end
	TweenService:Create(holder, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Rotation = 40 }):Play()
	Debris:AddItem(holder, seconds + 0.1)
end

----------------------------------------------------------------------------
-- World layer (short-lived parts, cleaned by Debris)
----------------------------------------------------------------------------
local function anchorPart(pos: Vector3, life: number): (Part, Attachment)
	local p = Instance.new("Part")
	p.Name = "CelebrationFx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	local a = Instance.new("Attachment")
	a.Parent = p
	Debris:AddItem(p, life)
	return p, a
end

local function emitter(parent: Attachment, color: ColorSequence, speed: NumberRange, size: number, life: number, spread: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEX
	e.Color = color
	e.Enabled = false
	e.Rate = 0
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = speed
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 1
	e.Drag = 2
	e.Parent = parent
	return e
end

local function burst(pos: Vector3, c1: Color3, c2: Color3, count: number, speed: number, size: number, life: number)
	local _, a = anchorPart(pos, life + 0.5)
	local e = emitter(a, ColorSequence.new(c1, c2), NumberRange.new(speed * 0.5, speed), size, life, 180)
	e:Emit(count)
end

-- Expanding hollow ring (stroke-only circle on a camera-facing BillboardGui): it frames the
-- drone instead of covering it. Sizes are in studs.
local function ring(pos: Vector3, color: Color3, startSize: number, endSize: number, seconds: number)
	local p = anchorPart(pos, seconds + 0.1)
	local bb = Instance.new("BillboardGui")
	bb.Name = "CelebrationRing"
	bb.Size = UDim2.fromScale(startSize, startSize) -- scale on a BillboardGui = studs
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = p
	bb.Parent = p
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 6
	stroke.Transparency = 0.15
	stroke.Parent = f
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { Size = UDim2.fromScale(endSize, endSize) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1, Thickness = 2 }):Play()
end

local function lightPulse(pos: Vector3, color: Color3, brightness: number, seconds: number)
	local _, a = anchorPart(pos, seconds + 0.2)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 30
	l.Brightness = brightness
	l.Parent = a
	TweenService:Create(l, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
end

-- Continuous storm of sparks around the drone for T5.
local function particleStorm(pos: Vector3, c1: Color3, c2: Color3, seconds: number)
	local _, a = anchorPart(pos, seconds + 2)
	local e = emitter(a, ColorSequence.new(c1, c2), NumberRange.new(14, 40), 0.8, 1.6, 180)
	e.Rate = 70
	e.Enabled = true
	e.Acceleration = Vector3.new(0, 6, 0)
	task.delay(seconds, function()
		if e.Parent then e.Enabled = false end
	end)
end

----------------------------------------------------------------------------
-- Celebration
----------------------------------------------------------------------------
local function lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end

local PURPLE = Color3.fromRGB(170, 90, 255)
local GOLD = Color3.fromRGB(255, 205, 80)

local function playWorld(tierN: number, pos: Vector3, c1: Color3, c2: Color3)
	if tierN == 0 then
		burst(pos, c1, c1, 8, 14, 0.45, 0.5)
	elseif tierN == 1 then
		burst(pos, c1, c2, 14, 18, 0.55, 0.7)
		burst(pos, Color3.new(1, 1, 1), lighten(c1, 0.5), 10, 22, 0.35, 0.9)
	elseif tierN == 2 then
		burst(pos, c1, c2, 22, 24, 0.65, 0.8)
		ring(pos, c1, 1.5, 8, 0.55)
		lightPulse(pos, c1, 6, 0.4)
	elseif tierN == 3 then
		burst(pos, c1, c2, 36, 30, 0.75, 0.9)
		ring(pos, c1, 1.5, 10, 0.6)
		ring(pos, c2, 1, 12, 0.8)
		lightPulse(pos, c1, 8, 0.5)
	elseif tierN == 4 then
		burst(pos, GOLD, c2, 50, 34, 0.85, 1.1)
		ring(pos, c1, 1.5, 10, 0.7)
		ring(pos, GOLD, 1, 12, 1.0)
		lightPulse(pos, GOLD, 10, 0.8)
	else
		burst(pos, c1, c2, 70, 40, 1, 1.3)
		ring(pos, c1, 1.5, 12, 0.8)
		ring(pos, c2, 1.5, 15, 1.1)
		ring(pos, Color3.new(1, 1, 1), 1, 18, 1.4)
		lightPulse(pos, c1, 12, 1.0)
		particleStorm(pos, c1, c2, 2.2)
	end
end

local function celebrate(info: CatchEvents.CatchInfo)
	local tier = Celebrations.forTier(info.rarity.tier)
	local tierN = math.clamp(info.rarity.tier, 0, Celebrations.MAX_TIER)
	-- real catches play at the nozzle (the creature is already pulled in); tests at worldPos
	local pos = if info.isTest then info.worldPos else FlightController.nozzleWorld()
	local c1 = info.rarity.color
	local c2 = info.rarity.color2 or lighten(c1, 0.45)

	-- toast text: "+ Name · Rarity [Modifier, Size]"
	local tags = {}
	local modColor: Color3? = nil
	for _, id in info.modifiers do
		local m = Modifiers.byId[id]
		if m then
			table.insert(tags, m.name)
			modColor = m.color
		end
	end
	if info.size ~= "Normal" then table.insert(tags, info.size) end
	if tier.toast then
		local text = string.format("+ %s  ·  %s", info.creature.name, info.rarity.name)
		if #tags > 0 then text ..= "  [" .. table.concat(tags, ", ") .. "]" end
		HUDController.toast(text, modColor or c1, tier.big or modColor ~= nil)
	end

	-- a modifier always feels at least like a T2 catch
	local shake = tier.shake
	if modColor then shake = math.max(shake, Celebrations.forTier(2).shake) end
	if shake > 0 then CameraController.shake(shake) end
	local slow = tier.slowmo
	if slow then TimeScale.pulse(slow.scale, slow.seconds) end

	-- in-world effect
	playWorld(tierN, pos, c1, c2)
	if modColor then burst(pos, modColor, lighten(modColor, 0.5), 12, 20, 0.9, 0.8) end

	-- screen effects
	if tierN == 2 then
		screenFlash(c1, tier.flash, 0.35)
	elseif tierN == 3 then
		screenFlash(c1, tier.flash, 0.4)
		edgeGlow(PURPLE, 0.75, 1.1)
		CameraController.shake(0.5) -- short camera punch
	elseif tierN == 4 then
		screenFlash(Color3.new(1, 0.95, 0.75), tier.flash, 0.6)
		lightRays(pos, GOLD, 1.6)
	elseif tierN >= 5 then
		screenFlash(Color3.new(1, 1, 1), tier.flash, 0.8)
		edgeGlow(c1, 0.5, 1.8)
		lightRays(pos, c2, 2.0)
		colorGrade(lighten(c1, 0.85), 2.2)
	end

	if tier.card then
		lastCardTier = tierN
		CatchEvents.CardRequested:Fire(info)
	end
end

function CelebrationController.init()
	CatchEvents.Landed:Connect(celebrate)
	-- effects end on their own timers; a closed card only clears the marker
	CatchEvents.CardClosed:Connect(function(info: CatchEvents.CatchInfo)
		lastCardTier = -1
	end)
	-- run end / leaving flight: never leave tinted lighting behind
	task.defer(function()
		local ok = pcall(function()
			workspace.CurrentCamera:GetPropertyChangedSignal("CameraType"):Connect(function()
				if not CameraController.isFlight() then resetScreen() end
			end)
		end)
		if not ok then warn("[CelebrationController] camera hook failed") end
	end)
end

return CelebrationController
