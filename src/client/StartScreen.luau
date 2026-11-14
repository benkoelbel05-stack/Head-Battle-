--!strict
-- Ausrüstungs-Wahl (Aufbau nach der Vorlage im Knete-Stil, angelehnt an Bopl Battle).
-- Öffnet sich nach "Spielen" im Hauptmenü; im Spiel über den Knopf "AUSRÜSTUNG" unten links.
--   * oben: lila Titelleiste "AUSRÜSTUNG"
--   * links (blaue Tafel): alle Fähigkeiten; Name oben, Erklärung unten (unter der Maus bzw. gewählter Slot)
--   * Mitte (orange Tafel): eigene 3 Slots (mittig, ohne Tasten-Beschriftung), Pfeile am gewählten Slot,
--     darunter die eigene Figur und der Knopf SPIELEN (im Spiel: übernehmen)
--   * rechts: die anderen Teilnehmer als Tafeln (Bots in ihrer Farbe), freie Plätze "Warte auf Spieler"
--   * unten rechts: Bot-Anzahl (– Zahl +) und Bot-Stärke (◀ NORMAL ▶)
-- Das gerade gezeigte Abzeichen wird größer und bekommt einen goldenen Schimmer.
-- Alle Positionen im Entwurfsraster 1280 x 720 (skaliert mit der Bildschirmgröße).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local MenuAssetIds = require(script.Parent.MenuAssetIds)
local SoundFX = require(script.Parent.SoundFX)

local StartScreen = {}

-- Wird vom Hauptmenü gesetzt: was der Knopf "Zurück" tun soll (Hauptmenü wieder öffnen)
StartScreen.onBack = nil :: (() -> ())?

-- open() kann schon aufgerufen werden, bevor start() fertig ist
local openImpl: (() -> ())? = nil
local openRequested = false

function StartScreen.open()
	if openImpl then
		openImpl()
	else
		openRequested = true
	end
end

---------------------------------------------------------------------------------------------------
-- Aussehen
---------------------------------------------------------------------------------------------------

local DESIGN = Vector2.new(1280, 720)
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.fromRGB(255, 248, 232)
local TEXT_STROKE = Color3.fromRGB(60, 30, 70)
local PURPLE = Color3.fromRGB(123, 42, 178)
local CREAM = Color3.fromRGB(255, 242, 219)
local TAB_TEXT = Color3.fromRGB(86, 44, 150)
local BLUE = Color3.fromRGB(31, 96, 210)
local ORANGE = Color3.fromRGB(236, 108, 51)
local GOLD = Color3.fromRGB(255, 214, 90)
local GRASS = Color3.fromRGB(110, 210, 60)
local GRASS_EDGE = Color3.fromRGB(52, 140, 40)

local BADGE = 80 -- Durchmesser eines Fähigkeiten-Abzeichens (Liste links; sichtbar ~91, vergrößert ~105)
local SLOT_BADGE = 72 -- Abzeichen in den eigenen Slots (schmalere Spalte)
-- Die Abzeichen haben im Bild einen durchsichtigen Rand: so weit vergrößern, dass sie den Platz füllen
local BADGE_FILL = 1.2
local BADGE_GROW = 1.15 -- so viel größer wird das gerade gezeigte Abzeichen

type Badge = { holder: Frame, image: ImageLabel, emoji: TextLabel, glow: UIStroke }
type Slot = { badge: Badge, left: TextButton, right: TextButton }

---------------------------------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color or WHITE
	l.TextStrokeColor3 = TEXT_STROKE
	l.TextStrokeTransparency = if color then 1 else 0.55
	l.TextScaled = true
	l.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.Parent = l
	l.Parent = parent
	return l
end

local function picture(parent: Instance, name: string, id: number?, x: number, y: number, w: number, h: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(w, h)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = if id and id ~= 0 then `rbxassetid://{id}` else ""
	image.Parent = parent
	return image
end

-- Tafel: gemaltes Bild, sonst farbige Fläche mit Cremerand
local function panel(parent: Instance, name: string, imageId: number?, color: Color3, x: number, y: number, w: number, h: number, radius: number): Frame
	local f = box(parent, name, x, y, w, h)
	if imageId and imageId ~= 0 then
		local image = picture(f, "PanelImage", imageId, 0, 0, w, h)
		image.ScaleType = Enum.ScaleType.Stretch
	else
		f.BackgroundTransparency = 0
		f.BackgroundColor3 = color
		corner(f, radius)
		stroke(f, CREAM, 5)
	end
	return f
end

-- Knopf (unsichtbare Klickfläche) mit Hover-Zoom und Klick-Squash
-- still = true: kein Hover-/Klick-Zoom (für Abzeichen, die beim Zeigen schon selbst größer werden)
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, still: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(cx, cy)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundTransparency = 1
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local function to(value: number, time: number)
		if still then
			return
		end
		TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	b.MouseEnter:Connect(function()
		to(1.08, 0.12)
		SoundFX.play("ui_hover")
	end)
	b.MouseLeave:Connect(function()
		to(1, 0.12)
	end)
	b.MouseButton1Down:Connect(function()
		to(0.9, 0.06)
		SoundFX.play("ui_click")
	end)
	b.MouseButton1Up:Connect(function()
		to(1.08, 0.12)
	end)
	return b
end

-- Runder Bildknopf (Pfeile, Plus, Minus); ohne Bild ein dunkelblauer Kreis mit Zeichen
local function iconButton(parent: Instance, name: string, cx: number, cy: number, size: number, imageId: number, fallback: string): TextButton
	local b = button(parent, name, cx, cy, size, size)
	if imageId ~= 0 then
		picture(b, "Icon", imageId, 0, 0, size, size)
	else
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = Color3.fromRGB(28, 46, 140)
		corner(b, size // 2)
		label(b, "T", fallback, 0, 0, size, size, size * 0.6)
	end
	return b
end

-- Fähigkeiten-Abzeichen in einer Fläche: Bild (oder Emoji), goldener Schimmer, wächst bei Auswahl
local function makeBadge(parent: GuiObject): Badge
	local holder = Instance.new("Frame")
	holder.Name = "Badge"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	corner(holder, 999)
	local glow = stroke(holder, GOLD, 5)
	glow.Transparency = 1
	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(BADGE_FILL, BADGE_FILL)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = holder
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.TextScaled = true
	emoji.Font = FONT
	emoji.Parent = holder
	return { holder = holder, image = image, emoji = emoji, glow = glow }
end

local function setBadge(badge: Badge, id: string)
	local info = Abilities.list[id]
	local imageId = AbilityIcons[id]
	local hasImage = imageId ~= nil and imageId ~= 0
	badge.image.Image = if hasImage then `rbxassetid://{imageId}` else ""
	badge.emoji.Text = if hasImage then "" else info.icon
	badge.holder.BackgroundTransparency = if hasImage then 1 else 0
	badge.holder.BackgroundColor3 = info.color
end

-- Weich auf normal oder groß (mit Schimmer) bringen – nur wenn sich das Ziel ändert
local function highlight(badge: Badge, on: boolean)
	if badge.holder:GetAttribute("On") == on then
		return
	end
	badge.holder:SetAttribute("On", on)
	local size = if on then BADGE_GROW else 1
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(badge.holder, info, { Size = UDim2.fromScale(size, size) }):Play()
	TweenService:Create(badge.glow, TweenInfo.new(0.18), { Transparency = if on then 0.15 else 1 }):Play()
end

local function skinFromColor(color: unknown): string?
	if typeof(color) ~= "Color3" then
		return nil
	end
	local best: string? = nil
	local bestDistance = math.huge
	for _, skin in Constants.SKINS do
		local c = skin.color
		local distance = math.abs(c.R - color.R) + math.abs(c.G - color.G) + math.abs(c.B - color.B)
		if distance < bestDistance then
			best, bestDistance = skin.key, distance
		end
	end
	return best
end

local function skinColor(skin: string?): Color3
	for _, entry in Constants.SKINS do
		if entry.key == skin then
			return entry.color
		end
	end
	return Color3.fromRGB(200, 170, 150)
end

local function mound(parent: Instance, x: number, y: number, w: number, h: number)
	local m = box(parent, "Mound", x, y, w, h)
	m.BackgroundTransparency = 0
	m.BackgroundColor3 = GRASS
	corner(m, h // 2)
	stroke(m, GRASS_EDGE, 3)
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	gloss.Parent = m
end

---------------------------------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------------------------------

function StartScreen.start()
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
	local joinGame = remotes:WaitForChild("JoinGame") :: RemoteEvent
	local setLoadout = remotes:WaitForChild("SetLoadout") :: RemoteEvent
	local setDifficulty = remotes:WaitForChild("SetDifficulty") :: RemoteEvent
	local changeBots = remotes:WaitForChild("ChangeBots") :: RemoteEvent
	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)
	local scores = roundState:WaitForChild("Scores")

	local chosen: { string } = table.clone(Abilities.DEFAULT_LOADOUT)
	local activeSlot = 1
	local hovered: string? = nil
	local joined = false

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleLoadout"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Hintergrund: dieselbe Knetwelt wie im Hauptmenü
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(80, 160, 235)
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- Klicks gehen nicht ins Spiel
	backdrop.ClipsDescendants = true
	backdrop.Parent = gui
	local scenery = Instance.new("ImageLabel")
	scenery.Name = "ClayWorld"
	scenery.Size = UDim2.fromScale(1, 1)
	scenery.BackgroundTransparency = 1
	scenery.ScaleType = Enum.ScaleType.Crop
	scenery.Image = if MenuAssetIds.menu_background ~= 0 then `rbxassetid://{MenuAssetIds.menu_background}` else ""
	scenery.Parent = backdrop

	-- Inhalt im Entwurfsraster, so groß wie möglich (nach der echten Fläche des Bildschirms)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	content.BackgroundTransparency = 1
	content.Parent = backdrop
	local contentScale = Instance.new("UIScale")
	contentScale.Parent = content
	local function fit()
		local available = backdrop.AbsoluteSize
		if available.X > 0 and available.Y > 0 then
			contentScale.Scale = math.min(available.X / (DESIGN.X + 24), available.Y / (DESIGN.Y + 24))
		end
	end
	backdrop:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)

	-- Titel
	local titleBar = box(content, "TitleBar", 406, 14, 765, 76)
	titleBar.BackgroundTransparency = 0
	titleBar.BackgroundColor3 = PURPLE
	corner(titleBar, 38)
	stroke(titleBar, CREAM, 4)
	local title = label(titleBar, "Title", "AUSRÜSTUNG", 0, 4, 765, 68, 56)
	title.TextStrokeTransparency = 0.3

	-------------------------------------------------------------------------------------------------
	-- Links: Fähigkeiten
	-------------------------------------------------------------------------------------------------

	local abilityPanel = panel(content, "Abilities", UIAssets.panel_abilities_blue, BLUE, 80, 88, 307, 574, 50)
	local abilityHeader = label(abilityPanel, "Header", "", 20, 38, 267, 44, 36)
	local divider = box(abilityPanel, "Divider", 31, 416, 245, 3)
	divider.BackgroundTransparency = 0.15
	divider.BackgroundColor3 = CREAM
	corner(divider, 2)
	local abilityDescription = label(abilityPanel, "Description", "", 24, 430, 259, 108, 23)
	abilityDescription.TextYAlignment = Enum.TextYAlignment.Top

	local tab = box(content, "Tab", 121, 60, 212, 53)
	tab.BackgroundTransparency = 0
	tab.BackgroundColor3 = Color3.fromRGB(255, 236, 210)
	corner(tab, 24)
	stroke(tab, CREAM, 3)
	local mouseIcon = picture(tab, "Mouse", UIAssets.icon_mouse, 12, 9, 34, 34)
	local tabLabel = label(tab, "Label", "FÄHIGKEITEN", 50, 8, 152, 37, 24, TAB_TEXT)
	if mouseIcon.Image == "" then
		tabLabel.Position = UDim2.fromOffset(10, 8)
		tabLabel.Size = UDim2.fromOffset(192, 37)
	end

	-- 2 Spalten um die Mitte der Tafel (153,5); Abstände so, dass sich auch ein vergrößertes Abzeichen
	-- nicht mit den Nachbarn überschneidet. Steht in der letzten Reihe nur eins, sitzt es mittig.
	local gridBadges: { [string]: Badge } = {}
	local PANEL_MID = 153.5
	local COLUMN_GAP = 120 -- Abstand der Spaltenmitten
	local ROW_GAP = 104 -- Abstand der Reihen
	local FIRST_ROW = 143
	local columns = { PANEL_MID - COLUMN_GAP / 2, PANEL_MID + COLUMN_GAP / 2 }
	local count = #Abilities.ORDER
	for index, id in Abilities.ORDER do
		local column = (index - 1) % 2 + 1
		local row = (index - 1) // 2
		local alone = column == 1 and index == count -- einzelnes Abzeichen in der letzten Reihe
		local x = if alone then PANEL_MID else columns[column]
		local cell = button(abilityPanel, id, x, FIRST_ROW + row * ROW_GAP, BADGE, BADGE, true)
		local badge = makeBadge(cell)
		setBadge(badge, id)
		gridBadges[id] = badge
		cell.MouseEnter:Connect(function()
			hovered = id
			StartScreen._refresh()
		end)
		cell.MouseLeave:Connect(function()
			if hovered == id then
				hovered = nil
				StartScreen._refresh()
			end
		end)
		cell.Activated:Connect(function()
			StartScreen._assign(id)
		end)
	end

	-------------------------------------------------------------------------------------------------
	-- Mitte: eigene Spalte
	-------------------------------------------------------------------------------------------------

	local column = panel(content, "Player", UIAssets.panel_player_orange, ORANGE, 397, 96, 229, 581, 100)
	local slotHeader = label(column, "Header", "", 14, 42, 201, 44, 36)

	-- Maße der Spalte (229 breit): Abzeichen mittig, Pfeile links und rechts mit etwas Abstand,
	-- alles innerhalb des Cremerands. Keine Tasten-Beschriftung (LM/MR/RM) mehr.
	local slots: { Slot } = {}
	local rows = { 140, 234, 328 }
	local SLOT_X = 114.5 -- Mitte der Spalte
	local ARROW_OFFSET = 68 -- aktives Abzeichen ist ~97 breit: so bleiben gut 5 Pixel Luft zum Pfeil
	local ARROW_SIZE = 28
	for index = 1, Abilities.MAX_SLOTS do
		local y = rows[index]
		local cell = button(column, `Slot{index}`, SLOT_X, y, SLOT_BADGE, SLOT_BADGE, true)
		local badge = makeBadge(cell)
		local left = iconButton(column, `Left{index}`, SLOT_X - ARROW_OFFSET, y, ARROW_SIZE, UIAssets.icon_arrow_left, "◀")
		local right = iconButton(column, `Right{index}`, SLOT_X + ARROW_OFFSET, y, ARROW_SIZE, UIAssets.icon_arrow_right, "▶")
		left.ZIndex = 3
		right.ZIndex = 3
		slots[index] = { badge = badge, left = left, right = right }
		cell.Activated:Connect(function()
			activeSlot = index
			StartScreen._refresh()
		end)
		left.Activated:Connect(function()
			StartScreen._cycle(-1)
		end)
		right.Activated:Connect(function()
			StartScreen._cycle(1)
		end)
	end

	-- Figur auf einem kleinen Hügel, mit Abstand zum Knopf darunter
	mound(column, 55, 458, 120, 20)
	local character = picture(column, "Character", nil, 69, 380, 92, 92)

	-- SPIELEN (vor dem Einstieg) bzw. übernehmen (im Spiel); sitzt auf dem unteren Rand der Spalte
	local ready = button(content, "Ready", 511, 650, 210, 78)
	local readyImage = picture(ready, "Image", UIAssets.button_spielen, 0, 0, 210, 78)
	local readyText = label(ready, "Text", "▶ SPIELEN", 0, 0, 210, 78, 34)
	local function styleReady()
		local id = if joined then UIAssets.button_ready_orange else UIAssets.button_spielen
		if id ~= 0 then
			readyImage.Image = `rbxassetid://{id}`
			readyText.Visible = false
			ready.BackgroundTransparency = 1
		else
			readyText.Text = if joined then "✔ ÜBERNEHMEN" else "▶ SPIELEN"
			readyText.Visible = true
			ready.BackgroundTransparency = 0
			ready.BackgroundColor3 = Color3.fromRGB(40, 190, 70)
			corner(ready, 39)
		end
	end
	styleReady()

	-------------------------------------------------------------------------------------------------
	-- Rechts: andere Teilnehmer, Bots und Stärke
	-------------------------------------------------------------------------------------------------

	local othersHolder = box(content, "Others", 0, 0, DESIGN.X, DESIGN.Y)
	local CARD_X = { 642, 834, 1027 }

	local bar = box(content, "BotBar", 637, 573, 580, 74)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = Color3.fromRGB(30, 80, 200)
	corner(bar, 37)
	stroke(bar, CREAM, 4)
	local barGloss = Instance.new("UIGradient")
	barGloss.Rotation = 90
	barGloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	barGloss.Parent = bar
	label(bar, "BotsLabel", "BOTS", 18, 18, 80, 38, 30)
	local minus = iconButton(bar, "Minus", 119, 37, 44, UIAssets.icon_minus, "–")
	local botCount = label(bar, "Count", "0", 143, 18, 36, 38, 32)
	local plus = iconButton(bar, "Plus", 203, 37, 44, UIAssets.icon_plus, "+")
	local separator = box(bar, "Separator", 241, 17, 3, 40)
	separator.BackgroundTransparency = 0.2
	separator.BackgroundColor3 = CREAM
	label(bar, "StrengthLabel", "STÄRKE", 256, 18, 104, 38, 30)
	local weaker = iconButton(bar, "Weaker", 382, 37, 44, UIAssets.icon_arrow_left, "◀")
	local strengthText = label(bar, "Strength", "", 406, 18, 114, 38, 30, GOLD)
	strengthText.TextStrokeTransparency = 0.6
	local stronger = iconButton(bar, "Stronger", 544, 37, 44, UIAssets.icon_arrow_right, "▶")

	local function difficulty(): number
		local value = roundState:GetAttribute("BotDifficulty")
		return if typeof(value) == "number" then value else Constants.BOT_DEFAULT_DIFFICULTY
	end
	minus.Activated:Connect(function()
		changeBots:FireServer(-1)
	end)
	plus.Activated:Connect(function()
		changeBots:FireServer(1)
	end)
	weaker.Activated:Connect(function()
		setDifficulty:FireServer(math.max(1, difficulty() - 1))
	end)
	stronger.Activated:Connect(function()
		setDifficulty:FireServer(math.min(#Constants.BOT_DIFFICULTIES, difficulty() + 1))
	end)

	-- Knopf im Spiel, um die Wahl wieder zu öffnen
	local reopen = Instance.new("TextButton")
	reopen.Name = "Reopen"
	reopen.AnchorPoint = Vector2.new(0, 1)
	reopen.Position = UDim2.new(0, 16, 1, -16)
	reopen.Size = UDim2.fromOffset(150, 44)
	reopen.BackgroundColor3 = ORANGE
	reopen.Font = FONT
	reopen.TextSize = 20
	reopen.TextColor3 = WHITE
	reopen.Text = "AUSRÜSTUNG"
	reopen.Visible = false
	corner(reopen, 14)
	stroke(reopen, CREAM, 3)
	reopen.Parent = gui

	-------------------------------------------------------------------------------------------------
	-- Anzeigen aktualisieren
	-------------------------------------------------------------------------------------------------

	local function refresh()
		local shownId = hovered or chosen[activeSlot]
		local shown = Abilities.list[shownId]
		abilityHeader.Text = string.upper(shown.label)
		abilityDescription.Text = shown.description
		slotHeader.Text = string.upper(Abilities.list[chosen[activeSlot]].label)

		for id, badge in gridBadges do
			highlight(badge, id == shownId)
		end
		for index, slot in slots do
			setBadge(slot.badge, chosen[index])
			local active = index == activeSlot
			highlight(slot.badge, active)
			slot.left.Visible = active
			slot.right.Visible = active
		end

		local skin = player:GetAttribute("Skin")
		character.Image = if typeof(skin) == "string" then SpriteAssets.frame(skin, "idle", 1) or "" else ""
		styleReady()
	end
	StartScreen._refresh = refresh

	-- Fähigkeit in den gewählten Slot legen (steckt sie schon woanders, tauschen die beiden)
	StartScreen._assign = function(id: string)
		local other = table.find(chosen, id)
		if other and other ~= activeSlot then
			chosen[other] = chosen[activeSlot]
		end
		chosen[activeSlot] = id
		activeSlot = activeSlot % Abilities.MAX_SLOTS + 1
		refresh()
	end

	-- ◀ ▶: im gewählten Slot zur nächsten Fähigkeit, die noch nicht belegt ist
	StartScreen._cycle = function(step: number)
		local order = Abilities.ORDER
		local index = table.find(order, chosen[activeSlot]) or 1
		for _ = 1, #order do
			index = (index - 1 + step) % #order + 1
			if not table.find(chosen, order[index]) then
				chosen[activeSlot] = order[index]
				break
			end
		end
		refresh()
	end

	-- Andere Teilnehmer: Tafel mit Name, Rolle und Figur; freie Plätze "Warte auf Spieler"
	local lastOthers = ""
	local function refreshOthers()
		local myKey = tostring(player.UserId)
		local others: { Instance } = {}
		local bots = 0
		for _, value in scores:GetChildren() do
			if value:GetAttribute("IsBot") == true then
				bots += 1
			end
			if value.Name ~= myKey then
				table.insert(others, value)
			end
		end
		table.sort(others, function(a, b)
			return a.Name < b.Name
		end)
		botCount.Text = tostring(bots)
		local strength = string.upper(Constants.BOT_DIFFICULTIES[difficulty()].name)
		strengthText.Text = strength

		-- Nur neu bauen, wenn sich etwas geändert hat
		local signature = strength
		for _, entry in others do
			signature ..= `|{entry.Name}:{entry:GetAttribute("DisplayName")}:{entry:GetAttribute("IsBot")}`
		end
		if signature == lastOthers then
			return
		end
		lastOthers = signature
		othersHolder:ClearAllChildren()

		for place = 1, Constants.MAX_PARTICIPANTS - 1 do
			local x = CARD_X[place]
			local entry = others[place]
			if x and entry then
				local skin = skinFromColor(entry:GetAttribute("Color"))
				local panelId = if skin == "green" or skin == "teal" or skin == "cyan"
					then UIAssets.panel_bot_green
					elseif skin == "yellow" or skin == "orange" then UIAssets.panel_bot_yellow
					else UIAssets.panel_bot_purple
				local card = panel(othersHolder, "Card", panelId, skinColor(skin):Lerp(BLUE, 0.35), x, 165, 186, 382, 80)
				local name = entry:GetAttribute("DisplayName")
				label(card, "Name", if typeof(name) == "string" then string.upper(name) else "?", 14, 50, 158, 38, 30)
				local isBot = entry:GetAttribute("IsBot") == true
				label(card, "Role", if isBot then `BOT · {strength}` else "SPIELER", 14, 96, 158, 26, 20)
				mound(card, 33, 282, 120, 20)
				picture(card, "Character", nil, 45, 202, 96, 96).Image = if skin then SpriteAssets.frame(skin, "idle", 1) or "" else ""
			elseif x then
				local waiting = picture(othersHolder, "Waiting", UIAssets.player_slot_empty, x + 8, 281, 170, 150)
				if waiting.Image == "" then
					waiting.BackgroundTransparency = 0
					waiting.BackgroundColor3 = BLUE
					corner(waiting, 30)
					stroke(waiting, CREAM, 5)
					label(waiting, "Text", "WARTE AUF\nSPIELER", 10, 0, 150, 150, 26)
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------
	-- Öffnen / Schließen
	-------------------------------------------------------------------------------------------------

	local function open()
		player:SetAttribute("MenuOpen", true)
		backdrop.Visible = true
		reopen.Visible = false
		hovered = nil
		fit()
		refresh()
		refreshOthers()
	end

	-- Zurück ins Hauptmenü (oben links, über dem Reiter "Fähigkeiten")
	local back = button(content, "Back", 165, 34, 170, 46)
	back.BackgroundTransparency = 0
	back.BackgroundColor3 = PURPLE
	back.ZIndex = 5
	corner(back, 23)
	stroke(back, CREAM, 3)
	local hasBackIcon = UIAssets.icon_back ~= 0
	if hasBackIcon then
		picture(back, "Icon", UIAssets.icon_back, 8, 5, 36, 36).ZIndex = 6
	end
	label(back, "Label", if hasBackIcon then "ZURÜCK" else "◀ ZURÜCK", if hasBackIcon then 46 else 10, 6, if hasBackIcon then 116 else 150, 34, 24).ZIndex = 6
	back.Activated:Connect(function()
		backdrop.Visible = false
		reopen.Visible = joined
		local onBack = StartScreen.onBack
		if onBack then
			onBack()
		else
			player:SetAttribute("MenuOpen", false)
		end
	end)

	ready.Activated:Connect(function()
		if joined then
			setLoadout:FireServer(table.clone(chosen))
		else
			joinGame:FireServer(table.clone(chosen))
			joined = true
		end
		backdrop.Visible = false
		reopen.Visible = true
		player:SetAttribute("MenuOpen", false)
		refresh()
	end)
	reopen.Activated:Connect(open)

	player:GetAttributeChangedSignal("Skin"):Connect(refresh)
	roundState:GetAttributeChangedSignal("BotDifficulty"):Connect(refreshOthers)

	-- Solange die Wahl offen ist, Teilnehmer aktuell halten
	task.spawn(function()
		while gui.Parent do
			if backdrop.Visible then
				refreshOthers()
			end
			task.wait(0.5)
		end
	end)

	refresh()
	backdrop.Visible = false
	openImpl = open
	if openRequested then
		open()
	end
end

-- Innere Funktionen (werden in start() gesetzt; vorher passiert nichts)
StartScreen._refresh = function() end
StartScreen._assign = function(_id: string) end
StartScreen._cycle = function(_step: number) end

return StartScreen
