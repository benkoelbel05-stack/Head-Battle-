--!strict
-- Erzeugt für jeden Spieler einen Knetkopf und lässt ihn nach einem Absturz wieder erscheinen.
--
-- Aufbau eines Kopfes (Model, Name = Spielername):
--   Body      unsichtbare Physik-Kugel, gesteuert vom Client des Spielers
--   Visual    sichtbare Knetkugel, wird auf jedem Client lokal animiert
--   EyeLeft / EyeRight   Augen, ebenfalls lokal animiert
--   Hat1–Hat3 ein Hut pro ausgerüsteter Fähigkeit (Attribut "Ability"), lokal animiert

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)

local HeadSpawner = {}

local headsFolder: Folder
local spawnPoints: { Vector3 } = {}
local heads: { [Player]: Model } = {}
local colorSlots: { [Player]: number } = {}
local respawning: { [Player]: boolean } = {}
local loadouts: { [Player]: { string } } = {}

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
	part.CastShadow = true
	part.Parent = parent
	return part
end

local function getColorSlot(player: Player): number
	local existing = colorSlots[player]
	if existing then
		return existing
	end
	local used = {}
	for _, slot in colorSlots do
		used[slot] = true
	end
	for slot = 1, #Constants.PLAYER_COLORS do
		if not used[slot] then
			colorSlots[player] = slot
			return slot
		end
	end
	colorSlots[player] = 1
	return 1
end

local function getLoadout(player: Player): { string }
	return loadouts[player] or table.clone(Abilities.DEFAULT_LOADOUT)
end

local function createHead(player: Player, color: Color3): Model
	local diameter = Constants.HEAD_RADIUS * 2
	local model = Instance.new("Model")
	model.Name = player.Name
	model:SetAttribute("UserId", player.UserId)
	-- Immer an alle Clients senden (wir haben keine Roblox-Figur, um die herum gestreamt wird)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local loadout = getLoadout(player)
	model:SetAttribute("Loadout", Abilities.formatLoadout(loadout))

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * diameter
	body.Transparency = 1
	body.Anchored = false
	body.CanCollide = true
	-- Federleicht (kleinste erlaubte Dichte), keine Reibung, kein Abprallen:
	-- so schiebt der Kopf die schwebenden Plattformen nicht weg. Die Steuerung übernimmt der Client.
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

	-- Ein Hut pro ausgerüsteter Fähigkeit, gestapelt in Slot-Reihenfolge (Hat1 unten)
	for slot, id in loadout do
		local info = Abilities.list[id]
		local hat = decorativePart(
			`Hat{slot}`,
			Enum.PartType.Cylinder,
			Vector3.new(info.hatThickness, info.hatDiameter, info.hatDiameter),
			info.hatColor,
			model
		)
		hat:SetAttribute("Ability", id)
	end

	return model
end

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

function HeadSpawner.getHead(player: Player): Model?
	return heads[player]
end

-- Ausrüstung ändern (max. 3 Fähigkeiten). Wird beim nächsten Erscheinen des Kopfes sichtbar.
function HeadSpawner.setLoadout(player: Player, loadout: { string })
	loadouts[player] = Abilities.parseLoadout(Abilities.formatLoadout(loadout))
end

function HeadSpawner.despawn(player: Player)
	local head = heads[player]
	if head then
		head:Destroy()
		heads[player] = nil
	end
end

function HeadSpawner.spawn(player: Player)
	HeadSpawner.despawn(player)
	if player.Parent == nil then
		return
	end

	local slot = getColorSlot(player)
	local head = createHead(player, Constants.PLAYER_COLORS[slot])
	local spawnPoint = spawnPoints[((slot - 1) % #spawnPoints) + 1]

	head:PivotTo(CFrame.new(spawnPoint))
	head.Parent = headsFolder
	heads[player] = head

	-- Der Spieler steuert seine Kugel selbst: Bewegung ohne Verzögerung
	local body = head.PrimaryPart :: BasePart
	body:SetNetworkOwner(player)
	-- Streaming-Mittelpunkt für diesen Spieler = sein Kopf
	player.ReplicationFocus = body
end

function HeadSpawner.removePlayer(player: Player)
	HeadSpawner.despawn(player)
	colorSlots[player] = nil
	respawning[player] = nil
	loadouts[player] = nil
end

-- Prüft jeden Frame, ob ein Kopf aus der Arena gefallen ist.
-- TODO (Phase 3): statt Respawn scheidet der Kopf für die Runde aus.
function HeadSpawner.checkFalls()
	for player, head in heads do
		local body = head.PrimaryPart
		if body and body.Position.Y < Constants.FALL_LIMIT_Y and not respawning[player] then
			respawning[player] = true
			HeadSpawner.despawn(player)
			task.delay(Constants.RESPAWN_DELAY, function()
				respawning[player] = nil
				if player.Parent then
					HeadSpawner.spawn(player)
				end
			end)
		end
	end
end

-- TODO (Phase 2): Positionen auf Plausibilität prüfen (Anti-Cheat), Treffer serverseitig entscheiden.

return HeadSpawner
