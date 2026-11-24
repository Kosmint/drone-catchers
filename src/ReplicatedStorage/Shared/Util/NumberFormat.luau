--!strict
-- Short number formatting for coins/values: 999, 1.2K, 3.4M, 5.6B, 7.8T, then
-- Qa, Qi, Sx, Sp, Oc, No, Dc, and finally aa, ab, ... for absurd numbers.
local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function letterSuffix(index: number): string
	-- index 0 -> "aa", 1 -> "ab", ...
	local a = string.byte("a")
	return string.char(a + math.floor(index / 26) % 26) .. string.char(a + index % 26)
end

function NumberFormat.short(n: number): string
	if n ~= n then return "0" end -- NaN guard
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	-- Always rounds DOWN so the UI never shows more than the player has
	-- (999,999 -> "999K", not "1M").
	local tier = math.floor(math.log10(n) / 3)
	local scaled = n / 10 ^ (tier * 3)
	-- guard against log10 float error at exact powers of 1000
	if scaled < 1 then
		tier -= 1
		scaled *= 1000
	elseif scaled >= 1000 then
		tier += 1
		scaled /= 1000
	end
	local suffix = SUFFIXES[tier + 1] or letterSuffix(tier - #SUFFIXES)
	local text = scaled >= 100 and string.format("%d", math.floor(scaled))
		or string.format("%.1f", math.floor(scaled * 10) / 10)
	text = text:gsub("%.0$", "")
	return sign .. text .. suffix
end

-- Full number with thousands separators: 1234567 -> "1,234,567"
function NumberFormat.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

-- "1 in 1,000,000" style odds text
function NumberFormat.odds(oneIn: number): string
	return "1 in " .. NumberFormat.commas(math.max(1, math.floor(oneIn + 0.5)))
end

-- 3725 -> "1h 2m", 95 -> "1m 35s"
function NumberFormat.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %ds", m, s) end
	return string.format("%ds", s)
end

return NumberFormat
