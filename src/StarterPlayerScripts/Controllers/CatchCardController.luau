--!strict
-- CatchCardController: the Catch Card for Epic+ catches (plan/02_CONTENT.md §1b, tiers T3-T5).
-- A "Mission Control" card slides in with the creature spinning in a ViewportFrame, its
-- name, rarity (gradient), modifier chips, size chip and coin value.
--   T3 (Epic)       normal card
--   T4 (Legendary)  + shine sweep across the card
--   T5 (Mythic+)    bigger card + pulsing glow border, plus the shine
-- Input: CatchEvents.CardRequested(info). Output: CatchEvents.CardClosed(info), exactly once
-- per card, when the player taps/clicks the card or after AUTO_CLOSE seconds.
-- Cards queue: a card requested while one is open shows after it closes.
-- The flight never pauses: the card only draws UI, and the spin runs on real time.
-- Every card owns a Trove (gui, model clone, tweens, connections) cleaned when it closes.
-- Creature model: ReplicatedStorage.Assets.Creatures[info.creature.id], falling back to
-- Assets.Creatures.Placeholder (tinted with info.creature.color).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Modifiers = require(Shared.Config.Modifiers)
local NumberFormat = require(Shared.Util.NumberFormat)
local Trove = require(Shared.Util.Trove)

local CatchEvents = require(script.Parent.CatchEvents)

local AUTO_CLOSE = 4 -- seconds a card stays up without a tap
local TAP_GRACE = 0.4 -- ignore taps right after the card appears (no accidental skips)
local SPIN_SPEED = 0.9 -- rad/s
local FILL_HEIGHT = 0.66 -- creature fills ~2/3 of the viewport height
local FILL_WIDTH = 0.9 -- ...unless that would clip it sideways while it spins
local EDGE_CLEAR = 76 -- px kept free above and below the card (Recall button: 16 + 46 from the bottom)

local C = {
	panel = Color3.fromRGB(11, 18, 32), -- #0B1220
	cyan = Color3.fromRGB(57, 213, 255), -- #39D5FF
	fg = Color3.fromRGB(233, 238, 248),
	muted = Color3.fromRGB(154, 166, 194),
	dark = Color3.fromRGB(16, 20, 32),
}
local FONT = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium
local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local TINT_PARTS = { Body = true, Rear = true, Tuft1 = true, Tuft2 = true, Tuft3 = true, Tuft4 = true }
local FIN_PARTS = { Fin = true, TailTop = true, TailBot = true }

local CatchCardController = {}

local queue: { CatchEvents.CatchInfo } = {}
local showing = false

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

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.fg
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	return make("TextLabel", props)
end

local function lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end

-- dark text on light chips, light text on dark ones
local function textOn(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return if lum > 0.55 then C.dark else C.fg
end

local function chip(text: string, color: Color3, filled: boolean, order: number, parent: Instance)
	local f = make("Frame", {
		Name = "Chip",
		BackgroundColor3 = if filled then color else C.panel,
		BackgroundTransparency = if filled then 0.05 else 0.2,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = order,
		Parent = parent,
	}, {
		corner(13),
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		make("UIStroke", { Color = color, Thickness = 1.5, Transparency = if filled then 0.6 else 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	label({
		Text = string.upper(text),
		TextSize = 14,
		TextColor3 = if filled then textOn(color) else color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = f,
	})
end

----------------------------------------------------------------------------
-- creature model for the viewport
----------------------------------------------------------------------------
local function cloneCreature(info: CatchEvents.CatchInfo): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Creatures")
	if not folder then return nil end
	local tpl = folder:FindFirstChild(info.creature.id) or folder:FindFirstChild("Placeholder")
	if not (tpl and tpl:IsA("Model")) then return nil end
	local m = tpl:Clone()
	m.Name = info.creature.id
	-- the viewport only needs the visuals
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") then d:Destroy() end
	end
	if tpl.Name == "Placeholder" then
		local col = info.creature.color
		local fin = col:Lerp(Color3.new(0, 0, 0), 0.25)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				if TINT_PARTS[p.Name] then
					p.Color = col
				elseif FIN_PARTS[p.Name] then
					p.Color = fin
					p.Transparency = 0.1
				elseif p.Name == "Belly" then
					p.Color = lighten(col, 0.5)
				end
			end
		end
	end
	return m
end

-- Puts the creature in the viewport and spins it. Returns nothing; all cleanup goes to trove.
-- aspect = viewport width / height
local function fillViewport(vp: ViewportFrame, info: CatchEvents.CatchInfo, trove: any, aspect: number)
	local m = cloneCreature(info)
	if not m then return end
	trove:Add(m)
	local cam = trove:Add(make("Camera", { FieldOfView = 34, Parent = vp }))
	vp.CurrentCamera = cam

	m:PivotTo(CFrame.new())
	local box, size = m:GetBoundingBox()
	local centre = box.Position -- spin around the model's visual centre
	local radius = math.max(size.Magnitude / 2, 0.5)
	-- fit by the real extents: height to FILL_HEIGHT, the spinning footprint (X/Z diagonal) to FILL_WIDTH
	local tanHalf = math.tan(math.rad(cam.FieldOfView / 2))
	local halfY = math.max(size.Y / 2, 0.25)
	local halfXZ = math.max(math.sqrt(size.X * size.X + size.Z * size.Z) / 2, 0.25)
	-- small extra distance: the near side of the spinning model is closer than its centre
	local dist = math.max(halfY / (FILL_HEIGHT * tanHalf), halfXZ / (FILL_WIDTH * tanHalf * aspect)) + halfXZ * 0.3
	cam.CFrame = CFrame.lookAt(Vector3.new(0, dist * 0.1, dist), Vector3.zero)
	m.Parent = vp

	local t0 = os.clock()
	trove:Connect(RunService.RenderStepped, function()
		local t = os.clock() - t0
		local spin = CFrame.Angles(math.sin(t * 1.7) * 0.08, t * SPIN_SPEED + 0.6, 0)
		local bob = CFrame.new(0, math.sin(t * 2.2) * radius * 0.05, 0)
		m:PivotTo(bob * spin * CFrame.new(-centre))
	end)
end

----------------------------------------------------------------------------
-- the card
----------------------------------------------------------------------------
local function buildCard(info: CatchEvents.CatchInfo, trove: any, onClosed: () -> ())
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	assert(playerGui, "no PlayerGui")
	local rarity = info.rarity
	local tier = rarity.tier
	local c1 = rarity.color
	local c2 = rarity.color2 or lighten(c1, 0.45)
	local big = tier >= 5
	local w, h = if big then 340 else 300, if big then 432 else 396

	local tweens: { Tween } = {}
	local function tween(inst: Instance, ti: TweenInfo, goal: { [string]: any }): Tween
		local tw = TweenService:Create(inst, ti, goal)
		table.insert(tweens, tw)
		tw:Play()
		return tw
	end
	trove:Add(function()
		for _, tw in tweens do
			tw:Cancel()
			tw:Destroy()
		end
		table.clear(tweens)
	end)

	local gui = trove:Add(make("ScreenGui", {
		Name = "CatchCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30, -- above the HUD (10) and the celebration layer (20)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}))
	-- same scale rule as the HUD, so the card reads the same on a phone and a desktop
	local uiScale = make("UIScale", { Parent = gui })
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local v = cam.ViewportSize
		-- vertically centred, so keep EDGE_CLEAR free top and bottom (clear of the Recall button)
		local fit = (v.Y - 2 * EDGE_CLEAR) / (h + 40)
		uiScale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720, fit), 0.5, 1.35)
	end
	rescale()
	if workspace.CurrentCamera then
		trove:Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), rescale)
	end

	-- right side, vertically centred: the flight camera centres the drone, so the middle stays free
	local shown = UDim2.new(0.97, 0, 0.5, 0)
	local hidden = UDim2.new(1, w + 60, 0.5, 0) -- off the right edge (incl. the T5 halo); slides in from the right

	-- holder slides; the glow (T5) sits behind the card inside it
	local holder = make("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = hidden,
		Size = UDim2.fromOffset(w, h),
		Parent = gui,
	})
	-- the whole card is the dismiss button
	local card: TextButton = make("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.03, -- nearly opaque: the world must not show through
		BorderSizePixel = 0,
		Selectable = true,
		Parent = holder,
	}, { corner(8) })
	local border = make("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = if big then 3 else 1.5,
		Transparency = if big then 0 else 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = card,
	})
	local borderGrad = make("UIGradient", {
		Color = ColorSequence.new(c1, c2),
		Rotation = 35,
		Parent = border,
	})

	-- T5: soft glow halo behind the card, pulsing
	if big then
		local halo = make("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 28, 1, 28),
			BackgroundColor3 = c1,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = holder,
		}, {
			corner(18),
			make("UIGradient", {
				Color = ColorSequence.new(c1, c2),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2),
					NumberSequenceKeypoint.new(0.5, 0.6),
					NumberSequenceKeypoint.new(1, 0.2),
				}),
				Rotation = 90,
			}),
		})
		tween(halo, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 0.88,
			Size = UDim2.new(1, 40, 1, 40),
		})
		tween(borderGrad, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 395 })
	end

	-- header + thin cyan accent line
	label({
		Name = "Header",
		Text = if big then "INCREDIBLE CATCH!" elseif tier >= 4 then "AMAZING CATCH!" else "RARE CATCH!",
		Font = FONT,
		TextSize = 13,
		TextColor3 = C.cyan,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 3,
		Parent = card,
	})
	make("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 33),
		Size = UDim2.new(1, -48, 0, 1),
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	}, {
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- creature viewport on a solid, dark rarity-tinted backdrop (opaque: nothing from the world behind)
	local vpSize = if big then 222 else 190
	local vpWidth = vpSize + 40
	local backdrop = make("Frame", {
		Name = "Backdrop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 42),
		Size = UDim2.fromOffset(vpWidth, vpSize),
		BackgroundColor3 = Color3.new(1, 1, 1), -- the gradient below gives the colour
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	}, {
		corner(8),
		make("UIGradient", {
			Color = ColorSequence.new(c1:Lerp(C.panel, 0.55), c1:Lerp(C.panel, 0.85)),
			Rotation = 90,
		}),
	})
	local vp: ViewportFrame = make("ViewportFrame", {
		Name = "Creature",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 205, 220),
		LightColor = Color3.fromRGB(255, 255, 250),
		LightDirection = Vector3.new(-1, -1.4, -1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = backdrop,
	})
	fillViewport(vp, info, trove, vpWidth / vpSize)

	-- name + rarity
	local y = 42 + vpSize + 8
	label({
		Name = "CreatureName",
		Text = info.creature.name,
		Font = FONT,
		TextSize = if big then 32 else 28,
		TextScaled = false,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 16, 0, y),
		Size = UDim2.new(1, -32, 0, 34),
		ZIndex = 3,
		Parent = card,
	})
	y += 34
	local rarityLabel = label({
		Name = "Rarity",
		Text = string.upper(rarity.name),
		Font = FONT,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Position = UDim2.new(0, 16, 0, y),
		Size = UDim2.new(1, -32, 0, 24),
		ZIndex = 3,
		Parent = card,
	})
	make("UIGradient", { Color = ColorSequence.new(c1, c2), Parent = rarityLabel })
	y += 30

	-- chips: modifiers (filled, modifier colour) + size (outlined, cyan); "Normal" size hidden
	local chips = make("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, y),
		Size = UDim2.new(1, -24, 0, 26),
		ZIndex = 3,
		Parent = card,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local nChips = 0
	for i, id in info.modifiers do
		local mod = Modifiers.byId[id]
		if mod then
			chip(mod.name, mod.color, true, i, chips)
			nChips += 1
		end
	end
	if info.size ~= "" and info.size ~= "Normal" then
		chip(info.size, C.cyan, false, 100, chips)
		nChips += 1
	end
	if nChips > 0 then y += 32 end

	-- coin value (hidden when 0, e.g. FakeCatch)
	if info.value > 0 then
		label({
			Name = "Value",
			Text = "+" .. NumberFormat.short(info.value) .. " coins",
			Font = FONT_BODY,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 214, 102),
			Position = UDim2.new(0, 16, 0, y),
			Size = UDim2.new(1, -32, 0, 20),
			ZIndex = 3,
			Parent = card,
		})
	end

	-- footer: hint + timer bar that drains until auto-close
	label({
		Name = "Hint",
		Text = "Tap to continue",
		Font = FONT_BODY,
		TextSize = 13,
		TextColor3 = C.muted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 3,
		Parent = card,
	})
	local timer = make("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 3),
		BackgroundColor3 = C.cyan,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	}, { corner(2) })

	-- T4+: shine sweep, a bright diagonal band crossing the card every ~1.6 s
	if tier >= 4 then
		local shine = make("Frame", {
			Name = "Shine",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = lighten(c2, 0.6),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 5,
			Active = false,
			Parent = card,
		}, { corner(8) })
		local sweep = make("UIGradient", {
			Rotation = 25,
			Offset = Vector2.new(-1.2, 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = shine,
		})
		tween(sweep, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, 0.5), { Offset = Vector2.new(1.2, 0) })
	end

	-- open
	gui.Parent = playerGui
	tween(holder, SLIDE_IN, { Position = shown })
	tween(timer, TweenInfo.new(AUTO_CLOSE, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) })

	-- close (exactly once)
	local openedAt = os.clock()
	local closing = false
	local function close()
		if closing then return end
		closing = true
		for _, tw in tweens do tw:Cancel() end -- stop the slide-in if it is still running
		local out = TweenService:Create(holder, SLIDE_OUT, { Position = hidden })
		trove:Add(out)
		local done = false
		local function finish()
			if done then return end
			done = true
			trove:Clean()
			onClosed()
		end
		out.Completed:Once(finish)
		out:Play()
		task.delay(SLIDE_OUT.Time + 0.3, finish) -- safety net if Completed never fires
	end
	trove:Connect(card.Activated, function()
		if os.clock() - openedAt >= TAP_GRACE then close() end
	end)
	trove:Add(task.delay(AUTO_CLOSE, close))
end

----------------------------------------------------------------------------
-- queue
----------------------------------------------------------------------------
local pump: () -> ()

local function show(info: CatchEvents.CatchInfo)
	local trove = Trove.new()
	local closed = false
	local function onClosed()
		if closed then return end
		closed = true
		showing = false
		CatchEvents.CardClosed:Fire(info)
		pump()
	end
	local ok, err = pcall(buildCard, info, trove, onClosed)
	if not ok then
		-- never block the flow: a broken card is cleaned up and counts as closed
		warn("[CatchCardController] card failed: " .. tostring(err))
		trove:Clean()
		onClosed()
	end
end

function pump()
	if showing or #queue == 0 then return end
	showing = true
	show(table.remove(queue, 1) :: CatchEvents.CatchInfo)
end

function CatchCardController.init()
	CatchEvents.CardRequested:Connect(function(info: CatchEvents.CatchInfo)
		table.insert(queue, info)
		pump()
	end)
end

return CatchCardController
