--!strict
-- Flugbahn der Granate. Wird vom Server (echte Granate) und vom Client (Zielstreifen) gleich gerechnet,
-- damit der Zielstreifen genau zeigt, wohin die Granate fliegt.

local Constants = require(script.Parent.Constants)
local PlatformShapes = require(script.Parent.PlatformShapes)
local PlatformSim = require(script.Parent.PlatformSim)

local GrenadePhysics = {}

-- Startpunkt und Startgeschwindigkeit. direction = Wurfrichtung (beliebig, 360°), charge = 0..1
-- (wie lange die Taste gehalten wurde). Die Granate startet am Kopfrand in Wurfrichtung.
function GrenadePhysics.launch(headPosition: Vector3, direction: Vector3, charge: number): (Vector3, Vector3)
	local flat = Vector3.new(direction.X, direction.Y, 0)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.xAxis
	local speed = Constants.GRENADE_MIN_SPEED
		+ (Constants.GRENADE_SPEED - Constants.GRENADE_MIN_SPEED) * math.clamp(charge, 0, 1)
	local start = headPosition + flat * (Constants.HEAD_RADIUS + Constants.GRENADE_RADIUS + 0.2)
	return Vector3.new(start.X, start.Y, Constants.PLANE_Z), flat * speed
end

-- Zielen mit Tasten (nur 8 Richtungen): leicht nach oben anheben, damit die Granate im Bogen fliegt.
-- Mit Maus oder Stick wird genau in die gezielte Richtung geworfen.
function GrenadePhysics.liftKeyboardAim(direction: Vector3): Vector3
	return (Vector3.new(direction.X, direction.Y, 0).Unit + Vector3.new(0, Constants.GRENADE_UPWARD, 0)).Unit
end

-- Ladezustand 0..1 aus der Haltedauer
function GrenadePhysics.chargeFromHold(seconds: number): number
	return math.clamp(seconds / Constants.GRENADE_CHARGE_TIME, 0, 1)
end

-- Einen Zeitschritt weiterrechnen, mit Abprallen an Plattformen.
-- Gibt neue Position, neue Geschwindigkeit und ob sie dabei eine Plattform getroffen hat zurück.
function GrenadePhysics.step(
	position: Vector3,
	velocity: Vector3,
	dt: number,
	shapes: { PlatformShapes.Shape }
): (Vector3, Vector3, boolean)
	velocity -= Vector3.new(0, Constants.GRENADE_GRAVITY * dt, 0)
	local delta = velocity * dt
	local steps = math.max(1, math.ceil(delta.Magnitude / 0.3))
	local hitSomething = false

	for _ = 1, steps do
		position += delta / steps
		for _, shape in shapes do
			local frame = PlatformShapes.frame(shape)
			local p = frame:PointToObjectSpace(position)
			local distance, closest = PlatformShapes.closest(shape.halfLength, p)
			local minDistance = shape.radius + Constants.GRENADE_RADIUS
			if distance < minDistance then
				hitSomething = true
				local localNormal = if distance > 0.001 then (Vector3.new(p.X, p.Y, 0) - closest) / distance else Vector3.yAxis
				local normal = frame:VectorToWorldSpace(localNormal)
				position = frame:PointToWorldSpace(closest + localNormal * minDistance)
				local intoSurface = velocity:Dot(normal)
				if intoSurface < 0 then
					-- Abprallen, entlang der Fläche etwas bremsen (Knete ist nicht sehr springfreudig)
					local tangential = velocity - normal * intoSurface
					velocity = tangential * 0.8 - normal * intoSurface * Constants.GRENADE_BOUNCE
				end
			end
		end
	end

	return Vector3.new(position.X, position.Y, Constants.PLANE_Z), velocity, hitSomething
end

-- Explosion stößt Plattformen weg (am stärksten nah an der Explosion; neben der Mitte: sie drehen sich).
-- Läuft auf Server und Clients gleich, damit alle dieselbe Bewegung sehen.
function GrenadePhysics.applyExplosion(sim: PlatformSim.Sim, shapes: { PlatformShapes.Shape }, position: Vector3)
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		local p = frame:PointToObjectSpace(position)
		local distance, closest = PlatformShapes.closest(shape.halfLength, p)
		local gap = math.max(distance - shape.radius, 0)
		if gap < Constants.GRENADE_PUSH_RADIUS then
			local localDirection = if distance > 0.001 then (closest - Vector3.new(p.X, p.Y, 0)) / distance else -Vector3.yAxis
			local direction = frame:VectorToWorldSpace(localDirection)
			local strength = Constants.GRENADE_IMPULSE * (1 - gap / Constants.GRENADE_PUSH_RADIUS)
			local surfacePoint = frame:PointToWorldSpace(closest - localDirection * shape.radius)
			PlatformSim.addImpulse(sim, shape.model, surfacePoint, direction * strength)
		end
	end
end

return GrenadePhysics
