--!strict
-- Fähigkeit Lenkrakete (Raketenrucksack).
--   * Die Rakete fliegt in Zielrichtung los. Solange der Schütze die Taste hält, lenkt er sie zur Maus;
--     losgelassen fliegt sie geradeaus. Sie wird dabei immer schneller (MISSILE_START_SPEED bis
--     MISSILE_MAX_SPEED), bei gleicher Drehrate werden die Kurven also immer weiter.
--     Spieler lenken auf dem eigenen PC, Bots lenkt der Server (zum nächsten Gegner).
--   * Explodiert bei Plattform- oder Kopftreffer oder nach MISSILE_LIFETIME (Bots zünden auch selbst).
--   * Nur wen die Rakete selbst berührt, scheidet aus (Hitbox = genau ihr Quader, siehe MissileShape).
--     Die Explosion danach ist Optik und schubst Plattformen leicht.
-- Die Rakete ist eine Part im Ordner "Missiles". Spieler-Raketen gehören dem Spieler (Network Owner),
-- damit das Lenken ohne Verzögerung reagiert. Treffer prüft der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaInfo = require(ReplicatedStorage.Shared.ArenaInfo)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local HeadHistory = require(script.Parent.HeadHistory)
local MissileShape = require(ReplicatedStorage.Shared.MissileShape)

type Participant = Player | string

type Missile = {
	id: string,
	owner: Participant,
	part: BasePart,
	firedAt: number,
	direction: Vector3, -- nur für Bots (Server lenkt)
	speed: number, -- nur für Bots
}

export type Context = {
	sim: PlatformSim.Sim,
	getHead: (Participant) -> Model?,
	getHeads: () -> { [Participant]: Model },
	eliminate: (Participant, string?, Vector3?) -> (),
	keyOf: (Participant) -> string,
	events: RemoteEvent,
}

local Missiles = {}

local readyAt: { [Participant]: number } = {}
local active: { Missile } = {}
local context: Context
local folder: Model

local function makeMissilePart(position: Vector3, direction: Vector3, ownerKey: string, id: string): Part
	local part = Instance.new("Part")
	part.Name = "Missile"
	-- Sichtbare Größe = Hitbox
	part.Size = Vector3.new(Constants.MISSILE_LENGTH, Constants.MISSILE_THICKNESS, Constants.MISSILE_THICKNESS)
	part.Color = Constants.MISSILE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	-- Lange Achse (X) zeigt in Flugrichtung
	part.CFrame = CFrame.fromMatrix(position, direction, Vector3.zAxis)
	part:SetAttribute("OwnerKey", ownerKey)
	part:SetAttribute("MissileId", id)

	-- Feuerschweif nach hinten
	local flame = Instance.new("ParticleEmitter")
	flame.EmissionDirection = Enum.NormalId.Left
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(230, 90, 40))
	flame.Size = NumberSequence.new(0.6, 0)
	flame.Lifetime = NumberRange.new(0.15, 0.3)
	flame.Speed = NumberRange.new(8, 12)
	flame.SpreadAngle = Vector2.new(15, 15)
	flame.Rate = 60
	flame.LightEmission = 0.4
	flame.Parent = part
	return part
end

-- Wer berührt die Rakete gerade? Gegner dort, wo der Schütze sie sieht; den Schützen selbst erst
-- nach MISSILE_OWNER_GRACE. slack = kleiner Spielraum (für vom Schützen gemeldete Treffer).
local function touchedHeads(missile: Missile, position: Vector3, forward: Vector3, slack: number): { Participant }
	local now = Workspace:GetServerTimeNow()
	local ownerProtected = now - missile.firedAt < Constants.MISSILE_OWNER_GRACE
	local seen = HeadHistory.positionsFor(missile.owner, context.getHeads())
	local touched: { Participant } = {}
	for participant, head in context.getHeads() do
		local isOwner = participant == missile.owner
		local target = if isOwner then (head.PrimaryPart and head.PrimaryPart.Position) else seen[head]
		if target and not (isOwner and ownerProtected) and MissileShape.hitsHead(position, forward, target, slack) then
			table.insert(touched, participant)
		end
	end
	return touched
end

local function explode(missile: Missile, shapes: { PlatformShapes.Shape }, at: Vector3?, slack: number?)
	local position = at or Vector3.new(missile.part.Position.X, missile.part.Position.Y, Constants.PLANE_Z)
	local forward = missile.part.CFrame.RightVector
	missile.part:Destroy()

	-- Nur direkte Treffer scheiden aus
	for _, participant in touchedHeads(missile, position, forward, slack or 0) do
		local head = context.getHead(participant)
		local body = head and head.PrimaryPart
		local direction = if body then Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0) else Vector3.zero
		context.eliminate(participant, "Blast", if direction.Magnitude > 0.01 then direction.Unit else forward)
	end

	local pushRadius = Constants.MISSILE_BLAST_RADIUS * 2
	GrenadePhysics.applyExplosion(context.sim, shapes, position, pushRadius, Constants.MISSILE_IMPULSE)
	context.events:FireAllClients("Explosion", missile.id, position, Constants.MISSILE_BLAST_RADIUS, pushRadius, Constants.MISSILE_IMPULSE)
end

local function findMissile(participant: Participant): (Missile?, number?)
	for index, missile in active do
		if missile.owner == participant then
			return missile, index
		end
	end
	return nil, nil
end

-- Eigene Rakete sofort zünden (nur Bots)
function Missiles.detonate(participant: Participant): boolean
	local existing, index = findMissile(participant)
	if existing and index then
		table.remove(active, index)
		explode(existing, PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER)))
		return true
	end
	return false
end

-- Rakete abfeuern (nur eine gleichzeitig)
function Missiles.fire(participant: Participant, direction: Vector3, id: string): boolean
	if findMissile(participant) then
		return false
	end

	local flat = Vector3.new(direction.X, direction.Y, 0)
	if flat.Magnitude < 0.1 then
		return false
	end
	flat = flat.Unit
	local now = Workspace:GetServerTimeNow()
	if (readyAt[participant] or 0) > now + 0.1 then
		return false
	end
	local head = context.getHead(participant)
	local body = head and head.PrimaryPart
	if not head or not body or not Abilities.hasEquipped(head, "Missile") then
		return false
	end
	readyAt[participant] = now + Constants.MISSILE_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Missile"), readyAt[participant])

	local key = context.keyOf(participant)
	local missileId = `{key}-{id}`
	local start = body.Position + flat * (Constants.HEAD_RADIUS + 1)
	local part = makeMissilePart(Vector3.new(start.X, start.Y, Constants.PLANE_Z), flat, key, missileId)
	part.Parent = folder
	part.AssemblyLinearVelocity = flat * Constants.MISSILE_START_SPEED
	if typeof(participant) == "string" then
		part:SetNetworkOwner(nil) -- Bot-Raketen lenkt der Server
	else
		part:SetNetworkOwner(participant :: Player) -- Spieler lenken selbst, ohne Verzögerung
	end

	table.insert(active, { id = missileId, owner = participant, part = part, firedAt = now, direction = flat, speed = Constants.MISSILE_START_SPEED })
	return true
end

-- Bots: Rakete zum nächsten Gegner lenken
local function steerBotMissile(missile: Missile, dt: number)
	local position = missile.part.Position
	local target: Vector3? = nil
	local best = math.huge
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		if participant ~= missile.owner and body then
			local distance = (body.Position - position).Magnitude
			if distance < best then
				-- Vorhalten: dorthin, wo der Gegner bald ist
				local timeToReach = distance / math.max(missile.speed, 1)
				target, best = body.Position + body.AssemblyLinearVelocity * math.min(timeToReach, 0.6) * 0.6, distance
			end
		end
	end
	local direction = missile.direction
	if target then
		local wanted = Vector3.new(target.X - position.X, target.Y - position.Y, 0)
		if wanted.Magnitude > 0.01 then
			local current = math.atan2(direction.Y, direction.X)
			local desired = math.atan2(wanted.Y, wanted.X)
			local difference = (desired - current + math.pi) % (2 * math.pi) - math.pi
			-- Wie ein Spieler: nur bei größeren Kurven lenken
			if math.abs(difference) > 0.25 then
				local maxTurn = Constants.MISSILE_TURN_RATE * dt
				local angle = current + math.clamp(difference, -maxTurn, maxTurn)
				direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
			end
		end
	end
	missile.direction = direction
	missile.speed = math.min(missile.speed + Constants.MISSILE_ACCELERATION * dt, Constants.MISSILE_MAX_SPEED)
	local nextPosition = Vector3.new(position.X, position.Y, Constants.PLANE_Z) + direction * missile.speed * dt
	missile.part.CFrame = CFrame.fromMatrix(nextPosition, direction, Vector3.zAxis)
	missile.part.AssemblyLinearVelocity = direction * missile.speed
end

function Missiles.step(dt: number)
	if #active == 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))

	for i = #active, 1, -1 do
		local missile = active[i]
		if not missile.part.Parent then
			table.remove(active, i)
			continue
		end
		if typeof(missile.owner) == "string" then
			steerBotMissile(missile, dt)
		end

		local position = Vector3.new(missile.part.Position.X, missile.part.Position.Y, Constants.PLANE_Z)
		local shouldExplode = now - missile.firedAt >= Constants.MISSILE_LIFETIME or position.Y < ArenaInfo.fallLimit()
		-- Treffer prüfen (genau die Form der Rakete, siehe MissileShape). Spieler-Raketen meldet meist
		-- schon der Schütze selbst (MissileHit), das hier ist die Absicherung.
		local forward = missile.part.CFrame.RightVector
		if not shouldExplode and MissileShape.hitsPlatform(shapes, position, forward) then
			shouldExplode = true
		end
		if not shouldExplode and #touchedHeads(missile, position, forward, 0) > 0 then
			shouldExplode = true
		end

		if shouldExplode then
			table.remove(active, i)
			explode(missile, shapes)
		end
	end
end

-- Der Schütze meldet einen Einschlag, den sein PC sofort erkannt hat. Der Server übernimmt die Stelle,
-- wenn sie zur Rakete passt (höchstens MISSILE_HIT_TOLERANCE von der Server-Position entfernt).
local MISSILE_HIT_TOLERANCE = 10
local function onReportedHit(player: Player, position: Vector3)
	local missile, index = findMissile(player)
	if not missile or not index then
		return
	end
	local serverPosition = missile.part.Position
	local reported = Vector3.new(position.X, position.Y, Constants.PLANE_Z)
	if (Vector3.new(serverPosition.X, serverPosition.Y, Constants.PLANE_Z) - reported).Magnitude > MISSILE_HIT_TOLERANCE then
		reported = Vector3.new(serverPosition.X, serverPosition.Y, Constants.PLANE_Z)
	end
	table.remove(active, index)
	-- Kleiner Spielraum, weil der Schütze die Lage einen Moment früher gesehen hat
	explode(missile, PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER)), reported, 0.4)
end

function Missiles.init(remote: RemoteEvent, missileContext: Context, hitRemote: RemoteEvent?)
	context = missileContext
	folder = Instance.new("Model")
	folder.Name = Constants.MISSILES_FOLDER
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Parent = Workspace

	if hitRemote then
		hitRemote.OnServerEvent:Connect(function(player: Player, position: unknown)
			if typeof(position) == "Vector3" then
				onReportedHit(player, position :: Vector3)
			end
		end)
	end

	remote.OnServerEvent:Connect(function(player: Player, direction: unknown, id: unknown)
		if typeof(direction) == "Vector3" and typeof(id) == "string" and #(id :: string) <= 40 then
			Missiles.fire(player, direction :: Vector3, id :: string)
		end
	end)
end

-- Für die Bots: wo fliegen gerade Raketen hin?
function Missiles.getActive(): { { id: string, owner: Participant, position: Vector3, direction: Vector3, speed: number } }
	local list = {}
	for _, missile in active do
		if missile.part.Parent then
			local direction = missile.part.CFrame.RightVector
			table.insert(list, {
				id = missile.id,
				owner = missile.owner,
				position = Vector3.new(missile.part.Position.X, missile.part.Position.Y, Constants.PLANE_Z),
				direction = Vector3.new(direction.X, direction.Y, 0).Unit,
				-- Spieler-Raketen lenkt der Schütze: deren Tempo kennt der Server nur über die Geschwindigkeit
				speed = math.max(missile.part.AssemblyLinearVelocity.Magnitude, Constants.MISSILE_START_SPEED),
			})
		end
	end
	return list
end

function Missiles.isReady(participant: Participant): boolean
	return (readyAt[participant] or 0) <= Workspace:GetServerTimeNow()
end

function Missiles.hasActive(participant: Participant): boolean
	return findMissile(participant) ~= nil
end

-- Neue Runde: alle Raketen weg, Abklingzeiten zurücksetzen
function Missiles.clear()
	for _, missile in active do
		missile.part:Destroy()
	end
	table.clear(active)
	table.clear(readyAt)
end

function Missiles.removeParticipant(participant: Participant)
	readyAt[participant] = nil
	local missile, index = findMissile(participant)
	if missile and index then
		missile.part:Destroy()
		table.remove(active, index)
	end
end

return Missiles
