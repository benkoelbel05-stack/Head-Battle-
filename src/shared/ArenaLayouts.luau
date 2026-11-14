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
local TON = Color3.fromRGB(190, 104, 76)
local HIMMEL = Color3.fromRGB(104, 150, 196)

local ArenaLayouts: { [string]: Layout } = {}

ArenaLayouts.Basteltisch = {
	name = "Basteltisch",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(60, 4), color = MOOS }, -- Hauptboden
		{ position = Vector2.new(-22, 14), size = Vector2.new(14, 2), color = SENF, density = 3 },
		{ position = Vector2.new(22, 14), size = Vector2.new(14, 2), color = SENF, density = 3 },
		{ position = Vector2.new(0, 26), size = Vector2.new(16, 2), color = PFLAUME, density = 2.5 },
		{ position = Vector2.new(-40, 7), size = Vector2.new(8, 2), color = PFLAUME, density = 2.5 },
		{ position = Vector2.new(40, 7), size = Vector2.new(8, 2), color = PFLAUME, density = 2.5 },
	},
	spawns = {
		Vector2.new(-20, 6),
		Vector2.new(20, 6),
		Vector2.new(-22, 18),
		Vector2.new(22, 18),
	},
	backgroundColor = Color3.fromRGB(58, 48, 44), -- dunkle Werkstatt
}

-- Schwebende Inseln ohne festen Boden
ArenaLayouts.Schwebeinseln = {
	name = "Schwebeinseln",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(22, 3), color = MOOS },
		{ position = Vector2.new(-26, 8), size = Vector2.new(14, 2), color = SENF, density = 2 },
		{ position = Vector2.new(26, 8), size = Vector2.new(14, 2), color = SENF, density = 2 },
		{ position = Vector2.new(-14, 20), size = Vector2.new(12, 2), color = HIMMEL, density = 2 },
		{ position = Vector2.new(14, 20), size = Vector2.new(12, 2), color = HIMMEL, density = 2 },
		{ position = Vector2.new(0, 31), size = Vector2.new(10, 2), color = PFLAUME, density = 2.5 },
		{ position = Vector2.new(-42, -6), size = Vector2.new(10, 2), color = TON, density = 1.5 },
		{ position = Vector2.new(42, -6), size = Vector2.new(10, 2), color = TON, density = 1.5 },
	},
	spawns = {
		Vector2.new(-6, 4),
		Vector2.new(6, 4),
		Vector2.new(-26, 11),
		Vector2.new(26, 11),
	},
	backgroundColor = Color3.fromRGB(44, 58, 78),
}

-- Zwei Ufer und eine Zickzack-Treppe in der Mitte
ArenaLayouts.Knettreppe = {
	name = "Knettreppe",
	platforms = {
		{ position = Vector2.new(-30, -4), size = Vector2.new(24, 3), color = TON },
		{ position = Vector2.new(30, -4), size = Vector2.new(24, 3), color = TON },
		{ position = Vector2.new(0, 6), size = Vector2.new(16, 2), color = PFLAUME, density = 2 },
		{ position = Vector2.new(-22, 16), size = Vector2.new(14, 2), color = SENF, density = 2.5 },
		{ position = Vector2.new(22, 16), size = Vector2.new(14, 2), color = SENF, density = 2.5 },
		{ position = Vector2.new(0, 26), size = Vector2.new(20, 2), color = MOOS, density = 2 },
	},
	spawns = {
		Vector2.new(-30, 0),
		Vector2.new(30, 0),
		Vector2.new(-22, 19),
		Vector2.new(22, 19),
	},
	backgroundColor = Color3.fromRGB(70, 46, 40),
}

-- Lange, leichte (wackelige) Brücke mit Inseln darüber
ArenaLayouts.Wackelbruecke = {
	name = "Wackelbrücke",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(70, 2), color = MOOS, density = 0.6 },
		{ position = Vector2.new(-18, 14), size = Vector2.new(10, 2), color = SENF, density = 3 },
		{ position = Vector2.new(18, 14), size = Vector2.new(10, 2), color = SENF, density = 3 },
		{ position = Vector2.new(0, 24), size = Vector2.new(8, 2), color = PFLAUME, density = 2 },
		{ position = Vector2.new(-46, 12), size = Vector2.new(6, 2), color = HIMMEL, density = 2 },
		{ position = Vector2.new(46, 12), size = Vector2.new(6, 2), color = HIMMEL, density = 2 },
	},
	spawns = {
		Vector2.new(-24, 3),
		Vector2.new(24, 3),
		Vector2.new(-8, 3),
		Vector2.new(8, 3),
	},
	backgroundColor = Color3.fromRGB(40, 52, 46),
}

return ArenaLayouts
