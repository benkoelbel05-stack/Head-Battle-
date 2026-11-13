--!strict
-- Hut 2: Thruster.
-- Der Client schickt eine Zielrichtung. Der Server sucht in dieser Richtung die nächste Plattform,
-- klebt dort einen Thruster an und schiebt die Plattform einige Sekunden lang von ihm weg.
-- Sitzt der Thruster nicht in der Mitte, dreht sich die Plattform.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformPhysics = require(script.Parent.PlatformPhysics)

local Thrusters = {}

local readyAt: { [Player]: number } = {}
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

local function makeFlame(parent: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.EmissionDirection = Enum.NormalId.Right -- entlang der Thruster-Achse nach außen
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(230, 90, 40))
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Lifetime = NumberRange.new(0.15, 0.3)
	emitter.Speed = NumberRange.new(14, 20)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Rate = 70
	emitter.LightEmission = 0.4
	emitter.Parent = parent
end

-- Gibt false zurück, wenn das getroffene Teil keine bewegliche Plattform ist
local function attachThruster(part: BasePart, position: Vector3, normal: Vector3): boolean
	-- Schub in die Plattform hinein, also weg vom Thruster
	if not PlatformPhysics.addThruster(part, position, -normal, Constants.THRUSTER_DURATION) then
		return false
	end

	-- Ausrichtung: X-Achse zeigt aus der Fläche heraus, Y-Achse zur Kamera
	local outward = CFrame.fromMatrix(position, normal, Vector3.zAxis)

	-- Sichtbarer Thruster: kleiner Knet-Zylinder, der aus der Fläche ragt
	local thruster = Instance.new("Part")
	thruster.Name = "Thruster"
	thruster.Shape = Enum.PartType.Cylinder
	thruster.Size = Vector3.new(1.6, 1.3, 1.3)
	thruster.CFrame = outward * CFrame.new(0.6, 0, 0)
	thruster.Color = Constants.HAT2_COLOR
	thruster.Material = Enum.Material.SmoothPlastic
	thruster.CanCollide = false
	thruster.CanQuery = false
	thruster.CanTouch = false
	thruster.Massless = true
	thruster.Anchored = false
	thruster.Parent = part

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = thruster
	weld.Parent = thruster
	makeFlame(thruster)

	task.delay(Constants.THRUSTER_DURATION, function()
		thruster:Destroy()
	end)
	return true
end

local function onPlaceThruster(player: Player, getHead: (Player) -> Model?, direction: unknown)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local aim = direction :: Vector3
	local flat = Vector3.new(aim.X, aim.Y, 0)
	if flat.Magnitude < 0.1 then
		return
	end
	flat = flat.Unit

	local now = Workspace:GetServerTimeNow()
	if (readyAt[player] or 0) > now then
		return
	end

	local head = getHead(player)
	local body = head and head.PrimaryPart
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	if not head or not body or not arena then
		return
	end
	-- Nur wer den Thruster ausgerüstet hat, darf ihn benutzen
	if not table.find(Abilities.parseLoadout(head:GetAttribute("Loadout")), "Thruster") then
		return
	end

	raycastParams.FilterDescendantsInstances = { arena }
	local reach = Constants.HEAD_RADIUS + Constants.THRUSTER_RANGE
	local hit = Workspace:Raycast(body.Position, flat * reach, raycastParams)
	if not hit then
		return -- nichts getroffen: Hut bleibt bereit
	end

	local part = hit.Instance
	if not part:IsA("BasePart") then
		return
	end

	local normal = Vector3.new(hit.Normal.X, hit.Normal.Y, 0)
	if normal.Magnitude < 0.01 then
		return
	end

	if attachThruster(part, hit.Position, normal.Unit) then
		readyAt[player] = now + Constants.THRUSTER_COOLDOWN
		head:SetAttribute(Abilities.readyAttribute("Thruster"), readyAt[player])
	end
end

function Thrusters.init(remote: RemoteEvent, getHead: (Player) -> Model?)
	remote.OnServerEvent:Connect(function(player: Player, direction: unknown)
		onPlaceThruster(player, getHead, direction)
	end)
end

function Thrusters.removePlayer(player: Player)
	readyAt[player] = nil
end

return Thrusters
