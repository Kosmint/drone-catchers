--!strict
-- Chapters and zones (plan/02_CONTENT.md §2).
-- Flight altitude is VIRTUAL: `from`/`to` are world studs inside the chapter's
-- flight column (200 studs per zone = 2000 units of the approved demo); `km` is
-- what the HUD shows. Only Chapter 1 is fully specified now.
export type Zone = {
	id: string,
	name: string,
	from: number, -- studs (bottom of zone in flight space)
	to: number,   -- studs (top)
	kmFrom: number,
	kmTo: number,
	baseValue: number, -- creature value base for this zone
}

export type Chapter = {
	id: number,
	name: string,
	tech: string, -- propulsion tech required
	zones: { Zone },
}

local chapters: { Chapter } = {
	{
		id = 1, name = "Earth", tech = "Chemical",
		zones = {
			{ id = "LowSky", name = "Low Sky", from = 0, to = 200, kmFrom = 0, kmTo = 10, baseValue = 10 },
			{ id = "StormLayer", name = "Storm Layer", from = 200, to = 400, kmFrom = 10, kmTo = 25, baseValue = 25 },
			{ id = "EdgeOfSpace", name = "Edge of Space", from = 400, to = 600, kmFrom = 25, kmTo = 100, baseValue = 60 },
		},
	},
	{
		id = 2, name = "Near Space", tech = "OrbitalBooster",
		zones = {
			{ id = "LowOrbit", name = "Low Orbit", from = 0, to = 200, kmFrom = 100, kmTo = 2000, baseValue = 150 },
			{ id = "MoonApproach", name = "Moon Approach", from = 200, to = 400, kmFrom = 2000, kmTo = 380000, baseValue = 400 },
			{ id = "AsteroidBelt", name = "Asteroid Belt", from = 400, to = 600, kmFrom = 380000, kmTo = 500000, baseValue = 1000 },
		},
	},
}

local zoneById: { [string]: Zone } = {}
local zoneChapter: { [string]: number } = {}
for _, ch in chapters do
	for _, z in ch.zones do
		zoneById[z.id] = z
		zoneChapter[z.id] = ch.id
	end
end

local Chapters = {
	list = chapters,
	zoneById = zoneById,
	zoneChapter = zoneChapter,
}

function Chapters.get(id: number): Chapter
	local ch = chapters[id]
	assert(ch, "Unknown chapter: " .. tostring(id))
	return ch
end

-- Which zone of a chapter contains this flight-space altitude (studs).
function Chapters.zoneAt(chapterId: number, y: number): Zone
	local zones = Chapters.get(chapterId).zones
	for _, z in zones do
		if y < z.to then return z end
	end
	return zones[#zones]
end

-- Studs -> displayed km (linear inside each zone).
function Chapters.toKm(chapterId: number, y: number): number
	local z = Chapters.zoneAt(chapterId, y)
	local t = math.clamp((y - z.from) / (z.to - z.from), 0, 1)
	return z.kmFrom + (z.kmTo - z.kmFrom) * t
end

return Chapters
