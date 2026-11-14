-- Wandelt Decal-IDs (z. B. aus Open-Cloud-Uploads) in Image-IDs um. Die Liste DECALS bei Bedarf austauschen.
-- Roblox meldet diese Uploads als "Decal" – Texturen und Bildflächen im Spiel brauchen aber die Image-ID.
--
-- Benutzung:
--   1. Roblox Studio öffnen (angemeldet mit dem Konto, dem die Bilder gehören)
--   2. Dieses ganze Skript kopieren, in die Befehlsleiste einfügen (Ansicht -> Befehlsleiste), Enter
--   3. Im Output erscheint eine fertige Liste "name = ImageID". Die komplett an Claude schicken.

local InsertService = game:GetService("InsertService")

local DECALS = {
	wolken_links = 130289073994565,
	wolken_rechts = 126053989467059,
	wolken_fern_gesamt = 75855415667887,
	wolke_klein_01 = 73531826914109,
	wolke_klein_02 = 114695650889992,
	wolke_klein_03 = 79818936500332,
	wolke_klein_04 = 93198978993068,
	wolke_klein_05 = 114974578305828,
	wolke_klein_06 = 103860179237170,
	wolke_klein_07 = 103403569038967,
	wolke_klein_08 = 131678906702333,
	ocean_water_base = 128025805325965,
	ocean_water_shimmer = 116982427595679,
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
