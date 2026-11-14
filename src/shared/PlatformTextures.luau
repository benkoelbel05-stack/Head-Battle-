--!strict
-- Knet-Texturen für die Plattformen (Roblox-IMAGE-IDs).
--   tex  = Fläche (512 x 512, kachelbar), liegt auf der Vorderseite der Plattform
--   trim = Kante (512 x 128), liegt oben auf dem hellen Rand (z. B. Gras auf Erde)
-- In ArenaLayouts bekommt jede Plattform ein "material", z. B. material = "grass".

local Textures = {
	stone = 100644710923693,
	wood = 78244742680082,
	cheese = 91744391332634,
	dirt = 71884214731037,
	grass = 128595781820177,
	ice = 91765426722063,
	lava = 94119887868556,
	purple_clay = 102742265604041,
	snow = 109586056503657,
}

local Trims = {
	grass = 102013673595652,
	lava = 74430856514665,
	purple_clay = 77228275085435,
	snow = 102342609421760,
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
