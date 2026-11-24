--!strict
-- Modifiers / Enchantments (plan/02_CONTENT.md §1c). Rolled server-side on catch.
-- weight = relative pick weight once a modifier is rolled.
-- minChapter = only from that chapter on; rift = only inside that rift tier or above.
export type Modifier = {
	id: string,
	name: string,
	weight: number,
	mult: number,
	color: Color3,
	minChapter: number?,
	riftOnly: string?,
}

local rgb = Color3.fromRGB
local list: { Modifier } = {
	{ id = "Glossy", name = "Glossy", weight = 30, mult = 1.5, color = rgb(235, 245, 255) },
	{ id = "Frosted", name = "Frosted", weight = 20, mult = 2, color = rgb(160, 220, 255) },
	{ id = "Blazing", name = "Blazing", weight = 15, mult = 2.5, color = rgb(255, 140, 60) },
	{ id = "Electric", name = "Electric", weight = 12, mult = 3, color = rgb(255, 240, 90) },
	{ id = "Glass", name = "Glass", weight = 8, mult = 4, color = rgb(200, 240, 255) },
	{ id = "Molten", name = "Molten", weight = 6, mult = 5, color = rgb(255, 90, 30) },
	{ id = "Crimson", name = "Crimson", weight = 4, mult = 6, color = rgb(200, 20, 50) },
	{ id = "Golden", name = "Golden", weight = 2.5, mult = 8, color = rgb(255, 205, 70) },
	{ id = "Starlit", name = "Starlit", weight = 1.5, mult = 10, color = rgb(190, 200, 255) },
	{ id = "Shadow", name = "Shadow", weight = 0.6, mult = 15, color = rgb(60, 30, 90) },
	{ id = "Prism", name = "Prism", weight = 0.3, mult = 25, color = rgb(255, 130, 220) },
	{ id = "Nebula", name = "Nebula", weight = 0.08, mult = 50, color = rgb(140, 90, 255), minChapter = 2 },
	{ id = "Glitched", name = "Glitched", weight = 1, mult = 100, color = rgb(90, 255, 160), riftOnly = "Anomaly" },
	{ id = "NullTouched", name = "Null-touched", weight = 1, mult = 1000, color = rgb(250, 250, 250), riftOnly = "Null" },
}

local byId: { [string]: Modifier } = {}
for _, m in list do byId[m.id] = m end

return {
	list = list,
	byId = byId,
	BASE_CHANCE = 1 / 25, -- chance a catch gets any modifier
	MAX_CHANCE = 1 / 4,   -- cap after all bonuses
	DOUBLE_CHANCE = 1 / 50, -- of modified catches, chance of a second modifier (Ch3+)
}
