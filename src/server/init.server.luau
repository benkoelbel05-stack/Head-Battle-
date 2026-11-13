--!strict
-- Head Battle – Server-Einstieg

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local Arena = require(script.Arena)
local HeadSpawner = require(script.HeadSpawner)

-- Keine normalen Roblox-Figuren: Jeder Spieler ist ein Knetkopf.
Players.CharacterAutoLoads = false
-- Schwerkraft rechnet der Client selbst (wegen Haften an Wand und Decke)
Workspace.Gravity = 0

-- Flaches, warmes Licht ohne Schatten: wirkt wie ein 2D-Bild
Lighting.GlobalShadows = false
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(170, 160, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 150)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.ClockTime = 12

local spawnPoints = Arena.build(ArenaLayouts.Basteltisch)
HeadSpawner.init(spawnPoints)

Players.PlayerAdded:Connect(HeadSpawner.spawn)
Players.PlayerRemoving:Connect(HeadSpawner.removePlayer)
for _, player in Players:GetPlayers() do
	task.spawn(HeadSpawner.spawn, player)
end

RunService.Heartbeat:Connect(HeadSpawner.checkFalls)

print("[HeadBattle] Server gestartet, Arena gebaut")
