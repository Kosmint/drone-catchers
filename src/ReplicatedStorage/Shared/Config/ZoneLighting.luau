--!strict
-- Per-zone lighting presets, blended by altitude in flight. They light only the 3D models (drone,
-- creatures): the sky itself is SkyController's flat demo-style art, so there is no atmosphere
-- haze. Colour correction (+saturation, +contrast) undoes the tone-mapper wash-out so the flat sky
-- art shows the demo colours.
export type Preset = {
	clockTime: number,
	latitude: number, -- Lighting.GeographicLatitude (with clockTime = sun position)
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
	sunRays: number,
}

local rgb = Color3.fromRGB
local NO_ATMOS = { density = 0, color = rgb(255, 255, 255), decay = rgb(255, 255, 255) }

local presets: { [string]: Preset } = {
	LowSky = {
		-- warm morning sun from the upper right, like the demo's sun glow
		clockTime = 8.605, latitude = -54.6, brightness = 2.4,
		ambient = rgb(150, 150, 170), outdoorAmbient = rgb(200, 196, 210),
		atmosDensity = NO_ATMOS.density, atmosOffset = 0, atmosColor = NO_ATMOS.color, atmosDecay = NO_ATMOS.decay,
		atmosGlare = 0, atmosHaze = 0,
		ccSaturation = 0.28, ccContrast = 0.12, ccBrightness = 0, ccTint = rgb(255, 255, 255),
		sunRays = 0,
	},
	SunsetHeights = {
		clockTime = 8.605, latitude = -54.6, brightness = 2.2,
		ambient = rgb(170, 130, 150), outdoorAmbient = rgb(220, 170, 175),
		atmosDensity = NO_ATMOS.density, atmosOffset = 0, atmosColor = NO_ATMOS.color, atmosDecay = NO_ATMOS.decay,
		atmosGlare = 0, atmosHaze = 0,
		ccSaturation = 0.28, ccContrast = 0.12, ccBrightness = 0, ccTint = rgb(255, 255, 255),
		sunRays = 0,
	},
	EdgeOfSpace = {
		clockTime = 8.605, latitude = -54.6, brightness = 2,
		ambient = rgb(120, 115, 175), outdoorAmbient = rgb(160, 150, 215),
		atmosDensity = NO_ATMOS.density, atmosOffset = 0, atmosColor = NO_ATMOS.color, atmosDecay = NO_ATMOS.decay,
		atmosGlare = 0, atmosHaze = 0,
		ccSaturation = 0.28, ccContrast = 0.12, ccBrightness = 0, ccTint = rgb(255, 255, 255),
		sunRays = 0,
	},
}

return {
	presets = presets,
	blendBand = 30, -- studs either side of a zone boundary
}
