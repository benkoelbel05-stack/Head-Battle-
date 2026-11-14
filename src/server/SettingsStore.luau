--!strict
-- Speichert die Optionen jedes Spielers dauerhaft (DataStore "ClayBattleSettings").
-- Beim Betreten: gespeicherte Werte laden und dem Client als Spieler-Attribut "SavedSettings" (JSON)
-- geben, danach "SettingsLoaded" = true. Der Client schickt Änderungen über das Remote "SaveSettings";
-- gespeichert wird beim Verlassen und beim Herunterfahren des Servers.
-- Ohne DataStore-Zugriff (z. B. Studio ohne "Studio-Zugriff auf API-Dienste") läuft alles weiter,
-- nur ohne Speichern.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SettingsSchema = require(ReplicatedStorage.Shared.SettingsSchema)

local SettingsStore = {}

local STORE_NAME = "ClayBattleSettings"
local SEND_GAP = 0.5 -- Sekunden: häufigere Nachrichten eines Spielers werden ignoriert

local store: DataStore? = nil
local pending: { [Player]: { [string]: any } } = {} -- noch nicht gespeicherte Änderungen
local lastMessage: { [Player]: number } = {}

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function load(player: Player)
	local data: unknown = nil
	local activeStore = store
	if activeStore then
		local ok, result = pcall(function()
			return activeStore:GetAsync(keyFor(player))
		end)
		if ok then
			data = result
		elseif RunService:IsStudio() then
			warn(`[ClayBattle] Optionen konnten nicht geladen werden: {result}`)
		end
	end
	local clean = SettingsSchema.sanitizeAll(data)
	player:SetAttribute("SavedSettings", if next(clean) then HttpService:JSONEncode(clean) else "")
	player:SetAttribute("SettingsLoaded", true)
end

local function save(player: Player)
	local data = pending[player]
	local activeStore = store
	if not data or not activeStore then
		return
	end
	pending[player] = nil
	local ok, problem = pcall(function()
		activeStore:SetAsync(keyFor(player), data, { player.UserId })
	end)
	if not ok and RunService:IsStudio() then
		warn(`[ClayBattle] Optionen konnten nicht gespeichert werden: {problem}`)
	end
end

function SettingsStore.init(remote: RemoteEvent)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	elseif RunService:IsStudio() then
		warn(`[ClayBattle] Kein DataStore für die Optionen (in Studio: Spieleinstellungen -> Sicherheit -> Studio-Zugriff auf API-Dienste): {result}`)
	end

	remote.OnServerEvent:Connect(function(player: Player, data: unknown)
		local now = os.clock()
		if now - (lastMessage[player] or 0) < SEND_GAP then
			return
		end
		lastMessage[player] = now
		local clean = SettingsSchema.sanitizeAll(data)
		if next(clean) then
			pending[player] = clean
		end
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		save(player)
		lastMessage[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
		task.wait(2)
	end)
end

return SettingsStore
