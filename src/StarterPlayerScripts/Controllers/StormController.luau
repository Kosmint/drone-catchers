--!strict
-- StormController: lightning in the Storm Layer (painted set FlightSpace.Chapter1.PaintedStorm).
-- Every few seconds the sky flashes (double flicker): the painted storm cards light up, a bolt
-- cracks across the bright gap and the camera shakes a little. On some flashes the light
-- back-lights a giant sky-whale gliding behind the clouds - visible only for that instant.
-- Stage 3 adds sound, lightning strikes as a hazard and mood changes.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local CameraController = require(script.Parent.CameraController)

local ORIGIN = Balance.flight.origin

local StormController = {}

local FLASH_GAP = { 4, 10 } -- seconds between flashes
local WHALE_CHANCE = 0.3 -- chance a flash reveals the whale
local WHALE_SPEED = 22 -- studs/s across the sky (at its depth)

type Lit = { gui: SurfaceGui, base: number }
local lit: { Lit } = {}
local whale: BasePart? = nil
local whaleArt: ImageLabel? = nil
local bolt: BasePart? = nil
local boltArt: ImageLabel? = nil
local flashCC: ColorCorrectionEffect? = nil
local rng = Random.new()

local active = false
local nextFlash = 0
local flashT = -1 -- time since the current flash started (-1 = none)
local whaleShown = false
local whaleX = 0
local boltOffset = Vector2.zero
local clock = 0

-- brightness envelope of one lightning flash (double flicker, ~0.6 s)
local function envelope(t: number): number
	if t < 0 then return 0 end
	if t < 0.06 then return t / 0.06 end
	if t < 0.12 then return 1 - (t - 0.06) / 0.06 * 0.7 end
	if t < 0.18 then return 0.3 + (t - 0.12) / 0.06 * 0.7 end
	if t < 0.6 then return 1 - (t - 0.18) / 0.42 end
	return 0
end

function StormController.begin()
	StormController.finish()
	local set = workspace:FindFirstChild("FlightSpace")
	set = set and set:FindFirstChild("Chapter1")
	set = set and set:FindFirstChild("PaintedStorm")
	if not set then return end
	for _, name in { "SkyStorm", "StormFar", "StormMid", "Ceiling" } do
		local p = set:FindFirstChild(name)
		local gui = p and p:FindFirstChildOfClass("SurfaceGui")
		if gui then table.insert(lit, { gui = gui, base = gui.Brightness }) end
	end
	whale = set:FindFirstChild("Whale") :: BasePart?
	whaleArt = whale and (whale :: any).SurfaceGui.Art
	bolt = set:FindFirstChild("Bolt") :: BasePart?
	boltArt = bolt and (bolt :: any).SurfaceGui.Art
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "LightningFlash"
	cc.Parent = Lighting
	flashCC = cc
	active = true
	nextFlash = rng:NextNumber(2, 5)
	flashT = -1
	whaleX = -500
	clock = 0
end

function StormController.finish()
	for _, l in lit do l.gui.Brightness = l.base end
	table.clear(lit)
	if whaleArt then whaleArt.ImageTransparency = 1 end
	if boltArt then boltArt.ImageTransparency = 1 end
	if flashCC then flashCC:Destroy() end
	flashCC = nil
	whale, whaleArt, bolt, boltArt = nil, nil, nil, nil
	active = false
end

-- weight: how much of the Storm Layer is in view (0..1, from the zone blend)
function StormController.update(dt: number, weight: number)
	if not active then return end
	clock += dt
	local cam = workspace.CurrentCamera.CFrame.Position

	-- schedule flashes only while inside the storm
	if weight > 0.5 then
		nextFlash -= dt
		if nextFlash <= 0 and flashT < 0 then
			flashT = 0
			nextFlash = rng:NextNumber(FLASH_GAP[1], FLASH_GAP[2])
			whaleShown = rng:NextNumber() < WHALE_CHANCE
			boltOffset = Vector2.new(rng:NextNumber(-260, 260), rng:NextNumber(30, 110))
			CameraController.shake(0.12)
		end
	end

	local e = 0
	if flashT >= 0 then
		flashT += dt
		e = envelope(flashT) * weight
		if flashT > 0.6 then flashT = -1 end
	end

	for _, l in lit do
		l.gui.Brightness = l.base * (1 + e * 1.8)
	end
	if flashCC then
		flashCC.Brightness = e * 0.18
		flashCC.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(215, 235, 255), e)
	end

	-- bolt: visible during the bright parts of the flicker
	if bolt and boltArt then
		boltArt.ImageTransparency = if e > 0.35 then 0 else 1
		bolt.CFrame = CFrame.new(cam.X + boltOffset.X, cam.Y + boltOffset.Y, ORIGIN.Z - 830)
	end

	-- whale glides continuously behind the clouds; only the flash reveals it
	if whale and whaleArt then
		whaleX += WHALE_SPEED * dt
		if whaleX > 520 then whaleX = -520 end
		whale.CFrame = CFrame.new(cam.X + whaleX, cam.Y + 120 + math.sin(clock * 0.4) * 8, ORIGIN.Z - 740) -- in front of the ceiling/far clouds, behind the mid layer
		local show = if whaleShown then e else 0
		whaleArt.ImageTransparency = 1 - math.clamp(show * 1.2, 0, 0.85)
	end
end

return StormController
