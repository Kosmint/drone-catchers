--!strict
-- CatchEvents: the Stage 2 contract between the catch systems (client only).
-- Every catch flows through these signals, so each system can be built on its own:
--
--   BeamController      server confirmed a catch      -> Caught(info, live)
--   CreatureSimClient   intake animation finished     -> Landed(info)
--   CelebrationController  tier needs the Catch Card  -> CardRequested(info)
--   CatchCardController card dismissed (or skipped)    -> CardClosed(info)
--
-- Listeners:
--   Caught        : catch animation starts (CreatureSimClient), beam VFX reacts (BeamController)
--   Landed        : celebration (CelebrationController), cargo slot pop + drone bounce
--                   (ExpeditionController -> HUDController.setCargo, FlightController.bounce)
--   CardRequested : Catch Card (CatchCardController)
--   CardClosed    : celebration ends its slow motion / effects early if it wants
--
-- Rules: never yield inside a handler that other systems wait on; never fire another
-- system's event; info is read-only for listeners. Test catches (info.isTest) skip
-- anything that changes the run (cargo, battery).
--
-- Studio only: ReplicatedStorage.DevHooks.FakeCatch (client-side BindableEvent) fires
-- Landed for any rarity without catching, e.g. from the command bar or the MCP:
--   game.ReplicatedStorage.DevHooks.FakeCatch:Fire("Legendary", { "Golden" }, "Big")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local Signal = require(Shared.Util.Signal)

export type CatchInfo = {
	creature: Creatures.Creature, -- def (id, name, behavior, lore...)
	rarity: Rarities.Rarity, -- rarity.tier = celebration tier
	modifiers: { string }, -- modifier ids rolled by the server (Config/Modifiers)
	size: string, -- "Tiny" | "Normal" | "Big" | "Huge" | "Colossal"
	value: number, -- coin value the server gave it
	cargoIndex: number, -- which cargo slot it fills (1-based)
	cargoMax: number,
	worldPos: Vector3, -- where it was when the catch was confirmed
	isTest: boolean, -- true when it came from DevHooks.FakeCatch
}

local CatchEvents = {}
CatchEvents.Caught = Signal.new() -- (info: CatchInfo, live: CreatureSimClient.Live)
CatchEvents.Landed = Signal.new() -- (info: CatchInfo)
CatchEvents.CardRequested = Signal.new() -- (info: CatchInfo)
CatchEvents.CardClosed = Signal.new() -- (info: CatchInfo)

local function asStringList(v: unknown): { string }
	local out = {}
	if typeof(v) == "table" then
		for _, s in v :: { any } do
			if typeof(s) == "string" then table.insert(out, s) end
		end
	end
	return out
end

-- Build the info for a confirmed catch. res = ReportCatch result { modifiers, size, value }.
function CatchEvents.info(
	creature: Creatures.Creature,
	rarity: Rarities.Rarity,
	res: any,
	cargoIndex: number,
	cargoMax: number,
	worldPos: Vector3
): CatchInfo
	local r = if typeof(res) == "table" then res else {}
	return {
		creature = creature,
		rarity = rarity,
		modifiers = asStringList(r.modifiers),
		size = if typeof(r.size) == "string" then r.size else "Normal",
		value = if typeof(r.value) == "number" then r.value else 0,
		cargoIndex = cargoIndex,
		cargoMax = cargoMax,
		worldPos = worldPos,
		isTest = false,
	}
end

----------------------------------------------------------------------------
-- Studio test hook
----------------------------------------------------------------------------
local function fakeCatch(rarityId: unknown, modifiers: unknown, size: unknown)
	local rarity = if typeof(rarityId) == "string" then Rarities.byId[rarityId] else nil
	if not rarity then
		warn("[CatchEvents] FakeCatch: unknown rarity " .. tostring(rarityId))
		return
	end
	-- a creature of that rarity if Chapter 1 has one, else any creature shown at that rarity
	local creature = Creatures.list[1]
	for _, c in Creatures.list do
		if c.rarity == rarity.id then
			creature = c
			break
		end
	end
	local cam = workspace.CurrentCamera
	local info = CatchEvents.info(creature, rarity, {
		modifiers = modifiers,
		size = if typeof(size) == "string" then size else "Normal",
		value = 0,
	}, 1, 5, if cam then cam.Focus.Position else Vector3.zero)
	info.isTest = true
	CatchEvents.Landed:Fire(info)
end

function CatchEvents.init()
	if not RunService:IsStudio() then return end
	local folder = ReplicatedStorage:FindFirstChild("DevHooks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DevHooks"
		folder.Parent = ReplicatedStorage
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = "FakeCatch"
	ev.Event:Connect(fakeCatch)
	ev.Parent = folder
end

return CatchEvents
