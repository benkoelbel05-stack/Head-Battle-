-- Wandelt die Decal-IDs der Arena-Bilder (Plattform-Texturen und Hintergründe) in Image-IDs um.
-- Roblox meldet diese Uploads als "Decal" – Texturen und Bildflächen im Spiel brauchen aber die Image-ID.
--
-- Benutzung:
--   1. Roblox Studio öffnen (angemeldet mit dem Konto, dem die Bilder gehören)
--   2. Dieses ganze Skript kopieren, in die Befehlsleiste einfügen (Ansicht -> Befehlsleiste), Enter
--   3. Im Output erscheint eine fertige Liste "name = ImageID". Die komplett an Claude schicken.

local InsertService = game:GetService("InsertService")

local DECALS = {
	tex_stone = 100644710923693,
	tex_wood = 78244742680082,
	tex_cheese = 91744391332634,
	tex_dirt = 71884214731037,
	tex_grass = 128595781820177,
	tex_ice = 91765426722063,
	tex_lava = 94119887868556,
	tex_purple_clay = 102742265604041,
	tex_snow = 109586056503657,
	trim_grass = 102013673595652,
	trim_lava = 74430856514665,
	trim_purple_clay = 77228275085435,
	trim_snow = 102342609421760,
	arena_day = 104043879202825,
	arena_sunset = 77320705436559,
	arena_night = 75529436510801,
}

local names = {}
for name in DECALS do
	table.insert(names, name)
end
table.sort(names)

local lines = {}
for _, name in names do
	local decalId = DECALS[name]
	local ok, result = pcall(function()
		return InsertService:LoadAsset(decalId)
	end)
	if not ok then
		table.insert(lines, `{name} = FEHLER ({result})`)
	else
		local loaded = result :: Instance
		local decal = loaded:FindFirstChildWhichIsA("Decal", true)
		local imageId = if decal then string.match(decal.Texture, "%d+") else nil
		table.insert(lines, `{name} = {imageId or "keine Decal gefunden"}`)
		loaded:Destroy()
	end
	task.wait(0.1)
end

print("[ConvertArenaDecals] FERTIG – diese Liste an Claude schicken:\n" .. table.concat(lines, "\n"))
