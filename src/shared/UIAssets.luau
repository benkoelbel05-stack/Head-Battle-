--!strict
-- Bild-IDs der Bedienelemente (Roblox-IMAGE-IDs; Decal-IDs vorher mit tools/ConvertArenaDecals.luau umwandeln).
-- 0 = kein Bild: dann zeigt das Spiel einen gezeichneten Ersatz (Text/Farbfläche).

return {
	icon_arrow_left = 84996660844065,
	icon_arrow_right = 87013952780591,
	icon_check_cream = 109850735637486,
	icon_minus = 76932206669004,
	icon_plus = 103285560555748,
	icon_mouse = 104342299235652,
	icon_play_triangle = 135853255956629,
	-- Symbole (freigestellt, 14.11.)
	icon_back = 103659282157847, -- Optionen: Zurück
	icon_cancel = 135720387369837, -- Verlassen-Nachfrage: Abbrechen
	icon_confirm = 117036000882566, -- Verlassen-Nachfrage: Verlassen
	icon_crown = 95644466899649, -- Rundensieger und Führender in der Punkteliste
	icon_exit = 136467943148126, -- noch nicht benutzt
	icon_home = 85855978096404, -- Menü-Knopf im Spiel
	icon_music = 80002238861874, -- Optionen: Musik
	icon_pause = 124564389148503, -- noch nicht benutzt
	icon_play = 138238448957877, -- noch nicht benutzt
	icon_settings_gear = 136688272736676, -- Optionen: Überschrift
	icon_shop_cart = 127960994806570, -- Shop-Hinweis
	icon_sound = 101386347028651, -- Optionen: Soundeffekte
	bot_control_bar_static = 121169591707135,
	button_ready_orange = 99558000165672,
	button_spielen = 76865933878187, -- freigestellte Version (wie im Hauptmenü)
	player_slot_empty = 98187466625813,
	-- Tafeln der Ausrüstungs-Wahl
	panel_abilities_blue = 132936371469456,
	panel_player_orange = 104798035918957,
	panel_bot_green = 92986174486061,
	panel_bot_purple = 82685424866580,
	panel_bot_yellow = 87894327948717,
} :: { [string]: number }
