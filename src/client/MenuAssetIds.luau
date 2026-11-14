--!strict
-- Bild-IDs für das Hauptmenü (aus Menu_AssetIds.txt). Kurze Bildnamen, nicht die Datei-Pfad-Schlüssel
-- aus AssetIds_Approved.txt.
-- 0 = noch keine bestätigte, freigegebene ID. Dann zeigt das Menü einen Ersatz (Text-Logo, farbige
-- Knöpfe, Figuren aus den Spiel-Sprites). Hier müssen IMAGE-IDs stehen, keine Decal-IDs.

return {
	menu_background = 102278082298675,
	settings_background = 90513161932618, -- nicht benutzt (Optionen liegen über dem Titelbild)
	logo_clay_battle = 108060134585257,
	character_red_sword = 119822554427267,
	character_blue_jump = 90465783794271,
	character_yellow_shield = 109952360172830,
	character_green_hammer = 127909036725205,
	button_play = 94014650594529,
	button_options = 87472846432339,
	button_shop = 137758145357653,
	button_exit = 73354850763082,
	button_start_prompt = 137425263851321, -- nicht benutzt (Knopf entfernt)
	arena_sunset = 73285968060700,
	arena_night = 85048047291829,
	-- Musik im Hauptmenü (Audio-ID aus dem Creator Hub; 0 = keine Musik)
	menu_theme = 0, -- echobrainz-retro-arcade.mp3
} :: { [string]: number }
