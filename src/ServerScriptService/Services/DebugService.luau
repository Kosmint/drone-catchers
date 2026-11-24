--!strict
-- DebugService: QA commands for fast testing. Gated server-side:
-- only works in Studio, or for the game's owner in a live server.
-- Usage from the client (dev console / debug UI): Net.invoke("DebugCommand", "coins", 1000)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Guard = require(ReplicatedStorage.Shared.Util.Guard)
local DataService = require(script.Parent.DataService)

local DebugService = {}

local function isAllowed(player: Player): boolean
	if RunService:IsStudio() then return true end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	return false -- group-owned: add an explicit UserId allowlist here if needed
end

-- Each command: (player, arg) -> string result
local commands: { [string]: (Player, any) -> string } = {}
DebugService.commands = commands -- other services register their own QA commands

commands.help = function()
	local names = {}
	for name in commands do table.insert(names, name) end
	table.sort(names)
	return "commands: " .. table.concat(names, ", ")
end

commands.coins = function(player, amount)
	if not Guard.number(amount, -1e15, 1e15) then return "usage: coins <number>" end
	local ok = DataService.addCoins(player, amount)
	local data = DataService.get(player)
	return ok and ("coins = " .. tostring(data and data.coins)) or "failed"
end

commands.reset = function(player)
	DataService.resetForDebug(player)
	return "profile reset to defaults"
end

commands.save = function(player)
	return DataService.saveNow(player) and "saved" or "save failed"
end

commands.dump = function(player)
	local data = DataService.get(player)
	if not data then return "no data" end
	return game:GetService("HttpService"):JSONEncode(data)
end

function DebugService.init()
	Net.on("DebugCommand", function(player: Player, name: unknown, arg: unknown)
		if not isAllowed(player) then return "not allowed" end
		if not Guard.string(name, 32) then return "bad command" end
		local cmd = commands[name :: string]
		if not cmd then return "unknown command (try 'help')" end
		return cmd(player, arg)
	end)
end

return DebugService
