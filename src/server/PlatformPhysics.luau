--!strict
-- Eigene Physik für die Plattformen (statt Roblox-Federn und -Kräften, die schwer zu kontrollieren sind):
--   * Jede Plattform hängt an einer weichen Feder an ihrem Startplatz (Position und Drehung)
--   * Thruster schieben die Plattform; sitzt der Thruster am Rand, dreht sie sich
--   * Die Plattform entfernt sich höchstens PLATFORM_MAX_OFFSET Studs von ihrem Platz
--   * Sie bleibt in der 2D-Ebene und dreht sich nur um die Kamera-Achse (Z)
-- Der Server rechnet die Plattformen (Network Owner = Server), damit alle Spieler dasselbe sehen.
-- Wir setzen jeden Frame die Geschwindigkeit, Roblox bewegt die Plattform dann und kümmert sich um Kollisionen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

type Thruster = {
	localPosition: Vector3, -- Klebepunkt relativ zur Plattform
	localDirection: Vector3, -- Schubrichtung relativ zur Plattform (dreht mit)
	endTime: number,
}

type PlatformInfo = {
	root: BasePart,
	home: CFrame,
	inertiaPerMass: number, -- Trägheit pro Masse, für Drehungen
	velocity: Vector3,
	angularVelocity: number, -- um Z, rad/s
	thrusters: { Thruster },
}

local PlatformPhysics = {}

local platforms: { [BasePart]: PlatformInfo } = {}

local function zAngle(cframe: CFrame, home: CFrame): number
	local relative = home.Rotation:ToObjectSpace(cframe.Rotation)
	local right = relative.RightVector
	return math.atan2(right.Y, right.X)
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Muss aufgerufen werden, nachdem die Plattform im Workspace ist.
function PlatformPhysics.register(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	root:SetNetworkOwner(nil) -- Server rechnet, nicht der Spieler, der gerade darauf steht

	local size = model:GetExtentsSize()
	platforms[root] = {
		root = root,
		home = root.CFrame,
		inertiaPerMass = (size.X ^ 2 + size.Y ^ 2) / 12,
		velocity = Vector3.zero,
		angularVelocity = 0,
		thrusters = {},
	}
end

-- Thruster an eine Plattform hängen. part = getroffenes Teil, position = Klebepunkt,
-- direction = Schubrichtung (in die Plattform hinein). Gibt false zurück, wenn es keine Plattform ist.
function PlatformPhysics.addThruster(part: BasePart, position: Vector3, direction: Vector3, duration: number): boolean
	local root = part.AssemblyRootPart
	local info = root and platforms[root]
	if not info then
		return false
	end
	table.insert(info.thrusters, {
		localPosition = info.root.CFrame:PointToObjectSpace(position),
		localDirection = info.root.CFrame:VectorToObjectSpace(direction),
		endTime = Workspace:GetServerTimeNow() + duration,
	})
	return true
end

function PlatformPhysics.clear()
	table.clear(platforms)
end

local function stepPlatform(info: PlatformInfo, dt: number, now: number)
	local root = info.root
	local cframe = root.CFrame
	local position = Vector3.new(cframe.X, cframe.Y, 0)
	local homePosition = Vector3.new(info.home.X, info.home.Y, 0)
	local angle = zAngle(cframe, info.home)

	-- 1. Schub aller aktiven Thruster
	local acceleration = Vector3.zero
	local angularAcceleration = 0
	for i = #info.thrusters, 1, -1 do
		local thruster = info.thrusters[i]
		if now >= thruster.endTime then
			table.remove(info.thrusters, i)
		else
			local push = cframe:VectorToWorldSpace(thruster.localDirection) * Constants.THRUSTER_ACCEL
			push = Vector3.new(push.X, push.Y, 0)
			local lever = cframe:PointToWorldSpace(thruster.localPosition) - cframe.Position
			acceleration += push
			-- Drehmoment in 2D: Hebel × Kraft (nur Z-Anteil)
			angularAcceleration += (lever.X * push.Y - lever.Y * push.X) / info.inertiaPerMass
		end
	end

	-- 2. Feder zurück zum Startplatz + Dämpfung
	local offset = position - homePosition
	acceleration += -offset * Constants.PLATFORM_SPRING - info.velocity * Constants.PLATFORM_DAMPING
	local angleOffset = wrapAngle(angle)
	angularAcceleration += -angleOffset * Constants.PLATFORM_ANGULAR_SPRING
		- info.angularVelocity * Constants.PLATFORM_ANGULAR_DAMPING

	info.velocity += acceleration * dt
	info.angularVelocity += angularAcceleration * dt

	-- 3. Nicht weiter als PLATFORM_MAX_OFFSET vom Startplatz weg
	local nextOffset = offset + info.velocity * dt
	if nextOffset.Magnitude > Constants.PLATFORM_MAX_OFFSET then
		local outward = nextOffset.Unit
		local outwardSpeed = info.velocity:Dot(outward)
		if outwardSpeed > 0 then
			info.velocity -= outward * outwardSpeed
		end
	end

	-- 4. Nicht stärker kippen als PLATFORM_MAX_ANGLE
	local nextAngle = angleOffset + info.angularVelocity * dt
	if math.abs(nextAngle) > Constants.PLATFORM_MAX_ANGLE and info.angularVelocity * nextAngle > 0 then
		info.angularVelocity = 0
	end

	-- Ruhende Plattform nicht anfassen (sonst weckt man ständig die Roblox-Physik)
	local resting = #info.thrusters == 0
		and offset.Magnitude < 0.02
		and math.abs(angleOffset) < 0.002
		and info.velocity.Magnitude < 0.05
		and math.abs(info.angularVelocity) < 0.005
	if resting then
		info.velocity = Vector3.zero
		info.angularVelocity = 0
		if root.AssemblyLinearVelocity.Magnitude > 0.01 or root.AssemblyAngularVelocity.Magnitude > 0.001 then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = info.home
		end
		return
	end

	root.AssemblyLinearVelocity = info.velocity
	root.AssemblyAngularVelocity = Vector3.new(0, 0, info.angularVelocity)

	-- In der 2D-Ebene halten (nur Drehung um Z ist erlaubt)
	local relative = info.home.Rotation:ToObjectSpace(cframe.Rotation)
	local tilted = math.abs(relative.LookVector.Z + 1) > 0.002
	if tilted or math.abs(cframe.Z - Constants.PLANE_Z) > 0.05 then
		root.CFrame = CFrame.new(cframe.X, cframe.Y, Constants.PLANE_Z) * info.home.Rotation * CFrame.Angles(0, 0, angle)
	end
end

function PlatformPhysics.step(dt: number)
	local now = Workspace:GetServerTimeNow()
	for root, info in platforms do
		if root.Parent then
			stepPlatform(info, dt, now)
		else
			platforms[root] = nil
		end
	end
end

return PlatformPhysics
