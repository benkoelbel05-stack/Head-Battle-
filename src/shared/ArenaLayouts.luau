--!strict
-- Arena-Layouts. Positionen sind die Mitte jeder Plattform (X = links/rechts, Y = oben/unten).
-- Die Tiefe (Z) setzt Arena.luau automatisch.

export type Platform = {
	position: Vector2,
	size: Vector2,
	color: Color3,
	density: number?, -- optional: schwerer (> 1) oder leichter (< 1) als normal
	material: string?, -- optional: Knet-Textur aus PlatformTextures (z. B. "grass", "stone", "ice")
	rotation: number?, -- optional: Neigung in Grad (gegen den Uhrzeigersinn)
}

export type Layout = {
	name: string,
	platforms: { Platform },
	spawns: { Vector2 },
	backgroundColor: Color3,
	waterLevel: number?, -- optional: Wasser am unteren Rand; wer hineinfällt, scheidet aus
}

local MOOS = Color3.fromRGB(110, 132, 78)
local SENF = Color3.fromRGB(196, 160, 70)
local PFLAUME = Color3.fromRGB(112, 74, 104)
local TON = Color3.fromRGB(190, 104, 76)
local HIMMEL = Color3.fromRGB(104, 150, 196)

local ArenaLayouts: { [string]: Layout } = {}

-- Karten im Stil von Bopl Battle: dicke, runde Knet-Inseln (auch ganze Kreise und schräge Würste),
-- die unteren stehen im Wasser. Größe = Breite x Höhe; ist beides gleich, wird es ein Kreis.

ArenaLayouts.Basteltisch = {
	name = "Basteltisch",
	platforms = {
		{ position = Vector2.new(0, -4), size = Vector2.new(44, 10), color = MOOS, material = "dirt", density = 0.55 },
		{ position = Vector2.new(-34, -5), size = Vector2.new(12, 12), color = MOOS, material = "grass", density = 0.6 },
		{ position = Vector2.new(34, -5), size = Vector2.new(12, 12), color = MOOS, material = "grass", density = 0.6 },
		{ position = Vector2.new(-24, 14), size = Vector2.new(18, 6), color = SENF, material = "stone", density = 0.6, rotation = 12 },
		{ position = Vector2.new(24, 14), size = Vector2.new(18, 6), color = SENF, material = "stone", density = 0.6, rotation = -12 },
		{ position = Vector2.new(0, 25), size = Vector2.new(10, 10), color = SENF, material = "cheese", density = 0.5 },
	},
	spawns = {
		Vector2.new(-12, 3),
		Vector2.new(12, 3),
		Vector2.new(-24, 19),
		Vector2.new(24, 19),
	},
	backgroundColor = Color3.fromRGB(58, 48, 44),
	waterLevel = -6,
}

ArenaLayouts.Schwebeinseln = {
	name = "Schwebeinseln",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(14, 14), color = MOOS, material = "grass", density = 0.5 },
		{ position = Vector2.new(-24, 8), size = Vector2.new(10, 10), color = SENF, material = "stone", density = 0.6 },
		{ position = Vector2.new(24, 8), size = Vector2.new(10, 10), color = SENF, material = "stone", density = 0.6 },
		{ position = Vector2.new(-12, 23), size = Vector2.new(8, 8), color = HIMMEL, material = "ice", density = 0.6 },
		{ position = Vector2.new(12, 23), size = Vector2.new(8, 8), color = HIMMEL, material = "ice", density = 0.6 },
		{ position = Vector2.new(-40, -9), size = Vector2.new(16, 7), color = TON, material = "lava", density = 0.5, rotation = 20 },
		{ position = Vector2.new(40, -9), size = Vector2.new(16, 7), color = TON, material = "lava", density = 0.5, rotation = -20 },
	},
	spawns = {
		Vector2.new(-4, 9),
		Vector2.new(4, 9),
		Vector2.new(-24, 15),
		Vector2.new(24, 15),
	},
	backgroundColor = Color3.fromRGB(44, 58, 78),
	waterLevel = -12,
}

-- Schräge Würste wie im Vorbild
ArenaLayouts.Knettreppe = {
	name = "Knettreppe",
	platforms = {
		{ position = Vector2.new(-30, -6), size = Vector2.new(30, 7), color = TON, material = "dirt", density = 0.5, rotation = 18 },
		{ position = Vector2.new(30, -6), size = Vector2.new(30, 7), color = TON, material = "dirt", density = 0.5, rotation = -18 },
		{ position = Vector2.new(0, 4), size = Vector2.new(22, 6), color = PFLAUME, material = "purple_clay", density = 0.5 },
		{ position = Vector2.new(-22, 18), size = Vector2.new(20, 6), color = SENF, material = "cheese", density = 0.5, rotation = -15 },
		{ position = Vector2.new(22, 18), size = Vector2.new(20, 6), color = SENF, material = "cheese", density = 0.5, rotation = 15 },
		{ position = Vector2.new(0, 30), size = Vector2.new(14, 5), color = MOOS, material = "grass", density = 0.6 },
	},
	spawns = {
		Vector2.new(-4, 9),
		Vector2.new(4, 9),
		Vector2.new(-22, 23),
		Vector2.new(22, 23),
	},
	backgroundColor = Color3.fromRGB(70, 46, 40),
	waterLevel = -10,
}

-- Lange, leichte (wackelige) Brücke zwischen zwei Felsen im Wasser
ArenaLayouts.Wackelbruecke = {
	name = "Wackelbrücke",
	platforms = {
		{ position = Vector2.new(0, 0), size = Vector2.new(64, 4), color = MOOS, material = "wood", density = 0.3 },
		{ position = Vector2.new(-40, -6), size = Vector2.new(12, 12), color = SENF, material = "stone", density = 0.6 },
		{ position = Vector2.new(40, -6), size = Vector2.new(12, 12), color = SENF, material = "stone", density = 0.6 },
		{ position = Vector2.new(-16, 14), size = Vector2.new(12, 6), color = HIMMEL, material = "snow", density = 0.6 },
		{ position = Vector2.new(16, 14), size = Vector2.new(12, 6), color = HIMMEL, material = "snow", density = 0.6 },
		{ position = Vector2.new(0, 26), size = Vector2.new(9, 9), color = PFLAUME, material = "purple_clay", density = 0.5 },
	},
	spawns = {
		Vector2.new(-24, 4),
		Vector2.new(24, 4),
		Vector2.new(-8, 4),
		Vector2.new(8, 4),
	},
	backgroundColor = Color3.fromRGB(40, 52, 46),
	waterLevel = -8,
}

return ArenaLayouts
