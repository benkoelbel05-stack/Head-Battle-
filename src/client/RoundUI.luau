--!strict
-- Anzeige für das Rundensystem:
--   * oben Mitte: Nachricht ("Runde 2", "Knetbert gewinnt die Runde!") und Countdown
--   * oben links: Punkte aller Teilnehmer (ausgeschiedene grau)
--   * unten rechts: Knöpfe "+ Bot" / "– Bot"
-- Liest den Zustand aus ReplicatedStorage.RoundState (vom Server gesetzt).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local RoundUI = {}

local FONT = Enum.Font.FredokaOne
local TEXT_COLOR = Color3.fromRGB(255, 244, 226)
local STROKE_COLOR = Color3.fromRGB(58, 40, 34)
local PANEL_COLOR = Color3.fromRGB(58, 48, 44)

local function makeLabel(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeColor3 = STROKE_COLOR
	label.TextStrokeTransparency = 0
	label.Text = ""
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(110, 44)
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = PANEL_COLOR
	button.Font = FONT
	button.TextSize = 22
	button.TextColor3 = TEXT_COLOR
	button.Text = text
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button
	button.Parent = parent
	return button
end

function RoundUI.start()
	local player = Players.LocalPlayer
	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)
	local scores = roundState:WaitForChild("Scores")
	local changeBots = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER):WaitForChild("ChangeBots") :: RemoteEvent

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleRound"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Nachricht und Countdown
	local message = makeLabel(gui, "Message", UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 70), 38)
	local countdown = makeLabel(gui, "Countdown", UDim2.new(1, 0, 0, 120), UDim2.new(0, 0, 0.35, 0), 110)

	-- Punkte
	local board = Instance.new("Frame")
	board.Name = "Scores"
	board.Position = UDim2.fromOffset(16, 70)
	board.Size = UDim2.fromOffset(240, 0)
	board.AutomaticSize = Enum.AutomaticSize.Y
	board.BackgroundColor3 = PANEL_COLOR
	board.BackgroundTransparency = 0.25
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 14)
	boardCorner.Parent = board
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = board
	board.Parent = gui

	-- Bot-Knöpfe
	local addBot = makeButton(gui, "+ Bot", UDim2.new(1, -16, 1, -16))
	local removeBot = makeButton(gui, "– Bot", UDim2.new(1, -136, 1, -16))
	addBot.Activated:Connect(function()
		changeBots:FireServer(1)
	end)
	removeBot.Activated:Connect(function()
		changeBots:FireServer(-1)
	end)

	local function refreshScores()
		for _, child in board:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local winPoints = roundState:GetAttribute("WinPoints") or Constants.WIN_POINTS
		local entries = scores:GetChildren()
		table.sort(entries, function(a, b)
			return (a :: IntValue).Value > (b :: IntValue).Value
		end)
		for index, entry in entries do
			local value = entry :: IntValue
			local alive = value:GetAttribute("Alive") ~= false
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundTransparency = 1
			row.LayoutOrder = index

			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(16, 16)
			dot.Position = UDim2.new(0, 0, 0.5, -8)
			local color = value:GetAttribute("Color")
			dot.BackgroundColor3 = if typeof(color) == "Color3" then color else TEXT_COLOR
			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot
			dot.Parent = row

			local name = makeLabel(row, "Name", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(24, 0), 20)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local displayName = value:GetAttribute("DisplayName")
			name.Text = (if typeof(displayName) == "string" then displayName else value.Name)
				.. (if value:GetAttribute("IsBot") then " (Bot)" else "")
			local points = makeLabel(row, "Points", UDim2.new(0, 56, 1, 0), UDim2.new(1, -56, 0, 0), 20)
			points.TextXAlignment = Enum.TextXAlignment.Right
			points.Text = `{value.Value} / {winPoints}`

			local fade = if alive then 0 else 0.6
			name.TextTransparency = fade
			points.TextTransparency = fade
			dot.BackgroundTransparency = fade
			row.Parent = board
		end
	end

	local lastRefresh = 0
	local lastPhase: unknown = nil
	local goShownAt = 0
	while true do
		local phase = roundState:GetAttribute("Phase")
		local text = roundState:GetAttribute("Message")
		message.Text = if typeof(text) == "string" then text else ""

		-- Countdown-Zahl, beim Start kurz "Los!"
		local endsAt = roundState:GetAttribute("EndsAt")
		if phase == "Countdown" and typeof(endsAt) == "number" then
			local remaining = math.ceil(endsAt - Workspace:GetServerTimeNow())
			countdown.Text = if remaining > 0 then tostring(remaining) else "Los!"
		elseif phase == "Playing" and lastPhase == "Countdown" then
			countdown.Text = "Los!"
			goShownAt = os.clock()
		elseif phase ~= "Playing" or os.clock() - goShownAt > 0.7 then
			countdown.Text = ""
		end
		lastPhase = phase

		if os.clock() - lastRefresh > 0.25 then
			lastRefresh = os.clock()
			refreshScores()
		end
		task.wait(0.05)
	end
end

return RoundUI
