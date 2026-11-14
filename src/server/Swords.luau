--!strict
-- Fähigkeit Schwert: Schlag im Bogen vor sich.
--   * Köpfe im Bogen (Reichweite SWORD_RANGE, halber Winkel SWORD_ARC) scheiden aus
--   * Granaten im Bogen werden zurückgeschlagen
-- Spieler zeigen den Schlag sofort selbst an und schicken die Richtung; Bots schlagen über Swords.swing.
-- Der Server entscheidet über Treffer und verteilt den Schlag an alle Clients (Event "Slash").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)

type Participant = Player | string

export type Context = {
	getHead: (Participant) -> Model?,
	getHeads: () -> { [Participant]: Model },
	eliminate: (Participant, string?, Vector3?) -> (),
	keyOf: (Participant) -> string,
	-- Mitte, Richtung, Reichweite, cos(Bogen), erreichbar(Punkt)
	deflectGrenades: (Vector3, Vector3, number, number, (Vector3) -> boolean) -> (),
	events: RemoteEvent,
}

local Swords = {}

local readyAt: { [Participant]: number } = {}
local context: Context

-- Liegt ein Punkt im Schlagbogen?
local function inArc(origin: Vector3, direction: Vector3, point: Vector3, range: number): boolean
	local offset = Vector3.new(point.X - origin.X, point.Y - origin.Y, 0)
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < Constants.HEAD_RADIUS then
		return true -- direkt am Kopf: immer getroffen
	end
	return offset.Unit:Dot(direction) >= math.cos(math.rad(Constants.SWORD_ARC))
end

-- Kommt die Klinge von origin bis point, ohne durch eine Plattform zu gehen?
-- slack = so weit darf der Punkt hinter der ersten Plattform-Oberfläche liegen (Kopf-Rand)
local function reachable(shapes: { PlatformShapes.Shape }, origin: Vector3, point: Vector3, slack: number): boolean
	local offset = Vector3.new(point.X - origin.X, point.Y - origin.Y, 0)
	local distance = offset.Magnitude
	if distance < 0.05 then
		return true
	end
	local hit = PlatformShapes.raycast(shapes, origin, offset, distance)
	return hit == nil or hit >= distance - slack
end

-- Schlagen. direction = Schlagrichtung (360°). Gibt true zurück, wenn geschlagen wurde.
function Swords.swing(participant: Participant, direction: Vector3): boolean
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
	if not head or not body or not Abilities.hasEquipped(head, "Sword") then
		return false
	end
	readyAt[participant] = now + Constants.SWORD_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Sword"), readyAt[participant])

	local origin = body.Position
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
	-- Etwas Spielraum für Netzwerk-Verzögerung bei der Reichweite
	local reach = Constants.SWORD_RANGE + Constants.HEAD_RADIUS + 0.5
	local R = Constants.HEAD_RADIUS
	local hit: { Participant } = {}
	for other, otherHead in context.getHeads() do
		local otherBody = otherHead.PrimaryPart
		if other ~= participant and otherBody and inArc(origin, flat, otherBody.Position, reach) then
			-- Nicht durch Plattformen: Mitte oder Rand des Kopfes muss frei erreichbar sein
			local target = otherBody.Position
			local toTarget = Vector3.new(target.X - origin.X, target.Y - origin.Y, 0)
			local side = if toTarget.Magnitude > 0.01 then Vector3.new(-toTarget.Y, toTarget.X, 0).Unit * R * 0.7 else Vector3.zero
			if
				reachable(shapes, origin, target, R * 0.3)
				or reachable(shapes, origin, target + side, 0.1)
				or reachable(shapes, origin, target - side, 0.1)
			then
				table.insert(hit, other)
			end
		end
	end
	for _, other in hit do
		context.eliminate(other, "Slash", flat)
	end

	context.deflectGrenades(
		origin,
		flat,
		Constants.SWORD_RANGE + Constants.GRENADE_RADIUS,
		math.cos(math.rad(Constants.SWORD_ARC)),
		function(point: Vector3): boolean
			return reachable(shapes, origin, point, Constants.GRENADE_RADIUS)
		end
	)
	context.events:FireAllClients("Slash", context.keyOf(participant), origin, flat)
	return true
end

function Swords.init(remote: RemoteEvent, swordContext: Context)
	context = swordContext
	remote.OnServerEvent:Connect(function(player: Player, direction: unknown)
		if typeof(direction) == "Vector3" then
			Swords.swing(player, direction :: Vector3)
		end
	end)
end

function Swords.isReady(participant: Participant): boolean
	return (readyAt[participant] or 0) <= Workspace:GetServerTimeNow()
end

function Swords.removeParticipant(participant: Participant)
	readyAt[participant] = nil
end

function Swords.resetCooldowns()
	table.clear(readyAt)
end

return Swords
