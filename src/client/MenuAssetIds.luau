--!strict
-- Bild-IDs für das Hauptmenü. Kurze Bildnamen, nicht die Datei-Pfad-Schlüssel aus AssetIds_Approved.txt.
-- 0 = noch keine bestätigte, freigegebene ID. Dann zeigt das Menü einen Ersatz (Text-Logo, farbige
-- Knöpfe, Figuren aus den Spiel-Sprites). Hier müssen IMAGE-IDs stehen, keine Decal-IDs.
-- Freigestellte Versionen vom 14.11., umgewandelt mit tools/ConvertArenaDecals.luau (Decal-ID dahinter).

return {
	menu_background = 102278082298675,
	settings_background = 90513161932618, -- nicht benutzt (Optionen liegen über dem Titelbild)
	logo_clay_battle = 130494141667352, -- logo_clay_battle_hd (Decal 107299522262948)
	character_red_sword = 135414162282637, -- char_red_sword (Decal 130431979826668)
	character_blue_jump = 139697369164890, -- char_blue_jump (Decal 86343583704928)
	character_yellow_shield = 126304860089531, -- char_yellow_shield (Decal 102024818087749)
	character_green_hammer = 140732157935823, -- char_green_hammer (Decal 94421082607120)
	button_play = 79638055814174, -- button_spielen (Decal 76865933878187)
	button_options = 99817727413107, -- button_optionen (Decal 104053378200021)
	button_shop = 108853186037963, -- button_shop (Decal 107318057720196)
	button_exit = 80484737427961, -- button_verlassen (Decal 79245000873262)
	button_start_prompt = 120618529940598, -- button_zum_starten, nicht benutzt (Decal 115580670848073)
	arena_sunset = 73285968060700,
	arena_night = 85048047291829,
	-- Requisiten (freigestellt)
	prop_red_flag_left = 85026269947215, -- Fahne links neben dem Logo (Decal 119817659521845)
	prop_red_flag_right = 95103356777266, -- Fahne rechts neben dem Logo (Decal 122158699621985)
	prop_hammer_star = 120399468373303, -- noch nicht platziert (Decal 85772871682967)
	prop_shield_star = 109160301114424, -- noch nicht platziert (Decal 101887751852924)
	prop_sword = 110679197349244, -- noch nicht platziert (Decal 115198525694506)
	-- Musik im Hauptmenü (Audio-ID aus dem Creator Hub; 0 = keine Musik)
	menu_theme = 71059893920309, -- echobrainz-retro-arcade.mp3
} :: { [string]: number }
