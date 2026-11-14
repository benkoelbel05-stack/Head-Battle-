--!strict
-- Audio-IDs der Soundeffekte (aus dem Creator Hub). 0 = noch nicht hochgeladen: dann bleibt es still.
-- Die Dateien heißen genauso wie die Schlüssel hier (z. B. jump.ogg).

return {
	-- Menü
	ui_click = 96634480549809,
	ui_hover = 138198553783359,
	-- Bewegung
	jump = 113541418090222,
	double_jump = 91144957607928,
	land = 122454592350378,
	dash = 123052287223230,
	respawn_pop = 138436870104093,
	eliminate = 122262894322210,
	-- Fähigkeiten
	thruster = 94927775791873,
	grenade_throw = 113696977363995,
	explosion = 78679352298694,
	sword = 82082750230922,
	missile_launch = 134035751225712,
	-- Runden
	countdown_tick = 95629598801079,
	countdown_go = 137104344734845,
	map_tick = 131578652980047,
	map_select = 126243866504991,
	round_win = 85168300351444,
} :: { [string]: number }
