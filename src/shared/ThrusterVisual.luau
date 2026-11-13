--!strict
-- Aussehen eines Thrusters: kleiner Knet-Zylinder mit Flamme, der aus der Plattform ragt.
-- Wird vom Server (echter Thruster) und vom Client (Sofort-Vorschau gegen Verzögerung) gleich gebaut.

local Constants = require(script.Parent.Constants)

local ThrusterVisual = {}

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

-- part = Plattform-Teil, position = Klebepunkt, normal = Flächennormale (zeigt aus der Plattform heraus)
function ThrusterVisual.create(part: BasePart, position: Vector3, normal: Vector3): Part
	-- Ausrichtung: X-Achse zeigt aus der Fläche heraus, Y-Achse zur Kamera
	local outward = CFrame.fromMatrix(position, normal, Vector3.zAxis)

	local thruster = Instance.new("Part")
	thruster.Name = "Thruster"
	thruster.Shape = Enum.PartType.Cylinder
	thruster.Size = Vector3.new(1.6, 1.3, 1.3)
	thruster.CFrame = outward * CFrame.new(0.6, 0, 0)
	thruster.Color = Constants.THRUSTER_COLOR
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

	return thruster
end

return ThrusterVisual
