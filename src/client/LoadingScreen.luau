--!strict
-- Ladebildschirm beim Spielstart: liegt deckend über allem, lädt mit dem AssetPreloader einmal alle
-- Bilder und Klänge vollständig (und scharf) vor und blendet dann zum Hauptmenü über.
-- Zeigt das Logo (sobald es da ist), einen hüpfenden Knetball, einen Fortschrittsbalken und Tipps.
-- Kein CanvasGroup (die würde den ganzen Bildschirm unscharf machen); ausgeblendet wird mit Fade.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local AssetPreloader = require(script.Parent.AssetPreloader)
local MenuAssetIds = require(script.Parent.MenuAssetIds)
local Fade = require(script.Parent.Fade)

local LoadingScreen = {}

local done = false
local doneEvent = Instance.new("BindableEvent")

-- Wartet, bis der Ladebildschirm fertig ist (das Hauptmenü erscheint erst danach)
function LoadingScreen.waitUntilDone()
	if not done then
		doneEvent.Event:Wait()
	end
end

local MAX_WAIT = 120 -- Sekunden: Notbremse, falls Roblox gar nicht antwortet
local SKIP_AFTER = 3 -- Sekunden, bis der Knopf "Überspringen" erscheint
local FONT = Enum.Font.FredokaOne
local CREAM = Color3.fromRGB(255, 242, 219)
local PURPLE = Color3.fromRGB(123, 42, 178)
local TEXT_STROKE = Color3.fromRGB(60, 30, 70)

local TIPS = {
	"Halte die Granaten-Taste, um weiter zu werfen.",
	"Mit dem Schwert schlägst du Granaten zurück.",
	"Halte die Raketen-Taste, um die Rakete zu lenken.",
	"Ein Thruster kann eine ganze Plattform umdrehen.",
	"Doppelsprung: in der Luft nochmal springen.",
	"Fällst du ins Wasser, bist du raus.",
	"Mit M öffnest du im Spiel das Menü.",
}

function LoadingScreen.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleLoading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	root.BorderSizePixel = 0
	root.Active = true
	root.Parent = gui
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 150, 235)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(150, 205, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 205, 90)),
	})
	sky.Parent = root

	local function text(value: string, y: number, height: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.new(0.8, 0, height, 0)
		l.BackgroundTransparency = 1
		l.Font = FONT
		l.Text = value
		l.TextScaled = true
		l.TextColor3 = CREAM
		l.TextStrokeColor3 = TEXT_STROKE
		l.TextStrokeTransparency = 0.3
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size
		limit.Parent = l
		l.Parent = root
		return l
	end
	local title = text("CLAY BATTLE", 0.28, 0.16, 110)

	-- Logo: wird als Erstes geladen und ersetzt dann den Schriftzug
	local logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.27)
	logo.Size = UDim2.fromScale(0.62, 0.4)
	logo.BackgroundTransparency = 1
	logo.ScaleType = Enum.ScaleType.Fit
	logo.ImageTransparency = 1
	logo.Parent = root
	if MenuAssetIds.logo_clay_battle ~= 0 then
		logo.Image = `rbxassetid://{MenuAssetIds.logo_clay_battle}`
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ logo })
			end)
			local started = os.clock()
			while not logo.IsLoaded and os.clock() - started < 10 and logo.Parent do
				task.wait(0.05)
			end
			if logo.IsLoaded and logo.Parent and not done then
				TweenService:Create(logo, TweenInfo.new(0.35), { ImageTransparency = 0 }):Play()
				TweenService:Create(title, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	-- Hüpfender Knetball (ohne Bild, damit er sofort da ist)
	local ball = Instance.new("Frame")
	ball.AnchorPoint = Vector2.new(0.5, 1)
	ball.Size = UDim2.fromScale(0.06, 0.06)
	ball.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ball.BackgroundColor3 = Color3.fromRGB(70, 130, 240)
	ball.Parent = root
	local ballCorner = Instance.new("UICorner")
	ballCorner.CornerRadius = UDim.new(0.5, 0)
	ballCorner.Parent = ball
	local ballStroke = Instance.new("UIStroke")
	ballStroke.Color = TEXT_STROKE
	ballStroke.Thickness = 3
	ballStroke.Parent = ball

	-- Fortschrittsbalken
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.7)
	bar.Size = UDim2.fromScale(0.5, 0.045)
	bar.BackgroundColor3 = Color3.fromRGB(60, 34, 98)
	bar.Parent = root
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = bar
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = CREAM
	barStroke.Thickness = 4
	barStroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = PURPLE
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	local status = text("Lädt …", 0.78, 0.05, 32)
	local tip = text(TIPS[math.random(1, #TIPS)], 0.88, 0.04, 26)
	tip.TextColor3 = Color3.fromRGB(255, 250, 240)

	-- Ball hüpft, Tipp wechselt
	local clock = 0
	local nextTip = 4
	local connection = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local bounce = math.abs(math.sin(clock * 3.2))
		local squash = 1 - 0.25 * math.max(0, 0.25 - bounce) * 4 -- unten kurz breit gedrückt
		ball.Position = UDim2.fromScale(0.5, 0.6 - 0.12 * bounce)
		ball.Size = UDim2.fromScale(0.06 / squash, 0.06 * squash)
		if clock > nextTip then
			nextTip = clock + 4
			tip.Text = TIPS[math.random(1, #TIPS)]
		end
	end)

	-- Überspringen: erscheint nach ein paar Sekunden; was noch fehlt, lädt dann im Spiel nach
	local finished = false
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, -24)
	skip.Size = UDim2.fromOffset(190, 52)
	skip.BackgroundColor3 = PURPLE
	skip.AutoButtonColor = true
	skip.Font = FONT
	skip.TextSize = 24
	skip.TextColor3 = CREAM
	skip.Text = "ÜBERSPRINGEN ▶"
	skip.Visible = false
	skip.Parent = root
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0.5, 0)
	skipCorner.Parent = skip
	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = CREAM
	skipStroke.Thickness = 3
	skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	skipStroke.Parent = skip
	skip.Activated:Connect(function()
		if finished then
			return
		end
		AssetPreloader.cancel()
		finished = true
	end)
	task.delay(SKIP_AFTER, function()
		if not finished and skip.Parent then
			skip.Visible = true
		end
	end)

	-- Laden
	if not game:IsLoaded() then
		status.Text = "Verbinde …"
		game.Loaded:Wait()
	end
	local lastFraction = 0
	local function preload()
		local ok, problem = pcall(AssetPreloader.run, function(count: number, total: number, section: string)
			local fraction = if total > 0 then count / total else 1
			if fraction > lastFraction then
				lastFraction = fraction
				TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) }):Play()
			end
			status.Text = `Lädt {section} … {math.floor(lastFraction * 100 + 0.5)} %`
		end)
		if not ok then
			warn(`[ClayBattle] Vorladen abgebrochen: {problem}`)
		end
		finished = true -- auch bei einem Fehler weiter zum Menü
	end
	if not finished then -- schon übersprungen, während Roblox noch verbunden hat: gar nicht erst vorladen
		task.spawn(preload)
	end
	local started = os.clock()
	while not finished and os.clock() - started < MAX_WAIT do
		task.wait(0.1)
	end
	if os.clock() - started >= MAX_WAIT then
		AssetPreloader.cancel()
	end
	skip.Visible = false
	TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 1) }):Play()
	status.Text = "Fertig!"
	task.wait(0.25)
	done = true
	doneEvent:Fire()

	-- Ausblenden (jedes Element einzeln, ohne CanvasGroup)
	Fade.to(root, 1, 0.6)
	task.delay(0.65, function()
		connection:Disconnect()
		gui:Destroy()
	end)
end

return LoadingScreen
