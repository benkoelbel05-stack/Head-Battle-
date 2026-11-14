--!strict
-- Fähigkeit Lenkrakete (Raketenrucksack).
--   * Die Rakete fliegt in Zielrichtung los und wird gelenkt: bei Spielern vom eigenen PC (Maus),
--     bei Bots vom Server (zum nächsten Gegner). Sie dreht sich höchstens MISSILE_TURN_RATE rad/s.
--   * Explodiert bei Plattform- oder Kopftreffer, nach MISSILE_LIFETIME oder wenn der Schütze
--     die Taste nochmal drückt.
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

type Participant = Player | string

type Missile = {
	id: string,
	owner: Participant,
	part: BasePart,
	firedAt: number,
	direction: Vector3, -- nur für Bots (Server lenkt)
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
	part.Size = Vector3.new(1.6, 0.6, 0.6)
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

-- Rakete abfeuern (oder, falls schon eine fliegt, diese zünden)
function Missiles.fire(participant: Participant, direction: Vector3, id: string): boolean
	local existing, index = findMissile(participant)
	if existing and index then
		table.remove(active, index)
		explode(existing, PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER)))
		return true
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

	table.insert(active, { id = missileId, owner = participant, part = part, firedAt = now, direction = flat })
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
	if target then
		local wanted = Vector3.new(target.X - position.X, target.Y - position.Y, 0)
		if wanted.Magnitude > 0.01 then
			local current = math.atan2(direction.Y, direction.X)
			local desired = math.atan2(wanted.Y, wanted.X)
			local difference = (desired - current + math.pi) % (2 * math.pi) - math.pi
			local maxTurn = Constants.MISSILE_TURN_RATE * dt
			local angle = current + math.clamp(difference, -maxTurn, maxTurn)
			direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
		end
	end
	missile.direction = direction
	local nextPosition = Vector3.new(position.X, position.Y, Constants.PLANE_Z) + direction * Constants.MISSILE_SPEED * dt
	missile.part.CFrame = CFrame.fromMatrix(nextPosition, direction, Vector3.zAxis)
	missile.part.AssemblyLinearVelocity = direction * Constants.MISSILE_SPEED
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

		local position = missile.part.Position
		local shouldExplode = now - missile.firedAt >= Constants.MISSILE_LIFETIME or position.Y < Constants.FALL_LIMIT_Y

		-- Plattform getroffen?
		if not shouldExplode then
			for _, shape in shapes do
				local frame = PlatformShapes.frame(shape)
				local distance = PlatformShapes.closest(shape.halfLength, frame:PointToObjectSpace(position))
				if distance < shape.radius + Constants.MISSILE_RADIUS then
					shouldExplode = true
					break
				end
			end
		end

		-- Kopf getroffen? (den Schützen erst nach MISSILE_OWNER_GRACE)
		if not shouldExplode then
			local ownerProtected = now - missile.firedAt < Constants.MISSILE_OWNER_GRACE
			for participant, head in context.getHeads() do
				local body = head.PrimaryPart
				if body and not (participant == missile.owner and ownerProtected) then
					local offset = Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0)
					if offset.Magnitude <= Constants.HEAD_RADIUS + Constants.MISSILE_RADIUS then
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
