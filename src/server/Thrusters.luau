--!strict
-- Fähigkeit Thruster (Schweißerbrille).
-- Der Client setzt den Thruster sofort selbst (in seiner eigenen Plattform-Simulation) und schickt ihn
-- an den Server. Der Server prüft ihn, rechnet ihn in seine Simulation ein und verteilt ihn an alle
-- Clients. Positionen sind immer relativ zur Plattform, damit es überall dieselbe Stelle ist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)

local Thrusters = {}

local readyAt: { [Player]: number } = {}

export type Context = {
	sim: PlatformSim.Sim,
	getHead: (Player) -> Model?,
	events: RemoteEvent, -- Server -> alle Clients
}

local function onPlaceThruster(
	context: Context,
	player: Player,
	modelValue: unknown,
	localPositionValue: unknown,
	localNormalValue: unknown,
	idValue: unknown
)
	if
		typeof(modelValue) ~= "Instance"
		or typeof(localPositionValue) ~= "Vector3"
		or typeof(localNormalValue) ~= "Vector3"
		or typeof(idValue) ~= "string"
	then
		return
	end
	local model = modelValue :: Instance
	local localPosition = localPositionValue :: Vector3
	local localNormal = localNormalValue :: Vector3
	local id = idValue :: string
	if not model:IsA("Model") or #id > 40 then
		return
	end
	local state = PlatformSim.get(context.sim, model)
	if not state then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if (readyAt[player] or 0) > now + 0.1 then -- etwas Spielraum für Uhren-Abweichung
		return
	end
	local head = context.getHead(player)
	local body = head and head.PrimaryPart
	if not head or not body or not Abilities.hasEquipped(head, "Thruster") then
		return
	end

	local flatNormal = Vector3.new(localNormal.X, localNormal.Y, 0)
	if flatNormal.Magnitude < 0.01 or localPosition.Magnitude > 200 then
		return
	end
	flatNormal = flatNormal.Unit

	-- Reichweite prüfen (mit Spielraum für Netzwerk-Verzögerung)
	local worldPoint = PlatformSim.cframeOf(state):PointToWorldSpace(localPosition)
	local offset = Vector3.new(worldPoint.X - body.Position.X, worldPoint.Y - body.Position.Y, 0)
	if offset.Magnitude > Constants.HEAD_RADIUS + Constants.THRUSTER_RANGE + 6 then
		return
	end

	local thruster: PlatformSim.Thruster = {
		id = `{player.UserId}-{id}`,
		localPosition = Vector3.new(localPosition.X, localPosition.Y, 0),
		localDirection = -flatNormal, -- Schub in die Plattform hinein, also weg vom Thruster
		startTime = now,
		endTime = now + Constants.THRUSTER_DURATION,
	}
	if PlatformSim.addThruster(context.sim, model, thruster) then
		readyAt[player] = now + Constants.THRUSTER_COOLDOWN
		head:SetAttribute(Abilities.readyAttribute("Thruster"), readyAt[player])
		context.events:FireAllClients("Thruster", model, thruster, player.UserId)
	end
end

function Thrusters.init(remote: RemoteEvent, context: Context)
	remote.OnServerEvent:Connect(function(player: Player, model: unknown, localPosition: unknown, localNormal: unknown, id: unknown)
		onPlaceThruster(context, player, model, localPosition, localNormal, id)
	end)
end

function Thrusters.removePlayer(player: Player)
	readyAt[player] = nil
end

return Thrusters
