--!strict
-- Validation helpers for remote arguments. Every client argument is hostile until
-- it passes one of these (type -> range -> permission -> plausibility).
local Guard = {}

-- finite number (rejects NaN and +/-inf)
function Guard.number(v: unknown, min: number?, max: number?): boolean
	if typeof(v) ~= "number" then return false end
	local n = v :: number
	if n ~= n or n == math.huge or n == -math.huge then return false end
	if min and n < min then return false end
	if max and n > max then return false end
	return true
end

function Guard.int(v: unknown, min: number?, max: number?): boolean
	return Guard.number(v, min, max) and math.floor(v :: number) == v
end

function Guard.string(v: unknown, maxLen: number?): boolean
	if typeof(v) ~= "string" then return false end
	return #(v :: string) <= (maxLen or 64)
end

-- string that is a key in the given lookup table (e.g. Upgrades.drone)
function Guard.oneOf(v: unknown, lookup: { [any]: any }): boolean
	return typeof(v) == "string" and #(v :: string) <= 64 and lookup[v] ~= nil
end

function Guard.boolean(v: unknown): boolean
	return typeof(v) == "boolean"
end

return Guard
