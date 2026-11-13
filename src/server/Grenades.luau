--!strict
-- Fähigkeit Granate (Granatengürtel).
-- Der Client wirft die Granate sofort selbst (eigene Vorschau) und schickt Richtung + Wurfkraft.
-- Der Server rechnet die echte Granate, verteilt den Wurf an alle Clients (die sie flüssig selbst
-- fliegen lassen) und entscheidet bei der Explosion:
--   * Köpfe im GRENADE_BLAST_RADIUS scheiden aus
--   * Plattformen werden weggestoßen (gleiche Rechnung auf allen Clients, GrenadePhysics.applyExplosion)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

type Grenade = {
	id: string,
	position: Vector3,
	velocity: Vector3,
	explodeAt: number,
}

export type Context = {
	sim: PlatformSim.Sim,
	getHead: (Player) -> Model?,
	getHeads: () -> { [Player]: Model },
	eliminate: (Player) -> (),
	events: RemoteEvent, -- Server -> alle Clients
}

local Grenades = {}

local readyAt: { [Player]: number } = {}
local active: { Grenade } = {}
local context: Context

local function explode(grenade: Grenade, shapes: { PlatformShapes.Shape })
	local position = grenade.position

	-- Köpfe im Radius scheiden aus
	for player, head in context.getHeads() do
		local body = head.PrimaryPart
		if body then
			local flat = Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0)
			if flat.Magnitude <= Constants.GRENADE_BLAST_RADIUS + Constants.HEAD_RADIUS then
				context.eliminate(player)
			end
		end
	end

	GrenadePhysics.applyExplosion(context.sim, shapes, position)
	context.events:FireAllClients("Explosion", grenade.id, position)
end

local function onThrow(player: Player, directionValue: unknown, chargeValue: unknown, idValue: unknown)
	if typeof(directionValue) ~= "Vector3" or typeof(idValue) ~= "string" then
		return
	end
	local aim = directionValue :: Vector3
	local flat = Vector3.new(aim.X, aim.Y, 0)
	if flat.Magnitude < 0.1 or #(idValue :: string) > 40 then
		return
	end
	flat = flat.Unit
	local charge = if typeof(chargeValue) == "number" then math.clamp(chargeValue, 0, 1) else 1

	local now = Workspace:GetServerTimeNow()
	if (readyAt[player] or 0) > now + 0.1 then
		return
	end
	local head = context.getHead(player)
	local body = head and head.PrimaryPart
	if not head or not body or not Abilities.hasEquipped(head, "Grenade") then
		return
	end

	readyAt[player] = now + Constants.GRENADE_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Grenade"), readyAt[player])

	local id = `{player.UserId}-{idValue}`
	local start, launchVelocity = GrenadePhysics.launch(body.Position, flat, charge)
	table.insert(active, {
		id = id,
		position = start,
		velocity = launchVelocity,
		explodeAt = now + Constants.GRENADE_FUSE,
	})
	context.events:FireAllClients("GrenadeThrown", id, start, launchVelocity, now, player.UserId)
end

function Grenades.init(remote: RemoteEvent, grenadeContext: Context)
	context = grenadeContext
	remote.OnServerEvent:Connect(onThrow)
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
		end
	end
end

function Grenades.removePlayer(player: Player)
	readyAt[player] = nil
end

return Grenades
