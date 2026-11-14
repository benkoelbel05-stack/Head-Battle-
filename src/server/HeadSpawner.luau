--!strict
-- Erzeugt die Knetköpfe aller Teilnehmer (Spieler und Bots) und meldet, wenn einer ausscheidet.
-- Ob und wann ein Kopf wieder erscheint, entscheidet der RoundManager.
--
-- Teilnehmer = ein Player oder eine Bot-ID (Text, z. B. "Bot1").
--
-- Aufbau eines Kopfes (Model, Name = Anzeigename):
--   Body         unsichtbare Kugel. Spieler steuern sie selbst (Network Owner = Spieler),
--                Bots steuert der Server. Keine Roblox-Kollisionen, die Bewegung rechnet HeadMotor.
--   Visual       sichtbare Knetkugel, wird auf jedem Client lokal animiert
--   EyeLeft / EyeRight   Augen, ebenfalls lokal animiert
--   Wear1–Wear3  ein Kleidungsstück pro ausgerüsteter Fähigkeit (Attribut "Ability"), lokal animiert
-- Attribute am Model: UserId (Spieler) oder BotId (Bot), Skin (Charakter-Farbe), Loadout, <Fähigkeit>ReadyAt

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

-- Mit Sprites ist die 3D-Knetkugel (samt Augen und Kleidung) nur Platzhalter: von Anfang an unsichtbar.
-- Sonst stünde sie bis zum ersten Bild sichtbar am Weltmittelpunkt.
local CLAY_HIDDEN = Constants.USE_SPRITES and SpriteAssets.hasImages()

export type Participant = Player | string

local HeadSpawner = {}

local headsFolder: Folder
local spawnPoints: { Vector3 } = {}
local heads: { [Participant]: Model } = {}
local colorSlots: { [Participant]: number } = {}
local loadouts: { [Participant]: { string } } = {}
local botNames: { [string]: string } = {}
local onEliminated: ((Participant) -> ())? = nil
local effectsRemote: RemoteEvent? = nil

---------------------------------------------------------------------------------------------------
-- Teilnehmer
---------------------------------------------------------------------------------------------------

function HeadSpawner.isBot(participant: Participant): boolean
	return typeof(participant) == "string"
end

-- Eindeutiger Schlüssel als Text (für Punkte-Anzeige und IDs)
function HeadSpawner.keyOf(participant: Participant): string
	if typeof(participant) == "string" then
		return participant
	end
	return tostring((participant :: Player).UserId)
end

function HeadSpawner.displayName(participant: Participant): string
	if typeof(participant) == "string" then
		return botNames[participant] or participant
	end
	return (participant :: Player).DisplayName
end

function HeadSpawner.setBotName(botId: string, name: string)
	botNames[botId] = name
end

local function getColorSlot(participant: Participant): number
	local existing = colorSlots[participant]
	if existing then
		return existing
	end
	local used = {}
	for _, slot in colorSlots do
		used[slot] = true
	end
	for slot = 1, #Constants.SKINS do
		if not used[slot] then
			colorSlots[participant] = slot
			return slot
		end
	end
	colorSlots[participant] = 1
	return 1
end

function HeadSpawner.getColor(participant: Participant): Color3
	return Constants.SKINS[getColorSlot(participant)].color
end

-- Name der Charakter-Farbe (Sprite-Satz), z. B. "blue"
function HeadSpawner.getSkin(participant: Participant): string
	return Constants.SKINS[getColorSlot(participant)].key
end

---------------------------------------------------------------------------------------------------
-- Köpfe bauen
---------------------------------------------------------------------------------------------------

local function decorativePart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = not CLAY_HIDDEN
	part.Transparency = if CLAY_HIDDEN then 1 else 0
	part.Parent = parent
	return part
end

local function getLoadout(participant: Participant): { string }
	return loadouts[participant] or table.clone(Abilities.DEFAULT_LOADOUT)
end

local function createHead(participant: Participant, color: Color3, skin: string): Model
	local diameter = Constants.HEAD_RADIUS * 2
	local model = Instance.new("Model")
	model.Name = HeadSpawner.displayName(participant)
	if typeof(participant) == "string" then
		model:SetAttribute("BotId", participant)
	else
		model:SetAttribute("UserId", (participant :: Player).UserId)
	end
	-- Immer an alle Clients senden (wir haben keine Roblox-Figur, um die herum gestreamt wird)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local loadout = getLoadout(participant)
	model:SetAttribute("Loadout", Abilities.formatLoadout(loadout))
	model:SetAttribute("Skin", skin)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * diameter
	body.Transparency = 1
	body.Anchored = false
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 100, 100)
	body.Parent = model
	model.PrimaryPart = body

	-- Sichtbarer Kopf: ein Block mit Kugel-Mesh. Anders als eine Ball-Part lässt sich das
	-- in jede Richtung quetschen und strecken (Ball-Parts sind in Roblox immer rund).
	local visual = decorativePart("Visual", Enum.PartType.Block, Vector3.one * diameter, color, model)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = visual
	local eyeSize = Vector3.one * (Constants.HEAD_RADIUS * 0.32)
	local eyeColor = Color3.fromRGB(30, 26, 28)
	decorativePart("EyeLeft", Enum.PartType.Ball, eyeSize, eyeColor, model)
	decorativePart("EyeRight", Enum.PartType.Ball, eyeSize, eyeColor, model)

	-- Ein Kleidungsstück pro ausgerüsteter Fähigkeit (Hut, Brille, Gürtel ...), in Slot-Reihenfolge
	for slot, id in loadout do
		local info = Abilities.list[id]
		local item = decorativePart(`Wear{slot}`, info.shape, info.size, info.color, model)
		item:SetAttribute("Ability", id)
	end

	return model
end

---------------------------------------------------------------------------------------------------
-- Öffentliche Funktionen
---------------------------------------------------------------------------------------------------

function HeadSpawner.init(points: { Vector3 })
	spawnPoints = points
	local existing = Workspace:FindFirstChild(Constants.HEADS_FOLDER)
	if existing then
		existing:Destroy()
	end
	headsFolder = Instance.new("Folder")
	headsFolder.Name = Constants.HEADS_FOLDER
	headsFolder.Parent = Workspace
end

-- Wird aufgerufen, wenn ein Kopf ausscheidet (gefallen, Granate ...)
function HeadSpawner.setEliminatedCallback(callback: (Participant) -> ())
	onEliminated = callback
end

-- Über dieses Event bekommen die Clients Bescheid, um einen Effekt zu zeigen (Knetfladen, Brocken)
function HeadSpawner.setEffectsRemote(remote: RemoteEvent)
	effectsRemote = remote
end

function HeadSpawner.getHead(participant: Participant): Model?
	return heads[participant]
end

function HeadSpawner.getHeads(): { [Participant]: Model }
	return heads
end

-- Ausrüstung ändern (max. 3 Fähigkeiten). Wird beim nächsten Erscheinen des Kopfes sichtbar.
function HeadSpawner.setLoadout(participant: Participant, loadout: { string })
	loadouts[participant] = Abilities.parseLoadout(Abilities.formatLoadout(loadout))
end

function HeadSpawner.despawn(participant: Participant)
	local head = heads[participant]
	if head then
		head:Destroy()
		heads[participant] = nil
	end
end

function HeadSpawner.spawn(participant: Participant)
	HeadSpawner.despawn(participant)
	if typeof(participant) ~= "string" and (participant :: Player).Parent == nil then
		return
	end

	local slot = getColorSlot(participant)
	local head = createHead(participant, Constants.SKINS[slot].color, Constants.SKINS[slot].key)
	local spawnPoint = spawnPoints[((slot - 1) % #spawnPoints) + 1]

	head:PivotTo(CFrame.new(spawnPoint))
	-- Zur Mitte der Arena schauen
	head:SetAttribute("Facing", if spawnPoint.X > 0 then -1 else 1)
	head.Parent = headsFolder
	heads[participant] = head

	local body = head.PrimaryPart :: BasePart
	if typeof(participant) == "string" then
		body:SetNetworkOwner(nil) -- Bots steuert der Server
	else
		local player = participant :: Player
		body:SetNetworkOwner(player) -- Spieler steuern ihre Kugel selbst: Bewegung ohne Verzögerung
		player.ReplicationFocus = body -- Streaming-Mittelpunkt für diesen Spieler = sein Kopf
	end
end

-- Kopf scheidet aus. cause: "Fall", "Blast" oder "Crush"; direction: z. B. Richtung des Drucks
function HeadSpawner.eliminate(participant: Participant, cause: string?, direction: Vector3?)
	local head = heads[participant]
	if not head then
		return
	end
	local body = head.PrimaryPart
	if effectsRemote and body then
		effectsRemote:FireAllClients(
			"Eliminated",
			body.Position,
			HeadSpawner.getColor(participant),
			cause or "Fall",
			direction or Vector3.yAxis,
			HeadSpawner.getSkin(participant)
		)
	end
	HeadSpawner.despawn(participant)
	if onEliminated then
		onEliminated(participant)
	end
end

-- Teilnehmer verlässt das Spiel (Spieler geht, Bot wird entfernt)
function HeadSpawner.removeParticipant(participant: Participant)
	HeadSpawner.despawn(participant)
	colorSlots[participant] = nil
	loadouts[participant] = nil
	if typeof(participant) == "string" then
		botNames[participant] = nil
	end
end

-- Prüft jeden Frame, ob ein Kopf aus der Arena gefallen ist
function HeadSpawner.checkFalls()
	for participant, head in heads do
		local body = head.PrimaryPart
		if body and body.Position.Y < Constants.FALL_LIMIT_Y then
			HeadSpawner.eliminate(participant, "Fall")
		end
	end
end

-- Prüft jeden Frame, ob ein Kopf zwischen zwei Plattformen zerquetscht wird
function HeadSpawner.checkCrush(shapes: { PlatformShapes.Shape })
	local crushed: { { participant: Participant, direction: Vector3 } } = {}
	for participant, head in heads do
		local body = head.PrimaryPart
		if body then
			local direction = PlatformShapes.findCrush(shapes, body.Position, Constants.HEAD_RADIUS, Constants.CRUSH_GAP_RATIO)
			if direction then
				table.insert(crushed, { participant = participant, direction = direction })
			end
		end
	end
	for _, entry in crushed do
		HeadSpawner.eliminate(entry.participant, "Crush", entry.direction)
	end
end

-- TODO: Positionen der Spieler auf Plausibilität prüfen (Anti-Cheat).

return HeadSpawner
