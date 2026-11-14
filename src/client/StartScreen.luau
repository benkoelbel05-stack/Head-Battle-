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

type Icon = { button: TextButton, ring: UIStroke }
type Slot = { button: TextButton, ring: UIStroke, icon: TextLabel, left: TextButton, right: TextButton }

-- Farben und Schrift
local TITLE_FONT = Enum.Font.LuckiestGuy
local BODY_FONT = Enum.Font.FredokaOne
local SKY = Color3.fromRGB(36, 130, 228)
local SKY_DOT = Color3.fromRGB(62, 158, 246)
local CLOUD = Color3.fromRGB(236, 245, 255)
local CLOUD_EDGE = Color3.fromRGB(196, 222, 248)
local PANEL = Color3.fromRGB(40, 118, 214)
local NAVY = Color3.fromRGB(22, 58, 112)
local ORANGE = Color3.fromRGB(228, 106, 60)
local BROWN = Color3.fromRGB(112, 42, 22)
local WHITE = Color3.fromRGB(255, 255, 255)
local GRASS = Color3.fromRGB(122, 200, 72)
local GRASS_EDGE = Color3.fromRGB(56, 120, 40)
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

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function frame(parent: Instance, name: string, position: Vector2, size: Vector2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(position.X, position.Y)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
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

	-- Himmel mit Punktmuster
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = SKY
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- Klicks gehen nicht ins Spiel
	backdrop.ClipsDescendants = true
	backdrop.Parent = gui

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.AnchorPoint = Vector2.new(0.5, 0.5)
	dots.Position = UDim2.fromScale(0.5, 0.5)
	dots.Size = UDim2.fromOffset(2400, 1400)
	dots.BackgroundTransparency = 1
	dots.Parent = backdrop
	local dotGrid = Instance.new("UIGridLayout")
	dotGrid.CellSize = UDim2.fromOffset(72, 72)
	dotGrid.CellPadding = UDim2.fromOffset(26, 26)
	dotGrid.Parent = dots
	for _ = 1, 25 * 15 do
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = SKY_DOT
		dot.BorderSizePixel = 0
		corner(dot, UDim.new(0.5, 0))
		dot.Parent = dots
	end

	-- Wolkenrand: überlappende Kreise an allen Rändern
	local clouds = Instance.new("Frame")
	clouds.Name = "Clouds"
	clouds.Size = UDim2.fromScale(1, 1)
	clouds.BackgroundTransparency = 1
	clouds.Parent = backdrop
	local function cloud(x: number, y: number, size: number)
		local puff = Instance.new("Frame")
		puff.AnchorPoint = Vector2.new(0.5, 0.5)
		puff.Position = UDim2.fromScale(x, y)
		puff.Size = UDim2.fromScale(size, size)
		puff.SizeConstraint = Enum.SizeConstraint.RelativeYY
		puff.BackgroundColor3 = CLOUD
		puff.BorderSizePixel = 0
		corner(puff, UDim.new(0.5, 0))
		stroke(puff, CLOUD_EDGE, 3)
		puff.Parent = clouds
	end
	for i = 0, 9 do
		local t = i / 9
		cloud(-0.02, t, 0.22 + (i % 3) * 0.05) -- links
		cloud(1.02, t, 0.22 + ((i + 1) % 3) * 0.05) -- rechts
	end
	for i = 0, 12 do
		local t = i / 12
		cloud(t, -0.04, 0.2 + (i % 3) * 0.05) -- oben
		cloud(t, 1.04, 0.2 + ((i + 2) % 3) * 0.05) -- unten
	end

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

	local title = text(content, "Title", "AUSRÜSTUNG", Vector2.new(860, 14), Vector2.new(400, 54), TITLE_FONT, 46, WHITE)
	title.TextXAlignment = Enum.TextXAlignment.Right
	stroke(title, NAVY, 3).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-------------------------------------------------------------------------------------------------
	-- Links: Fähigkeiten
	-------------------------------------------------------------------------------------------------

	local abilityPanel = frame(content, "Abilities", Vector2.new(40, 80), Vector2.new(310, 600), PANEL)
	corner(abilityPanel, UDim.new(0, 54))
	stroke(abilityPanel, NAVY, 5)

	-- Reiter über dem Panel (wie das Tastatur-Symbol im Vorbild)
	local tab = frame(content, "InputTab", Vector2.new(125, 52), Vector2.new(140, 40), Color3.fromRGB(236, 240, 246))
	corner(tab, UDim.new(0, 12))
	stroke(tab, NAVY, 3)
	text(tab, "Label", "🖱 MAUS", Vector2.zero, Vector2.new(140, 40), TITLE_FONT, 22, NAVY)

	local abilityHeader = text(abilityPanel, "Header", "", Vector2.new(15, 22), Vector2.new(280, 36), TITLE_FONT, 30, NAVY)
	local abilityDescription =
		text(abilityPanel, "Description", "", Vector2.new(28, 330), Vector2.new(254, 200), BODY_FONT, 22, WHITE)
	abilityDescription.TextYAlignment = Enum.TextYAlignment.Top

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icons"
	iconHolder.Position = UDim2.fromOffset(30, 80)
	iconHolder.Size = UDim2.fromOffset(250, 230)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = abilityPanel
	local iconGrid = Instance.new("UIGridLayout")
	iconGrid.CellSize = UDim2.fromOffset(70, 70)
	iconGrid.CellPadding = UDim2.fromOffset(20, 20)
	iconGrid.SortOrder = Enum.SortOrder.LayoutOrder
	iconGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	iconGrid.Parent = iconHolder

	local icons: { [string]: Icon } = {}

	-------------------------------------------------------------------------------------------------
	-- Mitte: eigene Spalte
	-------------------------------------------------------------------------------------------------

	local column = frame(content, "Player", Vector2.new(390, 80), Vector2.new(240, 600), ORANGE)
	corner(column, UDim.new(0, 110))
	stroke(column, BROWN, 5)

	-- Abzeichen oben: eigenes Roblox-Bild
	local badge = Instance.new("ImageLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(390 + 120, 80)
	badge.Size = UDim2.fromOffset(72, 72)
	badge.BackgroundColor3 = Color3.fromRGB(245, 235, 225)
	badge.ZIndex = 3
	corner(badge, UDim.new(0.5, 0))
	stroke(badge, BROWN, 4)
	badge.Parent = content
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			badge.Image = image
		end
	end)

	local slotHeader = text(column, "Header", "", Vector2.new(10, 44), Vector2.new(220, 36), TITLE_FONT, 28, BROWN)
	local slots: { Slot } = {}

	local mound = frame(column, "Mound", Vector2.new(30, 500), Vector2.new(180, 48), GRASS)
	corner(mound, UDim.new(0.5, 0))
	stroke(mound, GRASS_EDGE, 3)
	local character = Instance.new("ImageLabel")
	character.Name = "Character"
	character.Position = UDim2.fromOffset(55, 395)
	character.Size = UDim2.fromOffset(130, 130)
	character.BackgroundTransparency = 1
	character.ScaleType = Enum.ScaleType.Fit
	character.ZIndex = 2
	character.Parent = column

	local ready = bouncyButton(content, "Ready", Vector2.new(390 + 120 - 42, 80 + 600 - 42), Vector2.new(84, 84), Color3.fromRGB(196, 78, 40))
	corner(ready, UDim.new(0.5, 0))
	stroke(ready, BROWN, 5)
	ready.ZIndex = 3
	local readyMark = text(ready, "Mark", "✔", Vector2.zero, Vector2.new(84, 84), TITLE_FONT, 46, WHITE)
	readyMark.ZIndex = 4

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
	stroke(botBar, NAVY, 4)
	text(botBar, "BotsLabel", "BOTS", Vector2.new(18, 0), Vector2.new(80, 72), TITLE_FONT, 26, WHITE)
	local function roundButton(name: string, x: number, label: string, font: Enum.Font, size: number): TextButton
		local button = bouncyButton(botBar, name, Vector2.new(x, 14), Vector2.new(44, 44), NAVY)
		corner(button, UDim.new(0.5, 0))
		text(button, "T", label, Vector2.zero, Vector2.new(44, 44), font, size, WHITE)
		return button
	end
	local minus = roundButton("Minus", 100, "–", TITLE_FONT, 30)
	local plus = roundButton("Plus", 152, "+", TITLE_FONT, 30)
	text(botBar, "StrengthLabel", "STÄRKE", Vector2.new(222, 0), Vector2.new(110, 72), TITLE_FONT, 26, WHITE)
	local weaker = roundButton("Weaker", 334, "◀", BODY_FONT, 22)
	local strengthText =
		text(botBar, "Strength", "", Vector2.new(380, 0), Vector2.new(126, 72), TITLE_FONT, 26, Color3.fromRGB(255, 220, 90))
	local stronger = roundButton("Stronger", 508, "▶", BODY_FONT, 22)

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
	stroke(reopen, BROWN, 3)
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
			icon.ring.Color = if slot == activeSlot then Color3.fromRGB(120, 230, 255) elseif slot then WHITE else NAVY
			icon.ring.Thickness = if slot == activeSlot then 6 elseif slot then 4 else 3
		end
		for index, slot in slots do
			local info = Abilities.list[chosen[index]]
			slot.icon.Text = info.icon
			slot.button.BackgroundColor3 = info.color
			local active = index == activeSlot
			slot.ring.Color = if active then WHITE else BROWN
			slot.ring.Thickness = if active then 6 else 4
			slot.left.Visible = active
			slot.right.Visible = active
		end

		local skin = player:GetAttribute("Skin")
		character.Image = if typeof(skin) == "string" then SpriteAssets.frame(skin, "idle", 1) or "" else ""
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
		button.TextSize = 38
		button.Font = BODY_FONT
		button.AutoButtonColor = true
		corner(button, UDim.new(0.5, 0))
		local ring = stroke(button, NAVY, 3)
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
		local y = 105 + (index - 1) * 125
		text(column, `Key{index}`, SLOT_KEYS[index], Vector2.new(6, y + 30), Vector2.new(40, 40), TITLE_FONT, 18, BROWN)
		local button = bouncyButton(column, `Slot{index}`, Vector2.new(70, y), Vector2.new(100, 100), WHITE)
		corner(button, UDim.new(0.5, 0))
		local ring = stroke(button, BROWN, 4)
		local icon = text(button, "Icon", "", Vector2.zero, Vector2.new(100, 100), BODY_FONT, 52, WHITE)
		local left = bouncyButton(column, `Left{index}`, Vector2.new(30, y + 30), Vector2.new(36, 40), ORANGE)
		left.BackgroundTransparency = 1
		text(left, "T", "◀", Vector2.zero, Vector2.new(36, 40), BODY_FONT, 28, BROWN)
		local right = bouncyButton(column, `Right{index}`, Vector2.new(174, y + 30), Vector2.new(36, 40), ORANGE)
		right.BackgroundTransparency = 1
		text(right, "T", "▶", Vector2.zero, Vector2.new(36, 40), BODY_FONT, 28, BROWN)
		slots[index] = { button = button, ring = ring, icon = icon, left = left, right = right }
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
				stroke(card, NAVY, 5)
				local name = entry:GetAttribute("DisplayName")
				text(card, "Name", if typeof(name) == "string" then string.upper(name) else "?", Vector2.new(10, 34), Vector2.new(160, 60), TITLE_FONT, 24, WHITE)
				local role = if isBot then `BOT · {string.upper(Constants.BOT_DIFFICULTIES[difficulty()].name)}` else "SPIELER"
				text(card, "Role", role, Vector2.new(10, 92), Vector2.new(160, 30), BODY_FONT, 18, Color3.fromRGB(230, 240, 255))
				local grass = frame(card, "Mound", Vector2.new(20, 330), Vector2.new(140, 40), GRASS)
				corner(grass, UDim.new(0.5, 0))
				stroke(grass, GRASS_EDGE, 3)
				local picture = Instance.new("ImageLabel")
				picture.Position = UDim2.fromOffset(25, 210)
				picture.Size = UDim2.fromOffset(130, 130)
				picture.BackgroundTransparency = 1
				picture.ScaleType = Enum.ScaleType.Fit
				picture.Image = if skin then SpriteAssets.frame(skin, "idle", 1) or "" else ""
				picture.ZIndex = 2
				picture.Parent = card
			else
				local box = frame(othersHolder, "Waiting", Vector2.new(x + 5, 300), Vector2.new(170, 150), PANEL)
				corner(box, UDim.new(0, 34))
				stroke(box, NAVY, 5)
				local label = text(box, "Text", `WARTE AUF\nSPIELER{string.rep(".", waitingDots)}`, Vector2.new(8, 0), Vector2.new(154, 150), TITLE_FONT, 24, NAVY)
				label.TextYAlignment = Enum.TextYAlignment.Center
			end
		end

		strengthText.Text = string.upper(Constants.BOT_DIFFICULTIES[difficulty()].name)
	end

	-------------------------------------------------------------------------------------------------
	-- Öffnen / Schließen
	-------------------------------------------------------------------------------------------------

	local function open()
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
