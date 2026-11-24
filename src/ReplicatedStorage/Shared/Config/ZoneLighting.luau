--!strict
-- Per-zone lighting presets, blended by altitude in flight.
-- Low Sky uses the painted sky (Workspace.FlightSpace.Chapter1.Painted): the real sun is placed
-- right behind the painted sun (clock 8.605 at latitude -54.6 -> sun dir ≈ (0.16, 0.13, -0.98)),
-- so the drone and creatures are warmly back-lit like the painting.
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
	sunRays: number, -- SunRaysEffect.Intensity (0 where the sun is in frame: it washes the painting out)
	-- weights for FlightSpace layers: ParticleEmitters (attribute FxLayer + BaseRate -> Rate)
	-- and painted ImageLabels (attribute FxLayer -> ImageTransparency = 1 - weight)
	fxStars: number,
	fxRain: number,
	fxSkyLow: number,
	fxSkyStorm: number,
}

local rgb = Color3.fromRGB
local presets: { [string]: Preset } = {
	LowSky = {
		clockTime = 8.605, latitude = -54.6, brightness = 2.4,
		ambient = rgb(138, 126, 168), outdoorAmbient = rgb(196, 178, 210),
		atmosDensity = 0.02, atmosOffset = 0, atmosColor = rgb(255, 224, 206), atmosDecay = rgb(186, 170, 226),
		atmosGlare = 0, atmosHaze = 0,
		ccSaturation = 0.12, ccContrast = 0.14, ccBrightness = 0, ccTint = rgb(255, 248, 242),
		sunRays = 0,
		fxStars = 0, fxRain = 0, fxSkyLow = 1, fxSkyStorm = 0,
	},
	StormLayer = {
		-- painted grey thunderstorm (FlightSpace.Chapter1.PaintedStorm): cold light from the bright gap
		-- above and ahead (clock 11.2, lat -36 -> sun dir ≈ (0.1, 0.5, -0.86)); StormController flashes it
		clockTime = 11.2, latitude = -36, brightness = 1.6, ambient = rgb(90, 100, 105), outdoorAmbient = rgb(125, 138, 142),
		atmosDensity = 0.03, atmosOffset = 0, atmosColor = rgb(150, 165, 170), atmosDecay = rgb(70, 85, 90),
		atmosGlare = 0, atmosHaze = 0,
		ccSaturation = -0.25, ccContrast = 0.15, ccBrightness = 0, ccTint = rgb(215, 228, 230),
		sunRays = 0,
		fxStars = 0, fxRain = 1, fxSkyLow = 0, fxSkyStorm = 1,
	},
	EdgeOfSpace = {
		-- low sun + dark atmosphere = deep violet sky with a thin glowing horizon
		clockTime = 18.25, latitude = 35, brightness = 3, ambient = rgb(110, 100, 160), outdoorAmbient = rgb(150, 135, 200),
		atmosDensity = 0.32, atmosOffset = 0.05, atmosColor = rgb(70, 70, 150), atmosDecay = rgb(30, 25, 80),
		atmosGlare = 0.8, atmosHaze = 0,
		ccSaturation = 0.1, ccContrast = 0.12, ccBrightness = 0.02, ccTint = rgb(230, 222, 255),
		sunRays = 0,
		fxStars = 1, fxRain = 0, fxSkyLow = 0, fxSkyStorm = 0,
	},
}

return {
	presets = presets,
	blendBand = 30, -- studs either side of a zone boundary
}
