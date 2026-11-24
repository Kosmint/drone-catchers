--!strict
-- Basic per-zone lighting presets, blended by altitude in flight (Stage 1).
-- Stage 2 replaces these with full presets (Sky, SunRays, Bloom, parallax layers).
-- LowSky = the approved Style Test baseline (plan/03_ART_AND_AUDIO.md §1a).
export type Preset = {
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	atmosDensity: number,
	atmosOffset: number,
	atmosColor: Color3,
	atmosDecay: Color3,
	atmosGlare: number,
	atmosHaze: number,
	ccSaturation: number,
	ccContrast: number,
	ccBrightness: number,
	ccTint: Color3,
	-- weights for particle layers in FlightSpace (ParticleEmitters with attribute FxLayer = "stars"/"rain")
	fxStars: number,
	fxRain: number,
}

local rgb = Color3.fromRGB
local presets: { [string]: Preset } = {
	LowSky = {
		clockTime = 15.2, brightness = 2.6, ambient = rgb(120, 110, 140), outdoorAmbient = rgb(175, 160, 190),
		atmosDensity = 0.24, atmosOffset = 0.15, atmosColor = rgb(255, 220, 205), atmosDecay = rgb(170, 160, 220),
		atmosGlare = 0.35, atmosHaze = 1,
		ccSaturation = 0.12, ccContrast = 0.06, ccBrightness = 0.02, ccTint = rgb(255, 250, 245),
		fxStars = 0, fxRain = 0,
	},
	StormLayer = {
		clockTime = 15.2, brightness = 1.5, ambient = rgb(95, 100, 125), outdoorAmbient = rgb(120, 125, 150),
		atmosDensity = 0.38, atmosOffset = 0.1, atmosColor = rgb(160, 168, 190), atmosDecay = rgb(92, 100, 132),
		atmosGlare = 0, atmosHaze = 2.2,
		ccSaturation = -0.18, ccContrast = 0.14, ccBrightness = -0.03, ccTint = rgb(220, 228, 245),
		fxStars = 0, fxRain = 1,
	},
	EdgeOfSpace = {
		-- low sun + dark atmosphere = deep violet sky with a thin glowing horizon
		clockTime = 18.25, brightness = 3, ambient = rgb(110, 100, 160), outdoorAmbient = rgb(150, 135, 200),
		atmosDensity = 0.32, atmosOffset = 0.05, atmosColor = rgb(70, 70, 150), atmosDecay = rgb(30, 25, 80),
		atmosGlare = 0.8, atmosHaze = 0,
		ccSaturation = 0.1, ccContrast = 0.12, ccBrightness = 0.02, ccTint = rgb(230, 222, 255),
		fxStars = 1, fxRain = 0,
	},
}

return {
	presets = presets,
	blendBand = 30, -- studs either side of a zone boundary
}
