--!strict
-- Fähigkeit Thruster (Schweißerbrille).
-- Der Client sucht die Plattform in Zielrichtung und zeigt sofort eine Vorschau. Der Server prüft das,
-- klebt den echten Thruster an und schiebt die Plattform einige Sekunden lang von ihm weg.
-- Sitzt der Thruster nicht in der Mitte, dreht sich die Plattform.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local ThrusterVisual = require(ReplicatedStorage.Shared.ThrusterVisual)
local PlatformPhysics = require(script.Parent.PlatformPhysics)

local Thrusters = {}

local readyAt: { [Player]: number } = {}

-- Gibt false zurück, wenn das getroffene Teil keine bewegliche Plattform ist
local function attachThruster(part: BasePart, position: Vector3, normal: Vector3, ownerUserId: number): boolean
	-- Schub in die Plattform hinein, also weg vom Thruster
	if not PlatformPhysics.addThruster(part, position, -normal, Constants.THRUSTER_DURATION) then
		return false
	end

	local thruster = ThrusterVisual.create(part, position, normal)
	thruster:SetAttribute("OwnerUserId", ownerUserId)

	task.delay(Constants.THRUSTER_DURATION, function()
		thruster:Destroy()
	end)
	return true
end

-- Der Client schickt: getroffenes Plattform-Teil, Klebepunkt und Normale (beides relativ zum Teil).
-- So sitzt der Thruster genau dort, wo der Client ihn schon als Vorschau anzeigt, auch wenn sich
-- die Plattform inzwischen bewegt hat. Der Server prüft, ob das plausibel ist.
local function onPlaceThruster(player: Player, getHead: (Player) -> Model?, part: unknown, localPosition: unknown, localNormal: unknown)
	if typeof(part) ~= "Instance" or typeof(localPosition) ~= "Vector3" or typeof(localNormal) ~= "Vector3" then
		return
	end
	local hitPart = part :: Instance
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	if not arena or not hitPart:IsA("BasePart") or not hitPart:IsDescendantOf(arena) then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if (readyAt[player] or 0) > now then
		return
	end

	local head = getHead(player)
	local body = head and head.PrimaryPart
	if not head or not body then
		return
	end
	-- Nur wer den Thruster ausgerüstet hat, darf ihn benutzen
	if not Abilities.hasEquipped(head, "Thruster") then
		return
	end

	local position = hitPart.CFrame:PointToWorldSpace(localPosition :: Vector3)
	local worldNormal = hitPart.CFrame:VectorToWorldSpace(localNormal :: Vector3)
	local normal = Vector3.new(worldNormal.X, worldNormal.Y, 0)
	if normal.Magnitude < 0.01 then
		return
	end

	-- Reichweite prüfen (mit etwas Spielraum für Netzwerk-Verzögerung)
	local reach = Constants.HEAD_RADIUS + Constants.THRUSTER_RANGE + 4
	local flatOffset = Vector3.new(position.X - body.Position.X, position.Y - body.Position.Y, 0)
	if flatOffset.Magnitude > reach then
		return
	end

	if attachThruster(hitPart, position, normal.Unit, player.UserId) then
		readyAt[player] = now + Constants.THRUSTER_COOLDOWN
		head:SetAttribute(Abilities.readyAttribute("Thruster"), readyAt[player])
	end
end

function Thrusters.init(remote: RemoteEvent, getHead: (Player) -> Model?)
	remote.OnServerEvent:Connect(function(player: Player, part: unknown, localPosition: unknown, localNormal: unknown)
		onPlaceThruster(player, getHead, part, localPosition, localNormal)
	end)
end

function Thrusters.removePlayer(player: Player)
	readyAt[player] = nil
end

return Thrusters
