--!strict
-- HUDController: TEMPORARY Stage 1 HUD in the "Mission Control" style
-- (battery, hull, cargo, altimeter with zone bands + engine limit, zone banner,
-- toasts, recall/beam/launch buttons, run results). The final HUD is Stage 2.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
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
	panel = Color3.fromRGB(13, 19, 36),
	fg = Color3.fromRGB(233, 238, 248),
	muted = Color3.fromRGB(154, 166, 194),
	peach = Color3.fromRGB(255, 179, 138),
	cyan = Color3.fromRGB(79, 216, 255),
	danger = Color3.fromRGB(255, 90, 110),
	empty = Color3.fromRGB(60, 68, 92),
}
local ZONE_COLORS = {
	LowSky = Color3.fromRGB(140, 192, 122),
	SunsetHeights = Color3.fromRGB(255, 179, 138),
	EdgeOfSpace = Color3.fromRGB(143, 111, 214),
}
local FONT = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui: ScreenGui
local flightFrame: Frame
local baseFrame: Frame
local resultsFrame: Frame
local fadeFrame: Frame
local toastHolder: Frame
local bannerFrame: CanvasGroup
local refs: { [string]: any } = {}
local mode = "base"
local altMax = 600
local chapterId = 1

----------------------------------------------------------------------------
-- builders
----------------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	if children then
		for _, c in children do c.Parent = inst end
	end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(r: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color: Color3, transp: number): UIStroke
	return make("UIStroke", { Color = color, Transparency = transp, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function panel(props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or C.panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.28
	props.BorderSizePixel = 0
	local f = make("Frame", props)
	corner(10).Parent = f
	stroke(Color3.fromRGB(255, 255, 255), 0.88).Parent = f
	return f
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.fg
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props)
end

local function button(props: { [string]: any }, color: Color3): TextButton
	props.BackgroundColor3 = color
	props.AutoButtonColor = true
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(26, 16, 32)
	props.BorderSizePixel = 0
	local b = make("TextButton", props)
	corner(12).Parent = b
	-- press pop
	b.MouseButton1Down:Connect(function()
		local s = b:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = b })
		s.Scale = 0.93
		TweenService:Create(s, POP, { Scale = 1 }):Play()
	end)
	return b
end

local function buildFlight()
	flightFrame = make("Frame", { Name = "Flight", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })

	-- status panel
	local status = panel({ Name = "Status", Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(250, 92), Parent = flightFrame })
	local function row(y: number, text: string): TextLabel
		return label({ Text = text, TextSize = 12, TextColor3 = C.muted, Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(70, 16), Parent = status })
	end
	row(10, "BATTERY")
	local batTrack = make("Frame", { BackgroundColor3 = C.empty, BorderSizePixel = 0, Position = UDim2.fromOffset(84, 12), Size = UDim2.fromOffset(152, 12), Parent = status }, { corner(6) })
	refs.batFill = make("Frame", { BackgroundColor3 = C.cyan, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = batTrack }, { corner(6) })
	row(38, "HULL")
	refs.hull = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(84, 38), Size = UDim2.fromOffset(152, 14), Parent = status }, {
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5) }),
	})
	row(64, "CARGO")
	refs.cargo = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(84, 63), Size = UDim2.fromOffset(160, 16), Parent = status }, {
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), VerticalAlignment = Enum.VerticalAlignment.Center }),
	})

	-- altimeter
	local alt = panel({ Name = "Altimeter", Position = UDim2.fromOffset(14, 116), Size = UDim2.fromOffset(150, 270), Parent = flightFrame })
	refs.altTrack = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -70), Parent = alt })
	refs.altKm = label({ Text = "0.0 km", TextSize = 20, Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(1, -24, 0, 24), Parent = alt })
	refs.altZone = label({ Text = "", Font = FONT_BODY, TextSize = 13, TextColor3 = C.muted, Position = UDim2.new(0, 12, 1, -28), Size = UDim2.new(1, -24, 0, 18), Parent = alt })

	-- zone banner
	bannerFrame = make("CanvasGroup", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(460, 78), BackgroundTransparency = 1, GroupTransparency = 1, Parent = flightFrame })
	label({ Text = "ENTERING", TextSize = 14, TextColor3 = C.fg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), TextStrokeTransparency = 0.6, Parent = bannerFrame })
	refs.bannerName = label({ Text = "", TextSize = 38, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 46), TextStrokeTransparency = 0.55, Parent = bannerFrame })

	-- buttons (right side)
	refs.recall = button({ Name = "Recall", Text = "RECALL  (R)", TextSize = 15, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(150, 46), TextColor3 = C.fg, Parent = flightFrame }, Color3.fromRGB(34, 44, 72))
	stroke(C.fg, 0.6).Parent = refs.recall
	refs.beam = button({ Name = "Beam", Text = "BEAM", TextSize = 18, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -80), Size = UDim2.fromOffset(110, 110), Visible = false, TextColor3 = C.fg, BackgroundTransparency = 0.35, Parent = flightFrame }, Color3.fromRGB(40, 120, 160))
	refs.beam:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	stroke(C.cyan, 0.2).Parent = refs.beam
end

local function buildBase()
	baseFrame = make("Frame", { Name = "Base", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local wallet = panel({ Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(230, 64), Parent = baseFrame })
	refs.coins = label({ Text = "0 coins", TextSize = 20, TextColor3 = C.peach, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), Parent = wallet })
	refs.owned = label({ Text = "0 creatures caught", Font = FONT_BODY, TextSize = 13, TextColor3 = C.muted, Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18), Parent = wallet })

	refs.launch = button({ Name = "Launch", Text = "LAUNCH", TextSize = 26, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(240, 64), Parent = baseFrame }, C.peach)
	refs.launchSub = label({ Text = "Chapter 1 · Earth", Font = FONT_BODY, TextSize = 13, TextColor3 = C.fg, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(240, 18), TextStrokeTransparency = 0.5, Parent = baseFrame })
end

local function buildResults()
	resultsFrame = make("Frame", { Name = "Results", BackgroundColor3 = Color3.fromRGB(8, 12, 26), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	local card = panel({ Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 380), BackgroundTransparency = 0.08, ZIndex = 21, Parent = resultsFrame })
	refs.resultsCard = card
	refs.resTitle = label({ Text = "Drone recovered", TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 32), ZIndex = 22, Parent = card })
	refs.resList = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 60), Size = UDim2.new(1, -48, 1, -170), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ZIndex = 22, Parent = card }, {
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.resTotal = label({ Text = "", Font = FONT_BODY, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 24, 1, -104), Size = UDim2.new(1, -48, 0, 40), ZIndex = 22, Parent = card })
	refs.resContinue = button({ Text = "CONTINUE", TextSize = 18, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(200, 48), ZIndex = 22, Parent = card }, C.peach)
end

----------------------------------------------------------------------------
-- flight HUD updates
----------------------------------------------------------------------------
local function rebuildAltimeter(chapter: number, maxAlt: number)
	local track = refs.altTrack :: Frame
	track:ClearAllChildren()
	local zones = Chapters.get(chapter).zones
	local top = zones[#zones].to
	local function yOf(a: number): number return 1 - math.clamp(a / top, 0, 1) end
	for _, z in zones do
		local col = ZONE_COLORS[z.id] or C.muted
		make("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Position = UDim2.fromScale(0, yOf(z.to)), Size = UDim2.new(0, 6, yOf(z.from) - yOf(z.to), 0), Parent = track })
		label({ Text = z.name, Font = FONT_BODY, TextSize = 11, TextColor3 = C.fg, Position = UDim2.new(0, 14, yOf((z.from + z.to) / 2), -7), Size = UDim2.new(1, -14, 0, 14), Parent = track })
	end
	-- engine limit line
	make("Frame", { Name = "Limit", BackgroundColor3 = C.danger, BorderSizePixel = 0, Position = UDim2.new(0, -4, yOf(maxAlt), 0), Size = UDim2.new(1, 4, 0, 2), Parent = track })
	label({ Text = "ENGINE LIMIT", TextSize = 9, TextColor3 = C.danger, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0, 0, yOf(maxAlt), -12), Size = UDim2.new(1, 0, 0, 11), Parent = track })
	refs.altMarker = make("Frame", { Name = "Marker", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(12, 4), Parent = track }, { corner(2) })
	refs.altYOf = yOf
end

local hullCount = -1
local function setHull(n: number, max: number)
	if hullCount == n * 100 + max then return end
	hullCount = n * 100 + max
	local holder = refs.hull :: Frame
	for _, c in holder:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	for i = 1, max do
		make("Frame", { BackgroundColor3 = if i <= n then C.peach else C.empty, BorderSizePixel = 0, Size = UDim2.fromOffset(22, 12), Parent = holder }, { corner(3) })
	end
end

function HUDController.setCargo(colors: { Color3 }, max: number)
	local holder = refs.cargo :: Frame
	for _, c in holder:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	for i = 1, max do
		local filled = colors[i]
		local dot = make("Frame", { BackgroundColor3 = filled or C.empty, BorderSizePixel = 0, Size = UDim2.fromOffset(13, 13), Parent = holder }, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		if filled and i == #colors then
			-- pop the newest slot
			local s = make("UIScale", { Scale = 1.8, Parent = dot })
			TweenService:Create(s, POP, { Scale = 1 }):Play()
		end
	end
end

local lastBatteryLow = false
function HUDController.updateFlight(state: any, t: number)
	local frac = math.clamp(state.battery / state.batteryMax, 0, 1)
	local fill = refs.batFill :: Frame
	fill.Size = UDim2.fromScale(frac, 1)
	local low = frac < 0.25
	if low then
		fill.BackgroundColor3 = if math.sin(t * 10) > 0 then C.danger else C.danger:Lerp(C.panel, 0.4)
	elseif lastBatteryLow ~= low then
		fill.BackgroundColor3 = C.cyan
	end
	lastBatteryLow = low

	local yOf = refs.altYOf
	if yOf then
		(refs.altMarker :: Frame).Position = UDim2.fromScale(0, yOf(math.max(0, state.y)))
	end
	local km = Chapters.toKm(state.chapter, math.max(0, state.y))
	;(refs.altKm :: TextLabel).Text = string.format("%.1f km", km)
end

function HUDController.zoneBanner(zoneName: string)
	(refs.altZone :: TextLabel).Text = zoneName
	;(refs.bannerName :: TextLabel).Text = string.upper(zoneName)
	bannerFrame.GroupTransparency = 1
	TweenService:Create(bannerFrame, FADE, { GroupTransparency = 0 }):Play()
	task.delay(2.4, function()
		TweenService:Create(bannerFrame, TweenInfo.new(0.8), { GroupTransparency = 1 }):Play()
	end)
end

function HUDController.setZoneName(zoneName: string)
	(refs.altZone :: TextLabel).Text = zoneName
end

function HUDController.toast(text: string, color: Color3?, big: boolean?)
	local size = if big then 22 else 16
	local t = panel({ BackgroundTransparency = 0.2, Size = UDim2.fromOffset(0, size + 18), AutomaticSize = Enum.AutomaticSize.X, Parent = toastHolder })
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = t })
	label({ Text = text, TextSize = size, TextColor3 = color or C.fg, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = t })
	local s = make("UIScale", { Scale = 0.6, Parent = t })
	TweenService:Create(s, POP, { Scale = 1 }):Play()
	task.delay(2.6, function()
		if t.Parent then
			TweenService:Create(s, FADE, { Scale = 0 }):Play()
			task.wait(0.35)
			t:Destroy()
		end
	end)
	-- keep at most 4
	local items = {}
	for _, c in toastHolder:GetChildren() do if c:IsA("Frame") then table.insert(items, c) end end
	if #items > 4 then items[1]:Destroy() end
end

----------------------------------------------------------------------------
-- modes, fade, results
----------------------------------------------------------------------------
-- run = launch reply; called when a flight starts
function HUDController.beginFlight(run: any)
	altMax = run.maxAltitude
	chapterId = run.chapter
	rebuildAltimeter(chapterId, altMax)
	hullCount = -1
	setHull(run.stats.armor, run.stats.armor)
	HUDController.setCargo({}, run.stats.cargo)
	lastBatteryLow = false
	;(refs.batFill :: Frame).BackgroundColor3 = C.cyan
end

function HUDController.setMode(m: string)
	mode = m
	flightFrame.Visible = m == "flight"
	baseFrame.Visible = m == "base"
	refs.beam.Visible = m == "flight" and InputController.device() == "touch"
end

function HUDController.fade(to: number, duration: number)
	local tw = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 - to })
	tw:Play()
	tw.Completed:Wait()
end

function HUDController.setLaunch(enabled: boolean, text: string)
	local b = refs.launch :: TextButton
	b.Text = text
	b.AutoButtonColor = enabled
	b.BackgroundColor3 = if enabled then C.peach else Color3.fromRGB(120, 110, 120)
end

local function refreshWallet()
	local data = DataController.get()
	if not data then return end
	(refs.coins :: TextLabel).Text = NumberFormat.short(data.coins or 0) .. " coins"
	local n = 0
	for _ in data.creatures or {} do n += 1 end
	;(refs.owned :: TextLabel).Text = string.format("%d creatures caught", n)
end

-- results = server EndRun reply
function HUDController.showResults(results: any, onContinue: () -> ())
	local list = refs.resList :: ScrollingFrame
	for _, c in list:GetChildren() do if not c:IsA("UIListLayout") then c:Destroy() end end
	(refs.resTitle :: TextLabel).Text = if results.towed then "Battery empty: emergency tow" else "Drone recovered"

	-- group identical catches (creature + modifiers + size)
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
		label({ Text = "No creatures this time", Font = FONT_BODY, TextSize = 15, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), ZIndex = 23, Parent = list })
	end
	for i, key in order do
		local g = groups[key]
		local def = Creatures.byId[g.item.creature]
		local rarity = Rarities.byId[def.rarity]
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, ZIndex = 23, Parent = list })
		local tags = {}
		for _, m in g.item.modifiers or {} do
			local mod = Modifiers.byId[m]
			table.insert(tags, mod and mod.name or m)
		end
		if g.item.size and g.item.size ~= "Normal" then table.insert(tags, g.item.size) end
		local name = string.format("%d× %s", g.n, def.name)
		if #tags > 0 then name ..= "  [" .. table.concat(tags, ", ") .. "]" end
		label({ Text = name, TextSize = 15, TextColor3 = rarity.color, Size = UDim2.new(0.72, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 23, Parent = row })
		label({ Text = NumberFormat.short(g.value), Font = FONT_BODY, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.72, 0), Size = UDim2.new(0.28, 0, 1, 0), ZIndex = 23, Parent = row })
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
	s.Scale = 0.7
	TweenService:Create(s, POP, { Scale = 1 }):Play()

	local conn: RBXScriptConnection? = nil
	conn = (refs.resContinue :: TextButton).Activated:Connect(function()
		if conn then conn:Disconnect() end
		resultsFrame.Visible = false
		onContinue()
	end)
end

----------------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------------
function HUDController.init()
	gui = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10 })
	-- one global scale keeps the layout identical from phones to desktops
	local uiScale = make("UIScale", { Parent = gui })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.62, 1.35)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	buildFlight()
	buildBase()
	buildResults()
	toastHolder = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(600, 200), Parent = gui }, {
		make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	fadeFrame = make("Frame", { Name = "Fade", BackgroundColor3 = Color3.fromRGB(255, 248, 240), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = gui })
	gui.Parent = player:WaitForChild("PlayerGui")

	InputController.bindButton("Launch", refs.launch)
	InputController.bindButton("Recall", refs.recall)
	InputController.bindButton("Beam", refs.beam)
	InputController.DeviceChanged:Connect(function()
		HUDController.setMode(mode)
	end)

	DataController.Loaded:Connect(refreshWallet)
	DataController.Changed:Connect(function(key)
		if key == "coins" or key == "creatures" then refreshWallet() end
	end)
	refreshWallet()
	HUDController.setMode("base")
end

return HUDController
