--!strict
-- Alle Fähigkeiten (= Hüte) und das Ausrüstungs-System.
-- Ein Spieler hat höchstens 3 Fähigkeiten gleichzeitig ausgerüstet (Slot 1–3).
-- Slot 1 = linke Maustaste, Slot 2 = Mausrad-Klick, Slot 3 = rechte Maustaste.
--
-- Neue Fähigkeit hinzufügen:
--   1. Eintrag in Abilities.list anlegen
--   2. Auslösen im Client (HeadController) und ggf. auf dem Server umsetzen

local Constants = require(script.Parent.Constants)

export type AbilityInfo = {
	id: string,
	hatName: string, -- Name des Huts (für Anzeige)
	cooldown: number,
	hatColor: Color3,
	hatThickness: number,
	hatDiameter: number,
}

local Abilities = {}

Abilities.MAX_SLOTS = 3

local R = Constants.HEAD_RADIUS

Abilities.list = {
	Dash = {
		id = "Dash",
		hatName = "Fliegerkappe",
		cooldown = Constants.DASH_COOLDOWN,
		hatColor = Constants.HAT_COLOR,
		hatThickness = R * 0.5,
		hatDiameter = R * 2 * 0.8,
	},
	Thruster = {
		id = "Thruster",
		hatName = "Raketenhut",
		cooldown = Constants.THRUSTER_COOLDOWN,
		hatColor = Constants.HAT2_COLOR,
		hatThickness = R * 0.6,
		hatDiameter = R * 2 * 0.5,
	},
} :: { [string]: AbilityInfo }

-- Bis es einen Auswahlbildschirm gibt, startet jeder mit dieser Ausrüstung
Abilities.DEFAULT_LOADOUT = { "Dash", "Thruster" }

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

return Abilities
