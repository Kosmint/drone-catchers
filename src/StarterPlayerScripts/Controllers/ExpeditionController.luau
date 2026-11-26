--!strict
-- ExpeditionController: the client side of a run.
--   base --Launch--> launching --server ok--> flight --Recall/battery--> returning --> results --> base
-- Owns the single per-frame flight loop so update order is explicit:
--   drone sim -> beam -> camera -> creatures (render culling uses the camera) -> HUD.
-- Stage 1: no rocket yet (Stage 4); launch = fade into the sky with a drone deploy.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)
local SpawnGen = require(Shared.SpawnGen)

local Controllers = script.Parent
local InputController = require(Controllers.InputController)
local CameraController = require(Controllers.CameraController)
local FlightController = require(Controllers.FlightController)
local CreatureSimClient = require(Controllers.CreatureSimClient)
local BeamController = require(Controllers.BeamController)
local HUDController = require(Controllers.HUDController)
local SkyController = require(Controllers.SkyController)
local CatchEvents = require(Controllers.CatchEvents)
local TimeScale = require(Controllers.TimeScale)

local player = Players.LocalPlayer
local ORIGIN = Balance.flight.origin
local CYAN = Color3.fromRGB(79, 216, 255)
local PEACH = Color3.fromRGB(255, 179, 138)
local DANGER = Color3.fromRGB(255, 90, 110)

local ExpeditionController = {}

local phase = "base" -- base | launching | flight | returning | results
local run: any = nil
local cargoColors: { Color3 } = {}
local loopConn: RBXScriptConnection? = nil
local cooldownUntil = 0
local hudTimer = 0
local lowBatteryWarned = false
local forcedResults: any = nil

-- Freeze the character at the base while the drone flies (WASD/Space drive the
-- drone). Works with or without the default PlayerModule (this place has none).
local savedMove: { walk: number, jump: number, jumpPower: number }? = nil
local function setCharacterControls(enabled: boolean)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum then return end
	if not enabled then
		if not savedMove then
			savedMove = { walk = hum.WalkSpeed, jump = hum.JumpHeight, jumpPower = hum.JumpPower }
		end
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		hum.JumpPower = 0
		if hrp then hrp.Anchored = true end
	else
		local s = savedMove
		if s then
			hum.WalkSpeed = s.walk
			hum.JumpHeight = s.jump
			hum.JumpPower = s.jumpPower
		end
		savedMove = nil
		if hrp then hrp.Anchored = false end
	end
end

local function phaseIs(p: string): boolean
	return phase == p
end

----------------------------------------------------------------------------
-- per-frame flight loop
----------------------------------------------------------------------------
local function stepFlight(rawDt: number)
	TimeScale.update(rawDt)
	local dt = math.min(rawDt, 1 / 20) * TimeScale.get() -- catch slow motion
	local fs = FlightController.state
	FlightController.update(dt, InputController.move())

	local nozzle = FlightController.nozzleWorld()
	local aim = InputController.aimPoint(nozzle)
	BeamController.update(dt, phaseIs("flight") and InputController.beamHeld(), aim, fs, nozzle)

	CameraController.updateFlight(dt, FlightController.cameraTarget())
	FlightController.updateSky()
	SkyController.update(dt)
	local camPos = workspace.CurrentCamera.CFrame.Position
	local speed = math.sqrt(fs.vx * fs.vx + fs.vy * fs.vy)
	CreatureSimClient.update(dt, fs.x, fs.y, speed, nozzle, camPos.X - ORIGIN.X, camPos.Y - ORIGIN.Y)

	hudTimer -= rawDt
	if hudTimer <= 0 then
		hudTimer = 1 / 20
		HUDController.updateFlight(fs, os.clock())
		if not lowBatteryWarned and fs.battery / fs.batteryMax < Balance.battery.lowThreshold and not fs.diving then
			lowBatteryWarned = true
			HUDController.toast("Battery low: recall soon", DANGER, true)
		end
	end
end

local function connectLoop()
	local ok, signal = pcall(function()
		return (RunService :: any).PreRender
	end)
	loopConn = (if ok and signal then signal else RunService.RenderStepped):Connect(stepFlight)
end

----------------------------------------------------------------------------
-- launch / end
----------------------------------------------------------------------------
local function refreshLaunchButton()
	if not phaseIs("base") then return end
	local left = cooldownUntil - os.clock()
	if left > 0 then
		HUDController.setLaunch(false, string.format("REFUELLING  %ds", math.ceil(left)))
	else
		HUDController.setLaunch(true, "LAUNCH")
	end
end

local function launch()
	if not phaseIs("base") then return end
	if os.clock() < cooldownUntil then
		HUDController.toast("The rocket is still refuelling", PEACH)
		return
	end
	phase = "launching"
	HUDController.setLaunch(false, "LAUNCHING...")
	local ok, res = pcall(Net.invoke, "RequestLaunch", 1)
	if not ok or typeof(res) ~= "table" or not res.ok then
		phase = "base"
		if ok and typeof(res) == "table" and res.reason == "cooldown" then
			cooldownUntil = os.clock() + (tonumber(res.wait) or 5)
		elseif ok and typeof(res) == "table" and res.reason == "loading" then
			HUDController.toast("Loading your save, try again in a moment", PEACH)
		else
			HUDController.toast("Launch failed, try again", DANGER)
		end
		refreshLaunchButton()
		return
	end

	run = res
	forcedResults = nil
	lowBatteryWarned = false
	cargoColors = {}
	cooldownUntil = os.clock() + Balance.launch.cooldownSeconds
	local plan = SpawnGen.build(res.seed, res.chapter, res.maxAltitude)

	setCharacterControls(false)
	InputController.setMode("none")
	HUDController.fade(1, 0.45)

	FlightController.begin(res)
	SkyController.begin()
	CreatureSimClient.begin(plan)
	BeamController.begin(res, FlightController.nozzleAttachment())
	CameraController.enterFlight(FlightController.cameraTarget())
	HUDController.beginFlight(res)
	HUDController.setMode("flight")
	connectLoop()

	phase = "flight"
	InputController.setMode("flight")
	HUDController.fade(0, 0.6)
	HUDController.toast("Drone deployed", CYAN)
end

local function finishFlight()
	if loopConn then loopConn:Disconnect() end
	loopConn = nil
	TimeScale.reset()
	BeamController.finish()
	SkyController.finish()
	CreatureSimClient.finish()
	FlightController.finish()
	CameraController.exitFlight()
	setCharacterControls(true)
end

local function endRun(reason: string)
	if not phaseIs("flight") then return end
	phase = "returning"
	InputController.setMode("none")
	FlightController.startDive()
	if reason == "battery" then
		HUDController.toast("Battery empty: emergency tow", DANGER, true)
	else
		HUDController.toast("Recalling drone", CYAN)
	end
	task.wait(1.1)
	HUDController.fade(1, 0.5)

	local results = forcedResults
	if not results then
		local ok, res = pcall(Net.invoke, "EndRun", run.runId, reason, FlightController.state.peak)
		results = if ok and typeof(res) == "table" then res else nil
	end
	if not results then
		results = { cargo = {}, total = 0, fee = 0, towed = reason == "battery" }
	end

	finishFlight()
	HUDController.setMode("base")
	phase = "results"
	HUDController.fade(0, 0.5)
	HUDController.showResults(results, function()
		phase = "base"
		InputController.setMode("base")
		refreshLaunchButton()
	end)
end

----------------------------------------------------------------------------
-- feedback
----------------------------------------------------------------------------
-- A caught creature reached the drone: fill the cargo slot and bounce the drone.
-- The toast, shake and celebration are CelebrationController's (CatchEvents.Landed).
local function onLanded(info: CatchEvents.CatchInfo)
	if info.isTest or not run or not (phaseIs("flight") or phaseIs("returning")) then return end
	table.insert(cargoColors, info.rarity.color)
	HUDController.setCargo(cargoColors, run.stats.cargo)
	FlightController.bounce()

	if cargoColors[run.stats.cargo] then
		HUDController.toast(if InputController.device() == "touch" then "Cargo full: tap RECALL" else "Cargo full: press R to recall", PEACH)
	end
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function ExpeditionController.init()
	InputController.action("Launch").Pressed:Connect(function()
		task.spawn(launch)
	end)
	InputController.action("Recall").Pressed:Connect(function()
		task.spawn(endRun, "recall")
	end)
	FlightController.BatteryEmpty:Connect(function()
		task.spawn(endRun, "battery")
	end)
	FlightController.ZoneChanged:Connect(function(zone, first)
		if first then
			HUDController.setZoneName(zone.name)
		else
			HUDController.zoneBanner(zone.name)
		end
	end)
	FlightController.CeilingHit:Connect(function()
		HUDController.toast("Rocket limit reached: upgrade the Engine to fly higher", PEACH)
	end)
	CatchEvents.Landed:Connect(onLanded)
	BeamController.CargoFull:Connect(function()
		HUDController.toast(if InputController.device() == "touch" then "Cargo full: tap RECALL" else "Cargo full: press R to recall", PEACH)
	end)
	BeamController.Struggle:Connect(function()
		CameraController.shake(0.08)
	end)
	Net.on("RunEnded", function(results)
		forcedResults = results
		task.spawn(endRun, "battery")
	end)
end

function ExpeditionController.start()
	while true do
		task.wait(0.25)
		refreshLaunchButton()
	end
end

return ExpeditionController
