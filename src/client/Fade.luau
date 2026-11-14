--!strict
-- Weiches Ein- und Ausblenden ganzer Oberflächen OHNE CanvasGroup.
-- Eine CanvasGroup malt ihren Inhalt erst in ein Zwischenbild; Roblox verkleinert dieses Bild bei wenig
-- Grafikspeicher oder niedriger Grafikstufe, dann wirkt alles darin unscharf. Stattdessen blendet Fade
-- jedes einzelne Element (Bild, Text, Fläche, Rand) von seiner eigenen Transparenz aus.
--
--   Fade.to(frame, 1, 0)       sofort unsichtbar
--   Fade.to(frame, 0, 0.4)     in 0,4 s wieder ganz sichtbar
--   Fade.to(frame, 0.15, 0.2)  leicht abgedunkelt (15 % durchsichtiger)
--
-- Die "eigene" Transparenz jedes Elements wird beim ersten Aufruf gemerkt. Darum Fade.to erst aufrufen,
-- wenn die Oberfläche fertig gebaut und sichtbar eingestellt ist. Elemente, die später dazukommen,
-- werden beim nächsten Aufruf mit ihrem dann aktuellen Wert gemerkt.

local TweenService = game:GetService("TweenService")

local Fade = {}

local FIELDS: { [string]: { string } } = {
	Frame = { "BackgroundTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	UIStroke = { "Transparency" },
}

-- Grundwerte werden als Attribut am Element selbst gemerkt ("FadeBase_<Eigenschaft>"): so bleiben sie
-- erhalten, solange das Element lebt, und verschwinden mit ihm.
local function baseValue(item: Instance, field: string): number
	local key = `FadeBase_{field}`
	local stored = item:GetAttribute(key)
	if typeof(stored) == "number" then
		return stored
	end
	local value = (item :: any)[field] :: number
	item:SetAttribute(key, value)
	return value
end

-- Grundwert neu setzen (wenn ein Skript die Transparenz eines Elements absichtlich ändert)
function Fade.setBase(item: Instance, field: string, value: number)
	item:SetAttribute(`FadeBase_{field}`, value)
end

-- Laufende Blenden je Element (eine neue Blende bricht die alte ab)
local running: { [Instance]: Tween } = {}

function Fade.to(root: Instance, alpha: number, seconds: number, style: Enum.EasingStyle?)
	local info = TweenInfo.new(math.max(seconds, 0), style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function apply(item: Instance)
		local fields = FIELDS[item.ClassName]
		if not fields then
			return
		end
		local goal: { [string]: number } = {}
		for _, field in fields do
			local base = baseValue(item, field)
			goal[field] = base + (1 - base) * alpha
		end
		local previous = running[item]
		if previous then
			previous:Cancel()
			running[item] = nil
		end
		if seconds <= 0 then
			for field, value in goal do
				(item :: any)[field] = value
			end
		else
			local tween = TweenService:Create(item, info, goal)
			running[item] = tween
			tween.Completed:Once(function()
				if running[item] == tween then
					running[item] = nil
				end
			end)
			tween:Play()
		end
	end
	apply(root)
	for _, item in root:GetDescendants() do
		apply(item)
	end
end

return Fade
