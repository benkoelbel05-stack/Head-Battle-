--!strict
-- Kleine Abfragen zur aktuellen Arena, die Server und Client brauchen.

local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Constants)

local ArenaInfo = {}

-- Ab dieser Höhe ist man ausgeschieden: die Wasseroberfläche der Karte (falls sie Wasser hat),
-- sonst die allgemeine Fallgrenze.
function ArenaInfo.fallLimit(): number
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	local water = arena and arena:GetAttribute("WaterLevel")
	return if typeof(water) == "number" then water else Constants.FALL_LIMIT_Y
end

return ArenaInfo
