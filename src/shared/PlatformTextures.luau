--!strict
-- Knet-Texturen für die Plattformen (Roblox-IMAGE-IDs, umgewandelt mit tools/ConvertArenaDecals.luau).
--   tex  = Fläche (512 x 512, kachelbar), liegt auf der Vorderseite der Plattform
--   trim = Kante (512 x 128), liegt oben auf dem hellen Rand (z. B. Gras auf Erde)
-- In ArenaLayouts bekommt jede Plattform ein "material", z. B. material = "grass".

local Textures = {
	stone = 74798227722916,
	wood = 81523256479120,
	cheese = 126067958864375,
	dirt = 95557357987203,
	grass = 89983785250381,
	ice = 78026613970796,
	lava = 110154795974533,
	purple_clay = 104955789397818,
	snow = 84715782404917,
}

local Trims = {
	grass = 140387261223350,
	lava = 103990847604397,
	purple_clay = 124293240412548,
	snow = 95652427740734,
}

export type Material = { tex: number, trim: number? }

local PlatformTextures: { [string]: Material } = {
	grass = { tex = Textures.grass, trim = Trims.grass },
	dirt = { tex = Textures.dirt, trim = Trims.grass },
	stone = { tex = Textures.stone, trim = Trims.grass },
	wood = { tex = Textures.wood },
	cheese = { tex = Textures.cheese },
	ice = { tex = Textures.ice, trim = Trims.snow },
	snow = { tex = Textures.snow, trim = Trims.snow },
	lava = { tex = Textures.lava, trim = Trims.lava },
	purple_clay = { tex = Textures.purple_clay, trim = Trims.purple_clay },
}

return PlatformTextures
