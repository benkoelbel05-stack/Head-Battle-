--!strict
-- Fähigkeit Granate (Granatengürtel).
-- Der Client schickt eine Wurfrichtung und die Wurfkraft (0..1, je nach Haltedauer). Der Server wirft eine Knet-Granate im Bogen, lässt sie an
-- Plattformen abprallen (exakte Form aus PlatformShapes) und nach GRENADE_FUSE Sekunden explodieren:
--   * Köpfe im GRENADE_BLAST_RADIUS scheiden aus
--   * Plattformen im GRENADE_PUSH_RADIUS werden weggestoßen (neben der Mitte getroffen: sie drehen sich)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local PlatformPhysics = require(script.Parent.PlatformPhysics)

type Grenade = {
	part: BasePart,
	position: Vector3,
	velocity: Vector3,
	explodeAt: number,
}

type HeadAccess = {
	getHead: (Player) -> Model?,
	getHeads: () -> { [Player]: Model },
	eliminate: (Player) -> (),
}

local Grenades = {}

local readyAt: { [Player]: number } = {}
local active: { Grenade } = {}
local heads: HeadAccess
local effectsFolder: Instance

local function makeGrenadePart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Grenade"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Constants.GRENADE_RADIUS * 2
	part.Color = Constants.GRENADE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)
	part.Parent = effectsFolder
	return part
end

-- Knet-Explosion: eine Kugel, die schnell wächst und verblasst
local function explosionEffect(position: Vector3)
	local blob = Instance.new("Part")
	blob.Name = "Blast"
	blob.Shape = Enum.PartType.Ball
	blob.Size = Vector3.one
	blob.Color = Color3.fromRGB(255, 196, 92)
	blob.Material = Enum.Material.SmoothPlastic
	blob.Anchored = true
	blob.CanCollide = false
	blob.CanQuery = false
	blob.CanTouch = false
	blob.CFrame = CFrame.new(position)
	blob.Parent = effectsFolder

	local tween = TweenService:Create(
		blob,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * Constants.GRENADE_BLAST_RADIUS * 2, Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		blob:Destroy()
	end)
end

local function explode(position: Vector3)
	explosionEffect(position)

	-- Köpfe im Radius scheiden aus
	for player, head in heads.getHeads() do
		local body = head.PrimaryPart
		if body then
			local flat = Vector3.new(body.Position.X - position.X, body.Position.Y - position.Y, 0)
			if flat.Magnitude <= Constants.GRENADE_BLAST_RADIUS + Constants.HEAD_RADIUS then
				heads.eliminate(player)
			end
		end
	end

	-- Plattformen wegstoßen, am stärksten nah an der Explosion
	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	for _, shape in PlatformShapes.collect(arena) do
		local frame = PlatformShapes.frame(shape)
		local p = frame:PointToObjectSpace(position)
		local distance, c = PlatformShapes.closest(shape.halfLength, p)
		local gap = math.max(distance - shape.radius, 0)
		if gap < Constants.GRENADE_PUSH_RADIUS then
			local localDirection = if distance > 0.001 then (c - Vector3.new(p.X, p.Y, 0)) / distance else -Vector3.yAxis
			local direction = frame:VectorToWorldSpace(localDirection)
			local strength = Constants.GRENADE_PUSH * (1 - gap / Constants.GRENADE_PUSH_RADIUS)
			local surfacePoint = frame:PointToWorldSpace(c - localDirection * shape.radius)
			PlatformPhysics.addImpulse(shape.model, surfacePoint, direction * strength)
		end
	end
end

-- Granate bewegen, an Plattformen abprallen lassen (gleiche Rechnung wie der Zielstreifen)
local function stepGrenade(grenade: Grenade, dt: number, shapes: { PlatformShapes.Shape })
	grenade.position, grenade.velocity = GrenadePhysics.step(grenade.position, grenade.velocity, dt, shapes)
	grenade.part.CFrame = CFrame.new(grenade.position)
end

local function onThrow(player: Player, direction: unknown, chargeValue: unknown)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local charge = if typeof(chargeValue) == "number" then math.clamp(chargeValue, 0, 1) else 1
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
	local head = heads.getHead(player)
	local body = head and head.PrimaryPart
	if not head or not body or not Abilities.hasEquipped(head, "Grenade") then
		return
	end

	readyAt[player] = now + Constants.GRENADE_COOLDOWN
	head:SetAttribute(Abilities.readyAttribute("Grenade"), readyAt[player])

	local start, launchVelocity = GrenadePhysics.launch(body.Position, flat, charge)
	table.insert(active, {
		part = makeGrenadePart(start),
		position = start,
		velocity = launchVelocity,
		explodeAt = now + Constants.GRENADE_FUSE,
	})
end

function Grenades.init(remote: RemoteEvent, headAccess: HeadAccess, effects: Instance)
	heads = headAccess
	effectsFolder = effects
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
		if now >= grenade.explodeAt or grenade.position.Y < Constants.FALL_LIMIT_Y then
			table.remove(active, i)
			local position = grenade.position
			grenade.part:Destroy()
			if position.Y >= Constants.FALL_LIMIT_Y then
				explode(position)
			end
		else
			stepGrenade(grenade, dt, shapes)
		end
	end
end

function Grenades.removePlayer(player: Player)
	readyAt[player] = nil
end

return Grenades
