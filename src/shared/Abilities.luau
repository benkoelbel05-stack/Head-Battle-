--!strict
-- Alle Fähigkeiten und das Ausrüstungs-System.
-- Jede Fähigkeit ist ein Kleidungsstück, das der Kopf trägt (Hut, Brille, Schal, Gürtel ...).
-- Ein Spieler hat höchstens 3 Fähigkeiten gleichzeitig ausgerüstet (Slot 1–3).
-- Slot 1 = linke Maustaste, Slot 2 = Mausrad-Klick, Slot 3 = rechte Maustaste.
--
-- Neue Fähigkeit hinzufügen:
--   1. Eintrag in Abilities.list anlegen (mit Kleidungsstück)
--   2. Auslösen im Client (HeadController.useAbility) und ggf. auf dem Server umsetzen
--
-- Wo am Kopf ein Kleidungsstück sitzt ("wearAt"):
--   "Top"     oben auf dem Kopf (Hüte, Mützen, Helme) – mehrere werden gestapelt
--   "Eyes"    Band auf Augenhöhe (Brillen, Masken) – die Augen bleiben sichtbar
--   "Bottom"  Band unten am Kopf (Schals, Gürtel, Halstücher)
-- Neue Stellen (z. B. "Side" für Ohrenschützer) lassen sich in ClayAnimator.placeWearable ergänzen.

local Constants = require(script.Parent.Constants)

export type WearAt = "Top" | "Eyes" | "Bottom"

export type AbilityInfo = {
	id: string,
	itemName: string, -- Name des Kleidungsstücks (für Anzeige)
	cooldown: number,
	wearAt: WearAt,
	shape: Enum.PartType,
	size: Vector3, -- Größe des Kleidungsstücks (bei "Top": X = Dicke, Y/Z = Durchmesser;
	-- bei Bändern: Z = Tiefe, muss so groß sein, dass das Band vorne aus dem Kopf herausschaut)
	color: Color3,
	chargeable: boolean?, -- Taste halten lädt auf, Loslassen löst aus (z. B. Granate)
}

local Abilities = {}

Abilities.MAX_SLOTS = 3

local R = Constants.HEAD_RADIUS

Abilities.list = {
	Dash = {
		id = "Dash",
		itemName = "Fliegerkappe",
		cooldown = Constants.DASH_COOLDOWN,
		wearAt = "Top",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(R * 0.5, R * 1.6, R * 1.6),
		color = Color3.fromRGB(120, 78, 50),
	},
	Thruster = {
		id = "Thruster",
		itemName = "Schweißerbrille",
		cooldown = Constants.THRUSTER_COOLDOWN,
		wearAt = "Eyes",
		shape = Enum.PartType.Block,
		size = Vector3.new(R * 2.15, R * 0.42, R * 2.0),
		color = Constants.THRUSTER_COLOR,
	},
	Grenade = {
		id = "Grenade",
		itemName = "Granatengürtel",
		cooldown = Constants.GRENADE_COOLDOWN,
		chargeable = true,
		wearAt = "Bottom",
		shape = Enum.PartType.Block,
		size = Vector3.new(R * 2.05, R * 0.38, R * 1.9),
		color = Constants.GRENADE_COLOR,
	},
} :: { [string]: AbilityInfo }

-- Bis es einen Auswahlbildschirm gibt, startet jeder mit dieser Ausrüstung
Abilities.DEFAULT_LOADOUT = { "Dash", "Thruster", "Grenade" }

-- Name des Attributs am Kopf, das den Bereit-Zeitpunkt (Serverzeit) speichert
function Abilities.readyAttribute(id: string): string
	return `{id}ReadyAt`
end

-- Ausrüstung wird als Text am Kopf gespeichert ("Dash,Thruster"), damit alle Clients sie sehen
function Abilities.formatLoadout(loadout: { string }): string
	return table.concat(loadout, ",")
end

function Abilities.parseLoadout(text: unknown): { string }
	local loadout = {}
	if typeof(text) == "string" then
		for id in string.gmatch(text, "[^,]+") do
			if Abilities.list[id] and #loadout < Abilities.MAX_SLOTS then
				table.insert(loadout, id)
			end
		end
	end
	return loadout
end

function Abilities.hasEquipped(head: Instance, id: string): boolean
	return table.find(Abilities.parseLoadout(head:GetAttribute("Loadout")), id) ~= nil
end

return Abilities
