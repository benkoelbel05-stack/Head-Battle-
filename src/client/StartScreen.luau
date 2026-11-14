--!strict
-- Ausrüstungs-Wahl: öffnet sich nach "Spielen" im Hauptmenü (MainMenu).
--   * 3 Fähigkeiten wählen (Klick-Reihenfolge = Taste: Linke Maus, Mausrad, Rechte Maus)
--   * Bot-Stärke und Anzahl der Bots einstellen
--   * "Spielen" steigt ein (JoinGame). Im Spiel öffnet der Knopf "Ausrüstung" (unten links) das Menü wieder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)

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

type Card = { frame: TextButton, outline: UIStroke, badge: TextLabel, info: Abilities.AbilityInfo }

local FONT = Enum.Font.FredokaOne
local TEXT_COLOR = Color3.fromRGB(255, 244, 226)
local DARK_TEXT = Color3.fromRGB(58, 40, 34)
local STROKE_COLOR = Color3.fromRGB(58, 40, 34)
local PANEL_COLOR = Color3.fromRGB(58, 48, 44)
local CARD_COLOR = Color3.fromRGB(246, 232, 210)
local PLAY_COLOR = Color3.fromRGB(116, 196, 98)
local DISABLED_COLOR = Color3.fromRGB(120, 110, 104)
local SLOT_KEYS = { "Linke Maus", "Mausrad", "Rechte Maus" }
local SLOT_SHORT = { "LM", "MR", "RM" }

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

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color or TEXT_COLOR
	l.Text = text
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, size: UDim2, color: Color3, textSize: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextSize = textSize
	b.TextColor3 = TEXT_COLOR
	b.Text = text
	b.AutoButtonColor = true
	corner(b, 14)
	b.Parent = parent
	return b
end

local function row(parent: Instance, height: number, order: number, padding: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = order
	f.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = f
	return f
end

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
	local joined = false

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleStart"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Abgedunkelter Hintergrund (die Arena schimmert durch)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(40, 30, 26)
	backdrop.BackgroundTransparency = 0.25
	backdrop.Active = true -- Klicks gehen nicht ins Spiel
	backdrop.Parent = gui

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(1000, 680)
	content.BackgroundTransparency = 1
	content.Parent = backdrop
	local scale = Instance.new("UIScale")
	scale.Parent = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 14)
	list.Parent = content

	local function fitScale()
		local camera = Workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			scale.Scale = math.min(1, view.X / 1040, view.Y / 720)
		end
	end
	fitScale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
	end

	-- Titel
	local title = label(content, "AUSRÜSTUNG", 64)
	title.LayoutOrder = 1
	title.TextStrokeColor3 = STROKE_COLOR
	title.TextStrokeTransparency = 0
	local subtitle = label(content, "Wähle 3 Fähigkeiten – die Reihenfolge bestimmt die Taste", 24)
	subtitle.LayoutOrder = 2

	-- Fähigkeiten-Karten
	local cardRow = row(content, 230, 3, 14)
	local cards: { [string]: Card } = {}

	-- Gewählte Slots
	local slotRow = row(content, 48, 4, 12)
	local slotLabels: { TextLabel } = {}
	for slot = 1, Abilities.MAX_SLOTS do
		local box = Instance.new("TextLabel")
		box.Size = UDim2.fromOffset(250, 44)
		box.BackgroundColor3 = PANEL_COLOR
		box.Font = FONT
		box.TextSize = 20
		box.TextColor3 = TEXT_COLOR
		box.LayoutOrder = slot
		corner(box, 12)
		box.Parent = slotRow
		slotLabels[slot] = box
	end

	-- Bot-Stärke
	local difficultyRow = row(content, 46, 5, 10)
	local difficultyTitle = label(difficultyRow, "Bot-Stärke:", 22)
	difficultyTitle.Size = UDim2.fromOffset(130, 40)
	difficultyTitle.LayoutOrder = 0
	local difficultyButtons: { TextButton } = {}
	for level, info in Constants.BOT_DIFFICULTIES do
		local b = button(difficultyRow, info.name, UDim2.fromOffset(120, 40), PANEL_COLOR, 20)
		b.LayoutOrder = level
		b.Activated:Connect(function()
			setDifficulty:FireServer(level)
		end)
		difficultyButtons[level] = b
	end

	-- Anzahl Bots
	local botRow = row(content, 46, 6, 10)
	local botTitle = label(botRow, "Bots:", 22)
	botTitle.Size = UDim2.fromOffset(70, 40)
	botTitle.LayoutOrder = 0
	local minus = button(botRow, "–", UDim2.fromOffset(46, 40), PANEL_COLOR, 26)
	minus.LayoutOrder = 1
	local botCount = label(botRow, "0", 26)
	botCount.Size = UDim2.fromOffset(50, 40)
	botCount.LayoutOrder = 2
	local plus = button(botRow, "+", UDim2.fromOffset(46, 40), PANEL_COLOR, 26)
	plus.LayoutOrder = 3
	minus.Activated:Connect(function()
		changeBots:FireServer(-1)
	end)
	plus.Activated:Connect(function()
		changeBots:FireServer(1)
	end)

	-- Spielen
	local playRow = row(content, 70, 7, 0)
	local play = button(playRow, "SPIELEN", UDim2.fromOffset(300, 64), PLAY_COLOR, 36)
	stroke(play, STROKE_COLOR, 3)

	-- Knopf im Spiel, um das Menü wieder zu öffnen
	local reopen = button(gui, "Ausrüstung", UDim2.fromOffset(140, 44), PANEL_COLOR, 22)
	reopen.AnchorPoint = Vector2.new(0, 1)
	reopen.Position = UDim2.new(0, 16, 1, -16)
	reopen.Visible = false

	local function refresh()
		for id, card in cards do
			local slot = table.find(chosen, id)
			card.outline.Thickness = if slot then 5 else 2
			card.outline.Color = if slot then card.info.color else STROKE_COLOR
			card.frame.BackgroundColor3 = if slot then CARD_COLOR else CARD_COLOR:Lerp(PANEL_COLOR, 0.35)
			card.badge.Visible = slot ~= nil
			card.badge.Text = if slot then SLOT_SHORT[slot] else ""
		end
		for slot, box in slotLabels do
			local id = chosen[slot]
			box.Text = `{SLOT_KEYS[slot]}: {if id then Abilities.list[id].label else "–"}`
			box.BackgroundColor3 = if id then Abilities.list[id].color:Lerp(PANEL_COLOR, 0.45) else PANEL_COLOR
		end
		local complete = #chosen == Abilities.MAX_SLOTS
		play.BackgroundColor3 = if complete then PLAY_COLOR else DISABLED_COLOR
		play.Text = if not complete then `Noch {Abilities.MAX_SLOTS - #chosen} wählen` elseif joined then "WEITER" else "SPIELEN"
		play.TextSize = if complete then 36 else 26
	end

	local function refreshDifficulty()
		local current = roundState:GetAttribute("BotDifficulty")
		for level, b in difficultyButtons do
			local selected = current == level
			b.BackgroundColor3 = if selected then Color3.fromRGB(232, 160, 70) else PANEL_COLOR
			b.TextColor3 = if selected then DARK_TEXT else TEXT_COLOR
		end
	end

	local function refreshBots()
		local count = 0
		for _, value in scores:GetChildren() do
			if value:GetAttribute("IsBot") then
				count += 1
			end
		end
		botCount.Text = tostring(count)
	end

	for index, id in Abilities.ORDER do
		local info = Abilities.list[id]
		local card = Instance.new("TextButton")
		card.Name = id
		card.LayoutOrder = index
		card.Size = UDim2.fromOffset(180, 220)
		card.BackgroundColor3 = CARD_COLOR
		card.Text = ""
		card.AutoButtonColor = true
		corner(card, 20)
		local outline = stroke(card, STROKE_COLOR, 2)
		card.Parent = cardRow

		-- Farbiger Knetklecks als Symbol
		local blob = Instance.new("Frame")
		blob.AnchorPoint = Vector2.new(0.5, 0)
		blob.Position = UDim2.new(0.5, 0, 0, 14)
		blob.Size = UDim2.fromOffset(64, 64)
		blob.BackgroundColor3 = info.color
		corner(blob, 32)
		stroke(blob, STROKE_COLOR, 2)
		blob.Parent = card

		local name = label(card, info.label, 26, DARK_TEXT)
		name.Position = UDim2.fromOffset(0, 84)
		local item = label(card, info.itemName, 15, Color3.fromRGB(130, 100, 84))
		item.Position = UDim2.fromOffset(0, 114)
		local description = label(card, info.description, 15, DARK_TEXT)
		description.Font = Enum.Font.GothamMedium
		description.TextWrapped = true
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Position = UDim2.fromOffset(10, 140)
		description.Size = UDim2.new(1, -20, 0, 74)

		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -8, 0, 8)
		badge.Size = UDim2.fromOffset(42, 30)
		badge.BackgroundColor3 = info.color
		badge.Font = FONT
		badge.TextSize = 18
		badge.TextColor3 = TEXT_COLOR
		badge.TextStrokeColor3 = STROKE_COLOR
		badge.TextStrokeTransparency = 0.3
		corner(badge, 10)
		badge.Parent = card

		cards[id] = { frame = card, outline = outline, badge = badge, info = info }
		card.Activated:Connect(function()
			local slot = table.find(chosen, id)
			if slot then
				table.remove(chosen, slot)
			elseif #chosen < Abilities.MAX_SLOTS then
				table.insert(chosen, id)
			else
				chosen[#chosen] = id -- voll: das zuletzt gewählte ersetzen
			end
			refresh()
		end)
	end

	local function open()
		backdrop.Visible = true
		reopen.Visible = false
		refresh()
	end

	play.Activated:Connect(function()
		if #chosen ~= Abilities.MAX_SLOTS then
			return
		end
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

	roundState:GetAttributeChangedSignal("BotDifficulty"):Connect(refreshDifficulty)
	-- Kurz warten, bis die Attribute (IsBot) mit angekommen sind
	scores.ChildAdded:Connect(function()
		task.delay(0.1, refreshBots)
	end)
	scores.ChildRemoved:Connect(refreshBots)
	refreshDifficulty()
	refreshBots()
	backdrop.Visible = false
	openImpl = open
	if openRequested then
		open()
	end
end

return StartScreen
