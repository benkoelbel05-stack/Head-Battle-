--!strict
-- Fähigkeit Lenkrakete (Raketenrucksack).
--   * Die Rakete fliegt in Zielrichtung los. Solange der Schütze die Taste hält, lenkt er sie zur Maus
--     und sie fliegt extra langsam (MISSILE_STEER_SPEED); losgelassen fliegt sie geradeaus (MISSILE_SPEED).
--     Spieler lenken auf dem eigenen PC, Bots lenkt der Server (zum nächsten Gegner, langsam beim Kurven).
--   * Explodiert bei Plattform- oder Kopftreffer oder nach MISSILE_LIFETIME (Bots zünden auch selbst).
--   * Explosion: Köpfe im MISSILE_BLAST_RADIUS scheiden aus, Plattformen werden weggestoßen.
-- Die Rakete ist eine Part im Ordner "Missiles". Spieler-Raketen gehören dem Spieler (Network Owner),
-- damit das Lenken ohne Verzögerung reagiert. Treffer prüft der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local HeadHistory = require(script.Parent.HeadHistory)

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
	-- Form passt genau zur Treffer-Kapsel (MISSILE_HALF_LENGTH, MISSILE_RADIUS)
	part.Size = Vector3.new(
		(Constants.MISSILE_HALF_LENGTH + Constants.MISSILE_RADIUS) * 2,
		Constants.MISSILE_RADIUS * 2,
		Constants.MISSILE_RADIUS * 2
	)
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

local function explode(missile: Missile, shapes: { PlatformShapes.Shape })
	local position = Vector3.new(missile.part.Position.X, missile.part.Position.Y, Constants.PLANE_Z)
	missile.part:Destroy()
	local now = Workspace:GetServerTimeNow()
	local ownerProtected = now - missile.firedAt < Constants.MISSILE_OWNER_GRACE

	local hit: { { participant: Participant, direction: Vector3 } } = {}
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		if body and not (participant == missile.owner and ownerProtected) then
			local offset = Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0)
			if offset.Magnitude <= Constants.MISSILE_BLAST_RADIUS + Constants.HEAD_RADIUS then
				table.insert(hit, {
					participant = participant,
					direction = if offset.Magnitude > 0.01 then offset.Unit else Vector3.yAxis,
				})
			end
		end
	end
	for _, entry in hit do
		context.eliminate(entry.participant, "Blast", entry.direction)
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
	part.AssemblyLinearVelocity = flat * Constants.MISSILE_SPEED
	if typeof(participant) == "string" then
		part:SetNetworkOwner(nil) -- Bot-Raketen lenkt der Server
	else
		part:SetNetworkOwner(participant :: Player) -- Spieler lenken selbst, ohne Verzögerung
	end

	table.insert(active, { id = missileId, owner = participant, part = part, firedAt = now, direction = flat, speed = Constants.MISSILE_SPEED })
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
				local timeToReach = distance / Constants.MISSILE_SPEED
				target, best = body.Position + body.AssemblyLinearVelocity * math.min(timeToReach, 0.6) * 0.6, distance
			end
		end
	end
	local direction = missile.direction
	local steering = false
	if target then
		local wanted = Vector3.new(target.X - position.X, target.Y - position.Y, 0)
		if wanted.Magnitude > 0.01 then
			local current = math.atan2(direction.Y, direction.X)
			local desired = math.atan2(wanted.Y, wanted.X)
			local difference = (desired - current + math.pi) % (2 * math.pi) - math.pi
			-- Wie ein Spieler: nur bei größeren Kurven lenken (und dabei langsam fliegen)
			if math.abs(difference) > 0.25 then
				steering = true
				local maxTurn = Constants.MISSILE_TURN_RATE * dt
				local angle = current + math.clamp(difference, -maxTurn, maxTurn)
				direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
			end
		end
	end
	missile.direction = direction
	local wantedSpeed = if steering then Constants.MISSILE_STEER_SPEED else Constants.MISSILE_SPEED
	local change = Constants.MISSILE_SPEED_CHANGE * dt
	missile.speed = missile.speed + math.clamp(wantedSpeed - missile.speed, -change, change)
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
		local shouldExplode = now - missile.firedAt >= Constants.MISSILE_LIFETIME or position.Y < Constants.FALL_LIMIT_Y
		-- Die Rakete ist eine Kapsel: Strecke von hinten nach vorne, mit MISSILE_RADIUS Dicke
		local forward = missile.part.CFrame.RightVector
		forward = Vector3.new(forward.X, forward.Y, 0)
		forward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.xAxis
		local tail = position - forward * Constants.MISSILE_HALF_LENGTH
		local nose = position + forward * Constants.MISSILE_HALF_LENGTH

		-- Plattform getroffen? (Spitze, Mitte oder Ende berührt sie)
		if not shouldExplode then
			for _, shape in shapes do
				local frame = PlatformShapes.frame(shape)
				for _, point in { nose, position, tail } do
					local localPoint = frame:PointToObjectSpace(Vector3.new(point.X, point.Y, frame.Position.Z))
					if PlatformShapes.closest(shape.halfLength, localPoint) < shape.radius + Constants.MISSILE_RADIUS then
						shouldExplode = true
						break
					end
				end
				if shouldExplode then
					break
				end
			end
		end

		-- Kopf getroffen? Abstand Kopfmitte zur Raketen-Strecke. Gegner dort, wo der Schütze sie sieht;
		-- den Schützen selbst erst nach MISSILE_OWNER_GRACE.
		if not shouldExplode then
			local ownerProtected = now - missile.firedAt < Constants.MISSILE_OWNER_GRACE
			local seen = HeadHistory.positionsFor(missile.owner, context.getHeads())
			for participant, head in context.getHeads() do
				local isOwner = participant == missile.owner
				local target = if isOwner then (head.PrimaryPart and head.PrimaryPart.Position) else seen[head]
				if target and not (isOwner and ownerProtected) then
					local flatTarget = Vector3.new(target.X, target.Y, Constants.PLANE_Z)
					local along = math.clamp((flatTarget - tail):Dot(forward), 0, Constants.MISSILE_HALF_LENGTH * 2)
					local closest = tail + forward * along
					if (flatTarget - closest).Magnitude <= Constants.HEAD_RADIUS + Constants.MISSILE_RADIUS then
						shouldExplode = true
						break
					end
				end
			end
		end

		if shouldExplode then
			table.remove(active, i)
			explode(missile, shapes)
		end
	end
end

function Missiles.init(remote: RemoteEvent, missileContext: Context)
	context = missileContext
	folder = Instance.new("Model")
	folder.Name = Constants.MISSILES_FOLDER
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Parent = Workspace

	remote.OnServerEvent:Connect(function(player: Player, direction: unknown, id: unknown)
		if typeof(direction) == "Vector3" and typeof(id) == "string" and #(id :: string) <= 40 then
			Missiles.fire(player, direction :: Vector3, id :: string)
		end
	end)
end

-- Für die Bots: wo fliegen gerade Raketen hin?
function Missiles.getActive(): { { id: string, owner: Participant, position: Vector3, direction: Vector3 } }
	local list = {}
	for _, missile in active do
		if missile.part.Parent then
			local direction = missile.part.CFrame.RightVector
			table.insert(list, {
				id = missile.id,
				owner = missile.owner,
				position = Vector3.new(missile.part.Position.X, missile.part.Position.Y, Constants.PLANE_Z),
				direction = Vector3.new(direction.X, direction.Y, 0).Unit,
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
