--!strict
-- Audio-IDs der Soundeffekte (aus dem Creator Hub). 0 = noch nicht hochgeladen: dann bleibt es still.
-- Die Dateien heißen genauso wie die Schlüssel hier (z. B. jump.ogg).

return {
	-- Menü
	ui_click = 0,
	ui_hover = 0,
	-- Bewegung
	jump = 0,
	double_jump = 0,
	land = 0,
	dash = 0,
	respawn_pop = 0,
	eliminate = 0,
	-- Fähigkeiten
	thruster = 0,
	grenade_throw = 0,
	explosion = 0,
	sword = 0,
	missile_launch = 0,
	-- Runden
	countdown_tick = 0,
	countdown_go = 0,
	map_tick = 0,
	map_select = 0,
	round_win = 0,
} :: { [string]: number }
