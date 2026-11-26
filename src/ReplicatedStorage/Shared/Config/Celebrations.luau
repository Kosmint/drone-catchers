--!strict
-- Catch celebration tiers T0..T5 (plan/02_CONTENT.md §1b). A rarity's tier is
-- Rarities.<id>.tier. CelebrationController reads this table; the numbers here are
-- starting values to tune, the look of each tier lives in CelebrationController.
--
--   toast  : show the catch toast (HUDController.toast); big = the large variant
--   shake  : camera shake amount (CameraController.shake), 0 = none
--   flash  : screen flash strength 0..1 (0 = none)
--   slowmo : { scale, seconds } world slow motion via TimeScale.pulse, or nil
--   card   : request the Catch Card (CatchEvents.CardRequested)
--   sound  : sound id for the tier, or nil (audio arrives in Stage 3; placeholder slot)
export type Tier = {
	toast: boolean,
	big: boolean,
	shake: number,
	flash: number,
	slowmo: { scale: number, seconds: number }?,
	card: boolean,
	sound: string?,
}

-- T3+ keep the toast until the Catch Card ships; the celebration issue turns it off then.
local tiers: { [number]: Tier } = {
	[0] = { toast = true, big = false, shake = 0.06, flash = 0, slowmo = nil, card = false, sound = nil },
	[1] = { toast = true, big = false, shake = 0.1, flash = 0, slowmo = nil, card = false, sound = nil },
	[2] = { toast = true, big = false, shake = 0.2, flash = 0.15, slowmo = nil, card = false, sound = nil },
	[3] = { toast = true, big = true, shake = 0.35, flash = 0.3, slowmo = nil, card = true, sound = nil },
	[4] = { toast = true, big = true, shake = 0.45, flash = 0.5, slowmo = { scale = 0.25, seconds = 0.4 }, card = true, sound = nil },
	[5] = { toast = true, big = true, shake = 0.6, flash = 0.7, slowmo = { scale = 0.2, seconds = 0.8 }, card = true, sound = nil },
}

local Celebrations = {}
Celebrations.tiers = tiers
Celebrations.MAX_TIER = 5 -- T6+ arrive with rift rarities (Stage 11)

-- Tier config for a rarity tier; tiers above MAX_TIER use the top tier for now.
function Celebrations.forTier(tier: number): Tier
	return tiers[math.clamp(tier, 0, Celebrations.MAX_TIER)]
end

return Celebrations
