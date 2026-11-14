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

-- rim = Farbe des Rands rundherum, rimTex = Textur auf dem Rand (z. B. Gras rund um Erde)
export type Material = { tex: number, trim: number?, rim: Color3, rimTex: number? }

local GRASS_RIM = Color3.fromRGB(122, 196, 62)

local PlatformTextures: { [string]: Material } = {
	grass = { tex = Textures.grass, trim = Trims.grass, rim = GRASS_RIM, rimTex = Textures.grass },
	dirt = { tex = Textures.dirt, trim = Trims.grass, rim = GRASS_RIM, rimTex = Textures.grass },
	stone = { tex = Textures.stone, trim = Trims.grass, rim = GRASS_RIM, rimTex = Textures.grass },
	wood = { tex = Textures.wood, rim = Color3.fromRGB(214, 160, 100) },
	cheese = { tex = Textures.cheese, rim = Color3.fromRGB(252, 218, 112) },
	ice = { tex = Textures.ice, trim = Trims.snow, rim = Color3.fromRGB(236, 246, 255), rimTex = Textures.snow },
	snow = { tex = Textures.snow, trim = Trims.snow, rim = Color3.fromRGB(240, 246, 255), rimTex = Textures.snow },
	lava = { tex = Textures.lava, trim = Trims.lava, rim = Color3.fromRGB(255, 150, 60) },
	purple_clay = { tex = Textures.purple_clay, trim = Trims.purple_clay, rim = Color3.fromRGB(196, 128, 236) },
}

return PlatformTextures
