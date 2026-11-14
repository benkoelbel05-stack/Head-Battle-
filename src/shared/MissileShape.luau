--!strict
-- Form der Lenkrakete für Treffer: genau ihr Quader (MISSILE_LENGTH x MISSILE_THICKNESS), so wie man
-- sie sieht. Server und Client prüfen damit gleich: Der Schütze erkennt den Einschlag sofort auf
-- seinem PC, der Server prüft ihn ebenfalls (für Bots und als Sicherheit).

local Constants = require(script.Parent.Constants)
local PlatformShapes = require(script.Parent.PlatformShapes)

local MissileShape = {}

local function axes(forward: Vector3): (Vector3, Vector3)
	local f = Vector3.new(forward.X, forward.Y, 0)
	f = if f.Magnitude > 0.01 then f.Unit else Vector3.xAxis
	return f, Vector3.new(-f.Y, f.X, 0)
end

-- Abstand eines Punkts zum Raketen-Quader (0 = innen)
function MissileShape.distance(position: Vector3, forward: Vector3, point: Vector3): number
	local f, side = axes(forward)
	local relative = Vector3.new(point.X - position.X, point.Y - position.Y, 0)
	local halfLength = Constants.MISSILE_LENGTH / 2
	local halfThickness = Constants.MISSILE_THICKNESS / 2
	local along = relative:Dot(f)
	local across = relative:Dot(side)
	local dx = math.max(math.abs(along) - halfLength, 0)
	local dy = math.max(math.abs(across) - halfThickness, 0)
	return math.sqrt(dx * dx + dy * dy)
end

-- Berührt die Rakete (Mitte position, Flugrichtung forward) eine Plattform?
-- Geprüft werden Ecken, Kantenmitten und Mitte des Quaders.
function MissileShape.hitsPlatform(shapes: { PlatformShapes.Shape }, position: Vector3, forward: Vector3): boolean
	local f, side = axes(forward)
	local center = Vector3.new(position.X, position.Y, 0)
	local a = f * (Constants.MISSILE_LENGTH / 2)
	local b = side * (Constants.MISSILE_THICKNESS / 2)
	local points = { center + a + b, center + a - b, center - a + b, center - a - b, center + a, center - a, center + b, center - b, center }
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		for _, point in points do
			local localPoint = frame:PointToObjectSpace(Vector3.new(point.X, point.Y, frame.Position.Z))
			if PlatformShapes.closest(shape.halfLength, localPoint) < shape.radius then
				return true
			end
		end
	end
	return false
end

-- Berührt die Rakete einen Kopf mit Mittelpunkt headPosition? (slack = Spielraum, z. B. für Verzögerung)
function MissileShape.hitsHead(position: Vector3, forward: Vector3, headPosition: Vector3, slack: number?): boolean
	return MissileShape.distance(position, forward, headPosition) <= Constants.HEAD_RADIUS + (slack or 0)
end

return MissileShape
