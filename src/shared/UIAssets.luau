--!strict
-- Bild-IDs der Bedienelemente (Roblox-IMAGE-IDs, umgewandelt mit tools/ConvertArenaDecals.luau).
-- 0 = kein Bild: dann zeigt das Spiel einen gezeichneten Ersatz (Text/Farbfläche).

return {
	icon_arrow_left = 84996660844065,
	icon_arrow_right = 87013952780591,
	icon_check_cream = 109850735637486,
	icon_minus = 76932206669004,
	icon_plus = 103285560555748,
	icon_mouse = 104342299235652,
	icon_play_triangle = 135853255956629,
	bot_control_bar_static = 121169591707135,
	button_ready_orange = 99558000165672,
	button_spielen = 98531982695949,
	player_slot_empty = 98187466625813,
	-- Tafeln der Ausrüstungs-Wahl (noch Decal-IDs umzuwandeln, siehe tools/ConvertArenaDecals.luau)
	panel_abilities_blue = 0,
	panel_player_orange = 0,
	panel_bot_green = 0,
	panel_bot_purple = 0,
	panel_bot_yellow = 0,
} :: { [string]: number }
