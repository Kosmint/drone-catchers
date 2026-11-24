--!strict
-- CameraController: base camera (Roblox default) and the 2.5D side-view flight
-- camera (Scriptable, narrow FOV, lead + exponential smoothing, shake).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local DataController = require(script.Parent.DataController)

local F = Balance.flight

local CameraController = {}

local inFlight = false
local focus = Vector3.zero -- smoothed look target on the flight plane
local shakeAmount = 0
local rng = Random.new()
local savedFov = 70

local function distance(): number
	-- distance at which `viewHeight` studs fill the screen vertically
	return (F.viewHeight / 2) / math.tan(math.rad(F.fov / 2))
end

local function shakeEnabled(): boolean
	local data = DataController.get()
	return not (data and data.settings and data.settings.shake == false)
end

function CameraController.enterFlight(target: Vector3)
	local cam = workspace.CurrentCamera
	inFlight = true
	focus = target
	shakeAmount = 0
	savedFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = F.fov
	CameraController.updateFlight(0, target)
end

-- target = drone position + velocity lead (computed by the caller)
function CameraController.updateFlight(dt: number, target: Vector3)
	if not inFlight then return end
	local cam = workspace.CurrentCamera
	local k = 1 - math.exp(-F.cameraSmoothing * dt)
	focus = focus:Lerp(target, if dt == 0 then 1 else k)

	local offset = Vector3.zero
	if shakeAmount > 0 then
		if shakeEnabled() then
			local s = shakeAmount * 1.4
			offset = Vector3.new(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)
		end
		shakeAmount = math.max(0, shakeAmount - dt * 1.6)
	end

	local look = focus + offset
	-- slightly above the plane so tops of models read (style guide: tilt toward camera)
	local eye = look + Vector3.new(0, distance() * 0.06, distance())
	cam.CFrame = CFrame.lookAt(eye, look)
end

function CameraController.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

function CameraController.exitFlight()
	if not inFlight then return end
	inFlight = false
	local cam = workspace.CurrentCamera
	cam.FieldOfView = savedFov
	cam.CameraType = Enum.CameraType.Custom
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

function CameraController.isFlight(): boolean
	return inFlight
end

return CameraController
