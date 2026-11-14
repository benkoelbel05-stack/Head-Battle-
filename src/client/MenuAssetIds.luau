--!strict
-- Bild-IDs für das Hauptmenü. Kurze Bildnamen, nicht die Datei-Pfad-Schlüssel aus AssetIds_Approved.txt.
-- 0 = noch keine bestätigte, freigegebene ID. Dann zeigt das Menü einen Ersatz (Text-Logo, farbige
-- Knöpfe, Figuren aus den Spiel-Sprites). Hier müssen IMAGE-IDs stehen, keine Decal-IDs.
-- Die freigestellten Versionen vom 14.11. sind Decal-IDs (stehen dahinter). Bis sie mit
-- tools/ConvertArenaDecals.luau umgewandelt sind, bleiben hier die alten, funktionierenden Bilder.

return {
	menu_background = 102278082298675,
	settings_background = 90513161932618, -- nicht benutzt (Optionen liegen über dem Titelbild)
	logo_clay_battle = 108060134585257, -- HD-Version (Decal 107299522262948) kommt nach dem Umwandeln
	character_red_sword = 119822554427267, -- freigestellt: Decal 130431979826668
	character_blue_jump = 90465783794271, -- freigestellt: Decal 86343583704928
	character_yellow_shield = 109952360172830, -- freigestellt: Decal 102024818087749
	character_green_hammer = 127909036725205, -- freigestellt: Decal 94421082607120
	button_play = 94014650594529, -- freigestellt: Decal 76865933878187
	button_options = 87472846432339, -- freigestellt: Decal 104053378200021
	button_shop = 137758145357653, -- freigestellt: Decal 107318057720196
	button_exit = 73354850763082, -- freigestellt: Decal 79245000873262
	button_start_prompt = 137425263851321, -- nicht benutzt (Knopf entfernt); freigestellt: Decal 115580670848073
	arena_sunset = 73285968060700,
	arena_night = 85048047291829,
	-- Requisiten (freigestellt)
	prop_red_flag_left = 0, -- Fahne links neben dem Logo (Decal 119817659521845)
	prop_red_flag_right = 0, -- Fahne rechts neben dem Logo (Decal 122158699621985)
	prop_hammer_star = 0, -- noch nicht platziert (Decal 85772871682967)
	prop_shield_star = 0, -- noch nicht platziert (Decal 101887751852924)
	prop_sword = 0, -- noch nicht platziert (Decal 115198525694506)
	-- Musik im Hauptmenü (Audio-ID aus dem Creator Hub; 0 = keine Musik)
	menu_theme = 71059893920309, -- echobrainz-retro-arcade.mp3
} :: { [string]: number }
