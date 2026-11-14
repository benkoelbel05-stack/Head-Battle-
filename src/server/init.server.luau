--!strict
-- Clay Battle – Server-Einstieg

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
local Swords = require(script.Swords)
local Missiles = require(script.Missiles)
local HeadHistory = require(script.HeadHistory)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
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
local swingSword = makeRemote("RemoteEvent", "SwingSword") :: RemoteEvent -- Client -> Server
local fireMissile = makeRemote("RemoteEvent", "FireMissile") :: RemoteEvent
local missileHit = makeRemote("RemoteEvent", "MissileHit") :: RemoteEvent -- Client -> Server (Einschlag sofort erkannt) -- Client -> Server
local setLoadout = makeRemote("RemoteEvent", "SetLoadout") :: RemoteEvent -- Client -> Server
local joinGame = makeRemote("RemoteEvent", "JoinGame") :: RemoteEvent -- Client -> Server (Startmenü "Spielen")
local setDifficulty = makeRemote("RemoteEvent", "SetDifficulty") :: RemoteEvent -- Client -> Server (1-4)
local platformEvents = makeRemote("RemoteEvent", "PlatformEvents") :: RemoteEvent -- Server -> Clients
local platformSnapshot = makeRemote("UnreliableRemoteEvent", "PlatformSnapshot") :: UnreliableRemoteEvent
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------------------------------------
-- Arena und Plattform-Simulation
---------------------------------------------------------------------------------------------------

-- Die Plattformen rechnet jeder Rechner selbst (PlatformSim), der Server gleicht ab.
local currentMap = "Basteltisch"
local spawnPoints, platforms = Arena.build(ArenaLayouts[currentMap])
local sim = PlatformSim.new()
for _, platform in platforms do
	PlatformSim.register(sim, platform)
end

-- Andere Karte laden (vor einer Runde). Alte Plattformen verschwinden mit ihrem Model aus der Simulation.
local function loadArena(name: string)
	local layout = ArenaLayouts[name]
	if not layout or name == currentMap then
		return
	end
	currentMap = name
	local points, newPlatforms = Arena.build(layout)
	for _, platform in newPlatforms do
		PlatformSim.register(sim, platform)
	end
	HeadSpawner.setSpawnPoints(points)
end

-- Karte und Hintergrund für die nächste Runde auslosen (nicht zweimal hintereinander dasselbe)
local BACKGROUNDS = { "day", "sunset", "night" }
local function pickArena(currentBackground: string?): (string, string)
	local maps = {}
	for name in ArenaLayouts do
		if name ~= currentMap then
			table.insert(maps, name)
		end
	end
	local backgrounds = {}
	for _, key in BACKGROUNDS do
		if key ~= currentBackground then
			table.insert(backgrounds, key)
		end
	end
	local map = if #maps > 0 then maps[math.random(1, #maps)] else currentMap
	return map, backgrounds[math.random(1, #backgrounds)]
end
PlatformShapes.setFrameProvider(function(model: Model): CFrame?
	local state = PlatformSim.get(sim, model)
	return if state then PlatformSim.cframeOf(state) else nil
end)

HeadSpawner.init(spawnPoints)
HeadSpawner.setEffectsRemote(platformEvents)

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

Swords.init(swingSword, {
	getHead = HeadSpawner.getHead,
	getHeads = HeadSpawner.getHeads,
	eliminate = HeadSpawner.eliminate,
	keyOf = HeadSpawner.keyOf,
	deflectGrenades = Grenades.deflect,
	events = platformEvents,
})
Missiles.init(fireMissile, {
	sim = sim,
	getHead = HeadSpawner.getHead,
	getHeads = HeadSpawner.getHeads,
	eliminate = HeadSpawner.eliminate,
	keyOf = HeadSpawner.keyOf,
	events = platformEvents,
}, missileHit)

RoundManager.init({
	spawn = HeadSpawner.spawn,
	despawn = HeadSpawner.despawn,
	keyOf = HeadSpawner.keyOf,
	displayName = HeadSpawner.displayName,
	getColor = HeadSpawner.getColor,
	isBot = HeadSpawner.isBot,
	getBots = BotController.list,
	pickArena = pickArena,
	loadArena = loadArena,
	resetArena = function()
		PlatformSim.reset(sim)
		Grenades.clear()
		Missiles.clear()
		Thrusters.resetCooldowns()
		Swords.resetCooldowns()
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
		Swords.removeParticipant(botId)
		Missiles.removeParticipant(botId)
	end,
	throwGrenade = Grenades.throw,
	grenadeReady = Grenades.isReady,
	activeGrenades = Grenades.getActive,
	activeMissiles = Missiles.getActive,
	placeThruster = Thrusters.place,
	thrusterReady = Thrusters.isReady,
	swingSword = Swords.swing,
	swordReady = Swords.isReady,
	fireMissile = Missiles.fire,
	missileReady = Missiles.isReady,
	missileActive = Missiles.hasActive,
	detonateMissile = Missiles.detonate,
	setLoadout = HeadSpawner.setLoadout,
})

-- Ausrüstung prüfen: bis zu 3 verschiedene, bekannte Fähigkeiten
local function readLoadout(list: unknown): { string }?
	if typeof(list) ~= "table" then
		return nil
	end
	local ids = {}
	for _, id in list :: { any } do
		if typeof(id) == "string" and Abilities.list[id] and not table.find(ids, id) and #ids < Abilities.MAX_SLOTS then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Ausrüstung ändern (Menü im Spiel). Gilt ab dem nächsten Erscheinen; beim freien Spielen sofort.
setLoadout.OnServerEvent:Connect(function(player: Player, list: unknown)
	local ids = readLoadout(list)
	if not ids then
		return
	end
	HeadSpawner.setLoadout(player, ids)
	if RoundManager.getPhase() == "Waiting" and HeadSpawner.getHead(player) then
		HeadSpawner.spawn(player)
	end
end)

-- Startmenü: "Spielen" gedrückt -> mit der gewählten Ausrüstung einsteigen
joinGame.OnServerEvent:Connect(function(player: Player, list: unknown)
	local ids = readLoadout(list)
	if not ids then
		return
	end
	HeadSpawner.setLoadout(player, ids)
	if player:GetAttribute("InGame") ~= true then
		player:SetAttribute("InGame", true)
		RoundManager.addParticipant(player)
		-- Countdown beim Einstieg. Startet dadurch ein Match, zählt dessen Runden-Countdown;
		-- sonst (freies Spiel) einen eigenen: so lange steht man still.
		if RoundManager.getPhase() == "Waiting" and not RoundManager.enoughParticipants() then
			player:SetAttribute("FrozenUntil", Workspace:GetServerTimeNow() + Constants.COUNTDOWN_TIME)
		end
	elseif RoundManager.getPhase() == "Waiting" and HeadSpawner.getHead(player) then
		HeadSpawner.spawn(player)
	end
end)

-- Bot-Schwierigkeit (für alle Bots, sichtbar im RoundState)
local roundStateFolder = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)
roundStateFolder:SetAttribute("BotDifficulty", BotController.getDifficulty())
setDifficulty.OnServerEvent:Connect(function(_player: Player, level: unknown)
	if typeof(level) == "number" and level == level then
		BotController.setDifficulty(level)
		roundStateFolder:SetAttribute("BotDifficulty", BotController.getDifficulty())
	end
end)

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

-- Neue Spieler landen im Startmenü und steigen erst mit "Spielen" ein (JoinGame).
-- Ihre Charakter-Farbe steht schon vorher fest, damit das Menü sie zeigen kann.
local function onPlayerAdded(player: Player)
	player:SetAttribute("Skin", HeadSpawner.getSkin(player))
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	RoundManager.removeParticipant(player)
	HeadSpawner.removeParticipant(player)
	Thrusters.removeParticipant(player)
	Grenades.removeParticipant(player)
	Swords.removeParticipant(player)
	Missiles.removeParticipant(player)
end)

---------------------------------------------------------------------------------------------------
-- Jeder Frame
---------------------------------------------------------------------------------------------------

local weightTracker = HeadWeight.newTracker()
local snapshotTimer = 0

RunService.Heartbeat:Connect(function(dt)
	BotController.step(dt)
	HeadSpawner.checkFalls()
	HeadHistory.record(HeadSpawner.getHeads())

	local headList = {}
	for _, head in HeadSpawner.getHeads() do
		table.insert(headList, head)
	end
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	local shapes = PlatformShapes.collect(arena)
	HeadWeight.step(weightTracker, sim, shapes, headList)
	PlatformSim.step(sim, dt, Workspace:GetServerTimeNow())
	HeadSpawner.checkCrush(shapes)
	Grenades.step(dt)
	Missiles.step(dt)

	-- Regelmäßiger Abgleich an alle Clients
	snapshotTimer += dt
	if snapshotTimer >= Constants.SNAPSHOT_INTERVAL then
		snapshotTimer = 0
		platformSnapshot:FireAllClients(PlatformSim.snapshot(sim))
	end
end)

print("[ClayBattle] Server gestartet, Arena gebaut")
