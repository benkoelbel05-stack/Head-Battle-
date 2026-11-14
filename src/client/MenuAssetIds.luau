--!strict
-- Bild-IDs für das Hauptmenü (aus Menu_AssetIds.txt). Kurze Bildnamen, nicht die Datei-Pfad-Schlüssel
-- aus AssetIds_Approved.txt.
-- 0 = noch keine bestätigte, freigegebene ID. Dann zeigt das Menü einen Ersatz (Text-Logo, farbige
-- Knöpfe, Figuren aus den Spiel-Sprites). Hier müssen IMAGE-IDs stehen, keine Decal-IDs.

return {
	menu_background = 0,
	settings_background = 0,
	logo_clay_battle = 0,
	character_red_sword = 0,
	character_blue_jump = 0,
	character_yellow_shield = 0,
	character_green_hammer = 0,
	button_play = 0,
	button_options = 0,
	button_shop = 0,
	button_exit = 0,
	button_start_prompt = 0,
	arena_sunset = 0,
	arena_night = 0,
} :: { [string]: number }
