--!strict
-- Einheitlicher Look für alle Anzeigen im Spiel: Knet-Lila mit cremefarbenem Rand und leichtem Glanz.
-- (Hauptmenü und Optionen haben ihren eigenen Stil und nutzen das nicht.)

local UIStyle = {}

UIStyle.FONT = Enum.Font.FredokaOne
UIStyle.PANEL = Color3.fromRGB(85, 49, 134)
UIStyle.PANEL_DARK = Color3.fromRGB(60, 34, 98)
UIStyle.RIM = Color3.fromRGB(250, 238, 214)
UIStyle.TEXT = Color3.fromRGB(255, 250, 240)
UIStyle.TEXT_STROKE = Color3.fromRGB(50, 24, 70)
UIStyle.ACCENT = Color3.fromRGB(236, 108, 51)

-- Glanz: oben etwas heller, unten etwas dunkler. Nur für Flächen ohne Text (ein UIGradient färbt
-- auch die Schrift ein).
function UIStyle.gloss(parent: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	gradient.Parent = parent
end

-- Fläche im Spiel-Look: Farbe, runde Ecken, Rand, Glanz
function UIStyle.panel(frame: GuiObject, color: Color3?, radius: number?)
	frame.BackgroundColor3 = color or UIStyle.PANEL
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	local corner = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIStyle.RIM
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	if not frame:IsA("TextLabel") and not frame:IsA("TextButton") then
		UIStyle.gloss(frame)
	end
end

-- Schrift im Spiel-Look (weiß mit dunklem Rand)
function UIStyle.text(label: TextLabel | TextButton)
	label.Font = UIStyle.FONT
	label.TextColor3 = UIStyle.TEXT
	label.TextStrokeColor3 = UIStyle.TEXT_STROKE
	label.TextStrokeTransparency = 0.4
end

return UIStyle
