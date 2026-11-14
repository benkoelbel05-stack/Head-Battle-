--!strict
-- Bild-IDs für das Hauptmenü. Kurze Bildnamen, nicht die Datei-Pfad-Schlüssel aus AssetIds_Approved.txt.
-- 0 = noch keine bestätigte, freigegebene ID. Dann zeigt das Menü einen Ersatz (Text-Logo, farbige
-- Knöpfe, Figuren aus den Spiel-Sprites). Hier müssen IMAGE-IDs stehen, keine Decal-IDs.
-- Stand: freigestellte Versionen (Knöpfe, Figuren, HD-Logo) vom 14.11.

return {
	menu_background = 102278082298675,
	settings_background = 90513161932618, -- nicht benutzt (Optionen liegen über dem Titelbild)
	logo_clay_battle = 107299522262948, -- logo_clay_battle_hd
	character_red_sword = 130431979826668, -- char_red_sword
	character_blue_jump = 86343583704928, -- char_blue_jump
	character_yellow_shield = 102024818087749, -- char_yellow_shield
	character_green_hammer = 94421082607120, -- char_green_hammer
	button_play = 76865933878187, -- button_spielen
	button_options = 104053378200021, -- button_optionen
	button_shop = 107318057720196,
	button_exit = 79245000873262, -- button_verlassen
	button_start_prompt = 115580670848073, -- button_zum_starten (nicht benutzt, Knopf entfernt)
	arena_sunset = 73285968060700,
	arena_night = 85048047291829,
	-- Requisiten (freigestellt)
	prop_red_flag_left = 119817659521845, -- Fahne links neben dem Logo
	prop_red_flag_right = 122158699621985, -- Fahne rechts neben dem Logo
	prop_hammer_star = 85772871682967, -- noch nicht platziert
	prop_shield_star = 101887751852924, -- noch nicht platziert
	prop_sword = 115198525694506, -- noch nicht platziert
	-- Musik im Hauptmenü (Audio-ID aus dem Creator Hub; 0 = keine Musik)
	menu_theme = 71059893920309, -- echobrainz-retro-arcade.mp3
} :: { [string]: number }
