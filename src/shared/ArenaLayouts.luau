--!strict
-- Arena-Layouts. Positionen sind die Mitte jeder Plattform (X = links/rechts, Y = oben/unten).
-- Die Tiefe (Z) setzt Arena.luau automatisch.

export type Platform = {
	position: Vector2,
	size: Vector2,
	color: Color3,
	density: number?, -- optional: schwerer (> 1) oder leichter (< 1) als normal
}

export type Layout = {
	name: string,
	platforms: { Platform },
	spawns: { Vector2 },
	backgroundColor: Color3,
}

local MOOS = Color3.fromRGB(110, 132, 78)
local SENF = Color3.fromRGB(196, 160, 70)
local PFLAUME = Color3.fromRGB(112, 74, 104)

local ArenaLayouts: { [string]: Layout } = {}

ArenaLayouts.Basteltisch = {
	name = "Basteltisch",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(60, 4), color = MOOS }, -- Hauptboden
		{ position = Vector2.new(-22, 14), size = Vector2.new(14, 2), color = SENF },
		{ position = Vector2.new(22, 14), size = Vector2.new(14, 2), color = SENF },
		{ position = Vector2.new(0, 26), size = Vector2.new(16, 2), color = PFLAUME, density = 0.7 }, -- leicht
		{ position = Vector2.new(-40, 7), size = Vector2.new(8, 2), color = PFLAUME, density = 0.7 },
		{ position = Vector2.new(40, 7), size = Vector2.new(8, 2), color = PFLAUME, density = 0.7 },
	},
	spawns = {
		Vector2.new(-20, 6),
		Vector2.new(20, 6),
		Vector2.new(-22, 18),
		Vector2.new(22, 18),
	},
	backgroundColor = Color3.fromRGB(58, 48, 44), -- dunkle Werkstatt
}

return ArenaLayouts
