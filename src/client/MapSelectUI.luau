--!strict
-- Glücksrad vor jeder Runde (Phase "MapSelect"): Karte und Hintergrund wechseln schnell durch,
-- werden langsamer und bleiben auf der ausgelosten Kombination stehen (NextMap / NextBackground).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)

local MapSelectUI = {}

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.fromRGB(255, 246, 224)
local PURPLE = Color3.fromRGB(85, 49, 134)
local CREAM = Color3.fromRGB(255, 242, 219)

local BACKGROUND_NAMES: { [string]: string } = { ocean = "Meer", day = "Tag", sunset = "Sonnenuntergang", night = "Nacht" }
local BACKGROUND_ORDER = { "ocean", "day", "sunset", "night" }

function MapSelectUI.start()
	local player = Players.LocalPlayer
	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)

	-- Alle Karten (Anzeigename), fest sortiert
	local mapKeys: { string } = {}
	for key in ArenaLayouts do
		table.insert(mapKeys, key)
	end
	table.sort(mapKeys)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleMapSelect"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.48)
	card.Size = UDim2.fromOffset(560, 370)
	card.BackgroundColor3 = PURPLE
	card.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 30)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = CREAM
	cardStroke.Thickness = 5
	cardStroke.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromOffset(0, 10)
	heading.Size = UDim2.new(1, 0, 0, 40)
	heading.Font = FONT
	heading.TextSize = 30
	heading.TextColor3 = WHITE
	heading.Text = "NÄCHSTE ARENA"
	heading.Parent = card

	-- Vorschau: Hintergrundbild mit dem Kartennamen darüber
	local preview = Instance.new("ImageLabel")
	preview.Name = "Preview"
	preview.Position = UDim2.fromOffset(30, 56)
	preview.Size = UDim2.fromOffset(500, 230)
	preview.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
	preview.ScaleType = Enum.ScaleType.Crop
	preview.Parent = card
	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 20)
	previewCorner.Parent = preview

	local mapName = Instance.new("TextLabel")
	mapName.BackgroundTransparency = 1
	mapName.Size = UDim2.fromScale(1, 1)
	mapName.Font = FONT
	mapName.TextSize = 54
	mapName.TextColor3 = WHITE
	mapName.TextStrokeColor3 = Color3.fromRGB(50, 24, 70)
	mapName.TextStrokeTransparency = 0
	mapName.Parent = preview
	local nameScale = Instance.new("UIScale")
	nameScale.Parent = mapName

	local backgroundName = Instance.new("TextLabel")
	backgroundName.BackgroundTransparency = 1
	backgroundName.Position = UDim2.fromOffset(0, 296)
	backgroundName.Size = UDim2.new(1, 0, 0, 50)
	backgroundName.Font = FONT
	backgroundName.TextSize = 32
	backgroundName.TextColor3 = Color3.fromRGB(255, 214, 90)
	backgroundName.Parent = card

	local function show(mapKey: string, backgroundKey: string)
		local layout = ArenaLayouts[mapKey]
		mapName.Text = string.upper(if layout then layout.name else mapKey)
		local id = ArenaAssets[backgroundKey]
		preview.Image = if id then `rbxassetid://{id}` else ""
		-- Meer hat kein Bild (gezeichnet): Vorschau in Meerblau
		preview.BackgroundColor3 = if backgroundKey == "ocean" then Color3.fromRGB(56, 150, 226) else Color3.fromRGB(40, 30, 60)
		backgroundName.Text = BACKGROUND_NAMES[backgroundKey] or backgroundKey
	end

	local running = 0
	local function spin()
		running += 1
		local myRun = running
		task.wait(0.05) -- alle Attribute der neuen Phase abwarten (kommen im selben Paket, aber nacheinander)
		local endsAt = roundState:GetAttribute("EndsAt")
		local finalMap = roundState:GetAttribute("NextMap")
		local finalBackground = roundState:GetAttribute("NextBackground")
		if typeof(endsAt) ~= "number" or typeof(finalMap) ~= "string" or typeof(finalBackground) ~= "string" then
			return
		end
		gui.Enabled = true
		cardScale.Scale = 0.6
		TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		-- Durchwechseln, immer langsamer; ca. 0,9 s vor Schluss steht das Ergebnis
		local mapIndex = math.random(1, #mapKeys)
		local backgroundIndex = math.random(1, #BACKGROUND_ORDER)
		local interval = 0.06
		local landAt = endsAt - 0.9
		while myRun == running and Workspace:GetServerTimeNow() < landAt do
			mapIndex = mapIndex % #mapKeys + 1
			backgroundIndex = backgroundIndex % #BACKGROUND_ORDER + 1
			show(mapKeys[mapIndex], BACKGROUND_ORDER[backgroundIndex])
			task.wait(interval)
			interval = math.min(interval * 1.15, 0.3)
		end
		if myRun ~= running then
			return
		end
		show(finalMap, finalBackground)
		nameScale.Scale = 1.4
		TweenService:Create(nameScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		cardStroke.Color = Color3.fromRGB(255, 214, 90)
		task.wait(0.15)
		cardStroke.Color = CREAM
	end

	roundState:GetAttributeChangedSignal("Phase"):Connect(function()
		if roundState:GetAttribute("Phase") == "MapSelect" then
			task.spawn(spin)
		else
			running += 1
			gui.Enabled = false
		end
	end)
	if roundState:GetAttribute("Phase") == "MapSelect" then
		task.spawn(spin)
	end
end

return MapSelectUI
