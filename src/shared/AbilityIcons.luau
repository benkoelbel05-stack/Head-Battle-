--!strict
-- Bild-IDs der Fähigkeiten-Symbole (Roblox-IMAGE-IDs, umgewandelt mit tools/ConvertArenaDecals.luau).
-- 0 = noch kein Bild: dann wird das Emoji aus Abilities.list[...].icon gezeigt.
-- Die Bilder sind fertige runde Abzeichen (mit eigenem Hintergrund und Rand).

return {
	Dash = 133990650586069,
	Thruster = 100233199011280,
	Grenade = 94044266715938,
	Sword = 88759219459966,
	Missile = 95182104605564,
} :: { [string]: number }
