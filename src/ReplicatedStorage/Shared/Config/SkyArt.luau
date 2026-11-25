--!strict
-- Flight sky art in the style of the approved Stage 0.5 demo (art/demo_sky.py -> art/out/demo).
-- Sizes are in DEMO UNITS (the demo canvas is 620 units tall = Balance.flight.viewHeight studs).
-- Cloud images are neutral grey shading; SkyController tints them per altitude like the demo.

export type CloudArt = { image: string, unitsW: number, unitsH: number, originU: number, originV: number }

local SkyArt = {}

SkyArt.clouds = {
	{ image = "rbxassetid://125183408553249", unitsW = 265.14, unitsH = 158.52, originU = 0.4851, originV = 0.5816 },
	{ image = "rbxassetid://83477122971234", unitsW = 350.91, unitsH = 200.11, originU = 0.5232, originV = 0.5907 },
	{ image = "rbxassetid://78212555138558", unitsW = 235.76, unitsH = 158.61, originU = 0.5285, originV = 0.6139 },
	{ image = "rbxassetid://138459197346180", unitsW = 318.94, unitsH = 191.19, originU = 0.5202, originV = 0.5751 },
	{ image = "rbxassetid://91804615781905", unitsW = 355.81, unitsH = 211.08, originU = 0.4852, originV = 0.5802 },
	{ image = "rbxassetid://82736910857271", unitsW = 341.09, unitsH = 204.03, originU = 0.5300, originV = 0.5419 },
	{ image = "rbxassetid://128783540978585", unitsW = 346.46, unitsH = 206.98, originU = 0.5201, originV = 0.6641 },
	{ image = "rbxassetid://100740558383842", unitsW = 261.66, unitsH = 147.59, originU = 0.5053, originV = 0.6043 },
} :: { CloudArt }
SkyArt.cloudBaseTone = 0.93 -- grey level of the base faces in the cloud images

-- ringed planet: image 512x300, planet radius 120 px (demo radius 70 units)
SkyArt.planet = { image = "rbxassetid://90963176051461", pxW = 512, pxH = 300, radiusPx = 120 }
-- moon: image 240x240, radius 110 px
SkyArt.moon = { image = "rbxassetid://91573281865447", pxW = 240, pxH = 240, radiusPx = 110 }
-- Earth cap: covers 2642 x 810 units, the curve top sits 90 units below the image top (rim glow above)
SkyArt.earth = { image = "rbxassetid://117462252036018", unitsW = 2642.5, unitsH = 810, topU = 90, radius = 1500 }
SkyArt.sunGlow = "rbxassetid://72749050278410"
-- far mountains (demo depth 0.3): 4 tiles of 1300 units from x = -2600, heights +380 .. -340 units
SkyArt.mountains = {
	images = {
		"rbxassetid://131659522168320",
		"rbxassetid://127716657159557",
		"rbxassetid://130803215536282",
		"rbxassetid://82375967419236",
	},
	x0 = -2600, tileW = 1300, top = 380, bottom = -340, depth = 0.3,
}

-- demo sky gradient keyframes (altitude in demo units: 10 per stud)
SkyArt.sky = {
	{ a = 0, top = Color3.fromRGB(118, 196, 240), bot = Color3.fromRGB(255, 226, 198) },
	{ a = 2200, top = Color3.fromRGB(146, 128, 214), bot = Color3.fromRGB(255, 178, 140) },
	{ a = 4200, top = Color3.fromRGB(42, 36, 92), bot = Color3.fromRGB(124, 92, 172) },
	{ a = 6000, top = Color3.fromRGB(8, 10, 30), bot = Color3.fromRGB(36, 38, 88) },
}

return SkyArt
