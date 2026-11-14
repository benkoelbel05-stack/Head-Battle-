-- Wandelt Decal-IDs (z. B. aus Open-Cloud-Uploads) in Image-IDs um. Die Liste DECALS bei Bedarf austauschen.
-- Roblox meldet diese Uploads als "Decal" – Texturen und Bildflächen im Spiel brauchen aber die Image-ID.
--
-- Benutzung:
--   1. Roblox Studio öffnen (angemeldet mit dem Konto, dem die Bilder gehören)
--   2. Dieses ganze Skript kopieren, in die Befehlsleiste einfügen (Ansicht -> Befehlsleiste), Enter
--   3. Im Output erscheint eine fertige Liste "name = ImageID". Die komplett an Claude schicken.

local InsertService = game:GetService("InsertService")

local DECALS = {
	ability_dash = 133589046424620,
	ability_grenade = 115182418895603,
	ability_missile = 133740377680607,
	ability_sword = 70909575194183,
	ability_thruster = 113745614423780,
	icon_arrow_left = 72288701381741,
	icon_arrow_right = 136796167336045,
	icon_check_cream = 120038562063595,
	icon_minus = 71367765696394,
	icon_mouse = 119228889141929,
	icon_play_triangle = 84028554424940,
	icon_plus = 113016617157508,
	bot_control_bar_static = 106382209174968,
	button_ready_orange = 115094442191254,
	button_spielen = 110760932849666,
	player_slot_empty = 124154352933672,
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
