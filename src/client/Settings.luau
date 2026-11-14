--!strict
-- Einstellungen des Spielers (Optionen-Menü). Werte und erlaubte Werte stehen in SettingsSchema.
--   Settings.get("shake")           aktueller Wert
--   Settings.set("shake", false)    ändern (prüft den Wert, speichert kurz danach beim Server)
--   Settings.changed                Signal (name, wert) bei jeder Änderung
--   Settings.waitUntilReady()       wartet, bis die gespeicherten Werte vom Server da sind
-- Gespeichert wird über das Remote "SaveSettings" (Server: SettingsStore, DataStore). Klappt das nicht
-- (z. B. in Studio ohne API-Zugriff), gelten einfach die Standardwerte.
-- Jede Einstellung steht zusätzlich als Spieler-Attribut "ClayBattle_<name>" bereit.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SettingsSchema = require(ReplicatedStorage.Shared.SettingsSchema)

local Settings = {}

local values: { [string]: any } = SettingsSchema.defaults()
local changedEvent = Instance.new("BindableEvent")
Settings.changed = changedEvent.Event

local ready = false
local readyEvent = Instance.new("BindableEvent")
local LOAD_WAIT = 6 -- Sekunden: so lange auf die gespeicherten Werte vom Server warten
local SAVE_DELAY = 1.5 -- mehrere Änderungen kurz hintereinander werden zusammen gespeichert

-- SoundGroup holen oder anlegen (Musik und Soundeffekte laufen darüber)
function Settings.soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		return group
	end
	local newGroup = Instance.new("SoundGroup")
	newGroup.Name = name
	newGroup.Parent = SoundService
	return newGroup
end

local function apply(name: string, value: any)
	Players.LocalPlayer:SetAttribute(`ClayBattle_{name}`, value)
	if name == "musicVolume" then
		Settings.soundGroup("Music").Volume = value
	elseif name == "sfx" then
		Settings.soundGroup("SFX").Volume = value
	end
end

local saveQueued = false
local function scheduleSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(SAVE_DELAY, function()
		saveQueued = false
		local remotes = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER)
		local remote = remotes and remotes:FindFirstChild("SaveSettings")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(table.clone(values))
		end
	end)
end

function Settings.get(name: string): any
	return values[name]
end

function Settings.set(name: string, value: any)
	local clean = SettingsSchema.sanitize(name, value)
	if clean == nil or values[name] == clean then
		return
	end
	values[name] = clean
	apply(name, clean)
	changedEvent:Fire(name, clean)
	scheduleSave()
end

function Settings.waitUntilReady()
	if not ready then
		readyEvent.Event:Wait()
	end
end

-- Beim Start: Standardwerte anwenden, dann die gespeicherten Werte vom Server übernehmen
function Settings.start()
	for name, value in values do
		apply(name, value)
	end
	local player = Players.LocalPlayer
	local started = os.clock()
	while player:GetAttribute("SettingsLoaded") ~= true and os.clock() - started < LOAD_WAIT do
		task.wait(0.1)
	end
	local saved = player:GetAttribute("SavedSettings")
	if typeof(saved) == "string" and saved ~= "" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		if ok then
			for name, value in SettingsSchema.sanitizeAll(data) do
				if values[name] ~= value then
					values[name] = value
					apply(name, value)
					changedEvent:Fire(name, value)
				end
			end
		end
	end
	ready = true
	readyEvent:Fire()
end

return Settings
