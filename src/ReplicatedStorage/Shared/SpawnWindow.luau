--!strict
-- SpawnWindow: which queued spawns of a zone can be in the sky (pure, no Roblox APIs).
-- Client (CreatureSimClient) and server (ExpeditionService) both use it, so they
-- agree on the window: a zone's queue is activated in WHOLE swarm groups, at deploy
-- (until `active` entries are out) and once more per catch in that zone.
-- `nextIndex` = first queue index not yet activated (everything below it is out).
-- Unit tests: scripts/tests/SpawnWindow.spec.luau (run with lune).

-- any queue entry with a swarm group (SpawnGen.Spawn fits)
export type Entry = { group: number }

local SpawnWindow = {}

-- Index after activating the whole group that starts at `nextIndex`.
-- Returns `nextIndex` unchanged when the queue is used up.
function SpawnWindow.advance(queue: { Entry }, nextIndex: number): number
	local s = queue[nextIndex]
	if not s then return nextIndex end
	local group = s.group
	local i = nextIndex
	repeat
		i += 1
	until not queue[i] or queue[i].group ~= group
	return i
end

-- Index after the deploy activation: `active` entries, a swarm straddling the limit comes in whole.
function SpawnWindow.initial(queue: { Entry }, active: number): number
	local i = 1
	while i <= active do
		local n = SpawnWindow.advance(queue, i)
		if n == i then break end -- queue shorter than `active`
		i = n
	end
	return i
end

-- Could the spawn at queue `index` be in the sky? `slack` absorbs timing (a catch
-- confirmed on the server just before the client activated the refill).
function SpawnWindow.allows(index: number, nextIndex: number, slack: number): boolean
	return index >= 1 and index < nextIndex + slack
end

return SpawnWindow
