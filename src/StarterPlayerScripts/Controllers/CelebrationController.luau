--!strict
-- CelebrationController: plays the rarity celebration when a catch lands (T0..T5,
-- Config/Celebrations, plan/02_CONTENT.md §1b).
-- CONTRACT SKELETON (Stage 2): toast + shake + slow motion + Catch Card request.
-- The celebration Issue replaces the inside of `celebrate` with the real VFX, screen
-- flash and sounds; keep the inputs (CatchEvents.Landed) and outputs
-- (CatchEvents.CardRequested, HUDController.toast, CameraController.shake, TimeScale.pulse).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Celebrations = require(Shared.Config.Celebrations)
local Modifiers = require(Shared.Config.Modifiers)

local Controllers = script.Parent
local CatchEvents = require(Controllers.CatchEvents)
local CameraController = require(Controllers.CameraController)
local HUDController = require(Controllers.HUDController)
local TimeScale = require(Controllers.TimeScale)

local CelebrationController = {}

local function celebrate(info: CatchEvents.CatchInfo)
	local tier = Celebrations.forTier(info.rarity.tier)

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
		HUDController.toast(text, modColor or info.rarity.color, tier.big or modColor ~= nil)
	end

	-- a modifier always feels at least like a T2 catch
	local shake = tier.shake
	if modColor then shake = math.max(shake, Celebrations.forTier(2).shake) end
	if shake > 0 then CameraController.shake(shake) end
	local slow = tier.slowmo
	if slow then TimeScale.pulse(slow.scale, slow.seconds) end
	if tier.card then CatchEvents.CardRequested:Fire(info) end
end

function CelebrationController.init()
	CatchEvents.Landed:Connect(celebrate)
end

return CelebrationController
