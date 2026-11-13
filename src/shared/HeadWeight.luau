--!strict
-- Köpfe beeinflussen die Plattformen, an denen sie kleben:
--   * Gewicht: zieht die Plattform leicht nach unten; steht ein Kopf am Ende, kippt sie (Wippe)
--   * Landen: ein harter Aufprall stößt die Plattform kurz weg
--   * Laufen: schiebt die Plattform leicht in Gegenrichtung (wie beim Laufen auf einem Boot)
-- Läuft auf Server und Clients gleich (jeder simuliert die Plattformen selbst).

local Constants = require(script.Parent.Constants)
local PlatformShapes = require(script.Parent.PlatformShapes)
local PlatformSim = require(script.Parent.PlatformSim)

type Contact = {
	shape: PlatformShapes.Shape,
	normal: Vector3, -- Welt
	point: Vector3, -- Berührpunkt auf der Plattform-Oberfläche (Welt)
}

export type Tracker = {
	wasAttached: { [Model]: boolean },
	previousVelocity: { [Model]: Vector3 },
}

local HeadWeight = {}

function HeadWeight.newTracker(): Tracker
	return { wasAttached = {}, previousVelocity = {} }
end

-- Plattform, an der der Kopf klebt (oder nil)
local function findContact(shapes: { PlatformShapes.Shape }, position: Vector3): Contact?
	local best: Contact? = nil
	local bestGap = Constants.PLATFORM_CONTACT_DISTANCE
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		local p = frame:PointToObjectSpace(position)
		local distance, closest = PlatformShapes.closest(shape.halfLength, p)
		local gap = distance - (shape.radius + Constants.HEAD_RADIUS)
		if gap < bestGap then
			bestGap = gap
			local localNormal = if distance > 0.001 then (Vector3.new(p.X, p.Y, 0) - closest) / distance else Vector3.yAxis
			best = {
				shape = shape,
				normal = frame:VectorToWorldSpace(localNormal),
				point = frame:PointToWorldSpace(closest + localNormal * shape.radius),
			}
		end
	end
	return best
end

-- Geschwindigkeit der Plattform an einem Punkt (aus der Simulation)
local function platformVelocityAt(sim: PlatformSim.Sim, model: Model, point: Vector3): Vector3
	local state = PlatformSim.get(sim, model)
	if not state then
		return Vector3.zero
	end
	local r = point - PlatformSim.cframeOf(state).Position
	return state.velocity + Vector3.new(-state.angularVelocity * r.Y, state.angularVelocity * r.X, 0)
end

-- heads: Liste der Kopf-Models (mit PrimaryPart "Body")
function HeadWeight.step(tracker: Tracker, sim: PlatformSim.Sim, shapes: { PlatformShapes.Shape }, heads: { Model })
	local seen: { [Model]: boolean } = {}

	for _, head in heads do
		local body = head.PrimaryPart
		if body then
			seen[head] = true
			local velocity = Vector3.new(body.AssemblyLinearVelocity.X, body.AssemblyLinearVelocity.Y, 0)
			local contact = findContact(shapes, body.Position)

			if contact then
				local model = contact.shape.model
				local relative = velocity - platformVelocityAt(sim, model, contact.point)

				-- Gewicht: immer nach unten, am Berührpunkt (am Ende einer Plattform kippt sie)
				PlatformSim.addForce(sim, model, contact.point, Vector3.new(0, -Constants.HEAD_WEIGHT_FORCE, 0))

				-- Laufen: Gegenschub entlang der Fläche
				local tangent = PlatformShapes.tangent(contact.normal)
				local along = relative:Dot(tangent)
				PlatformSim.addForce(sim, model, contact.point, -tangent * along * Constants.HEAD_WALK_FORCE)

				-- Landen: Aufprall in die Fläche hinein als kurzer Stoß
				if not tracker.wasAttached[head] then
					local before = tracker.previousVelocity[head] or velocity
					local impact = -before:Dot(contact.normal)
					if impact > 0 then
						PlatformSim.addImpulse(sim, model, contact.point, -contact.normal * impact * Constants.HEAD_LANDING_IMPULSE)
					end
				end
			end

			tracker.wasAttached[head] = contact ~= nil
			tracker.previousVelocity[head] = velocity
		end
	end

	for head in tracker.wasAttached do
		if not seen[head] then
			tracker.wasAttached[head] = nil
			tracker.previousVelocity[head] = nil
		end
	end
end

return HeadWeight
