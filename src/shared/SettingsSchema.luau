--!strict
-- Alle Einstellungen aus dem Optionen-Menü: Art, Standardwert und erlaubte Werte.
-- Client (Settings) und Server (SettingsStore) prüfen damit gleich, was gespeichert werden darf.

export type Field = {
	kind: string, -- "number" | "boolean" | "choice"
	default: any,
	min: number?,
	max: number?,
	choices: { string }?,
}

local SettingsSchema = {}

SettingsSchema.FIELDS = {
	-- Ton
	music = { kind = "number", default = 0.6, min = 0, max = 1 },
	sfx = { kind = "number", default = 0.85, min = 0, max = 1 },
	musicInGame = { kind = "boolean", default = false }, -- Menümusik leise auch im Spiel
	-- Grafik
	graphics = { kind = "choice", default = "Hoch", choices = { "Niedrig", "Mittel", "Hoch" } },
	shake = { kind = "boolean", default = true }, -- Bildschirmwackeln bei Explosionen
	showStats = { kind = "boolean", default = false }, -- FPS und Ping oben links
	-- Spiel
	bubbles = { kind = "choice", default = "Alle", choices = { "Alle", "Nur eigene", "Aus" } }, -- Fähigkeiten über den Köpfen
	ownArrow = { kind = "boolean", default = true }, -- Pfeil über der eigenen Figur
	vibration = { kind = "boolean", default = true }, -- Controller-Vibration
} :: { [string]: Field }

-- Gültigen Wert zurückgeben (Zahlen auf den Bereich begrenzt) oder nil, wenn der Wert nicht passt
function SettingsSchema.sanitize(name: string, value: unknown): any
	local field = SettingsSchema.FIELDS[name]
	if not field then
		return nil
	end
	if field.kind == "number" then
		if typeof(value) ~= "number" or value ~= value then
			return nil
		end
		return math.clamp(value, field.min or -math.huge, field.max or math.huge)
	elseif field.kind == "boolean" then
		return if typeof(value) == "boolean" then value else nil
	else
		if typeof(value) ~= "string" or not table.find(field.choices or {}, value) then
			return nil
		end
		return value
	end
end

-- Nur die gültigen Einträge einer (z. B. geladenen) Tabelle
function SettingsSchema.sanitizeAll(data: unknown): { [string]: any }
	local result: { [string]: any } = {}
	if typeof(data) ~= "table" then
		return result
	end
	for name in SettingsSchema.FIELDS do
		local clean = SettingsSchema.sanitize(name, (data :: any)[name])
		if clean ~= nil then
			result[name] = clean
		end
	end
	return result
end

function SettingsSchema.defaults(): { [string]: any }
	local result: { [string]: any } = {}
	for name, field in SettingsSchema.FIELDS do
		result[name] = field.default
	end
	return result
end

return SettingsSchema
