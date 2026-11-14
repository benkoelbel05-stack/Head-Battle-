--!strict
-- Ausrüstungs-Wahl (im Stil der Charakter-Auswahl von Bopl Battle). Öffnet sich nach "Spielen" im Hauptmenü.
--   * links (blau): alle Fähigkeiten als runde Symbole; Name und Erklärung beim Drüberfahren
--   * Mitte (orange): die eigene Spalte mit 3 Slots (Linke Maus / Mausrad / Rechte Maus) und der Figur.
--     Slot anklicken = auswählen, dann links eine Fähigkeit anklicken (oder mit ◀ ▶ durchschalten).
--     Der Haken unten steigt ein (JoinGame) bzw. übernimmt die Ausrüstung im Spiel (SetLoadout).
--   * rechts: die anderen Teilnehmer (Spieler und Bots), freie Plätze zeigen "Warte auf Spieler …"
--   * unten rechts: Bots hinzufügen/entfernen und Bot-Stärke
-- Im Spiel öffnet der Knopf "Ausrüstung" (unten links) die Wahl wieder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local MenuAssetIds = require(script.Parent.MenuAssetIds)

local StartScreen = {}

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

-- Die Fähigkeiten-Abzeichen haben im Bild einen durchsichtigen Rand: so weit vergrößern, dass der
-- runde Rand des Abzeichens genau auf dem Auswahlring sitzt
local BADGE_FILL = 1.2

type Icon = { button: TextButton, ring: UIStroke }
type Slot = { button: TextButton, ring: UIStroke, icon: TextLabel, image: ImageLabel, left: TextButton, right: TextButton }

-- Farben und Schrift
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.FredokaOne
-- Knet-Materialfarben: sichtbare Glanzkante, warme helle Ränder und plastische Abstufungen.
local SKY = Color3.fromRGB(50, 147, 235)
local PANEL = Color3.fromRGB(31, 116, 223)
local NAVY = Color3.fromRGB(61, 36, 104)
local ORANGE = Color3.fromRGB(236, 108, 51)
local BROWN = Color3.fromRGB(110, 48, 63)
local WHITE = Color3.fromRGB(255, 246, 224)
local GRASS = Color3.fromRGB(99, 207, 50)
local GRASS_EDGE = Color3.fromRGB(42, 136, 36)
local CREAM_RIM = Color3.fromRGB(255, 242, 219)
local PURPLE = Color3.fromRGB(123, 42, 178)
local SLOT_KEYS = { "LM", "MR", "RM" }

local DESIGN = Vector2.new(1280, 720)

---------------------------------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------------------------------

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- Bild aus UIAssets/AbilityIcons über die ganze Fläche legen (nil, wenn es keins gibt)
local function imageOn(parent: GuiObject, id: number?): ImageLabel?
	if not id or id == 0 then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = `rbxassetid://{id}`
	image.ZIndex = parent.ZIndex + 1
	image.Parent = parent
	return image
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function clayGradient(parent: Instance, _color: Color3)
	-- Weißer Verlauf = nur Glanz, keine Umfärbung. Nicht auf Text-Objekten (würde die Schrift einfärben).
	if parent:IsA("TextLabel") or parent:IsA("TextButton") then
		return
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	gradient.Parent = parent
end

local function frame(parent: Instance, name: string, position: Vector2, size: Vector2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(position.X, position.Y)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	clayGradient(f, color)
	f.Parent = parent
	return f
end

local function text(
	parent: Instance,
	name: string,
	value: string,
	position: Vector2,
	size: Vector2,
	font: Enum.Font,
	textSize: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = value
	label.TextWrapped = true
	label.TextStrokeColor3 = Color3.fromRGB(62, 31, 79)
	label.TextStrokeTransparency = if color == WHITE then 0.68 else 0.92
	label.Parent = parent
	return label
end

-- Knopf mit Hover-Zoom und Klick-Squash
local function bouncyButton(parent: Instance, name: string, position: Vector2, size: Vector2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Text = ""
	clayGradient(button, color)
	button.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function to(value: number, time: number)
		TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(1.08, 0.12)
	end)
	button.MouseLeave:Connect(function()
		to(1, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.9, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.08, 0.12)
	end)
	return button
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
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Dieselbe leere Wasserfall-Knetwelt wie das bestehende Hauptmenü.
	-- Bild-ID ist bereits in MenuAssetIds vorhanden, keine neue Asset-ID nötig.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = SKY
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- Klicks gehen nicht ins Spiel
	backdrop.ClipsDescendants = true
	backdrop.Parent = gui

	local scenery = Instance.new("ImageLabel")
	scenery.Name = "ClayWorld"
	scenery.Size = UDim2.fromScale(1, 1)
	scenery.BackgroundTransparency = 1
	scenery.ScaleType = Enum.ScaleType.Crop
	scenery.Image = if MenuAssetIds.menu_background and MenuAssetIds.menu_background ~= 0
		then `rbxassetid://{MenuAssetIds.menu_background}` else ""
	scenery.Parent = backdrop

	-- Farbliche Schicht für gut lesbare Karten und Kontrast vor den Wasserfällen.
	local tint = Instance.new("Frame")
	tint.Name = "ClayOverlay"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(68, 30, 119)
	tint.BackgroundTransparency = 0.65
	tint.BorderSizePixel = 0
	tint.Parent = backdrop

		-- Inhalt im Entwurfsraster 1280 x 720, passt sich der Bildschirmgröße an
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
		local camera = Workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			contentScale.Scale = math.min(view.X / (DESIGN.X + 20), view.Y / (DESIGN.Y + 20))
		end
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	local title = text(content, "Title", "AUSRÜSTUNG", Vector2.new(394, 5), Vector2.new(742, 64), TITLE_FONT, 48, WHITE)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.BackgroundColor3 = PURPLE
	title.BackgroundTransparency = 0.03
	corner(title, UDim.new(0, 26))
	stroke(title, CREAM_RIM, 4)
	clayGradient(title, PURPLE)

	-------------------------------------------------------------------------------------------------
	-- Links: Fähigkeiten
	-------------------------------------------------------------------------------------------------

	local abilityPanel = frame(content, "Abilities", Vector2.new(40, 80), Vector2.new(310, 600), PANEL)
	corner(abilityPanel, UDim.new(0, 54))
	stroke(abilityPanel, CREAM_RIM, 5)

	-- Reiter über dem Panel (wie das Tastatur-Symbol im Vorbild)
	local tab = frame(content, "InputTab", Vector2.new(110, 52), Vector2.new(165, 45), Color3.fromRGB(255, 234, 206))
	corner(tab, UDim.new(0, 12))
	stroke(tab, CREAM_RIM, 3)
	local tabLabel = text(tab, "Label", "FÄHIGKEITEN", Vector2.zero, Vector2.new(165, 45), TITLE_FONT, 21, NAVY)
	if UIAssets.icon_mouse ~= 0 then
		local mouseIcon = frame(tab, "MouseIcon", Vector2.new(6, 6), Vector2.new(33, 33), Color3.new(1, 1, 1))
		mouseIcon.BackgroundTransparency = 1
		imageOn(mouseIcon, UIAssets.icon_mouse)
		tabLabel.Position = UDim2.fromOffset(36, 0)
		tabLabel.Size = UDim2.fromOffset(127, 45)
	end

	local abilityHeader = text(abilityPanel, "Header", "", Vector2.new(15, 22), Vector2.new(280, 40), TITLE_FONT, 30, WHITE)
	local abilityDescription =
		text(abilityPanel, "Description", "", Vector2.new(27, 357), Vector2.new(255, 180), BODY_FONT, 21, WHITE)
	abilityDescription.TextYAlignment = Enum.TextYAlignment.Top

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icons"
	iconHolder.Position = UDim2.fromOffset(30, 84)
	iconHolder.Size = UDim2.fromOffset(250, 262)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = abilityPanel
	local iconGrid = Instance.new("UIGridLayout")
	iconGrid.CellSize = UDim2.fromOffset(76, 76)
	iconGrid.CellPadding = UDim2.fromOffset(24, 14)
	iconGrid.SortOrder = Enum.SortOrder.LayoutOrder
	iconGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	iconGrid.Parent = iconHolder

	local icons: { [string]: Icon } = {}

	-------------------------------------------------------------------------------------------------
	-- Mitte: eigene Spalte
	-------------------------------------------------------------------------------------------------

	local column = frame(content, "Player", Vector2.new(390, 80), Vector2.new(240, 600), ORANGE)
	corner(column, UDim.new(0, 110))
	stroke(column, CREAM_RIM, 5)

	-- Kein Roblox-Avatar über dem mittleren Knete-Panel: die Kopfbild-Vorschau
	-- hatte eine fremde Figur gezeigt und den Clay-Battle-Artstyle gebrochen.
	-- Die echte Knetefigur auf der grünen Plattform unten bleibt erhalten.

	local slotHeader = text(column, "Header", "", Vector2.new(10, 44), Vector2.new(220, 36), TITLE_FONT, 28, WHITE)
	local slots: { Slot } = {}

	local mound = frame(column, "Mound", Vector2.new(45, 488), Vector2.new(150, 34), GRASS)
	corner(mound, UDim.new(0.5, 0))
	stroke(mound, GRASS_EDGE, 3)
	local character = Instance.new("ImageLabel")
	character.Name = "Character"
	character.Position = UDim2.fromOffset(65, 405)
	character.Size = UDim2.fromOffset(110, 110)
	character.BackgroundTransparency = 1
	character.ScaleType = Enum.ScaleType.Fit
	character.ZIndex = 2
	character.Parent = column

	local ready = bouncyButton(content, "Ready", Vector2.new(405, 609), Vector2.new(210, 64), Color3.fromRGB(35, 194, 66))
	corner(ready, UDim.new(0, 29))
	stroke(ready, CREAM_RIM, 5)
	ready.ZIndex = 3
	local readyMark = text(ready, "Mark", "▶  SPIELEN", Vector2.zero, Vector2.new(210, 64), TITLE_FONT, 25, WHITE)
	readyMark.ZIndex = 4
	-- Mit Bildern: "SPIELEN"-Knopf vor dem Einstieg, oranger Haken (übernehmen) im Spiel
	local readyImage = imageOn(ready, UIAssets.button_spielen)
	local readyStroke = ready:FindFirstChildOfClass("UIStroke")
	local function styleReady(isJoined: boolean)
		local id = if isJoined then UIAssets.button_ready_orange else UIAssets.button_spielen
		if readyImage and id ~= 0 then
			readyImage.Image = `rbxassetid://{id}`
			readyImage.Visible = true
			readyMark.Visible = false
			ready.BackgroundTransparency = 1
			if readyStroke then
				readyStroke.Enabled = false
			end
		end
	end
	styleReady(false)

	-------------------------------------------------------------------------------------------------
	-- Rechts: andere Teilnehmer, Bots und Stärke
	-------------------------------------------------------------------------------------------------

	local othersHolder = Instance.new("Frame")
	othersHolder.Name = "Others"
	othersHolder.BackgroundTransparency = 1
	othersHolder.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	othersHolder.Parent = content

	local botBar = frame(content, "BotBar", Vector2.new(670, 600), Vector2.new(570, 72), PANEL)
	corner(botBar, UDim.new(0, 30))
	stroke(botBar, CREAM_RIM, 4)
	-- (bot_control_bar_static enthält fest gezeichnete Knöpfe und "NORMAL" – passt nicht zu den echten
	-- Knöpfen und der wechselnden Stärke, deshalb nicht als Hintergrund benutzt)
	text(botBar, "BotsLabel", "BOTS", Vector2.new(18, 0), Vector2.new(80, 72), TITLE_FONT, 26, WHITE)
	local function roundButton(name: string, x: number, label: string, font: Enum.Font, size: number, imageId: number?): TextButton
		local button = bouncyButton(botBar, name, Vector2.new(x, 14), Vector2.new(44, 44), Color3.fromRGB(66, 56, 162))
		corner(button, UDim.new(0.5, 0))
		button.ZIndex = 3
		if imageOn(button, imageId) then
			button.BackgroundTransparency = 1
		else
			text(button, "T", label, Vector2.zero, Vector2.new(44, 44), font, size, WHITE).ZIndex = 4
		end
		return button
	end
	local minus = roundButton("Minus", 100, "–", TITLE_FONT, 30, UIAssets.icon_minus)
	local plus = roundButton("Plus", 152, "+", TITLE_FONT, 30, UIAssets.icon_plus)
	text(botBar, "StrengthLabel", "STÄRKE", Vector2.new(222, 0), Vector2.new(110, 72), TITLE_FONT, 26, WHITE)
	local weaker = roundButton("Weaker", 334, "◀", BODY_FONT, 22, UIAssets.icon_arrow_left)
	local strengthText =
		text(botBar, "Strength", "", Vector2.new(380, 0), Vector2.new(126, 72), TITLE_FONT, 26, Color3.fromRGB(255, 220, 90))
	local stronger = roundButton("Stronger", 508, "▶", BODY_FONT, 22, UIAssets.icon_arrow_right)

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
	reopen.Font = TITLE_FONT
	reopen.TextSize = 20
	reopen.TextColor3 = WHITE
	reopen.Text = "AUSRÜSTUNG"
	reopen.Visible = false
	corner(reopen, UDim.new(0, 14))
	stroke(reopen, CREAM_RIM, 3)
	clayGradient(reopen, ORANGE)
	reopen.Parent = gui

	-------------------------------------------------------------------------------------------------
	-- Anzeigen aktualisieren
	-------------------------------------------------------------------------------------------------

	local function refresh()
		-- Kopfzeilen: Fähigkeit unter der Maus, sonst die im gewählten Slot
		local shown = Abilities.list[hovered or chosen[activeSlot]]
		abilityHeader.Text = string.upper(shown.label)
		abilityDescription.Text = shown.description
		slotHeader.Text = string.upper(Abilities.list[chosen[activeSlot]].label)

		for id, icon in icons do
			local slot = table.find(chosen, id)
			icon.ring.Color = if slot == activeSlot then Color3.fromRGB(255, 235, 96) elseif slot then CREAM_RIM else NAVY
			icon.ring.Thickness = if slot == activeSlot then 6 elseif slot then 4 else 3
		end
		for index, slot in slots do
			local info = Abilities.list[chosen[index]]
			local iconId = AbilityIcons[info.id]
			local hasImage = iconId ~= nil and iconId ~= 0
			slot.icon.Text = if hasImage then "" else info.icon
			slot.image.Image = if hasImage then `rbxassetid://{iconId}` else ""
			slot.button.BackgroundColor3 = info.color
			slot.button.BackgroundTransparency = if hasImage then 1 else 0
			local active = index == activeSlot
			slot.ring.Color = if active then CREAM_RIM else BROWN
			slot.ring.Thickness = if active then 6 else 4
			slot.left.Visible = active
			slot.right.Visible = active
		end

		local skin = player:GetAttribute("Skin")
		character.Image = if typeof(skin) == "string" then SpriteAssets.frame(skin, "idle", 1) or "" else ""
		readyMark.Text = if joined then "✔  ÜBERNEHMEN" else "▶  SPIELEN"
		styleReady(joined)
	end

	-- Fähigkeit in den gewählten Slot legen (steckt sie schon woanders, tauschen die beiden)
	local function assign(id: string)
		local other = table.find(chosen, id)
		if other and other ~= activeSlot then
			chosen[other] = chosen[activeSlot]
		end
		chosen[activeSlot] = id
		activeSlot = activeSlot % Abilities.MAX_SLOTS + 1
		refresh()
	end

	-- ◀ ▶: im gewählten Slot zur nächsten freien Fähigkeit
	local function cycle(step: number)
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

	for index, id in Abilities.ORDER do
		local info = Abilities.list[id]
		local button = Instance.new("TextButton")
		button.Name = id
		button.LayoutOrder = index
		button.BackgroundColor3 = info.color
		button.Text = info.icon
		local gridImage = imageOn(button, AbilityIcons[id])
		if gridImage then
			gridImage.AnchorPoint = Vector2.new(0.5, 0.5)
			gridImage.Position = UDim2.fromScale(0.5, 0.5)
			gridImage.Size = UDim2.fromScale(BADGE_FILL, BADGE_FILL)
			button.Text = ""
			button.BackgroundTransparency = 1
		end
		button.TextSize = 38
		button.Font = BODY_FONT
		button.AutoButtonColor = false
		clayGradient(button, info.color)
		corner(button, UDim.new(0.5, 0))
		local ring = stroke(button, CREAM_RIM, 4)
		button.TextStrokeColor3 = NAVY
		button.TextStrokeTransparency = 0.65
		button.Parent = iconHolder
		icons[id] = { button = button, ring = ring }
		button.MouseEnter:Connect(function()
			hovered = id
			refresh()
		end)
		button.MouseLeave:Connect(function()
			if hovered == id then
				hovered = nil
				refresh()
			end
		end)
		button.Activated:Connect(function()
			assign(id)
		end)
	end

	for index = 1, Abilities.MAX_SLOTS do
		local y = 88 + (index - 1) * 110
		text(column, `Key{index}`, SLOT_KEYS[index], Vector2.new(75, y + 90), Vector2.new(90, 18), TITLE_FONT, 15, WHITE)
		local button = bouncyButton(column, `Slot{index}`, Vector2.new(75, y), Vector2.new(90, 90), WHITE)
		corner(button, UDim.new(0.5, 0))
		local ring = stroke(button, CREAM_RIM, 4)
		local icon = text(button, "Icon", "", Vector2.zero, Vector2.new(90, 90), BODY_FONT, 48, WHITE)
		local slotImage = Instance.new("ImageLabel")
		slotImage.Name = "Image"
		slotImage.AnchorPoint = Vector2.new(0.5, 0.5)
		slotImage.Position = UDim2.fromScale(0.5, 0.5)
		slotImage.Size = UDim2.fromScale(BADGE_FILL, BADGE_FILL)
		slotImage.BackgroundTransparency = 1
		slotImage.ScaleType = Enum.ScaleType.Fit
		slotImage.ZIndex = button.ZIndex + 1
		slotImage.Parent = button
		local left = bouncyButton(column, `Left{index}`, Vector2.new(28, y + 25), Vector2.new(40, 40), ORANGE)
		left.BackgroundTransparency = 1
		if not imageOn(left, UIAssets.icon_arrow_left) then
			text(left, "T", "◀", Vector2.zero, Vector2.new(40, 40), BODY_FONT, 28, BROWN)
		end
		local right = bouncyButton(column, `Right{index}`, Vector2.new(172, y + 25), Vector2.new(40, 40), ORANGE)
		right.BackgroundTransparency = 1
		if not imageOn(right, UIAssets.icon_arrow_right) then
			text(right, "T", "▶", Vector2.zero, Vector2.new(40, 40), BODY_FONT, 28, BROWN)
		end
		slots[index] = { button = button, ring = ring, icon = icon, image = slotImage, left = left, right = right }
		button.Activated:Connect(function()
			activeSlot = index
			refresh()
		end)
		left.Activated:Connect(function()
			cycle(-1)
		end)
		right.Activated:Connect(function()
			cycle(1)
		end)
	end

	-- Andere Teilnehmer: belegte Plätze als Spalte, freie mit "Warte auf Spieler …"
	local waitingDots = 0
	local function refreshOthers()
		othersHolder:ClearAllChildren()
		local myKey = tostring(player.UserId)
		local others: { Instance } = {}
		for _, value in scores:GetChildren() do
			if value.Name ~= myKey then
				table.insert(others, value)
			end
		end
		table.sort(others, function(a, b)
			return a.Name < b.Name
		end)

		for place = 1, Constants.MAX_PARTICIPANTS - 1 do
			local x = 670 + (place - 1) * 195
			local entry = others[place]
			if entry then
				local skin = skinFromColor(entry:GetAttribute("Color"))
				local isBot = entry:GetAttribute("IsBot") == true
				local card = frame(othersHolder, "Card", Vector2.new(x, 150), Vector2.new(180, 420), skinColor(skin):Lerp(PANEL, 0.35))
				corner(card, UDim.new(0, 80))
				stroke(card, CREAM_RIM, 5)
				local name = entry:GetAttribute("DisplayName")
				text(card, "Name", if typeof(name) == "string" then string.upper(name) else "?", Vector2.new(10, 34), Vector2.new(160, 60), TITLE_FONT, 24, WHITE)
				local role = if isBot then `BOT · {string.upper(Constants.BOT_DIFFICULTIES[difficulty()].name)}` else "SPIELER"
				text(card, "Role", role, Vector2.new(10, 92), Vector2.new(160, 30), BODY_FONT, 18, Color3.fromRGB(230, 240, 255))
				local grass = frame(card, "Mound", Vector2.new(25, 318), Vector2.new(130, 34), GRASS)
				corner(grass, UDim.new(0.5, 0))
				stroke(grass, GRASS_EDGE, 3)
				local picture = Instance.new("ImageLabel")
				picture.Position = UDim2.fromOffset(30, 222)
				picture.Size = UDim2.fromOffset(120, 120)
				picture.BackgroundTransparency = 1
				picture.ScaleType = Enum.ScaleType.Fit
				picture.Image = if skin then SpriteAssets.frame(skin, "idle", 1) or "" else ""
				picture.ZIndex = 2
				picture.Parent = card
			else
				local box = frame(othersHolder, "Waiting", Vector2.new(x + 5, 300), Vector2.new(170, 150), PANEL)
				if imageOn(box, UIAssets.player_slot_empty) then
					-- Fertiges Bild mit "Warte auf Spieler"
					box.BackgroundTransparency = 1
				else
					corner(box, UDim.new(0, 34))
					stroke(box, CREAM_RIM, 5)
					local label = text(box, "Text", `WARTE AUF\nSPIELER{string.rep(".", waitingDots)}`, Vector2.new(8, 0), Vector2.new(154, 150), TITLE_FONT, 23, WHITE)
					label.TextYAlignment = Enum.TextYAlignment.Center
				end
			end
		end

		strengthText.Text = string.upper(Constants.BOT_DIFFICULTIES[difficulty()].name)
	end

	-------------------------------------------------------------------------------------------------
	-- Öffnen / Schließen
	-------------------------------------------------------------------------------------------------

	local function open()
		player:SetAttribute("MenuOpen", true)
		backdrop.Visible = true
		reopen.Visible = false
		hovered = nil
		refresh()
		refreshOthers()
	end

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
	end)
	reopen.Activated:Connect(open)

	player:GetAttributeChangedSignal("Skin"):Connect(refresh)
	roundState:GetAttributeChangedSignal("BotDifficulty"):Connect(refreshOthers)

	-- Solange die Wahl offen ist: Teilnehmer aktuell halten und die Punkte bei "Warte auf Spieler" laufen lassen
	task.spawn(function()
		while gui.Parent do
			if backdrop.Visible then
				waitingDots = waitingDots % 3 + 1
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

return StartScreen
