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
	-- Symbole (freigestellt, 14.11.): bisher nur Decal-IDs (stehen dahinter); 0 = ausgeblendet bzw. Ersatz,
	-- bis sie mit tools/ConvertArenaDecals.luau umgewandelt sind
	icon_back = 0, -- Optionen: Zurück (Decal 103659282157847)
	icon_cancel = 0, -- Verlassen-Nachfrage: Abbrechen (Decal 135720387369837)
	icon_confirm = 0, -- Verlassen-Nachfrage: Verlassen (Decal 117036000882566)
	icon_crown = 0, -- Rundensieger und Führender in der Punkteliste (Decal 95644466899649)
	icon_exit = 0, -- noch nicht benutzt (Decal 136467943148126)
	icon_home = 0, -- Menü-Knopf im Spiel (Decal 85855978096404)
	icon_music = 0, -- Optionen: Musik (Decal 80002238861874)
	icon_pause = 0, -- noch nicht benutzt (Decal 124564389148503)
	icon_play = 0, -- noch nicht benutzt (Decal 138238448957877)
	icon_settings_gear = 0, -- Optionen: Überschrift (Decal 136688272736676)
	icon_shop_cart = 0, -- Shop-Hinweis (Decal 127960994806570)
	icon_sound = 0, -- Optionen: Soundeffekte (Decal 101386347028651)
	bot_control_bar_static = 121169591707135,
	button_ready_orange = 99558000165672,
	button_spielen = 98531982695949, -- freigestellt: Decal 76865933878187
	player_slot_empty = 98187466625813,
	-- Tafeln der Ausrüstungs-Wahl
	panel_abilities_blue = 132936371469456,
	panel_player_orange = 104798035918957,
	panel_bot_green = 92986174486061,
	panel_bot_purple = 82685424866580,
	panel_bot_yellow = 87894327948717,
} :: { [string]: number }
