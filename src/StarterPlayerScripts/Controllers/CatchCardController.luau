--!strict
-- CatchCardController: the Catch Card for Epic+ catches (plan/02_CONTENT.md §1b):
-- spinning 3D creature in a ViewportFrame, name, rarity gradient, modifier tag, size.
-- CONTRACT SKELETON (Stage 2): no card yet, it closes at once so the flow never waits.
-- The Catch Card Issue builds the card here. Input: CatchEvents.CardRequested(info).
-- Output: CatchEvents.CardClosed(info) when the player dismisses it (or it times out).
-- Creature model for the viewport: ReplicatedStorage.Assets.Creatures[info.creature.id],
-- falling back to Assets.Creatures.Placeholder (tinted with info.creature.color).

local CatchEvents = require(script.Parent.CatchEvents)

local CatchCardController = {}

function CatchCardController.init()
	CatchEvents.CardRequested:Connect(function(info: CatchEvents.CatchInfo)
		CatchEvents.CardClosed:Fire(info)
	end)
end

return CatchCardController
