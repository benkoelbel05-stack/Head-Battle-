--!strict
-- Form der Lenkrakete für Treffer: eine Kapsel (Strecke von hinten nach vorne, MISSILE_RADIUS dick).
-- Server und Client prüfen damit gleich: Der Schütze erkennt den Einschlag sofort auf seinem PC,
-- der Server prüft ihn ebenfalls (für Bots und als Sicherheit).

local Constants = require(script.Parent.Constants)
local PlatformShapes = require(script.Parent.PlatformShapes)

local MissileShape = {}

local function flatForward(forward: Vector3): Vector3
	local f = Vector3.new(forward.X, forward.Y, 0)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.xAxis
end

-- Berührt die Rakete (Mitte position, Flugrichtung forward) eine Plattform?
function MissileShape.hitsPlatform(shapes: { PlatformShapes.Shape }, position: Vector3, forward: Vector3): boolean
	local f = flatForward(forward)
	local center = Vector3.new(position.X, position.Y, 0)
	local points = {
		center + f * Constants.MISSILE_HALF_LENGTH,
		center,
		center - f * Constants.MISSILE_HALF_LENGTH,
	}
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		for _, point in points do
			local localPoint = frame:PointToObjectSpace(Vector3.new(point.X, point.Y, frame.Position.Z))
			if PlatformShapes.closest(shape.halfLength, localPoint) < shape.radius + Constants.MISSILE_RADIUS then
				return true
			end
		end
	end
	return false
end

-- Berührt die Rakete einen Kopf mit Mittelpunkt headPosition?
function MissileShape.hitsHead(position: Vector3, forward: Vector3, headPosition: Vector3): boolean
	local f = flatForward(forward)
	local tail = Vector3.new(position.X, position.Y, 0) - f * Constants.MISSILE_HALF_LENGTH
	local head = Vector3.new(headPosition.X, headPosition.Y, 0)
	local along = math.clamp((head - tail):Dot(f), 0, Constants.MISSILE_HALF_LENGTH * 2)
	return (head - (tail + f * along)).Magnitude <= Constants.HEAD_RADIUS + Constants.MISSILE_RADIUS
end

return MissileShape
