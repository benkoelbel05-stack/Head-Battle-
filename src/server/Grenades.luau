--!strict
-- Fähigkeit Granate (Granatengürtel).
-- Spieler werfen sofort selbst (eigene Vorschau) und schicken Richtung + Wurfkraft. Bots werfen direkt
-- über Grenades.throw. Der Server rechnet die echte Granate, verteilt den Wurf an alle Clients (die sie
-- flüssig selbst fliegen lassen). Sie explodiert nach GRENADE_FUSE Sekunden oder sofort, wenn sie
-- einen Kopf trifft. Bei der Explosion entscheidet der Server:
--   * Köpfe im GRENADE_BLAST_RADIUS scheiden aus
--   * Plattformen werden weggestoßen (gleiche Rechnung auf allen Clients, GrenadePhysics.applyExplosion)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

type Participant = Player | string

export type Grenade = {
	id: string,
	owner: Participant,
	position: Vector3,
	velocity: Vector3,
	thrownAt: number,
	explodeAt: number,
}

export type Context = {
	sim: PlatformSim.Sim,
	getHead: (Participant) -> Model?,
	getHeads: () -> { [Participant]: Model },
	eliminate: (Participant, string?, Vector3?) -> (),
	keyOf: (Participant) -> string,
	events: RemoteEvent, -- Server -> alle Clients
}

local Grenades = {}

local readyAt: { [Participant]: number } = {}
local active: { Grenade } = {}
local context: Context

local function explode(grenade: Grenade, shapes: { PlatformShapes.Shape })
	local position = grenade.position

	-- Köpfe im Radius scheiden aus
	local hit: { { participant: Participant, direction: Vector3 } } = {}
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		if body then
			local flat = Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0)
			if flat.Magnitude <= Constants.GRENADE_BLAST_RADIUS + Constants.HEAD_RADIUS then
				local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.yAxis
				table.insert(hit, { participant = participant, direction = direction })
			end
		end
	end
	for _, entry in hit do
		context.eliminate(entry.participant, "Blast", entry.direction)
	end

	GrenadePhysics.applyExplosion(context.sim, shapes, position)
	context.events:FireAllClients("Explosion", grenade.id, position)
end

-- Granate werfen. direction = Wurfrichtung (360°), charge = 0..1. Gibt true zurück, wenn geworfen.
function Grenades.throw(participant: Participant, direction: Vector3, charge: number, id: string): boolean
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
	if not head or not body or not Abilities.hasEquipped(head, "Grenade") then
		return false
	end

	readyAt[participant] = now + Constants.GRENADE_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Grenade"), readyAt[participant])

	local grenadeId = `{context.keyOf(participant)}-{id}`
	local start, launchVelocity = GrenadePhysics.launch(body.Position, flat, math.clamp(charge, 0, 1))
	table.insert(active, {
		id = grenadeId,
		owner = participant,
		position = start,
		velocity = launchVelocity,
		thrownAt = now,
		explodeAt = now + Constants.GRENADE_FUSE,
	})
	context.events:FireAllClients("GrenadeThrown", grenadeId, start, launchVelocity, now)
	return true
end

function Grenades.init(remote: RemoteEvent, grenadeContext: Context)
	context = grenadeContext
	remote.OnServerEvent:Connect(function(player: Player, direction: unknown, charge: unknown, id: unknown)
		if typeof(direction) == "Vector3" and typeof(id) == "string" and #(id :: string) <= 40 then
			local chargeValue = if typeof(charge) == "number" then charge :: number else 1
			Grenades.throw(player, direction :: Vector3, chargeValue, id :: string)
		end
	end)
end

-- Trifft die Granate einen Kopf? (Den Werfer erst nach GRENADE_OWNER_GRACE Sekunden)
local function hitsHead(grenade: Grenade, now: number): boolean
	local reach = Constants.HEAD_RADIUS + Constants.GRENADE_RADIUS
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		local ownerProtected = participant == grenade.owner and now - grenade.thrownAt < Constants.GRENADE_OWNER_GRACE
		if body and not ownerProtected then
			local offset = Vector3.new(body.Position.X - grenade.position.X, body.Position.Y - grenade.position.Y, 0)
			if offset.Magnitude <= reach then
				return true
			end
		end
	end
	return false
end

function Grenades.step(dt: number)
	if #active == 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
	for i = #active, 1, -1 do
		local grenade = active[i]
		if now >= grenade.explodeAt then
			table.remove(active, i)
			explode(grenade, shapes)
		elseif grenade.position.Y < Constants.FALL_LIMIT_Y then
			table.remove(active, i)
		else
			grenade.position, grenade.velocity = GrenadePhysics.step(grenade.position, grenade.velocity, dt, shapes)
			-- Aufprall auf einen Kopf: sofort explodieren
			if hitsHead(grenade, now) then
				table.remove(active, i)
				explode(grenade, shapes)
			end
		end
	end
end

-- Fliegende Granaten (z. B. damit Bots ausweichen können)
function Grenades.getActive(): { Grenade }
	return active
end

function Grenades.isReady(participant: Participant): boolean
	return (readyAt[participant] or 0) <= Workspace:GetServerTimeNow()
end

-- Neue Runde: alle Granaten weg, Abklingzeiten zurücksetzen
function Grenades.clear()
	table.clear(active)
	table.clear(readyAt)
end

function Grenades.removeParticipant(participant: Participant)
	readyAt[participant] = nil
end

return Grenades
