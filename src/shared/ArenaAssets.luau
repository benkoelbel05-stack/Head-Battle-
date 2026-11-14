--!strict
-- Hintergrundbilder für die Arena im Spiel (Roblox-IMAGE-IDs).
-- Pro Runde sucht der Server einen davon aus (RoundState-Attribut "Background").
--
-- Die neuen Uploads arena_day 104043879202825, arena_sunset 77320705436559 und
-- arena_night 75529436510801 liefern bei Roblox nur ein Platzhalterbild (nicht freigegeben).
-- Deshalb vorerst: Sonnenuntergang und Nacht aus dem Menü-Export, Tag = Menü-Hintergrund.

return {
	day = 102278082298675, -- vorläufig: Hintergrund des Hauptmenüs
	sunset = 73285968060700,
	night = 85048047291829,
} :: { [string]: number }
