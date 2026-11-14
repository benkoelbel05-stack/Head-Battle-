--!strict
-- Fähigkeit Thruster (Schweißerbrille).
-- Spieler setzen den Thruster sofort selbst (in ihrer eigenen Plattform-Simulation) und schicken ihn
-- an den Server. Bots setzen ihn direkt über Thrusters.place. Der Server prüft, rechnet ihn in seine
-- Simulation ein und verteilt ihn an alle Clients. Positionen sind relativ zur Plattform.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)

type Participant = Player | string

export type Context = {
	sim: PlatformSim.Sim,
	getHead: (Participant) -> Model?,
	keyOf: (Participant) -> string,
	events: RemoteEvent, -- Server -> alle Clients
}

local Thrusters = {}

local readyAt: { [Participant]: number } = {}
local context: Context

-- Thruster setzen. localPosition/localNormal relativ zur Wurzel der Plattform. Gibt true zurück, wenn gesetzt.
-- requestedStart: Startzeit vom Client (Serverzeit). Wird übernommen, wenn sie plausibel ist; so schieben
-- Server und Clients exakt gleichzeitig. Sonst (und bei Bots): jetzt + THRUSTER_SYNC_DELAY.
function Thrusters.place(participant: Participant, model: Model, localPosition: Vector3, localNormal: Vector3, id: string, requestedStart: number?): boolean
	local state = PlatformSim.get(context.sim, model)
	if not state then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	if (readyAt[participant] or 0) > now + 0.1 then -- etwas Spielraum für Uhren-Abweichung
		return false
	end
	local head = context.getHead(participant)
	local body = head and head.PrimaryPart
	if not head or not body or not Abilities.hasEquipped(head, "Thruster") then
		return false
	end

	local flatNormal = Vector3.new(localNormal.X, localNormal.Y, 0)
	if flatNormal.Magnitude < 0.01 or localPosition.Magnitude > 200 then
		return false
	end
	flatNormal = flatNormal.Unit

	-- Reichweite prüfen (mit Spielraum für Netzwerk-Verzögerung)
	local worldPoint = PlatformSim.cframeOf(state):PointToWorldSpace(localPosition)
	local offset = Vector3.new(worldPoint.X - body.Position.X, worldPoint.Y - body.Position.Y, 0)
	if offset.Magnitude > Constants.HEAD_RADIUS + Constants.THRUSTER_RANGE + 6 then
		return false
	end

	local startTime = now + Constants.THRUSTER_SYNC_DELAY
	if requestedStart and requestedStart == requestedStart and requestedStart > now - 0.3 and requestedStart < now + 0.5 then
		startTime = requestedStart
	end
	local thruster: PlatformSim.Thruster = {
		id = `{context.keyOf(participant)}-{id}`,
		localPosition = Vector3.new(localPosition.X, localPosition.Y, 0),
		localDirection = -flatNormal, -- Schub in die Plattform hinein, also weg vom Thruster
		startTime = startTime,
		endTime = startTime + Constants.THRUSTER_DURATION,
	}
	if not PlatformSim.addThruster(context.sim, model, thruster) then
		return false
	end
	readyAt[participant] = now + Constants.THRUSTER_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Thruster"), readyAt[participant])
	context.events:FireAllClients("Thruster", model, thruster)
	return true
end

function Thrusters.init(remote: RemoteEvent, thrusterContext: Context)
	context = thrusterContext
	remote.OnServerEvent:Connect(function(player: Player, model: unknown, localPosition: unknown, localNormal: unknown, id: unknown, startTime: unknown)
		if
			typeof(model) == "Instance"
			and (model :: Instance):IsA("Model")
			and typeof(localPosition) == "Vector3"
			and typeof(localNormal) == "Vector3"
			and typeof(id) == "string"
			and #(id :: string) <= 40
		then
			Thrusters.place(player, model :: Model, localPosition :: Vector3, localNormal :: Vector3, id :: string, if typeof(startTime) == "number" then startTime else nil)
		end
	end)
end

function Thrusters.isReady(participant: Participant): boolean
	return (readyAt[participant] or 0) <= Workspace:GetServerTimeNow()
end

function Thrusters.removeParticipant(participant: Participant)
	readyAt[participant] = nil
end

function Thrusters.resetCooldowns()
	table.clear(readyAt)
end

return Thrusters
