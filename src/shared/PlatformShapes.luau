--!strict
-- Exakte 2D-Geometrie der Plattformen.
-- Jede Plattform ist eine "Knetwurst" (Stadion-Form): eine Strecke der Länge 2 * halfLength mit Radius radius.
-- Der Server schreibt die Maße als Attribute ans Plattform-Model (siehe Arena.luau):
--   HalfLength  halbe Länge der Mittelstrecke
--   Radius      Radius der Wurst (= halbe Höhe)
--   ShapeFrame  CFrame der Form relativ zur Wurzel-Part (X = entlang der Strecke, Y = quer, Z = zur Kamera)
--
-- Ein Kopf mit Radius R, der an der Plattform klebt, bewegt sich auf einer zweiten Wurst mit
-- Radius rho = radius + R. Diese Bahn ist ein geschlossener Ring, beschrieben durch einen Parameter u
-- (Strecke entlang des Rings, im Uhrzeigersinn, Start oben links):
--   oben (links -> rechts), rechte Rundung, unten (rechts -> links), linke Rundung.

local PlatformShapes = {}

export type Shape = {
	model: Model,
	root: BasePart,
	localFrame: CFrame,
	halfLength: number,
	radius: number,
}

local cache: { [Model]: Shape } = {}

-- Alle Plattform-Formen in der Arena
function PlatformShapes.collect(arena: Instance?): { Shape }
	local shapes = {}
	if not arena then
		return shapes
	end
	for _, child in arena:GetChildren() do
		if child:IsA("Model") then
			local shape = cache[child]
			if not shape then
				local root = child.PrimaryPart
				local halfLength = child:GetAttribute("HalfLength")
				local radius = child:GetAttribute("Radius")
				local localFrame = child:GetAttribute("ShapeFrame")
				if root and typeof(halfLength) == "number" and typeof(radius) == "number" and typeof(localFrame) == "CFrame" then
					shape = {
						model = child,
						root = root,
						localFrame = localFrame,
						halfLength = halfLength,
						radius = radius,
					}
					cache[child] = shape
				end
			end
			if shape and shape.root.Parent then
				table.insert(shapes, shape)
			end
		end
	end
	return shapes
end

-- Woher die aktuelle Lage einer Plattform kommt. Server und Client setzen hier ihre
-- Plattform-Simulation ein (PlatformSim); ohne Angabe gilt die Lage der Wurzel-Part.
local frameProvider: ((Model) -> CFrame?)? = nil

function PlatformShapes.setFrameProvider(provider: (Model) -> CFrame?)
	frameProvider = provider
end

-- Aktuelle Lage der Form in der Welt
function PlatformShapes.frame(shape: Shape): CFrame
	local rootFrame = if frameProvider then frameProvider(shape.model) else nil
	return (rootFrame or shape.root.CFrame) * shape.localFrame
end

-- Länge des Rings (Bahn des Kopf-Mittelpunkts)
function PlatformShapes.perimeter(halfLength: number, rho: number): number
	return 4 * halfLength + 2 * math.pi * rho
end

-- Punkt und Normale auf dem Ring (in Form-Koordinaten, z = 0)
function PlatformShapes.boundaryPoint(halfLength: number, rho: number, u: number): (Vector3, Vector3)
	local L = halfLength
	local perimeter = PlatformShapes.perimeter(L, rho)
	u = u % perimeter

	if u < 2 * L then
		return Vector3.new(-L + u, rho, 0), Vector3.yAxis
	end
	u -= 2 * L
	if u < math.pi * rho then
		local a = math.pi / 2 - u / rho
		local n = Vector3.new(math.cos(a), math.sin(a), 0)
		return Vector3.new(L, 0, 0) + n * rho, n
	end
	u -= math.pi * rho
	if u < 2 * L then
		return Vector3.new(L - u, -rho, 0), -Vector3.yAxis
	end
	u -= 2 * L
	local a = -math.pi / 2 - u / rho
	local n = Vector3.new(math.cos(a), math.sin(a), 0)
	return Vector3.new(-L, 0, 0) + n * rho, n
end

-- Ring-Parameter u für einen Punkt (in Form-Koordinaten), projiziert auf den Ring
function PlatformShapes.boundaryParam(halfLength: number, rho: number, p: Vector3): number
	local L = halfLength
	if p.X >= -L and p.X <= L then
		if p.Y >= 0 then
			return p.X + L
		end
		return 2 * L + math.pi * rho + (L - p.X)
	elseif p.X > L then
		local a = math.atan2(p.Y, p.X - L)
		return 2 * L + (math.pi / 2 - a) * rho
	else
		local a = math.atan2(p.Y, p.X + L)
		if a > 0 then
			a -= 2 * math.pi
		end
		return 4 * L + math.pi * rho + (-math.pi / 2 - a) * rho
	end
end

-- Tangente (Richtung wachsender u) zu einer Normalen
function PlatformShapes.tangent(normal: Vector3): Vector3
	return Vector3.new(normal.Y, -normal.X, 0)
end

-- Abstand eines Punkts (Form-Koordinaten) zur Mittelstrecke, und der nächste Punkt darauf
function PlatformShapes.closest(halfLength: number, p: Vector3): (number, Vector3)
	local c = Vector3.new(math.clamp(p.X, -halfLength, halfLength), 0, 0)
	local flat = Vector3.new(p.X, p.Y, 0)
	return (flat - c).Magnitude, c
end

-- Nächste Plattform-Oberfläche in Reichweite eines Kopfes: Normale in Weltkoordinaten oder nil.
-- extra = wie weit der Kopf höchstens von der Oberfläche entfernt sein darf.
function PlatformShapes.nearestNormal(shapes: { Shape }, worldPosition: Vector3, headRadius: number, extra: number): Vector3?
	local bestGap = extra
	local bestNormal: Vector3? = nil
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		local p = frame:PointToObjectSpace(worldPosition)
		local distance, c = PlatformShapes.closest(shape.halfLength, p)
		local gap = distance - (shape.radius + headRadius)
		if gap < bestGap then
			bestGap = gap
			local localNormal = if distance > 0.001
				then (Vector3.new(p.X, p.Y, 0) - c) / distance
				else Vector3.yAxis
			bestNormal = frame:VectorToWorldSpace(localNormal)
		end
	end
	return bestNormal
end

return PlatformShapes
