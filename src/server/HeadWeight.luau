--!strict
-- Köpfe beeinflussen die Plattformen, auf denen sie kleben:
--   * Gewicht: zieht die Plattform leicht nach unten; steht ein Kopf am Ende, kippt sie (Wippe)
--   * Landen: ein harter Aufprall stößt die Plattform kurz weg
--   * Laufen: schiebt die Plattform leicht in Gegenrichtung (wie beim Laufen auf einem Boot)
-- Der Server rechnet das aus den Kopf-Positionen, damit alle Spieler dieselbe Bewegung sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformPhysics = require(script.Parent.PlatformPhysics)

type Contact = {
	shape: PlatformShapes.Shape,
	normal: Vector3, -- Welt
	point: Vector3, -- Berührpunkt auf der Plattform-Oberfläche (Welt)
}

local HeadWeight = {}

local wasAttached: { [Model]: boolean } = {}
local previousVelocity: { [Model]: Vector3 } = {}

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

-- Plattform-Geschwindigkeit an einem Punkt (für relatives Laufen)
local function platformVelocityAt(shape: PlatformShapes.Shape, point: Vector3): Vector3
	local v = shape.root:GetVelocityAtPosition(point)
	return Vector3.new(v.X, v.Y, 0)
end

function HeadWeight.step(heads: { [Player]: Model })
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
	local seen: { [Model]: boolean } = {}

	for _, head in heads do
		local body = head.PrimaryPart
		if body then
			seen[head] = true
			local velocity = Vector3.new(body.AssemblyLinearVelocity.X, body.AssemblyLinearVelocity.Y, 0)
			local contact = findContact(shapes, body.Position)

			if contact then
				local model = contact.shape.model
				local relative = velocity - platformVelocityAt(contact.shape, contact.point)

				-- Gewicht: immer nach unten, am Berührpunkt (am Ende einer Plattform kippt sie)
				PlatformPhysics.addForce(model, contact.point, Vector3.new(0, -Constants.PLATFORM_HEAD_WEIGHT, 0))

				-- Laufen: Gegenschub entlang der Fläche
				local tangent = PlatformShapes.tangent(contact.normal)
				local along = relative:Dot(tangent)
				PlatformPhysics.addForce(model, contact.point, -tangent * along * Constants.PLATFORM_WALK_PUSH)

				-- Landen: Aufprall in die Fläche hinein als kurzer Stoß
				if not wasAttached[head] then
					local before = previousVelocity[head] or velocity
					local impact = -before:Dot(contact.normal)
					if impact > 0 then
						PlatformPhysics.addImpulse(model, contact.point, -contact.normal * impact * Constants.PLATFORM_LANDING_PUSH)
					end
				end
			end

			wasAttached[head] = contact ~= nil
			previousVelocity[head] = velocity
		end
	end

	-- Aufräumen für Köpfe, die es nicht mehr gibt
	for head in wasAttached do
		if not seen[head] then
			wasAttached[head] = nil
			previousVelocity[head] = nil
		end
	end
end

return HeadWeight
