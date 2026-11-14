--!strict
-- Ladebildschirm beim Spielstart: liegt über allem, lädt einmal alle Bilder und Klänge vor
-- (AssetPreloader) und blendet dann zum Hauptmenü über. Zeigt einen hüpfenden Knetball und einen
-- Fortschrittsbalken. Spätestens nach MAX_WAIT geht es trotzdem weiter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetPreloader = require(script.Parent.AssetPreloader)

local LoadingScreen = {}

local done = false
local doneEvent = Instance.new("BindableEvent")

-- Wartet, bis der Ladebildschirm fertig ist (das Hauptmenü erscheint erst danach)
function LoadingScreen.waitUntilDone()
	if not done then
		doneEvent.Event:Wait()
	end
end

local MAX_WAIT = 60 -- Sekunden: länger wartet niemand
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
}

function LoadingScreen.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleLoading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")

	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundColor3 = Color3.new(1, 1, 1)
	group.BorderSizePixel = 0
	group.Parent = gui
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 150, 235)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(150, 205, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 205, 90)),
	})
	sky.Parent = group

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
		l.Parent = group
		return l
	end
	text("CLAY BATTLE", 0.28, 0.16, 110)

	-- Hüpfender Knetball (ohne Bild, damit er sofort da ist)
	local ball = Instance.new("Frame")
	ball.AnchorPoint = Vector2.new(0.5, 1)
	ball.Size = UDim2.fromScale(0.06, 0.06)
	ball.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ball.BackgroundColor3 = Color3.fromRGB(70, 130, 240)
	ball.Parent = group
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
	bar.Parent = group
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

	-- Laden
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local finished = false
	task.spawn(function()
		local ok, problem = pcall(AssetPreloader.run, function(count: number, total: number, section: string)
			local fraction = if total > 0 then count / total else 1
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) }):Play()
			status.Text = `Lädt {section} … {math.floor(fraction * 100 + 0.5)} %`
		end)
		if not ok then
			warn(`[ClayBattle] Vorladen abgebrochen: {problem}`)
		end
		finished = true -- auch bei einem Fehler weiter zum Menü
	end)
	local started = os.clock()
	while not finished and os.clock() - started < MAX_WAIT do
		task.wait(0.1)
	end
	status.Text = "Fertig!"
	task.wait(0.3)
	done = true
	doneEvent:Fire()

	-- Ausblenden
	local fade = TweenService:Create(group, TweenInfo.new(0.6), { GroupTransparency = 1 })
	fade.Completed:Once(function()
		connection:Disconnect()
		gui:Destroy()
	end)
	fade:Play()
end

return LoadingScreen
