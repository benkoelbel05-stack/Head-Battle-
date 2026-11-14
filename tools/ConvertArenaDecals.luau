-- Wandelt Decal-IDs (z. B. aus Open-Cloud-Uploads) in Image-IDs um. Die Liste DECALS bei Bedarf austauschen.
-- Roblox meldet diese Uploads als "Decal" – Texturen und Bildflächen im Spiel brauchen aber die Image-ID.
--
-- Benutzung:
--   1. Roblox Studio öffnen (angemeldet mit dem Konto, dem die Bilder gehören)
--   2. Dieses ganze Skript kopieren, in die Befehlsleiste einfügen (Ansicht -> Befehlsleiste), Enter
--   3. Im Output erscheint eine fertige Liste "name = ImageID". Die komplett an Claude schicken.

local InsertService = game:GetService("InsertService")

-- Nur nötig, wenn der Ladebildschirm in Studio meldet, dass diese Bilder nicht laden.
-- "FEHLER" bei einem Eintrag heißt meist: das ist schon eine Image-ID und passt so.
local DECALS = {
	icon_back = 103659282157847,
	icon_cancel = 135720387369837,
	icon_confirm = 117036000882566,
	icon_crown = 95644466899649,
	icon_exit = 136467943148126,
	icon_home = 85855978096404,
	icon_music = 80002238861874,
	icon_pause = 124564389148503,
	icon_play = 138238448957877,
	icon_settings_gear = 136688272736676,
	icon_shop_cart = 127960994806570,
	icon_sound = 101386347028651,
	prop_hammer_star = 85772871682967,
	prop_red_flag_left = 119817659521845,
	prop_red_flag_right = 122158699621985,
	prop_shield_star = 101887751852924,
	prop_sword = 115198525694506,
	button_optionen = 104053378200021,
	button_shop = 107318057720196,
	button_spielen = 76865933878187,
	button_verlassen = 79245000873262,
	button_zum_starten = 115580670848073,
	char_blue_jump = 86343583704928,
	char_green_hammer = 94421082607120,
	char_red_sword = 130431979826668,
	char_yellow_shield = 102024818087749,
	logo_clay_battle_hd = 107299522262948,
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
