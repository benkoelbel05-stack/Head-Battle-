--!strict
-- Head Battle – Server-Einstieg

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local Arena = require(script.Arena)
local HeadSpawner = require(script.HeadSpawner)

-- Keine normalen Roblox-Figuren: Jeder Spieler ist ein Knetkopf.
Players.CharacterAutoLoads = false
Workspace.Gravity = Constants.GRAVITY

local spawnPoints = Arena.build(ArenaLayouts.Basteltisch)
HeadSpawner.init(spawnPoints)

Players.PlayerAdded:Connect(HeadSpawner.spawn)
Players.PlayerRemoving:Connect(HeadSpawner.removePlayer)
for _, player in Players:GetPlayers() do
	task.spawn(HeadSpawner.spawn, player)
end

RunService.Heartbeat:Connect(HeadSpawner.checkFalls)
