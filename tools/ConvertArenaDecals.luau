-- Wandelt Decal-IDs (z. B. aus Open-Cloud-Uploads) in Image-IDs um. Die Liste DECALS bei Bedarf austauschen.
-- Roblox meldet diese Uploads als "Decal" – Texturen und Bildflächen im Spiel brauchen aber die Image-ID.
--
-- Benutzung:
--   1. Roblox Studio öffnen (angemeldet mit dem Konto, dem die Bilder gehören)
--   2. Dieses ganze Skript kopieren, in die Befehlsleiste einfügen (Ansicht -> Befehlsleiste), Enter
--   3. Im Output erscheint eine fertige Liste "name = ImageID". Die komplett an Claude schicken.

local InsertService = game:GetService("InsertService")

local DECALS = {
	panel_abilities_blue = 124225716447370,
	panel_bot_green = 136969832694743,
	panel_bot_purple = 86310988857689,
	panel_bot_yellow = 116136309972021,
	panel_player_orange = 127788199510580,
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
