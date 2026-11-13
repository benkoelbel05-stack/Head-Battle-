--!strict
-- Head Battle – Server-Einstieg

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local Arena = require(script.Arena)
local HeadSpawner = require(script.HeadSpawner)
local PlatformPhysics = require(script.PlatformPhysics)
local Thrusters = require(script.Thrusters)
local Grenades = require(script.Grenades)
local HeadWeight = require(script.HeadWeight)

-- Keine normalen Roblox-Figuren: Jeder Spieler ist ein Knetkopf.
Players.CharacterAutoLoads = false

-- Schwerkraft rechnet der Client selbst (wegen Haften an Wand und Decke).
-- Ohne Roblox-Schwerkraft schweben auch die Plattformen.
Workspace.Gravity = 0

-- Flaches, warmes Licht ohne Schatten: wirkt wie ein 2D-Bild
Lighting.GlobalShadows = false
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(170, 160, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 150)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.ClockTime = 12

-- Netzwerk-Events zwischen Client und Server
local remotes = Instance.new("Folder")
remotes.Name = Constants.REMOTES_FOLDER
local placeThruster = Instance.new("RemoteEvent")
placeThruster.Name = "PlaceThruster"
placeThruster.Parent = remotes
local throwGrenade = Instance.new("RemoteEvent")
throwGrenade.Name = "ThrowGrenade"
throwGrenade.Parent = remotes
remotes.Parent = ReplicatedStorage

-- Ordner für Effekte (Granaten, Explosionen); "Persistent", damit alle Clients sie sehen
local effects = Instance.new("Model")
effects.Name = Constants.EFFECTS_FOLDER
effects.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
effects.Parent = Workspace

-- Arena bauen und Plattform-Physik anmelden
local spawnPoints, platforms = Arena.build(ArenaLayouts.Basteltisch)
for _, platform in platforms do
	PlatformPhysics.register(platform)
end
HeadSpawner.init(spawnPoints)
Thrusters.init(placeThruster, HeadSpawner.getHead)
Grenades.init(throwGrenade, {
	getHead = HeadSpawner.getHead,
	getHeads = HeadSpawner.getHeads,
	eliminate = HeadSpawner.eliminate,
}, effects)

Players.PlayerAdded:Connect(HeadSpawner.spawn)
Players.PlayerRemoving:Connect(function(player)
	HeadSpawner.removePlayer(player)
	Thrusters.removePlayer(player)
	Grenades.removePlayer(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(HeadSpawner.spawn, player)
end

RunService.Heartbeat:Connect(function(dt)
	HeadSpawner.checkFalls()
	HeadWeight.step(HeadSpawner.getHeads()) -- vor der Plattform-Physik: Köpfe drücken auf Plattformen
	PlatformPhysics.step(dt)
	Grenades.step(dt)
end)

print("[HeadBattle] Server gestartet, Arena gebaut")
