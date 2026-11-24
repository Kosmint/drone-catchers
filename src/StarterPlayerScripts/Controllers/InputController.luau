--!strict
-- InputController: unified PC / gamepad / touch input on the Input Action System.
-- The action tree is authored at edit time in ReplicatedStorage.Inputs:
--   FlightContext: Move (Direction2D), Beam (Bool), Aim (ViewportPosition),
--                  AimStick (Direction2D), Recall (Bool)
--   BaseContext:   Launch (Bool)
-- Touch: on-screen buttons are bound to the actions' "Touch" bindings at runtime
-- (the HUD is built by code); the thumbstick feeds Move's Scriptable binding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local player = Players.LocalPlayer

local InputController = {}
InputController.DeviceChanged = Signal.new() -- ("touch" | "gamepad" | "mouse")

local actions: { [string]: InputAction } = {}
local contexts: { [string]: InputContext } = {}
local touchStickBinding: InputBinding? = nil

-- touch thumbstick ---------------------------------------------------------
local stickGui: ScreenGui? = nil
local stickBase: Frame? = nil
local stickKnob: Frame? = nil
local stickTouch: InputObject? = nil
local stickOrigin = Vector2.zero
local STICK_RADIUS = 60

local function setStick(v: Vector2)
	if touchStickBinding then touchStickBinding:Fire(v) end
end

local function buildTouchStick()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchStick"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false

	-- invisible capture zone: left 45% of the screen, lower 75%
	local zone = Instance.new("Frame")
	zone.Name = "Zone"
	zone.BackgroundTransparency = 1
	zone.Size = UDim2.fromScale(0.45, 0.75)
	zone.Position = UDim2.fromScale(0, 0.25)
	zone.Parent = gui

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2)
	base.BackgroundColor3 = Color3.fromRGB(15, 22, 42)
	base.BackgroundTransparency = 0.55
	base.Visible = false
	base.Parent = gui
	local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(1, 0); c1.Parent = base
	local s1 = Instance.new("UIStroke"); s1.Color = Color3.fromRGB(255, 255, 255); s1.Transparency = 0.6; s1.Thickness = 2; s1.Parent = base

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(54, 54)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 179, 138)
	knob.BackgroundTransparency = 0.15
	knob.Parent = base
	local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(1, 0); c2.Parent = knob

	zone.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or stickTouch then return end
		stickTouch = input
		stickOrigin = Vector2.new(input.Position.X, input.Position.Y)
		base.Position = UDim2.fromOffset(stickOrigin.X, stickOrigin.Y)
		base.Visible = true
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end)
	UserInputService.TouchMoved:Connect(function(input: InputObject)
		if input ~= stickTouch then return end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - stickOrigin
		if delta.Magnitude > STICK_RADIUS then delta = delta.Unit * STICK_RADIUS end
		knob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
		local v = delta / STICK_RADIUS
		-- small dead zone, screen Y is down
		setStick(if v.Magnitude < 0.12 then Vector2.zero else Vector2.new(v.X, -v.Y))
	end)
	UserInputService.TouchEnded:Connect(function(input: InputObject)
		if input ~= stickTouch then return end
		stickTouch = nil
		base.Visible = false
		setStick(Vector2.zero)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	stickGui = gui
	stickBase = base
	stickKnob = knob
end

----------------------------------------------------------------------------
-- device
----------------------------------------------------------------------------
function InputController.device(): string
	local ok, pref = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and pref then
		if pref == Enum.PreferredInput.Touch then return "touch" end
		if pref == Enum.PreferredInput.Gamepad then return "gamepad" end
		return "mouse"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return "touch" end
	if UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then return "gamepad" end
	return "mouse"
end

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------
function InputController.action(name: string): InputAction
	local a = actions[name]
	assert(a, "[InputController] unknown action " .. name)
	return a
end

-- "base" | "flight" | "none"
local mode = "base"
function InputController.setMode(m: string)
	mode = m
	contexts.FlightContext.Enabled = m == "flight"
	contexts.BaseContext.Enabled = m == "base"
	if stickGui then
		stickGui.Enabled = m == "flight" and InputController.device() == "touch"
	end
	if m ~= "flight" then
		stickTouch = nil
		if stickBase then stickBase.Visible = false end
		setStick(Vector2.zero)
	end
end

function InputController.getMode(): string
	return mode
end

-- Bind a live on-screen button (PlayerGui) to an action's "Touch" binding.
function InputController.bindButton(actionName: string, button: GuiButton)
	local binding = InputController.action(actionName):FindFirstChild("Touch") :: InputBinding?
	if binding then binding.UIButton = button end
end

function InputController.move(): Vector2
	local v = actions.Move:GetState()
	if typeof(v) ~= "Vector2" then return Vector2.zero end
	if v.Magnitude > 1 then v = v.Unit end
	return v
end

function InputController.beamHeld(): boolean
	return actions.Beam:GetState() == true
end

-- Where the player aims, as a point on the flight plane (or nil = auto-aim).
-- mouse: pointer projected onto the plane; gamepad: right stick direction from `from`.
function InputController.aimPoint(from: Vector3): Vector3?
	local dev = InputController.device()
	if dev == "gamepad" then
		local s = actions.AimStick:GetState()
		if typeof(s) == "Vector2" and s.Magnitude > 0.35 then
			return from + Vector3.new(s.X, s.Y, 0).Unit * 20
		end
		return nil
	elseif dev == "mouse" then
		local p = actions.Aim:GetState()
		local cam = workspace.CurrentCamera
		if typeof(p) ~= "Vector2" or not cam then return nil end
		local ray = cam:ViewportPointToRay(p.X, p.Y)
		local planeZ = Balance.flight.origin.Z
		if math.abs(ray.Direction.Z) < 1e-4 then return nil end
		local t = (planeZ - ray.Origin.Z) / ray.Direction.Z
		if t <= 0 then return nil end
		return ray.Origin + ray.Direction * t
	end
	return nil -- touch: auto-aim
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function InputController.init()
	local inputs = ReplicatedStorage:WaitForChild("Inputs")
	for _, ctxName in { "FlightContext", "BaseContext" } do
		local ctx = inputs:WaitForChild(ctxName) :: InputContext
		contexts[ctxName] = ctx
		for _, a in ctx:GetChildren() do
			if a:IsA("InputAction") then actions[a.Name] = a end
		end
	end
	touchStickBinding = actions.Move:FindFirstChild("TouchStick") :: InputBinding?
	buildTouchStick()
	InputController.setMode("base")

	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			InputController.setMode(mode) -- re-evaluate touch stick visibility
			InputController.DeviceChanged:Fire(InputController.device())
		end)
	end)
end

return InputController
