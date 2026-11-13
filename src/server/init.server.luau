--!strict
-- Head Battle – Server-Einstieg

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local HeadWeight = require(ReplicatedStorage.Shared.HeadWeight)
local Arena = require(script.Arena)
local HeadSpawner = require(script.HeadSpawner)
local Thrusters = require(script.Thrusters)
local Grenades = require(script.Grenades)
local RoundManager = require(script.RoundManager)
local BotController = require(script.BotController)

-- Keine normalen Roblox-Figuren: Jeder Spieler ist ein Knetkopf.
Players.CharacterAutoLoads = false

-- Schwerkraft rechnet jeder Kopf selbst (wegen Haften an Wand und Decke).
Workspace.Gravity = 0

-- Flaches, warmes Licht ohne Schatten: wirkt wie ein 2D-Bild
Lighting.GlobalShadows = false
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(170, 160, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 150)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0
Lighting.ClockTime = 12

---------------------------------------------------------------------------------------------------
-- Netzwerk-Events
---------------------------------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = Constants.REMOTES_FOLDER
local function makeRemote(className: string, name: string): Instance
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end
local placeThruster = makeRemote("RemoteEvent", "PlaceThruster") :: RemoteEvent -- Client -> Server
local throwGrenade = makeRemote("RemoteEvent", "ThrowGrenade") :: RemoteEvent -- Client -> Server
local changeBots = makeRemote("RemoteEvent", "ChangeBots") :: RemoteEvent -- Client -> Server (+1 / -1)
local platformEvents = makeRemote("RemoteEvent", "PlatformEvents") :: RemoteEvent -- Server -> Clients
local platformSnapshot = makeRemote("UnreliableRemoteEvent", "PlatformSnapshot") :: UnreliableRemoteEvent
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------------------------------------
-- Arena und Plattform-Simulation
---------------------------------------------------------------------------------------------------

-- Die Plattformen rechnet jeder Rechner selbst (PlatformSim), der Server gleicht ab.
local spawnPoints, platforms = Arena.build(ArenaLayouts.Basteltisch)
local sim = PlatformSim.new()
for _, platform in platforms do
	PlatformSim.register(sim, platform)
end
PlatformShapes.setFrameProvider(function(model: Model): CFrame?
	local state = PlatformSim.get(sim, model)
	return if state then PlatformSim.cframeOf(state) else nil
end)

HeadSpawner.init(spawnPoints)

---------------------------------------------------------------------------------------------------
-- Fähigkeiten, Runden, Bots
---------------------------------------------------------------------------------------------------

Thrusters.init(placeThruster, {
	sim = sim,
	getHead = HeadSpawner.getHead,
	keyOf = HeadSpawner.keyOf,
	events = platformEvents,
})
Grenades.init(throwGrenade, {
	sim = sim,
	getHead = HeadSpawner.getHead,
	getHeads = HeadSpawner.getHeads,
	eliminate = HeadSpawner.eliminate,
	keyOf = HeadSpawner.keyOf,
	events = platformEvents,
})

RoundManager.init({
	spawn = HeadSpawner.spawn,
	despawn = HeadSpawner.despawn,
	keyOf = HeadSpawner.keyOf,
	displayName = HeadSpawner.displayName,
	getColor = HeadSpawner.getColor,
	isBot = HeadSpawner.isBot,
	getBots = BotController.list,
	resetArena = function()
		PlatformSim.reset(sim)
		Grenades.clear()
		Thrusters.resetCooldowns()
		platformEvents:FireAllClients("Reset")
	end,
})
HeadSpawner.setEliminatedCallback(RoundManager.onEliminated)

BotController.init({
	getHead = HeadSpawner.getHead,
	getHeads = HeadSpawner.getHeads,
	getPhase = RoundManager.getPhase,
	setBotName = HeadSpawner.setBotName,
	onAdded = RoundManager.addParticipant,
	onRemoved = function(botId: string)
		RoundManager.removeParticipant(botId)
		HeadSpawner.removeParticipant(botId)
		Grenades.removeParticipant(botId)
		Thrusters.removeParticipant(botId)
	end,
	throwGrenade = Grenades.throw,
	grenadeReady = Grenades.isReady,
	activeGrenades = Grenades.getActive,
	placeThruster = Thrusters.place,
	thrusterReady = Thrusters.isReady,
})

-- Bots über die Knöpfe auf dem Bildschirm hinzufügen / entfernen
changeBots.OnServerEvent:Connect(function(_player: Player, change: unknown)
	if change == 1 and #Players:GetPlayers() + #BotController.list() < Constants.MAX_PARTICIPANTS then
		BotController.add()
	elseif change == -1 then
		BotController.removeLast()
	end
end)

---------------------------------------------------------------------------------------------------
-- Spieler
---------------------------------------------------------------------------------------------------

Players.PlayerAdded:Connect(RoundManager.addParticipant)
Players.PlayerRemoving:Connect(function(player)
	RoundManager.removeParticipant(player)
	HeadSpawner.removeParticipant(player)
	Thrusters.removeParticipant(player)
	Grenades.removeParticipant(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(RoundManager.addParticipant, player)
end

---------------------------------------------------------------------------------------------------
-- Jeder Frame
---------------------------------------------------------------------------------------------------

local weightTracker = HeadWeight.newTracker()
local snapshotTimer = 0

RunService.Heartbeat:Connect(function(dt)
	BotController.step(dt)
	HeadSpawner.checkFalls()

	local headList = {}
	for _, head in HeadSpawner.getHeads() do
		table.insert(headList, head)
	end
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	HeadWeight.step(weightTracker, sim, PlatformShapes.collect(arena), headList)
	PlatformSim.step(sim, dt, Workspace:GetServerTimeNow())
	Grenades.step(dt)

	-- Regelmäßiger Abgleich an alle Clients
	snapshotTimer += dt
	if snapshotTimer >= Constants.SNAPSHOT_INTERVAL then
		snapshotTimer = 0
		platformSnapshot:FireAllClients(PlatformSim.snapshot(sim))
	end
end)

print("[HeadBattle] Server gestartet, Arena gebaut")
