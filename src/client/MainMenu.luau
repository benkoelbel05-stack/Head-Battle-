--!strict
-- Hauptmenü und Optionen (übernommen aus ClayBattleMenu_Code, angepasst an das Projekt).
--   * Titelbild (Hintergrund steht still) mit sanft wippenden Knetfiguren, leicht schwebendem Logo und Knöpfen (Hover-Zoom, Klick-Squash, Ein-/Ausblenden)
--   * "Spielen" -> Ausrüstungs-Wahl (StartScreen) -> JoinGame
--   * "Optionen" -> Einstellungen in Reitern (Ton, Grafik, Spiel, Steuerung) über dem abgedunkelten Bild
--   * "Shop" -> noch kein Shop im Spiel: kurzer Hinweis
--   * "Verlassen" -> Nachfrage, dann Spiel verlassen
-- Im Spiel öffnet der Haus-Knopf (oben rechts) oder die Taste M die Pause (Weiter, Ausrüstung, Optionen,
-- Zur Lobby). In der Pause läuft die Runde online weiter, die eigene Figur steht still. Nach "Zur Lobby"
-- erscheint wieder das Titelbild; "Spielen" führt dann über die Ausrüstungs-Wahl neu ins Spiel.
-- Bilder kommen aus MenuAssetIds. Fehlt eine ID (0), gibt es einen Ersatz, damit das Menü benutzbar bleibt.
-- Alle Positionen sind im Entwurfsraster 1672 x 941 (Menu_Vorschau.jpg) angegeben und skalieren mit.
-- Bilder behalten ihre Proportionen (ScaleType Fit), nur der Hintergrund füllt per Crop.
-- Titelbild und Optionen sind normale Frames (keine CanvasGroups: die machen alles unscharf);
-- ein- und ausgeblendet wird mit Fade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local Constants = require(ReplicatedStorage.Shared.Constants)
local images = require(script.Parent.MenuAssetIds)
local StartScreen = require(script.Parent.StartScreen)
local SoundFX = require(script.Parent.SoundFX)
local LoadingScreen = require(script.Parent.LoadingScreen)
local Fade = require(script.Parent.Fade)
local Settings = require(script.Parent.Settings)
local SettingsSchema = require(ReplicatedStorage.Shared.SettingsSchema)

local MainMenu = {}

type AvatarData = { name: string, x: number, y: number, w: number, h: number, phase: number, amp: number, speed: number, tilt: number }
type Avatar = { label: ImageLabel, x: number, y: number, phase: number, amp: number, speed: number, tilt: number }
type Flag = { label: ImageLabel, x: number, y: number, phase: number }

local W, H = 1672, 941
local WHITE = Color3.fromRGB(255, 250, 241)
local COLORS: { [string]: Color3 } = {
	play = Color3.fromRGB(18, 174, 49),
	options = Color3.fromRGB(30, 116, 238),
	shop = Color3.fromRGB(251, 183, 10),
	exit = Color3.fromRGB(222, 44, 43),
}

-- Ersatz-Figuren aus den Spiel-Sprites, solange die Menü-Figuren keine ID haben
local CHARACTER_SKINS: { [string]: string } = {
	character_red_sword = "red",
	character_blue_jump = "blue",
	character_yellow_shield = "yellow",
	character_green_hammer = "green",
}

local function imageId(name: string): string
	local value = images[name]
	if not value or value == 0 then
		return ""
	end
	return `rbxassetid://{value}`
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x / W, y / H)
end

local function dims(width: number, height: number): UDim2
	return UDim2.fromScale(width / W, height / H)
end

local function tween(obj: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Ersatz zeigen, wenn ein Bild keine ID hat oder nicht lädt (z. B. Decal- statt Image-ID, noch in Prüfung):
-- so bleibt das Menü immer sichtbar und bedienbar. Nach LOAD_GRACE Sekunden wird nachgesehen.
local LOAD_GRACE = 2.5
local SHOW_FLAGS = false -- schwebende Fahnen neben dem Logo (für später aufgehoben)
local function whenMissing(element: GuiObject, fallback: () -> ())
	local image = element :: any
	if image.Image == "" then
		fallback()
		return
	end
	task.delay(LOAD_GRACE, function()
		if element.Parent and not image.IsLoaded then
			if RunService:IsStudio() then
				warn(`[ClayBattle] Menübild lädt nicht, zeige Ersatz: {element.Name} ({image.Image})`)
			end
			image.Image = ""
			fallback()
		end
	end)
end

local function picture(parent: Instance, name: string, x: number, y: number, w: number, h: number, z: number): ImageLabel
	local element = Instance.new("ImageLabel")
	element.Name = name
	element.BackgroundTransparency = 1
	element.BorderSizePixel = 0
	element.Position = at(x, y)
	element.Size = dims(w, h)
	element.ScaleType = Enum.ScaleType.Fit -- Proportionen des Bildes behalten
	element.Image = imageId(name)
	element.ZIndex = z
	element.Parent = parent
	return element
end

local function textLabel(parent: Instance, name: string, text: string, rect: { number }, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = at(rect[1], rect[2])
	label.Size = dims(rect[3], rect[4])
	label.Text = text
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.55
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 22
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = size
	constraint.Parent = label
	return label
end

-- Symbol links in einen Knopf setzen; der Text rückt daneben (Maße im Entwurfsraster)
local function addButtonIcon(button: GuiObject, iconId: number, width: number, height: number)
	if iconId == 0 then
		return
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.06 * height / width, 0.5)
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = `rbxassetid://{iconId}`
	icon.ZIndex = button.ZIndex + 1
	icon.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new((0.12 * height + 0.8 * height) / width, 0)
	padding.Parent = button
end

-- Freistehendes Symbol im Entwurfsraster
local function iconImage(parent: Instance, name: string, iconId: number, rect: { number }, z: number)
	if iconId == 0 then
		return
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.BackgroundTransparency = 1
	icon.Position = at(rect[1], rect[2])
	icon.Size = dims(rect[3], rect[4])
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = `rbxassetid://{iconId}`
	icon.ZIndex = z
	icon.Parent = parent
end

local function boxButton(parent: Instance, name: string, text: string, rect: { number }, color: Color3, action: () -> (), iconId: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = dims(rect[3], rect[4])
	button.Position = at(rect[1], rect[2])
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.Font = Enum.Font.FredokaOne
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.TextScaled = true
	button.ZIndex = 24
	button.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 225, 200)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = button
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 26
	limit.Parent = button
	if iconId then
		addButtonIcon(button, iconId, rect[3], rect[4])
	end
	button.Activated:Connect(function()
		SoundFX.play("ui_click")
		action()
	end)
	return button
end

-- Ersatz-Hintergrund ohne Bild: Himmel mit Verlauf und eine Wiese
local function fallbackBackground(parent: GuiObject)
	local sky = Instance.new("Frame")
	sky.Name = "FallbackSky"
	sky.Size = UDim2.fromScale(1, 1)
	sky.BorderSizePixel = 0
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.ZIndex = 0
	sky.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(70, 160, 240), Color3.fromRGB(170, 220, 255))
	gradient.Parent = sky
	do
		local meadow = Instance.new("Frame")
		meadow.Name = "FallbackMeadow"
		meadow.Position = UDim2.fromScale(-0.1, 0.82)
		meadow.Size = UDim2.fromScale(1.2, 0.4)
		meadow.BorderSizePixel = 0
		meadow.BackgroundColor3 = Color3.fromRGB(110, 190, 70)
		meadow.ZIndex = 0
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = meadow
		meadow.Parent = parent
	end
end

function MainMenu.start()
	-- Erst nach dem Ladebildschirm: dann ist alles schon geladen und erscheint sofort scharf
	LoadingScreen.waitUntilDone()
	Settings.waitUntilReady() -- gespeicherte Optionen sind da (oder Standardwerte nach kurzer Wartezeit)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("ClayBattleMenu")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20 -- über HUD und Ausrüstungs-Wahl
	gui.Parent = playerGui

	local outer = Instance.new("Frame")
	outer.Name = "FullScreen"
	outer.Size = UDim2.fromScale(1, 1)
	outer.BackgroundColor3 = Color3.fromRGB(16, 30, 54)
	outer.BorderSizePixel = 0
	outer.Active = true -- Klicks gehen nicht ins Spiel
	outer.Parent = gui

	-- Entwurfsfläche im Seitenverhältnis 1672:941, so groß wie möglich
	local canvas = Instance.new("Frame")
	canvas.Name = "DesignCanvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.BorderSizePixel = 0
	canvas.BackgroundTransparency = 1
	canvas.ClipsDescendants = true
	canvas.Parent = outer
	local function resizeCanvas()
		local available = outer.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end
		local scale = math.min(available.X / W, available.Y / H)
		canvas.Size = UDim2.fromOffset(math.floor(W * scale + 0.5), math.floor(H * scale + 0.5))
	end
	outer:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeCanvas)
	task.defer(resizeCanvas)

	-------------------------------------------------------------------------------------------------
	-- Titelbild
	-------------------------------------------------------------------------------------------------

	local titleGroup = Instance.new("Frame")
	titleGroup.Name = "TitleScreen"
	titleGroup.Size = UDim2.fromScale(1, 1)
	titleGroup.BackgroundTransparency = 1
	titleGroup.Parent = canvas

	local background = picture(titleGroup, "menu_background", -20, -13, W + 40, H + 26, 1)
	background.ScaleType = Enum.ScaleType.Crop -- füllt die Fläche ohne Verzerrung
	if background.Image == "" then
		fallbackBackground(titleGroup)
	end

	-- Rote Fahnen links und rechts vom Logo; schwingen leicht im Wind. Zurzeit aus (SHOW_FLAGS),
	-- die Bilder bleiben in MenuAssetIds für später.
	local flags: { Flag } = {}
	local flagLayout = {
		{ name = "prop_red_flag_left", x = 300, y = 64, phase = 0 },
		{ name = "prop_red_flag_right", x = 1222, y = 64, phase = 1.7 },
	}
	for _, data in flagLayout do
		if SHOW_FLAGS and imageId(data.name) ~= "" then
			local flag = picture(titleGroup, data.name, data.x, data.y, 150, 210, 2)
			flag.AnchorPoint = Vector2.new(0.5, 0.5)
			flag.Position = at(data.x + 75, data.y + 105)
			table.insert(flags, { label = flag, x = data.x + 75, y = data.y + 105, phase = data.phase })
			whenMissing(flag, function()
				flag.Visible = false
			end)
		end
	end

	-- Schild "Clay Battle": schwebt nur ganz leicht auf und ab (LOGO_BOB Entwurfspixel)
	local LOGO_Y = 6
	local LOGO_BOB = 6
	local logo = picture(titleGroup, "logo_clay_battle", 452, LOGO_Y, 746, 388, 3)
	whenMissing(logo, function()
		local fallback = Instance.new("TextLabel")
		fallback.Name = "FallbackTitle"
		fallback.BackgroundTransparency = 1
		fallback.Position = UDim2.fromScale(0.05, 0.15)
		fallback.Size = UDim2.fromScale(0.9, 0.7)
		fallback.Text = "CLAY BATTLE"
		fallback.Font = Enum.Font.FredokaOne
		fallback.TextScaled = true
		fallback.TextColor3 = Color3.fromRGB(255, 218, 65)
		fallback.TextStrokeColor3 = Color3.fromRGB(99, 29, 159)
		fallback.TextStrokeTransparency = 0
		fallback.ZIndex = 3
		fallback.Parent = logo
	end)

	-- Knetfiguren: eigenständige, transparente Bilder, die sanft wippen und schweben
	--   Rot: Wippen ~6 px mit 1-2° Neigung, Blau: Hüpfen ~9 px, Gelb/Grün: versetztes Schweben
	local avatarLayout: { AvatarData } = {
		{ name = "character_red_sword", x = 17, y = 495, w = 336, h = 336, phase = 0, amp = 8, speed = 1.25, tilt = 1.5 },
		{ name = "character_blue_jump", x = 342, y = 539, w = 257, h = 219, phase = 1.6, amp = 10, speed = 1.45, tilt = 2.2 },
		{ name = "character_yellow_shield", x = 1022, y = 590, w = 298, h = 232, phase = 2.8, amp = 7, speed = 1.15, tilt = 1.6 },
		{ name = "character_green_hammer", x = 1266, y = 458, w = 373, h = 371, phase = 4.2, amp = 8, speed = 1.2, tilt = 1.4 },
	}
	local avatars: { Avatar } = {}
	for _, data in avatarLayout do
		local label = picture(titleGroup, data.name, data.x, data.y, data.w, data.h, 4)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		whenMissing(label, function()
			-- Ersatz: dieselbe Farbe als Spielfigur (quadratisch, damit sie nicht verzerrt)
			local skin = CHARACTER_SKINS[data.name]
			label.Image = (skin and SpriteAssets.frame(skin, "idle", 1)) or ""
			label.ScaleType = Enum.ScaleType.Fit
		end)
		local baseX, baseY = data.x + data.w / 2, data.y + data.h / 2
		label.Position = at(baseX, baseY)
		table.insert(avatars, {
			label = label,
			x = baseX,
			y = baseY,
			phase = data.phase,
			amp = data.amp,
			speed = data.speed,
			tilt = data.tilt,
		})
	end

	local function makeButton(name: string, rect: { number }, callback: () -> (), fallbackText: string): ImageButton
		local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
		local button = Instance.new("ImageButton")
		button.Name = `button_{name}`
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = at(x + w / 2, y + h / 2)
		button.Size = dims(w, h)
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Image = imageId(`button_{name}`)
		button.ScaleType = Enum.ScaleType.Fit -- freigestellte Knöpfe nicht verzerren
		button.AutoButtonColor = false
		button.ZIndex = 8
		button.Parent = titleGroup

		whenMissing(button, function()
			button.BackgroundTransparency = 0
			Fade.setBase(button, "BackgroundTransparency", 0)
			button.BackgroundColor3 = COLORS[name]
			local corners = Instance.new("UICorner")
			corners.CornerRadius = UDim.new(0.4, 0)
			corners.Parent = button
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(250, 246, 225)
			stroke.Thickness = 3
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = button
			local text = Instance.new("TextLabel")
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			text.Text = fallbackText
			text.Font = Enum.Font.FredokaOne
			text.TextScaled = true
			text.TextColor3 = Color3.new(1, 1, 1)
			text.ZIndex = 9
			text.Parent = button
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 34
			limit.Parent = text
		end)

		-- Hover-Zoom und Klick-Squash
		local scale = Instance.new("UIScale")
		scale.Parent = button
		button.MouseEnter:Connect(function()
			SoundFX.play("ui_hover")
			tween(scale, 0.14, { Scale = 1.055 }, Enum.EasingStyle.Back)
		end)
		button.MouseLeave:Connect(function()
			tween(scale, 0.13, { Scale = 1 })
		end)
		button.Activated:Connect(function()
			SoundFX.play("ui_click")
			tween(scale, 0.08, { Scale = 0.94 })
			task.delay(0.1, function()
				if scale.Parent then
					tween(scale, 0.16, { Scale = 1.04 }, Enum.EasingStyle.Back)
				end
			end)
			task.delay(0.13, callback)
		end)
		return button
	end

	-------------------------------------------------------------------------------------------------
	-- Optionen
	-------------------------------------------------------------------------------------------------

	local optionsGroup = Instance.new("Frame")
	optionsGroup.Name = "OptionsScreen"
	optionsGroup.Size = UDim2.fromScale(1, 1)
	optionsGroup.BackgroundTransparency = 1
	optionsGroup.Visible = false
	optionsGroup.ZIndex = 15
	optionsGroup.Parent = canvas
	-- Kein eigenes Bild: das Titelbild bleibt dahinter sichtbar, nur leicht abgedunkelt
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.fromRGB(20, 16, 40)
	dim.BackgroundTransparency = 0.35
	dim.Active = true -- Klicks gehen nicht an die Knöpfe dahinter
	dim.ZIndex = 1
	dim.Parent = optionsGroup

	textLabel(optionsGroup, "Heading", "OPTIONEN", { 574, 115, 510, 89 }, 65)
	iconImage(optionsGroup, "HeadingIcon", UIAssets.icon_settings_gear, { 490, 122, 74, 74 }, 22)

	-- Einstellungen liegen im Settings-Modul (gespeichert beim Server); hier ist nur die Oberfläche.

	-- Musik: läuft in Endlosschleife, solange ein Menü offen ist (Hauptmenü, Optionen, Ausrüstung).
	-- Im Spiel blendet sie weich aus, außer "Musik im Spiel" ist an: dann läuft sie leiser weiter.
	-- Das Stück hat am Ende ~1 s Stille: die Schleife springt schon vorher zurück an den Anfang.
	local THEME_LOOP_END = 63.55
	local THEME_VOLUME = 0.22 -- das Stück ist laut abgemischt: bewusst leise (früher 0,6)
	local THEME_VOLUME_IN_GAME = 0.1
	local theme: Sound? = nil
	if images.menu_theme and images.menu_theme ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "ClayBattleMenuTheme"
		sound.SoundId = `rbxassetid://{images.menu_theme}`
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = Settings.soundGroup("Music")
		pcall(function()
			(sound :: any).PlaybackRegionsEnabled = true
			(sound :: any).LoopRegion = NumberRange.new(0, THEME_LOOP_END)
		end)
		sound.Parent = SoundService
		theme = sound
	end
	local function wantsMusic(): boolean
		return player:GetAttribute("MenuOpen") == true or Settings.get("musicInGame") == true
	end
	local function updateTheme()
		local sound = theme
		if not sound then
			return
		end
		local target = if player:GetAttribute("MenuOpen") == true
			then THEME_VOLUME
			elseif Settings.get("musicInGame") == true then THEME_VOLUME_IN_GAME
			else 0
		if target > 0 then
			if not sound.IsPlaying then
				sound:Play()
			end
			TweenService:Create(sound, TweenInfo.new(1.2), { Volume = target }):Play()
		elseif sound.IsPlaying then
			local fade = TweenService:Create(sound, TweenInfo.new(1.2), { Volume = 0 })
			fade.Completed:Once(function()
				if not wantsMusic() then
					sound:Pause()
				end
			end)
			fade:Play()
		end
	end
	player:GetAttributeChangedSignal("MenuOpen"):Connect(updateTheme)
	Settings.changed:Connect(function(name: string)
		if name == "musicInGame" then
			updateTheme()
		end
	end)
	updateTheme()
	gui.Destroying:Connect(function()
		if theme then
			theme:Destroy()
		end
	end)

	-- Reiter: Ton / Grafik / Spiel / Steuerung. Jeder Reiter ist eine eigene, volle Fläche.
	local SMALL_BUTTON = Color3.fromRGB(77, 76, 120)
	local TAB_ACTIVE = Color3.fromRGB(236, 128, 34)
	local ON_COLOR = Color3.fromRGB(33, 172, 72)
	local OFF_COLOR = Color3.fromRGB(105, 104, 111)
	local CREAM = Color3.fromRGB(255, 242, 219)
	local ROW_TOP = 282
	local ROW_STEP = 66
	local TABS = { "Ton", "Grafik", "Spiel", "Steuerung" }
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local function showTab(name: string)
		for tabName, page in pages do
			page.Visible = tabName == name
		end
		for tabName, button in tabButtons do
			button.BackgroundColor3 = if tabName == name then TAB_ACTIVE else SMALL_BUTTON
		end
	end
	for index, name in TABS do
		local page = Instance.new("Frame")
		page.Name = `Page{name}`
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.ZIndex = 20
		page.Parent = optionsGroup
		pages[name] = page
		tabButtons[name] = boxButton(optionsGroup, `Tab{name}`, string.upper(name), { 382 + (index - 1) * 180, 212, 170, 50 }, SMALL_BUTTON, function()
			showTab(name)
		end)
	end

	local function rowY(row: number): number
		return ROW_TOP + (row - 1) * ROW_STEP
	end
	local function rowLabel(page: Frame, name: string, text: string, row: number, iconId: number?)
		local y = rowY(row)
		if iconId then
			iconImage(page, `{name}Icon`, iconId, { 378, y + 3, 50, 48 }, 22)
		end
		textLabel(page, `{name}Label`, text, { 440, y, 400, 54 }, 32)
	end
	local function onChanged(name: string, refresh: () -> ())
		Settings.changed:Connect(function(changed: string)
			if changed == name then
				refresh()
			end
		end)
	end
	-- Regler in 10-%-Schritten: − Wert +
	local function sliderRow(page: Frame, text: string, name: string, row: number, iconId: number?)
		rowLabel(page, name, text, row, iconId)
		local y = rowY(row)
		local valueText = textLabel(page, `{name}Value`, "", { 910, y, 120, 54 }, 29)
		valueText.TextXAlignment = Enum.TextXAlignment.Center
		local function refresh()
			valueText.Text = `{math.floor(Settings.get(name) * 100 + 0.5)}%`
		end
		local function step(delta: number)
			Settings.set(name, math.floor((Settings.get(name) + delta) * 10 + 0.5) / 10)
			refresh()
		end
		boxButton(page, `{name}Minus`, "−", { 850, y + 2, 54, 48 }, SMALL_BUTTON, function()
			step(-0.1)
		end)
		boxButton(page, `{name}Plus`, "+", { 1042, y + 2, 54, 48 }, SMALL_BUTTON, function()
			step(0.1)
		end)
		refresh()
		onChanged(name, refresh)
	end
	-- Ein/Aus
	local function toggleRow(page: Frame, text: string, name: string, row: number)
		rowLabel(page, name, text, row)
		local toggle: TextButton
		local function refresh()
			local on = Settings.get(name) == true
			toggle.Text = if on then "Ein" else "Aus"
			toggle.BackgroundColor3 = if on then ON_COLOR else OFF_COLOR
		end
		toggle = boxButton(page, `{name}Toggle`, "", { 884, rowY(row) + 2, 211, 49 }, ON_COLOR, function()
			Settings.set(name, not Settings.get(name))
			refresh()
		end)
		refresh()
		onChanged(name, refresh)
	end
	-- Auswahl: Klick schaltet zum nächsten Wert
	local function choiceRow(page: Frame, text: string, name: string, row: number)
		rowLabel(page, name, text, row)
		local field = SettingsSchema.FIELDS[name]
		local choices = (field and field.choices) or {}
		local button: TextButton
		local function refresh()
			button.Text = tostring(Settings.get(name))
		end
		button = boxButton(page, `{name}Choice`, "", { 884, rowY(row) + 2, 211, 49 }, SMALL_BUTTON, function()
			local index = table.find(choices, Settings.get(name)) or 1
			Settings.set(name, choices[index % #choices + 1])
			refresh()
		end)
		refresh()
		onChanged(name, refresh)
	end
	-- Erklärung unten auf einem Reiter
	local function hint(page: Frame, text: string)
		local label = textLabel(page, "Hint", text, { 382, 674, 714, 40 }, 21)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextColor3 = CREAM
	end
	-- Steuerung: Taste (cremefarbenes Schild) und was sie tut
	local function infoRow(page: Frame, key: string, action: string, row: number)
		local y = rowY(row)
		local chip = Instance.new("TextLabel")
		chip.Name = `Key{row}`
		chip.Position = at(382, y + 5)
		chip.Size = dims(360, 44)
		chip.BackgroundColor3 = CREAM
		chip.Font = Enum.Font.GothamBold
		chip.Text = key
		chip.TextScaled = true
		chip.TextColor3 = Color3.fromRGB(70, 37, 112)
		chip.ZIndex = 22
		chip.Parent = page
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0.3, 0)
		chipCorner.Parent = chip
		local chipPadding = Instance.new("UIPadding")
		chipPadding.PaddingTop = UDim.new(0.14, 0)
		chipPadding.PaddingBottom = UDim.new(0.14, 0)
		chipPadding.Parent = chip
		local chipLimit = Instance.new("UITextSizeConstraint")
		chipLimit.MaxTextSize = 24
		chipLimit.Parent = chip
		textLabel(page, `Action{row}`, action, { 768, y, 330, 54 }, 27)
	end

	local ton = pages.Ton
	sliderRow(ton, "Musik", "musicVolume", 1, UIAssets.icon_music)
	sliderRow(ton, "Soundeffekte", "sfx", 2, UIAssets.icon_sound)
	toggleRow(ton, "Musik im Spiel", "musicInGame", 3)
	hint(ton, "Musik im Spiel: Die Menümusik läuft beim Spielen leise weiter.")

	local grafik = pages.Grafik
	choiceRow(grafik, "Grafikqualität", "graphics", 1)
	toggleRow(grafik, "Bildschirmwackeln", "shake", 2)
	toggleRow(grafik, "FPS und Ping anzeigen", "showStats", 3)
	hint(grafik, "Mittel: ohne Glitzern auf dem Wasser · Niedrig: auch ohne Wolken und Wellen")

	local spiel = pages.Spiel
	choiceRow(spiel, "Symbole über Köpfen", "bubbles", 1)
	toggleRow(spiel, "Pfeil über mir", "ownArrow", 2)
	toggleRow(spiel, "Controller-Vibration", "vibration", 3)
	hint(spiel, "Deine Einstellungen werden für dein Konto gespeichert.")

	local steuerung = pages.Steuerung
	infoRow(steuerung, "W A S D / Pfeiltasten", "Bewegen", 1)
	infoRow(steuerung, "Leertaste", "Springen, in der Luft Doppelsprung", 2)
	infoRow(steuerung, "Linke Maustaste / 1", "Fähigkeit 1", 3)
	infoRow(steuerung, "Mausrad-Klick / 2", "Fähigkeit 2", 4)
	infoRow(steuerung, "Rechte Maustaste / 3", "Fähigkeit 3", 5)
	infoRow(steuerung, "M", "Menü öffnen", 6)
	hint(steuerung, "Halten: Granate weiter werfen, Rakete lenken · Controller: A springen, X/Y/B Fähigkeiten")

	showTab("Ton")

	-------------------------------------------------------------------------------------------------
	-- Wechsel zwischen den Seiten
	-------------------------------------------------------------------------------------------------

	local menuOpen = true
	local transitioning = false

	local function showOptions()
		if transitioning then
			return
		end
		transitioning = true
		optionsGroup.Visible = true
		optionsGroup.Position = at(0, 34)
		Fade.to(optionsGroup, 1, 0)
		titleGroup.Interactable = false
		Fade.to(titleGroup, 0.15, 0.22)
		Fade.to(optionsGroup, 0, 0.32, Enum.EasingStyle.Quart)
		tween(optionsGroup, 0.32, { Position = at(0, 0) }, Enum.EasingStyle.Quart)
		task.delay(0.33, function()
			transitioning = false
		end)
	end

	local function showTitle()
		if transitioning then
			return
		end
		transitioning = true
		titleGroup.Visible = true
		Fade.to(optionsGroup, 1, 0.2)
		tween(optionsGroup, 0.2, { Position = at(0, 34) })
		Fade.to(titleGroup, 0, 0.32)
		task.delay(0.33, function()
			optionsGroup.Visible = false
			titleGroup.Interactable = true
			transitioning = false
		end)
	end
	-- Optionen können auch aus dem Pause-Bildschirm kommen: dann führt "Zurück" dorthin
	local optionsFromPause = false
	local backToPause: () -> () = function() end
	boxButton(optionsGroup, "Back", if UIAssets.icon_back ~= 0 then "Zurück" else "← Zurück", { 689, 729, 280, 67 }, Color3.fromRGB(33, 112, 231), function()
		if optionsFromPause then
			backToPause()
		else
			showTitle()
		end
	end, UIAssets.icon_back)
	-- Grundwerte der Optionen merken (alles ist jetzt gebaut) und unsichtbar starten
	Fade.to(optionsGroup, 1, 0)

	-- Solange ein Menü offen ist, nimmt die Steuerung keine Eingaben an (HeadController liest das)
	local function setMenuOpen(open: boolean)
		menuOpen = open
		player:SetAttribute("MenuOpen", open)
	end
	setMenuOpen(true)

	local function inGame(): boolean
		return player:GetAttribute("InGame") == true
	end
	-- "Zur Lobby" gedrückt, der Server hat "InGame" aber noch nicht zurückgesetzt
	local leaving = false
	player:GetAttributeChangedSignal("InGame"):Connect(function()
		if not inGame() then
			leaving = false
		end
	end)

	-- Spielen: Menü ausblenden. Beim ersten Mal folgt die Ausrüstungs-Wahl (dort geht es ins Spiel),
	-- später geht es direkt zurück ins laufende Spiel.
	local function playGame()
		if not menuOpen or transitioning then
			return
		end
		transitioning = true
		local resume = inGame() and not leaving
		Fade.to(titleGroup, 1, 0.4, Enum.EasingStyle.Quart)
		if optionsGroup.Visible then
			Fade.to(optionsGroup, 1, 0.4)
		end
		task.delay(0.41, function()
			gui.Enabled = false
			optionsGroup.Visible = false
			titleGroup.Interactable = true
			transitioning = false
			if resume then
				setMenuOpen(false)
			else
				menuOpen = false
				StartScreen.open() -- setzt "MenuOpen" selbst, bis man einsteigt
			end
		end)
	end

	-- Im Spiel: Menü wieder öffnen (Titelbild)
	local function openMenu()
		if menuOpen or transitioning then
			return
		end
		setMenuOpen(true)
		gui.Enabled = true
		titleGroup.Visible = true
		titleGroup.Interactable = true
		optionsGroup.Visible = false
		Fade.to(titleGroup, 1, 0)
		Fade.to(titleGroup, 0, 0.35)
	end

	-------------------------------------------------------------------------------------------------
	-- Pause (im Spiel: Haus-Knopf oder Taste M)
	-- Weiter / Ausrüstung / Optionen / Zur Lobby. Online läuft die Runde für die anderen weiter, die
	-- eigene Figur steht still. "Zur Lobby" steigt aus (der Server bricht das Match ab, wenn sonst kein
	-- Spieler mehr dabei ist) und zeigt das Titelbild.
	-------------------------------------------------------------------------------------------------

	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
	local leaveGame = remotes:WaitForChild("LeaveGame") :: RemoteEvent

	local pauseGroup = Instance.new("Frame")
	pauseGroup.Name = "PauseScreen"
	pauseGroup.Size = UDim2.fromScale(1, 1)
	pauseGroup.BackgroundTransparency = 1
	pauseGroup.ZIndex = 40
	pauseGroup.Visible = false
	pauseGroup.Parent = canvas

	local pauseDim = Instance.new("Frame")
	pauseDim.Name = "Dim"
	pauseDim.Size = UDim2.fromScale(1, 1)
	pauseDim.BorderSizePixel = 0
	pauseDim.BackgroundColor3 = Color3.fromRGB(20, 16, 40)
	pauseDim.BackgroundTransparency = 0.4
	pauseDim.Active = true
	pauseDim.ZIndex = 1
	pauseDim.Parent = pauseGroup

	local pausePanel = Instance.new("Frame")
	pausePanel.Name = "Panel"
	pausePanel.Position = at(586, 200)
	pausePanel.Size = dims(500, 500)
	pausePanel.BackgroundColor3 = Color3.fromRGB(85, 49, 134)
	pausePanel.ZIndex = 2
	pausePanel.Parent = pauseGroup
	local pauseCorner = Instance.new("UICorner")
	pauseCorner.CornerRadius = UDim.new(0.08, 0)
	pauseCorner.Parent = pausePanel
	local pauseStroke = Instance.new("UIStroke")
	pauseStroke.Color = Color3.fromRGB(255, 242, 219)
	pauseStroke.Thickness = 4
	pauseStroke.Parent = pausePanel

	local pauseTitle = textLabel(pauseGroup, "Title", "PAUSE", { 700, 222, 300, 70 }, 56)
	pauseTitle.TextXAlignment = Enum.TextXAlignment.Center
	iconImage(pauseGroup, "TitleIcon", UIAssets.icon_pause, { 640, 226, 62, 62 }, 22)
	local pauseNote = textLabel(pauseGroup, "Note", "Online läuft die Runde weiter, deine Figur steht still.", { 536, 712, 600, 36 }, 22)
	pauseNote.TextXAlignment = Enum.TextXAlignment.Center
	pauseNote.TextColor3 = Color3.fromRGB(255, 242, 219)

	local function showPause()
		if transitioning or not inGame() then
			return
		end
		setMenuOpen(true)
		gui.Enabled = true
		titleGroup.Visible = false
		optionsGroup.Visible = false
		optionsFromPause = false
		pauseGroup.Visible = true
		Fade.to(pauseGroup, 1, 0)
		Fade.to(pauseGroup, 0, 0.22)
	end

	local function hidePause(thenDo: () -> ())
		transitioning = true
		Fade.to(pauseGroup, 1, 0.18)
		task.delay(0.19, function()
			pauseGroup.Visible = false
			transitioning = false
			thenDo()
		end)
	end

	local function resumeGame()
		if transitioning or not pauseGroup.Visible then
			return
		end
		hidePause(function()
			gui.Enabled = false
			titleGroup.Visible = true
			setMenuOpen(false)
		end)
	end

	backToPause = function()
		if transitioning then
			return
		end
		transitioning = true
		Fade.to(optionsGroup, 1, 0.18)
		task.delay(0.19, function()
			optionsGroup.Visible = false
			optionsFromPause = false
			titleGroup.Interactable = true
			transitioning = false
			pauseGroup.Visible = true
			Fade.to(pauseGroup, 1, 0)
			Fade.to(pauseGroup, 0, 0.2)
		end)
	end

	local GREEN = Color3.fromRGB(33, 172, 72)
	local ORANGE_BUTTON = Color3.fromRGB(236, 128, 34)
	local BLUE_BUTTON = Color3.fromRGB(33, 112, 231)
	local RED_BUTTON = Color3.fromRGB(218, 55, 55)
	boxButton(pauseGroup, "Resume", "WEITER", { 636, 312, 400, 70 }, GREEN, resumeGame, UIAssets.icon_play)
	boxButton(pauseGroup, "Loadout", "AUSRÜSTUNG", { 636, 396, 400, 70 }, ORANGE_BUTTON, function()
		if transitioning then
			return
		end
		hidePause(function()
			gui.Enabled = false
			titleGroup.Visible = true
			menuOpen = false -- StartScreen hält "MenuOpen", bis man übernimmt
			StartScreen.open()
		end)
	end)
	boxButton(pauseGroup, "Options", "OPTIONEN", { 636, 480, 400, 70 }, BLUE_BUTTON, function()
		if transitioning then
			return
		end
		optionsFromPause = true
		pauseGroup.Visible = false
		showOptions()
	end, UIAssets.icon_settings_gear)

	-- Zur Lobby: erster Klick fragt nach, zweiter (innerhalb von 3 s) steigt aus
	local lobbyButton: TextButton
	local lobbyArmedUntil = 0
	lobbyButton = boxButton(pauseGroup, "Lobby", "ZUR LOBBY", { 636, 564, 400, 70 }, RED_BUTTON, function()
		if transitioning then
			return
		end
		local now = os.clock()
		if now > lobbyArmedUntil then
			lobbyArmedUntil = now + 3
			lobbyButton.Text = "WIRKLICH? NOCHMAL KLICKEN"
			task.delay(3, function()
				if os.clock() >= lobbyArmedUntil then
					lobbyButton.Text = "ZUR LOBBY"
				end
			end)
			return
		end
		lobbyArmedUntil = 0
		lobbyButton.Text = "ZUR LOBBY"
		leaving = true
		leaveGame:FireServer()
		hidePause(function()
			titleGroup.Visible = true
			titleGroup.Interactable = true
			Fade.to(titleGroup, 1, 0)
			Fade.to(titleGroup, 0, 0.35)
		end)
	end, UIAssets.icon_exit)

	-- Grundwerte der Pause merken und unsichtbar starten
	Fade.to(pauseGroup, 1, 0)

	-- "Zurück" in der Ausrüstungs-Wahl: im Spiel zur Pause, sonst zum Titelbild
	StartScreen.onBack = function()
		if inGame() and not leaving then
			showPause()
		else
			openMenu()
		end
	end

	-- Knopf oben rechts (nur im Spiel sichtbar, wenn kein Menü offen ist)
	local menuButtonGui = Instance.new("ScreenGui")
	menuButtonGui.Name = "ClayBattleMenuButton"
	menuButtonGui.ResetOnSpawn = false
	menuButtonGui.DisplayOrder = 5
	menuButtonGui.Parent = playerGui
	-- Mit Bild: runder Haus-Knopf; ohne Bild: lila Textknopf "☰ MENÜ"
	local menuButton: GuiButton
	if UIAssets.icon_home ~= 0 then
		local homeButton = Instance.new("ImageButton")
		homeButton.Size = UDim2.fromOffset(58, 58)
		homeButton.BackgroundTransparency = 1
		homeButton.ScaleType = Enum.ScaleType.Fit
		homeButton.Image = `rbxassetid://{UIAssets.icon_home}`
		menuButton = homeButton
	else
		local textButton = Instance.new("TextButton")
		textButton.Size = UDim2.fromOffset(130, 44)
		textButton.BackgroundColor3 = Color3.fromRGB(85, 49, 134)
		textButton.Font = Enum.Font.FredokaOne
		textButton.TextSize = 22
		textButton.TextColor3 = WHITE
		textButton.Text = "☰ MENÜ"
		local menuCorner = Instance.new("UICorner")
		menuCorner.CornerRadius = UDim.new(0, 14)
		menuCorner.Parent = textButton
		local menuStroke = Instance.new("UIStroke")
		menuStroke.Color = Color3.fromRGB(250, 246, 225)
		menuStroke.Thickness = 2
		menuStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		menuStroke.Parent = textButton
		menuButton = textButton
	end
	menuButton.Name = "Menu"
	menuButton.AnchorPoint = Vector2.new(1, 0)
	menuButton.Position = UDim2.new(1, -14, 0, 10)
	menuButton.AutoButtonColor = false
	menuButton.Visible = false
	local menuScale = Instance.new("UIScale")
	menuScale.Parent = menuButton
	menuButton.MouseEnter:Connect(function()
		SoundFX.play("ui_hover")
		tween(menuScale, 0.12, { Scale = 1.08 }, Enum.EasingStyle.Back)
	end)
	menuButton.MouseLeave:Connect(function()
		tween(menuScale, 0.12, { Scale = 1 })
	end)
	menuButton.Parent = menuButtonGui
	menuButton.Activated:Connect(function()
		SoundFX.play("ui_click")
		showPause()
	end)

	local function refreshMenuButton()
		menuButton.Visible = inGame() and player:GetAttribute("MenuOpen") ~= true
	end
	player:GetAttributeChangedSignal("InGame"):Connect(refreshMenuButton)
	player:GetAttributeChangedSignal("MenuOpen"):Connect(refreshMenuButton)

	-- Taste M: Pause auf/zu (nur im Spiel)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.M or not inGame() or leaving then
			return
		end
		if pauseGroup.Visible and gui.Enabled then
			resumeGame()
		elseif player:GetAttribute("MenuOpen") ~= true then
			showPause()
		end
	end)

	-- Noch gibt es keinen Shop: kurzer Hinweis
	local function showShop()
		if titleGroup:FindFirstChild("ShopInfo") then
			return
		end
		local notice = textLabel(titleGroup, "ShopInfo", "Der Shop kommt bald!", { 475, 770, 735, 51 }, 28)
		notice.TextXAlignment = Enum.TextXAlignment.Center
		notice.BackgroundColor3 = Color3.fromRGB(70, 37, 112)
		notice.BackgroundTransparency = 0.15
		local noticeCorner = Instance.new("UICorner")
		noticeCorner.CornerRadius = UDim.new(0.5, 0)
		noticeCorner.Parent = notice
		addButtonIcon(notice, UIAssets.icon_shop_cart, 735, 51)
		task.delay(2.2, function()
			if notice.Parent then
				notice:Destroy()
			end
		end)
	end

	local exitConfirmation = false
	local function exitGame()
		if exitConfirmation then
			return
		end
		exitConfirmation = true
		local overlay = Instance.new("Frame")
		overlay.Name = "ExitConfirmation"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.34
		overlay.ZIndex = 30
		overlay.Parent = canvas
		local panel = Instance.new("Frame")
		panel.Position = at(500, 320)
		panel.Size = dims(672, 240)
		panel.BackgroundColor3 = Color3.fromRGB(85, 49, 134)
		panel.ZIndex = 31
		panel.Parent = overlay
		local rounded = Instance.new("UICorner")
		rounded.CornerRadius = UDim.new(0.1, 0)
		rounded.Parent = panel
		local question = Instance.new("TextLabel")
		question.Size = UDim2.fromScale(1, 0.48)
		question.BackgroundTransparency = 1
		question.Text = "Spiel wirklich verlassen?"
		question.TextColor3 = WHITE
		question.Font = Enum.Font.FredokaOne
		question.TextScaled = true
		question.ZIndex = 32
		question.Parent = panel
		local function confirmButton(text: string, x: number, color: Color3, iconId: number, action: () -> ())
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromScale(0.38, 0.26)
			b.Position = UDim2.fromScale(x, 0.6)
			b.Text = text
			b.Font = Enum.Font.FredokaOne
			b.TextScaled = true
			b.TextColor3 = WHITE
			b.BackgroundColor3 = color
			b.ZIndex = 32
			b.Parent = panel
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.3, 0)
			c.Parent = b
			-- Knopfgröße im Entwurfsraster: 38 % x 26 % der Tafel (672 x 240)
			addButtonIcon(b, iconId, 672 * 0.38, 240 * 0.26)
			b.Activated:Connect(function()
				SoundFX.play("ui_click")
				action()
			end)
		end
		confirmButton("Abbrechen", 0.08, Color3.fromRGB(33, 115, 217), UIAssets.icon_cancel, function()
			exitConfirmation = false
			overlay:Destroy()
		end)
		confirmButton("Verlassen", 0.54, Color3.fromRGB(218, 55, 55), UIAssets.icon_confirm, function()
			player:Kick("Du hast Clay Battle verlassen.")
		end)
	end

	makeButton("play", { 577, 379, 490, 116 }, playGame, "▶ Spielen")
	makeButton("options", { 618, 495, 411, 91 }, showOptions, "⚙ Optionen")
	makeButton("shop", { 617, 589, 413, 97 }, showShop, "Shop")
	makeButton("exit", { 617, 683, 412, 102 }, exitGame, "Verlassen")

	-------------------------------------------------------------------------------------------------
	-- Animation (nur solange das Titelbild offen ist)
	-------------------------------------------------------------------------------------------------

	local clock = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(delta)
		if not gui.Parent then
			connection:Disconnect()
			return
		end
		if not gui.Enabled or not titleGroup.Visible then
			return
		end
		clock += math.min(delta, 0.1)
		-- Eine ruhige Sinus-Bewegung pro Figur: auf und ab, dazu passend ganz leicht gekippt
		-- (kein seitliches Zittern mehr, Hintergrund steht still)
		for _, avatar in avatars do
			local t = clock * avatar.speed + avatar.phase
			avatar.label.Position = at(avatar.x, avatar.y + math.sin(t) * avatar.amp)
			avatar.label.Rotation = math.cos(t) * avatar.tilt
		end
		for _, flag in flags do
			flag.label.Rotation = math.sin(clock * 1.7 + flag.phase) * 3.5
			flag.label.Position = at(flag.x, flag.y + math.sin(clock * 1.3 + flag.phase) * 3)
		end
		logo.Position = at(452, LOGO_Y + math.sin(clock * 1.1) * LOGO_BOB)
	end)

	-- Grundwerte des Titelbilds merken (alles ist gebaut), dann einblenden
	Fade.to(titleGroup, 1, 0)
	Fade.to(titleGroup, 0, 0.75)

	-- Nur in Studio: nach ein paar Sekunden melden, welche Menübilder nicht geladen werden konnten
	-- (z. B. Decal- statt Image-ID oder noch nicht von Roblox freigegeben)
	if RunService:IsStudio() then
		task.delay(6, function()
			local broken = {}
			for _, item in titleGroup:GetDescendants() do
				if (item:IsA("ImageLabel") or item:IsA("ImageButton")) and item.Image ~= "" and not item.IsLoaded then
					table.insert(broken, `{item.Name} ({item.Image})`)
				end
			end
			if #broken > 0 then
				warn(`[ClayBattle] Menübilder nicht geladen: {table.concat(broken, ", ")}`)
			else
				print("[ClayBattle] Alle Menübilder geladen")
			end
		end)
	end
end

return MainMenu
