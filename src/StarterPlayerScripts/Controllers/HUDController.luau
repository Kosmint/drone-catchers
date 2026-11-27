--!strict
-- HUDController: Mission Control HUD (Stage 2, plan/03_ART_AND_AUDIO.md §4).
-- Flight monitor: battery bar + %, hull pips, vertical altimeter with zone bands
-- and engine limit, bottom-center cargo bay, top-center warning & zone banners,
-- toasts, touch-ready recall & beam controls. Also styles Base wallet/launch and
-- Mission Debrief results card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Config.Balance)
local Chapters = require(Shared.Config.Chapters)
local Creatures = require(Shared.Config.Creatures)
local Rarities = require(Shared.Config.Rarities)
local Modifiers = require(Shared.Config.Modifiers)
local NumberFormat = require(Shared.Util.NumberFormat)
local DataController = require(script.Parent.DataController)
local InputController = require(script.Parent.InputController)

local player = Players.LocalPlayer

local HUDController = {}

local C = {
	panel = Color3.fromRGB(11, 18, 32),      -- #0B1220
	panelTop = Color3.fromRGB(18, 29, 50),
	panelBot = Color3.fromRGB(8, 13, 24),
	inset = Color3.fromRGB(16, 26, 46),
	track = Color3.fromRGB(22, 34, 56),
	fg = Color3.fromRGB(237, 244, 255),
	muted = Color3.fromRGB(142, 164, 200),
	cyan = Color3.fromRGB(57, 213, 255),     -- #39D5FF (primary accent)
	cyanDim = Color3.fromRGB(26, 98, 130),
	cyanDark = Color3.fromRGB(8, 18, 30),
	amber = Color3.fromRGB(255, 184, 77),    -- caution / low battery / credits
	danger = Color3.fromRGB(255, 77, 106),   -- critical / hazard / engine limit
	dangerBg = Color3.fromRGB(40, 12, 22),
	disabled = Color3.fromRGB(36, 49, 74),
}

local ZONE_COLORS: { [string]: Color3 } = {
	LowSky = Color3.fromRGB(102, 212, 156),
	SunsetHeights = Color3.fromRGB(255, 158, 109),
	EdgeOfSpace = Color3.fromRGB(157, 124, 240),
	LowOrbit = Color3.fromRGB(88, 182, 255),
	MoonApproach = Color3.fromRGB(196, 204, 224),
	AsteroidBelt = Color3.fromRGB(232, 168, 108),
}

local FONT = Enum.Font.GothamBold
local FONT_HEAVY = Enum.Font.GothamBlack
local FONT_BODY = Enum.Font.GothamMedium

local POP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local WARN_PULSE = TweenInfo.new(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local gui: ScreenGui
local flightFrame: Frame
local baseFrame: Frame
local resultsFrame: Frame
local fadeFrame: Frame
local toastHolder: Frame
local bannerFrame: CanvasGroup
local warningFrame: CanvasGroup
local refs: { [string]: any } = {}

local mode = "base"
local altMax = 600
local chapterId = 1

-- flight smoothing & cached state (no per-frame Instance.new)
local lastUpdateT = 0
local smoothBat = 1
local trailBat = 1
local smoothAltY = 0
local lastBatState = "ok" -- "ok" | "low" | "crit"
local lastBatPct = -1
local lastKmText = ""
local lastBeaming = false

local hullPips: { Frame } = {}
local hullCount = -1
local cargoSlots: { Frame } = {}
local cargoDots: { Frame } = {}
local cargoStrokes: { UIStroke } = {}
local lastCargoFilled = 0

local bannerGen = 0
local warningGen = 0
local warningPulseTween: Tween? = nil
local warningStrokeTween: Tween? = nil

----------------------------------------------------------------------------
-- UI primitives
----------------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color: Color3, transp: number, thickness: number?): UIStroke
	return make("UIStroke", {
		Color = color,
		Transparency = transp,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function aspect(ratio: number): UIAspectRatioConstraint
	return make("UIAspectRatioConstraint", { AspectRatio = ratio })
end

local function addTopSheen(parent: Instance, color: Color3, zIndex: number?): Frame
	local bar = make("Frame", {
		Name = "AccentLine",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 0, 2),
		ZIndex = zIndex or 2,
		Parent = parent,
	})
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.15),
			NumberSequenceKeypoint.new(0.85, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bar,
	})
	return bar
end

local function addCornerTicks(parent: Instance, color: Color3, zIndex: number?)
	local z = zIndex or 3
	-- top-left L tick
	make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(10, 2), ZIndex = z, Parent = parent })
	make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(2, 10), ZIndex = z, Parent = parent })
	-- bottom-right L tick
	make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(10, 2), ZIndex = z, Parent = parent })
	make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(2, 10), ZIndex = z, Parent = parent })
end

local function panel(props: { [string]: any }, accent: Color3?, ticks: boolean?): Frame
	local col = accent or C.cyan
	props.BackgroundColor3 = props.BackgroundColor3 or C.panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.20
	props.BorderSizePixel = 0
	local f = make("Frame", props)
	corner(8).Parent = f
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(C.panelTop, C.panelBot),
		Parent = f,
	})
	stroke(col, 0.58, 1.2).Parent = f
	addTopSheen(f, col, (props.ZIndex or 1) + 1)
	if ticks then
		addCornerTicks(f, col, (props.ZIndex or 1) + 1)
	end
	return f
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.fg
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props)
end

local function button(props: { [string]: any }, color: Color3, borderCol: Color3?): TextButton
	props.BackgroundColor3 = color
	props.AutoButtonColor = true
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.cyanDark
	props.BorderSizePixel = 0
	local b = make("TextButton", props)
	corner(8).Parent = b
	if borderCol then
		stroke(borderCol, 0.3, 1.5).Parent = b
	end
	local s = make("UIScale", { Scale = 1, Parent = b })
	b.MouseButton1Down:Connect(function()
		s.Scale = 0.94
		TweenService:Create(s, POP, { Scale = 1 }):Play()
	end)
	return b
end

-- Crisp geometric vector icons (no external image ids needed)
local function buildBatteryIcon(parent: Instance, pos: UDim2): Frame
	local holder = make("Frame", { BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(18, 11), Parent = parent })
	local body = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(15, 11), Parent = holder }, {
		corner(2),
		stroke(C.cyan, 0.15, 1.4),
	})
	make("Frame", { Name = "Fill", BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Parent = body }, { corner(1) })
	make("Frame", { Name = "Nub", BackgroundColor3 = C.cyan, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 3), Size = UDim2.fromOffset(2, 5), Parent = holder }, { corner(1) })
	return holder
end

local function buildHullIcon(parent: Instance, pos: UDim2): Frame
	local holder = make("Frame", { BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(14, 14), Parent = parent }, { aspect(1) })
	local diamond = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(9, 9),
		Rotation = 45,
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = holder,
	}, {
		corner(2),
		stroke(C.cyan, 0.15, 1.3),
	})
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = C.cyan,
		BorderSizePixel = 0,
		Parent = diamond,
	})
	return holder
end

local function buildCargoIcon(parent: Instance, pos: UDim2): Frame
	local holder = make("Frame", { BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(14, 14), Parent = parent }, { aspect(1) })
	for r = 0, 1 do
		for c = 0, 1 do
			make("Frame", {
				BackgroundColor3 = C.cyan,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(c * 7 + 1, r * 7 + 1),
				Size = UDim2.fromOffset(5, 5),
				Parent = holder,
			}, { corner(1) })
		end
	end
	return holder
end

----------------------------------------------------------------------------
-- Flight HUD
----------------------------------------------------------------------------
local function buildFlight()
	flightFrame = make("Frame", {
		Name = "Flight",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})

	-- 1) Top-left Telemetry Status (Battery + Hull)
	local status = panel({
		Name = "Status",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(264, 96),
		Parent = flightFrame,
	}, C.cyan, true)
	refs.statusPanel = status
	refs.statusStroke = status:FindFirstChildOfClass("UIStroke")

	-- Battery row
	refs.batIcon = buildBatteryIcon(status, UDim2.fromOffset(12, 13))
	label({
		Text = "BATTERY",
		TextSize = 11,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(36, 11),
		Size = UDim2.fromOffset(80, 14),
		Parent = status,
	})
	refs.batDrainTag = label({
		Text = "BEAM",
		TextSize = 9,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(112, 11),
		Size = UDim2.fromOffset(44, 14),
		Visible = false,
		Parent = status,
	})
	refs.batPct = label({
		Text = "100%",
		TextSize = 14,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -74, 0, 9),
		Size = UDim2.fromOffset(62, 18),
		Parent = status,
	})

	local batTrack = make("Frame", {
		Name = "BatteryTrack",
		BackgroundColor3 = C.track,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(12, 31),
		Size = UDim2.new(1, -24, 0, 14),
		Parent = status,
	}, {
		corner(4),
		stroke(C.cyan, 0.78, 1),
	})
	refs.batTrail = make("Frame", {
		Name = "Trail",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = batTrack,
	}, { corner(4) })
	refs.batFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = batTrack,
	}, {
		corner(4),
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 210, 230)),
		}),
	})
	-- Subtle gauge notch ticks at 25%, 50%, 75%
	for _, frac in { 0.25, 0.5, 0.75 } do
		make("Frame", {
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(frac, 0),
			Size = UDim2.new(0, 1, 1, 0),
			ZIndex = 4,
			Parent = batTrack,
		})
	end

	-- Divider
	make("Frame", {
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -24, 0, 1),
		Parent = status,
	})

	-- Hull row
	buildHullIcon(status, UDim2.fromOffset(12, 66))
	label({
		Text = "HULL",
		TextSize = 11,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(32, 66),
		Size = UDim2.fromOffset(42, 14),
		Parent = status,
	})
	refs.hull = make("Frame", {
		Name = "HullPips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(78, 65),
		Size = UDim2.new(1, -132, 0, 16),
		Parent = status,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
		}),
	})
	refs.hullReadout = label({
		Text = "3/3",
		TextSize = 12,
		TextColor3 = C.fg,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -50, 0, 65),
		Size = UDim2.fromOffset(38, 16),
		Parent = status,
	})

	-- 2) Left Vertical Altimeter
	local alt = panel({
		Name = "Altimeter",
		Position = UDim2.fromOffset(16, 118),
		Size = UDim2.fromOffset(160, 256),
		Parent = flightFrame,
	}, C.cyan, true)
	label({
		Text = "ALTITUDE",
		TextSize = 10,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = alt,
	})
	refs.altKm = label({
		Text = "0.0 km",
		TextSize = 21,
		TextColor3 = C.fg,
		Position = UDim2.fromOffset(12, 21),
		Size = UDim2.new(1, -24, 0, 24),
		Parent = alt,
	})
	refs.altZone = label({
		Text = "LOW SKY",
		Font = FONT,
		TextSize = 11,
		TextColor3 = C.cyan,
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.new(1, -24, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = alt,
	})
	make("Frame", {
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 65),
		Size = UDim2.new(1, -24, 0, 1),
		Parent = alt,
	})
	refs.altTrack = make("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.new(1, -26, 1, -86),
		Parent = alt,
	})

	-- 3) Bottom-Center Cargo Bay Dock
	local cargoPanel = panel({
		Name = "CargoBay",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(0, 54),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = flightFrame,
	}, C.cyan, false)
	local cargoContent = make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 54),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = cargoPanel,
	}, {
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local cargoMeta = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(72, 34),
		LayoutOrder = 1,
		Parent = cargoContent,
	})
	buildCargoIcon(cargoMeta, UDim2.fromOffset(0, 2))
	label({
		Text = "CARGO",
		TextSize = 10,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(20, 2),
		Size = UDim2.fromOffset(52, 13),
		Parent = cargoMeta,
	})
	refs.cargoCount = label({
		Text = "0 / 5",
		TextSize = 14,
		TextColor3 = C.fg,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.fromOffset(72, 17),
		Parent = cargoMeta,
	})

	make("Frame", {
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(1, 30),
		LayoutOrder = 2,
		Parent = cargoContent,
	})

	refs.cargo = make("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		LayoutOrder = 3,
		Parent = cargoContent,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- 4) Zone Banner (top-center, below warning banner)
	bannerFrame = make("CanvasGroup", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(480, 76),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = flightFrame,
	})
	local bannerBg = make("Frame", {
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = bannerFrame,
	})
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.15),
			NumberSequenceKeypoint.new(0.82, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bannerBg,
	})
	local bannerTopLine = make("Frame", {
		BackgroundColor3 = C.cyan,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		Parent = bannerFrame,
	})
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bannerTopLine,
	})
	local bannerBotLine = make("Frame", {
		BackgroundColor3 = C.cyan,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = bannerFrame,
	})
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.35),
			NumberSequenceKeypoint.new(0.75, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bannerBotLine,
	})
	label({
		Text = "ENTERING SECTOR",
		TextSize = 11,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = bannerFrame,
	})
	refs.bannerName = label({
		Text = "",
		Font = FONT_HEAVY,
		TextSize = 32,
		TextColor3 = C.fg,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 40),
		TextStrokeTransparency = 0.65,
		Parent = bannerFrame,
	})

	-- 5) Bottom-Right Recall button (>= 44px even at 0.65 mobile UIScale -> 68px logical)
	local recall = button({
		Name = "Recall",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(156, 68),
		BackgroundTransparency = 0.14,
		Parent = flightFrame,
	}, C.panel, C.cyan)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(C.panelTop, C.panelBot),
		Parent = recall,
	})
	addTopSheen(recall, C.cyan, 2)
	label({
		Text = "RETURN TO BASE",
		Font = FONT_BODY,
		TextSize = 10,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(100, 13),
		Parent = recall,
	})
	label({
		Text = "RECALL",
		Font = FONT_HEAVY,
		TextSize = 19,
		TextColor3 = C.fg,
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.fromOffset(96, 24),
		Parent = recall,
	})
	-- Keycap badge (R)
	local keycap = make("Frame", {
		Name = "Keycap",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.inset,
		BorderSizePixel = 0,
		Parent = recall,
	}, {
		corner(6),
		stroke(C.cyan, 0.35, 1.4),
		aspect(1),
	})
	label({
		Text = "R",
		TextSize = 15,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = keycap,
	})
	refs.recall = recall

	-- Touch-only Beam button above Recall
	local beam = button({
		Name = "Beam",
		Text = "BEAM",
		Font = FONT_HEAVY,
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -92),
		Size = UDim2.fromOffset(104, 104),
		Visible = false,
		TextColor3 = C.fg,
		BackgroundTransparency = 0.28,
		Parent = flightFrame,
	}, C.cyanDim, C.cyan)
	local beamCorner = beam:FindFirstChildOfClass("UICorner")
	if beamCorner then
		beamCorner.CornerRadius = UDim.new(1, 0)
	end
	aspect(1).Parent = beam
	-- Inner target ring
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundTransparency = 1,
		Parent = beam,
	}, {
		make("UICorner", { CornerRadius = UDim.new(1, 0) }),
		stroke(C.cyan, 0.45, 1.5),
	})
	refs.beam = beam
end

----------------------------------------------------------------------------
-- Top-Center Warning Banner (Stage 3 hazards + info alerts)
----------------------------------------------------------------------------
local function buildWarning()
	warningFrame = make("CanvasGroup", {
		Name = "Warning",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 15,
		Parent = gui,
	})
	corner(8).Parent = warningFrame
	refs.warnStroke = stroke(C.cyan, 0.2, 1.8)
	refs.warnStroke.Parent = warningFrame
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 16),
		Parent = warningFrame,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = warningFrame,
	})
	local badge = make("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(22, 22),
		LayoutOrder = 1,
		Parent = warningFrame,
	}, {
		corner(5),
		aspect(1),
	})
	label({
		Text = "!",
		Font = FONT_HEAVY,
		TextSize = 15,
		TextColor3 = C.cyanDark,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	refs.warnBadge = badge
	refs.warnText = label({
		Text = "",
		Font = FONT_HEAVY,
		TextSize = 15,
		TextColor3 = C.fg,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = warningFrame,
	})
end

----------------------------------------------------------------------------
-- Base Screen & Mission Debrief Results
----------------------------------------------------------------------------
local function buildBase()
	baseFrame = make("Frame", {
		Name = "Base",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})

	local wallet = panel({
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(248, 72),
		Parent = baseFrame,
	}, C.cyan, true)
	label({
		Text = "CREDITS",
		TextSize = 10,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(14, 9),
		Size = UDim2.new(1, -28, 0, 12),
		Parent = wallet,
	})
	refs.coins = label({
		Text = "0 coins",
		Font = FONT_HEAVY,
		TextSize = 21,
		TextColor3 = C.amber,
		Position = UDim2.fromOffset(14, 22),
		Size = UDim2.new(1, -28, 0, 24),
		Parent = wallet,
	})
	refs.owned = label({
		Text = "0 creatures caught",
		Font = FONT_BODY,
		TextSize = 12,
		TextColor3 = C.muted,
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -28, 0, 16),
		Parent = wallet,
	})

	-- Keep exact path HUD.Base.Launch
	local launchBtn = button({
		Name = "Launch",
		Text = "LAUNCH",
		Font = FONT_HEAVY,
		TextSize = 24,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -38),
		Size = UDim2.fromOffset(264, 62),
		TextColor3 = C.cyanDark,
		Parent = baseFrame,
	}, C.cyan, Color3.fromRGB(165, 238, 255))
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 232, 245)),
		Parent = launchBtn,
	})
	refs.launch = launchBtn
	refs.launchStroke = launchBtn:FindFirstChildOfClass("UIStroke")

	local subBg = make("Frame", {
		Name = "LaunchSub",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(196, 20),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = baseFrame,
	}, {
		corner(6),
		stroke(C.cyan, 0.72, 1),
	})
	refs.launchSub = label({
		Text = "CHAPTER 1  ·  EARTH",
		Font = FONT,
		TextSize = 11,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = subBg,
	})
end

local function buildResults()
	resultsFrame = make("Frame", {
		Name = "Results",
		BackgroundColor3 = Color3.fromRGB(6, 10, 20),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})

	local card = panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(448, 400),
		BackgroundTransparency = 0.08,
		ZIndex = 21,
		Parent = resultsFrame,
	}, C.cyan, true)
	refs.resultsCard = card

	label({
		Text = "MISSION DEBRIEF",
		TextSize = 11,
		TextColor3 = C.cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 22,
		Parent = card,
	})
	refs.resTitle = label({
		Text = "Drone recovered",
		Font = FONT_HEAVY,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(16, 30),
		Size = UDim2.new(1, -32, 0, 30),
		ZIndex = 22,
		Parent = card,
	})
	make("Frame", {
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 68),
		Size = UDim2.new(1, -48, 0, 1),
		ZIndex = 22,
		Parent = card,
	})

	refs.resList = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 78),
		Size = UDim2.new(1, -48, 1, -200),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.cyan,
		ZIndex = 22,
		Parent = card,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local totalBox = make("Frame", {
		BackgroundColor3 = C.inset,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 24, 1, -114),
		Size = UDim2.new(1, -48, 0, 44),
		ZIndex = 22,
		Parent = card,
	}, {
		corner(6),
		stroke(C.cyan, 0.78, 1),
	})
	refs.resTotal = label({
		Text = "",
		Font = FONT_BODY,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(10, 2),
		Size = UDim2.new(1, -20, 1, -4),
		ZIndex = 23,
		Parent = totalBox,
	})

	-- Keep exact path HUD.Results.Card.TextButton (default Name = "TextButton")
	refs.resContinue = button({
		Text = "CONTINUE",
		Font = FONT_HEAVY,
		TextSize = 17,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(212, 46),
		TextColor3 = C.cyanDark,
		ZIndex = 22,
		Parent = card,
	}, C.cyan, Color3.fromRGB(165, 238, 255))
end

----------------------------------------------------------------------------
-- Flight HUD updates
----------------------------------------------------------------------------
local function rebuildAltimeter(chapter: number, maxAlt: number)
	local track = refs.altTrack :: Frame
	track:ClearAllChildren()
	local zones = Chapters.get(chapter).zones
	local top = zones[#zones].to
	local function yOf(a: number): number
		return 1 - math.clamp(a / top, 0, 1)
	end

	-- Recessed vertical bar backdrop
	make("Frame", {
		BackgroundColor3 = C.track,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 10, 1, 0),
		Parent = track,
	}, { corner(4) })

	for i, z in zones do
		local col = ZONE_COLORS[z.id] or C.muted
		local yTop = yOf(z.to)
		local yBot = yOf(z.from)
		make("Frame", {
			BackgroundColor3 = col,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 1, yTop, 1),
			Size = UDim2.new(0, 8, yBot - yTop, -2),
			ZIndex = 2,
			Parent = track,
		}, { corner(3) })

		-- Zone boundary tick
		if i > 1 then
			make("Frame", {
				BackgroundColor3 = C.fg,
				BackgroundTransparency = 0.65,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 10, yBot, 0),
				Size = UDim2.fromOffset(5, 1),
				ZIndex = 2,
				Parent = track,
			})
		end

		label({
			Text = z.name,
			Font = FONT_BODY,
			TextSize = 11,
			TextColor3 = C.fg,
			Position = UDim2.new(0, 18, yOf((z.from + z.to) / 2), -7),
			Size = UDim2.new(1, -18, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 2,
			Parent = track,
		})
	end

	-- Engine-limit horizontal line + compact tag
	local limY = yOf(maxAlt)
	make("Frame", {
		Name = "Limit",
		BackgroundColor3 = C.danger,
		BorderSizePixel = 0,
		Position = UDim2.new(0, -3, limY, 0),
		Size = UDim2.new(1, 3, 0, 2),
		ZIndex = 4,
		Parent = track,
	})
	local tagOffset = if limY < 0.12 then 4 else -14
	label({
		Text = "MAX LIMIT",
		TextSize = 9,
		TextColor3 = C.danger,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, limY, tagOffset),
		Size = UDim2.new(1, 0, 0, 11),
		ZIndex = 4,
		Parent = track,
	})

	-- Glowing drone altitude marker
	local marker = make("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(16, 4),
		ZIndex = 5,
		Parent = track,
	}, {
		corner(2),
		stroke(C.cyan, 0.1, 1.4),
	})
	refs.altMarker = marker
	refs.altYOf = yOf
end

local function setHull(n: number, max: number)
	local key = n * 100 + max
	if hullCount == key then return end
	hullCount = key

	local holder = refs.hull :: Frame
	if #hullPips ~= max then
		for _, p in hullPips do p:Destroy() end
		table.clear(hullPips)
		local pipW = math.clamp(math.floor((124 - (max - 1) * 5) / math.max(1, max)), 10, 28)
		for i = 1, max do
			local pip = make("Frame", {
				BackgroundColor3 = C.track,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(pipW, 12),
				LayoutOrder = i,
				Parent = holder,
			}, {
				corner(3),
				stroke(C.cyan, 0.65, 1),
			})
			table.insert(hullPips, pip)
		end
	end

	local fillCol = if n <= 1 then C.danger elseif n <= math.ceil(max / 2) and max > 2 then C.amber else C.cyan
	for i, pip in hullPips do
		local active = i <= n
		pip.BackgroundColor3 = if active then fillCol else C.track
		local st = pip:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if active then fillCol else C.cyanDim
			st.Transparency = if active then 0.2 else 0.7
		end
	end
	;(refs.hullReadout :: TextLabel).Text = string.format("%d/%d", n, max)
	;(refs.hullReadout :: TextLabel).TextColor3 = if n <= 1 then C.danger else C.fg
end

function HUDController.setCargo(colors: { Color3 }, max: number)
	local holder = refs.cargo :: Frame
	if #cargoSlots ~= max then
		for _, s in cargoSlots do s:Destroy() end
		table.clear(cargoSlots)
		table.clear(cargoDots)
		table.clear(cargoStrokes)
		for i = 1, max do
			local slot = make("Frame", {
				Name = "Slot" .. tostring(i),
				BackgroundColor3 = C.track,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(28, 28),
				LayoutOrder = i,
				Parent = holder,
			}, {
				corner(6),
				aspect(1),
			})
			local st = stroke(C.cyanDim, 0.55, 1.3)
			st.Parent = slot
			local dot = make("Frame", {
				Name = "Core",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = C.cyanDim,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Parent = slot,
			}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			make("UIScale", { Scale = 1, Parent = slot })
			table.insert(cargoSlots, slot)
			table.insert(cargoDots, dot)
			table.insert(cargoStrokes, st)
		end
	end

	local count = #colors
	for i = 1, max do
		local slot = cargoSlots[i]
		local dot = cargoDots[i]
		local st = cargoStrokes[i]
		local filled = colors[i]
		if filled then
			slot.BackgroundColor3 = filled
			st.Color = filled:Lerp(Color3.new(1, 1, 1), 0.45)
			st.Transparency = 0.1
			dot.Size = UDim2.fromOffset(10, 10)
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			dot.BackgroundTransparency = 0.65
			if i > lastCargoFilled then
				local sc = slot:FindFirstChildOfClass("UIScale")
				if sc then
					sc.Scale = 1.55
					TweenService:Create(sc, POP, { Scale = 1 }):Play()
				end
			end
		else
			slot.BackgroundColor3 = C.track
			st.Color = C.cyanDim
			st.Transparency = 0.55
			dot.Size = UDim2.fromOffset(6, 6)
			dot.BackgroundColor3 = C.cyanDim
			dot.BackgroundTransparency = 0.5
		end
	end
	lastCargoFilled = count

	local countLbl = refs.cargoCount :: TextLabel
	countLbl.Text = string.format("%d / %d", count, max)
	countLbl.TextColor3 = if count >= max and max > 0 then C.amber else C.fg
end

function HUDController.updateFlight(state: any, t: number)
	local dt = if lastUpdateT > 0 then math.clamp(t - lastUpdateT, 0.001, 0.25) else 0.05
	lastUpdateT = t

	-- Smooth battery bar + trailing drain indicator
	local frac = if state.batteryMax > 0 then math.clamp(state.battery / state.batteryMax, 0, 1) else 0
	smoothBat += (frac - smoothBat) * (1 - math.exp(-14 * dt))
	if frac < trailBat then
		trailBat += (frac - trailBat) * (1 - math.exp(-2.6 * dt))
	else
		trailBat = frac
	end

	local fill = refs.batFill :: Frame
	local trail = refs.batTrail :: Frame
	fill.Size = UDim2.fromScale(math.clamp(smoothBat, 0, 1), 1)
	trail.Size = UDim2.fromScale(math.clamp(trailBat, 0, 1), 1)

	local pct = math.ceil(frac * 100)
	local pctLbl = refs.batPct :: TextLabel
	if pct ~= lastBatPct then
		lastBatPct = pct
		pctLbl.Text = string.format("%d%%", pct)
	end

	local beaming = state.beaming == true
	if beaming ~= lastBeaming then
		lastBeaming = beaming
		;(refs.batDrainTag :: TextLabel).Visible = beaming
	end

	-- Battery color states from Balance thresholds
	local lowThresh = Balance.battery.lowThreshold
	local critThresh = Balance.battery.criticalThreshold
	local batState = if frac < critThresh then "crit" elseif frac < lowThresh then "low" else "ok"
	local stStroke = refs.statusStroke :: UIStroke?

	if batState == "crit" then
		local pulse = 0.5 + 0.5 * math.sin(t * 11)
		local col = C.danger:Lerp(Color3.fromRGB(255, 165, 175), pulse * 0.45)
		fill.BackgroundColor3 = col
		pctLbl.TextColor3 = col
		if stStroke then
			stStroke.Color = C.danger
			stStroke.Transparency = 0.12 + 0.5 * (1 - pulse)
		end
	elseif batState == "low" then
		if lastBatState ~= "low" then
			fill.BackgroundColor3 = C.amber
			pctLbl.TextColor3 = C.amber
			if stStroke then
				stStroke.Color = C.amber
				stStroke.Transparency = 0.42
			end
		end
	elseif lastBatState ~= "ok" then
		fill.BackgroundColor3 = C.cyan
		pctLbl.TextColor3 = C.cyan
		if stStroke then
			stStroke.Color = C.cyan
			stStroke.Transparency = 0.58
		end
	end
	lastBatState = batState

	-- Optional hull sync if Stage 3 exposes hull on state
	if typeof(state.hull) == "number" and typeof(state.hullMax) == "number" then
		setHull(state.hull, state.hullMax)
	end

	-- Smooth altimeter marker + km readout
	local altY = math.max(0, state.y)
	smoothAltY += (altY - smoothAltY) * (1 - math.exp(-14 * dt))
	local yOf = refs.altYOf
	if yOf and refs.altMarker then
		(refs.altMarker :: Frame).Position = UDim2.fromScale(0, yOf(smoothAltY))
	end
	local km = Chapters.toKm(state.chapter, altY)
	local kmText = string.format("%.1f km", km)
	if kmText ~= lastKmText then
		lastKmText = kmText
		;(refs.altKm :: TextLabel).Text = kmText
	end
end

local function applyZoneLabel(zoneName: string)
	local lbl = refs.altZone :: TextLabel
	lbl.Text = string.upper(zoneName)
	local ch = Chapters.get(chapterId)
	local col = C.cyan
	for _, z in ch.zones do
		if z.name == zoneName then
			col = ZONE_COLORS[z.id] or C.cyan
			break
		end
	end
	lbl.TextColor3 = col
end

function HUDController.zoneBanner(zoneName: string)
	applyZoneLabel(zoneName)
	;(refs.bannerName :: TextLabel).Text = string.upper(zoneName)
	bannerGen += 1
	local myGen = bannerGen
	bannerFrame.GroupTransparency = 1
	bannerFrame.Position = UDim2.new(0.5, 0, 0, 48)
	TweenService:Create(bannerFrame, FADE_IN, {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, 58),
	}):Play()
	task.delay(2.4, function()
		if myGen ~= bannerGen then return end
		TweenService:Create(bannerFrame, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		}):Play()
	end)
end

function HUDController.setZoneName(zoneName: string)
	applyZoneLabel(zoneName)
end

function HUDController.warning(text: string, level: "info" | "danger")
	local isDanger = level == "danger"
	warningGen += 1
	local myGen = warningGen

	if warningPulseTween then
		warningPulseTween:Cancel()
		warningPulseTween = nil
	end
	if warningStrokeTween then
		warningStrokeTween:Cancel()
		warningStrokeTween = nil
	end

	local accent = if isDanger then C.danger else C.cyan
	local bg = if isDanger then C.dangerBg else C.panel
	local warnStroke = refs.warnStroke :: UIStroke
	local warnBadge = refs.warnBadge :: Frame
	local warnText = refs.warnText :: TextLabel

	warningFrame.BackgroundColor3 = bg
	warnStroke.Color = accent
	warnStroke.Transparency = 0.15
	warnBadge.BackgroundColor3 = accent
	warnText.Text = string.upper(text)
	warnText.TextColor3 = if isDanger then Color3.fromRGB(255, 224, 230) else C.fg

	warningFrame.Visible = true
	warningFrame.GroupTransparency = 1
	warningFrame.Position = UDim2.new(0.5, 0, 0, 4)
	TweenService:Create(warningFrame, FADE_IN, {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, 12),
	}):Play()

	if isDanger then
		local pt = TweenService:Create(warningFrame, WARN_PULSE, {
			BackgroundColor3 = Color3.fromRGB(98, 18, 34),
		})
		warningPulseTween = pt
		pt:Play()
		local st = TweenService:Create(warnStroke, WARN_PULSE, {
			Transparency = 0.65,
		})
		warningStrokeTween = st
		st:Play()
	end

	task.delay(2.5, function()
		if myGen ~= warningGen then return end
		if warningPulseTween then
			warningPulseTween:Cancel()
			warningPulseTween = nil
		end
		if warningStrokeTween then
			warningStrokeTween:Cancel()
			warningStrokeTween = nil
		end
		local tw = TweenService:Create(warningFrame, FADE_OUT, { GroupTransparency = 1 })
		tw:Play()
		tw.Completed:Connect(function()
			if myGen == warningGen then
				warningFrame.Visible = false
			end
		end)
	end)
end

function HUDController.toast(text: string, color: Color3?, big: boolean?)
	local accent = color or C.cyan
	local size = if big then 20 else 15
	local t = make("Frame", {
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, size + 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = toastHolder,
	}, {
		corner(8),
		stroke(accent, 0.45, 1.3),
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 16) }),
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	make("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, size + 4),
		LayoutOrder = 1,
		Parent = t,
	}, { corner(2) })
	label({
		Text = text,
		Font = if big then FONT_HEAVY else FONT,
		TextSize = size,
		TextColor3 = accent:Lerp(C.fg, 0.22),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = t,
	})
	local s = make("UIScale", { Scale = 0.65, Parent = t })
	TweenService:Create(s, POP, { Scale = 1 }):Play()
	task.delay(2.6, function()
		if t.Parent then
			TweenService:Create(s, FADE_OUT, { Scale = 0 }):Play()
			task.wait(0.45)
			if t.Parent then t:Destroy() end
		end
	end)
	-- Keep at most 4 toasts stacked
	local items = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then table.insert(items, c) end
	end
	if #items > 4 then
		items[1]:Destroy()
	end
end

----------------------------------------------------------------------------
-- Modes, fade, results
----------------------------------------------------------------------------
function HUDController.beginFlight(run: any)
	altMax = run.maxAltitude
	chapterId = run.chapter
	rebuildAltimeter(chapterId, altMax)
	hullCount = -1
	setHull(run.stats.armor, run.stats.armor)
	lastCargoFilled = 0
	HUDController.setCargo({}, run.stats.cargo)

	lastUpdateT = 0
	smoothBat = 1
	trailBat = 1
	smoothAltY = Balance.flight.deployAltitude
	lastBatState = "ok"
	lastBatPct = -1
	lastKmText = ""
	lastBeaming = false

	;(refs.batFill :: Frame).Size = UDim2.fromScale(1, 1)
	;(refs.batFill :: Frame).BackgroundColor3 = C.cyan
	;(refs.batTrail :: Frame).Size = UDim2.fromScale(1, 1)
	;(refs.batPct :: TextLabel).Text = "100%"
	;(refs.batPct :: TextLabel).TextColor3 = C.cyan
	;(refs.batDrainTag :: TextLabel).Visible = false
	local stStroke = refs.statusStroke :: UIStroke?
	if stStroke then
		stStroke.Color = C.cyan
		stStroke.Transparency = 0.58
	end
end

function HUDController.setMode(m: string)
	mode = m
	flightFrame.Visible = m == "flight"
	baseFrame.Visible = m == "base"
	refs.beam.Visible = m == "flight" and InputController.device() == "touch"
end

function HUDController.fade(to: number, duration: number)
	local tw = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1 - to,
	})
	tw:Play()
	tw.Completed:Wait()
end

function HUDController.setLaunch(enabled: boolean, text: string)
	local b = refs.launch :: TextButton
	b.Text = text
	b.AutoButtonColor = enabled
	b.BackgroundColor3 = if enabled then C.cyan else C.disabled
	b.TextColor3 = if enabled then C.cyanDark else C.muted
	local st = refs.launchStroke :: UIStroke?
	if st then
		st.Color = if enabled then Color3.fromRGB(165, 238, 255) else C.cyanDim
		st.Transparency = if enabled then 0.25 else 0.72
	end
end

local function refreshWallet()
	local data = DataController.get()
	if not data then return end
	;(refs.coins :: TextLabel).Text = NumberFormat.short(data.coins or 0) .. " coins"
	local n = 0
	for _ in data.creatures or {} do
		n += 1
	end
	;(refs.owned :: TextLabel).Text = string.format("%d creatures caught", n)
end

-- results = server EndRun reply
function HUDController.showResults(results: any, onContinue: () -> ())
	local list = refs.resList :: ScrollingFrame
	for _, c in list:GetChildren() do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	local titleLbl = refs.resTitle :: TextLabel
	titleLbl.Text = if results.towed then "EMERGENCY TOW" else "DRONE RECOVERED"
	titleLbl.TextColor3 = if results.towed then C.amber else C.fg

	-- Group identical catches (creature + modifiers + size)
	local groups: { [string]: any } = {}
	local order: { string } = {}
	for _, item in results.cargo or {} do
		local key = item.creature .. "|" .. table.concat(item.modifiers or {}, ",") .. "|" .. tostring(item.size)
		if not groups[key] then
			groups[key] = { item = item, n = 0, value = 0 }
			table.insert(order, key)
		end
		groups[key].n += 1
		groups[key].value += item.value
	end
	table.sort(order, function(a, b)
		local ra = Rarities.byId[Creatures.byId[groups[a].item.creature].rarity].rank
		local rb = Rarities.byId[Creatures.byId[groups[b].item.creature].rarity].rank
		return if ra ~= rb then ra > rb else groups[a].value > groups[b].value
	end)
	if #order == 0 then
		label({
			Text = "No creatures caught this run",
			Font = FONT_BODY,
			TextSize = 14,
			TextColor3 = C.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 23,
			Parent = list,
		})
	end
	for i, key in order do
		local g = groups[key]
		local def = Creatures.byId[g.item.creature]
		local rarity = Rarities.byId[def.rarity]
		local row = make("Frame", {
			BackgroundColor3 = C.inset,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -6, 0, 30),
			LayoutOrder = i,
			ZIndex = 23,
			Parent = list,
		}, { corner(6) })
		make("Frame", {
			BackgroundColor3 = rarity.color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 5),
			Size = UDim2.new(0, 3, 1, -10),
			ZIndex = 24,
			Parent = row,
		}, { corner(2) })
		local tags = {}
		for _, m in g.item.modifiers or {} do
			local mod = Modifiers.byId[m]
			table.insert(tags, mod and mod.name or m)
		end
		if g.item.size and g.item.size ~= "Normal" then
			table.insert(tags, g.item.size)
		end
		local name = string.format("%d× %s", g.n, def.name)
		if #tags > 0 then
			name ..= "  [" .. table.concat(tags, ", ") .. "]"
		end
		label({
			Text = name,
			TextSize = 14,
			TextColor3 = rarity.color,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.72, -14, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 24,
			Parent = row,
		})
		label({
			Text = NumberFormat.short(g.value),
			Font = FONT,
			TextSize = 14,
			TextColor3 = C.amber,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.72, 0),
			Size = UDim2.new(0.28, -10, 1, 0),
			ZIndex = 24,
			Parent = row,
		})
	end

	local total = results.total or 0
	local fee = results.fee or 0
	;(refs.resTotal :: TextLabel).Text = if results.towed and fee > 0
		then string.format("Tow fee %s coins. You keep every creature. Cargo value: %s", NumberFormat.short(fee), NumberFormat.short(total))
		elseif results.towed then string.format("The tow was free this time. You keep every creature. Cargo value: %s", NumberFormat.short(total))
		else string.format("Cargo value: %s. Your creatures are now at the base.", NumberFormat.short(total))

	resultsFrame.Visible = true
	local card = refs.resultsCard :: Frame
	local s = card:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = card })
	s.Scale = 0.78
	TweenService:Create(s, POP, { Scale = 1 }):Play()

	local conn: RBXScriptConnection? = nil
	conn = (refs.resContinue :: TextButton).Activated:Connect(function()
		if conn then conn:Disconnect() end
		resultsFrame.Visible = false
		onContinue()
	end)
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
function HUDController.init()
	gui = make("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	})

	-- Global scale: keeps layout identical on PC (16:9) and landscape phones,
	-- while keeping touch targets >= 44px at minimum scale (0.65).
	local uiScale = make("UIScale", { Parent = gui })
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.65, 1.25)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	buildFlight()
	buildWarning()
	buildBase()
	buildResults()

	toastHolder = make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -78),
		Size = UDim2.fromOffset(620, 180),
		Parent = gui,
	}, {
		make("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Keep exact path HUD.Fade
	fadeFrame = make("Frame", {
		Name = "Fade",
		BackgroundColor3 = Color3.fromRGB(8, 13, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = gui,
	})

	gui.Parent = player:WaitForChild("PlayerGui")

	InputController.bindButton("Launch", refs.launch)
	InputController.bindButton("Recall", refs.recall)
	InputController.bindButton("Beam", refs.beam)
	InputController.DeviceChanged:Connect(function()
		HUDController.setMode(mode)
	end)

	DataController.Loaded:Connect(refreshWallet)
	DataController.Changed:Connect(function(key)
		if key == "coins" or key == "creatures" then
			refreshWallet()
		end
	end)
	refreshWallet()
	HUDController.setMode("base")
end

return HUDController
