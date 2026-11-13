--!strict
-- Physik der Plattformen. Läuft gleich auf dem Server UND auf jedem Client:
-- Ausgetauscht werden nur Ereignisse (Thruster gesetzt, Explosion) und ab und zu ein Abgleich.
-- So sieht jeder Spieler die Plattformen ohne Netzwerk-Verzögerung, und eigene Aktionen wirken sofort.
--
--   * Jede Plattform hängt an einer weichen Feder an ihrem Startplatz (Position und Drehung)
--   * Thruster schieben die Plattform; sitzt der Thruster am Rand, dreht sie sich
--   * Stöße (Explosionen, Landungen) und Kräfte (Gewicht der Köpfe)
--   * Höchstens PLATFORM_MAX_OFFSET Studs Versatz und PLATFORM_MAX_ANGLE Kippen
--   * Feste Zeitschritte (SIM_RATE pro Sekunde), damit alle Rechner möglichst gleich rechnen

local Constants = require(script.Parent.Constants)

local SIM_STEP = 1 / Constants.SIM_RATE

export type Thruster = {
	id: string,
	localPosition: Vector3, -- Klebepunkt relativ zur Plattform
	localDirection: Vector3, -- Schubrichtung relativ zur Plattform (dreht mit)
	startTime: number, -- Serverzeit
	endTime: number,
}

export type PlatformState = {
	model: Model,
	root: BasePart,
	home: CFrame,
	mass: number, -- Fläche * Dichte
	inertiaPerMass: number, -- Drehträgheit pro Masse
	offset: Vector3, -- Versatz vom Startplatz (x, y)
	angle: number, -- Drehung um Z gegenüber dem Startplatz
	velocity: Vector3,
	angularVelocity: number,
	thrusters: { Thruster },
	pendingAcceleration: Vector3,
	pendingAngular: number,
}

export type Sim = {
	platforms: { [Model]: PlatformState },
	accumulator: number,
}

local PlatformSim = {}

function PlatformSim.new(): Sim
	return { platforms = {}, accumulator = 0 }
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Aktuelle Lage der Wurzel-Part einer Plattform
function PlatformSim.cframeOf(state: PlatformState): CFrame
	return CFrame.new(state.home.Position + state.offset) * state.home.Rotation * CFrame.Angles(0, 0, state.angle)
end

function PlatformSim.register(sim: Sim, model: Model): PlatformState?
	local root = model.PrimaryPart
	local home = model:GetAttribute("HomeCFrame")
	if not root or typeof(home) ~= "CFrame" then
		return nil
	end
	-- Masse aus der Form: Stadion-Fläche (Rechteck + Kreis) * Dichte
	local halfLength = model:GetAttribute("HalfLength")
	local radius = model:GetAttribute("Radius")
	local density = model:GetAttribute("Density")
	local L = if typeof(halfLength) == "number" then halfLength else 1
	local r = if typeof(radius) == "number" then radius else 1
	local area = 4 * L * r + math.pi * r * r
	local width, height = 2 * L + 2 * r, 2 * r
	local state: PlatformState = {
		model = model,
		root = root,
		home = home,
		mass = math.max(area * (if typeof(density) == "number" then density else Constants.PLATFORM_DENSITY), 0.1),
		inertiaPerMass = (width ^ 2 + height ^ 2) / 12,
		offset = Vector3.zero,
		angle = 0,
		velocity = Vector3.zero,
		angularVelocity = 0,
		thrusters = {},
		pendingAcceleration = Vector3.zero,
		pendingAngular = 0,
	}
	sim.platforms[model] = state
	return state
end

function PlatformSim.get(sim: Sim, model: Model): PlatformState?
	return sim.platforms[model]
end

local function torque(state: PlatformState, point: Vector3, push: Vector3): number
	local lever = point - PlatformSim.cframeOf(state).Position
	return (lever.X * push.Y - lever.Y * push.X) / state.inertiaPerMass
end

-- Thruster hinzufügen (Positionen relativ zur Plattform). Doppelte IDs werden ignoriert.
function PlatformSim.addThruster(sim: Sim, model: Model, thruster: Thruster): boolean
	local state = sim.platforms[model]
	if not state then
		return false
	end
	for _, existing in state.thrusters do
		if existing.id == thruster.id then
			return false
		end
	end
	table.insert(state.thrusters, thruster)
	return true
end

-- Plötzlicher Stoß (Kraftstoß), angreifend an point (Welt). Geschwindigkeitsänderung = Stoß / Masse.
function PlatformSim.addImpulse(sim: Sim, model: Model, point: Vector3, impulse: Vector3)
	local state = sim.platforms[model]
	if not state then
		return
	end
	local push = Vector3.new(impulse.X, impulse.Y, 0) / state.mass
	state.velocity += push
	state.angularVelocity += torque(state, point, push)
end

-- Kraft für den nächsten Frame, angreifend an point (Welt). Beschleunigung = Kraft / Masse.
function PlatformSim.addForce(sim: Sim, model: Model, point: Vector3, force: Vector3)
	local state = sim.platforms[model]
	if not state then
		return
	end
	local push = Vector3.new(force.X, force.Y, 0) / state.mass
	state.pendingAcceleration += push
	state.pendingAngular += torque(state, point, push)
end

local function stepPlatform(state: PlatformState, dt: number, now: number, pendingAcceleration: Vector3, pendingAngular: number)
	local cframe = PlatformSim.cframeOf(state)
	local acceleration = pendingAcceleration
	local angularAcceleration = pendingAngular

	-- Thruster-Schub, läuft weich an und aus
	for i = #state.thrusters, 1, -1 do
		local thruster = state.thrusters[i]
		if now >= thruster.endTime then
			table.remove(state.thrusters, i)
		elseif now >= thruster.startTime then
			local strength = math.clamp(math.min(now - thruster.startTime, thruster.endTime - now) / Constants.THRUSTER_RAMP, 0, 1)
			local push = cframe:VectorToWorldSpace(thruster.localDirection) * (Constants.THRUSTER_FORCE / state.mass) * strength
			push = Vector3.new(push.X, push.Y, 0)
			local lever = cframe:PointToWorldSpace(thruster.localPosition) - cframe.Position
			acceleration += push
			angularAcceleration += (lever.X * push.Y - lever.Y * push.X) / state.inertiaPerMass
		end
	end

	-- Feder zurück zum Startplatz + Dämpfung
	acceleration += -state.offset * Constants.PLATFORM_SPRING - state.velocity * Constants.PLATFORM_DAMPING
	angularAcceleration += -state.angle * Constants.PLATFORM_ANGULAR_SPRING
		- state.angularVelocity * Constants.PLATFORM_ANGULAR_DAMPING

	state.velocity += acceleration * dt
	state.angularVelocity += angularAcceleration * dt

	-- Grenzen: Versatz und Kippen
	local nextOffset = state.offset + state.velocity * dt
	if nextOffset.Magnitude > Constants.PLATFORM_MAX_OFFSET then
		local outward = nextOffset.Unit
		local outwardSpeed = state.velocity:Dot(outward)
		if outwardSpeed > 0 then
			state.velocity -= outward * outwardSpeed
		end
	end
	local nextAngle = state.angle + state.angularVelocity * dt
	if math.abs(nextAngle) > Constants.PLATFORM_MAX_ANGLE and state.angularVelocity * nextAngle > 0 then
		state.angularVelocity = 0
	end

	state.offset += state.velocity * dt
	state.offset = Vector3.new(state.offset.X, state.offset.Y, 0)
	state.angle = wrapAngle(state.angle + state.angularVelocity * dt)
end

-- Simulation um dt weiterrechnen (in festen Schritten). now = aktuelle Serverzeit.
function PlatformSim.step(sim: Sim, dt: number, now: number)
	sim.accumulator = math.min(sim.accumulator + dt, 0.25)
	local steps = math.floor(sim.accumulator / SIM_STEP)
	sim.accumulator -= steps * SIM_STEP

	for model, state in sim.platforms do
		if not model.Parent then
			sim.platforms[model] = nil
		else
			-- Kräfte der Köpfe gelten für alle Teilschritte dieses Frames
			local pendingAcceleration, pendingAngular = state.pendingAcceleration, state.pendingAngular
			state.pendingAcceleration, state.pendingAngular = Vector3.zero, 0
			for i = 1, steps do
				local stepTime = now - (steps - i) * SIM_STEP
				stepPlatform(state, SIM_STEP, stepTime, pendingAcceleration, pendingAngular)
			end
		end
	end
end

-- Alle Plattformen zurück an ihren Startplatz (neue Runde)
function PlatformSim.reset(sim: Sim)
	for _, state in sim.platforms do
		state.offset = Vector3.zero
		state.angle = 0
		state.velocity = Vector3.zero
		state.angularVelocity = 0
		state.pendingAcceleration = Vector3.zero
		state.pendingAngular = 0
		table.clear(state.thrusters)
	end
end

-- Wurzel-Parts an die berechnete Lage setzen (nur Client, lokal)
function PlatformSim.apply(sim: Sim)
	for _, state in sim.platforms do
		state.root.CFrame = PlatformSim.cframeOf(state)
	end
end

-- Abgleich: Zustand aller Plattformen als kompakte Liste (vom Server verschickt; unzuverlässige
-- Netzwerk-Events dürfen nur ca. 900 Bytes groß sein, deshalb ohne Feldnamen):
-- { { model, offset, angle, velocity, angularVelocity }, ... }
export type Snapshot = { { any } }

function PlatformSim.snapshot(sim: Sim): Snapshot
	local list = {}
	for model, state in sim.platforms do
		table.insert(list, { model, state.offset, state.angle, state.velocity, state.angularVelocity })
	end
	return list
end

-- Weich an einen Abgleich angleichen (kein Springen). blend = Anteil der Abweichung, der korrigiert wird.
function PlatformSim.correct(sim: Sim, snapshot: unknown, blend: number)
	if typeof(snapshot) ~= "table" then
		return
	end
	for _, entry in snapshot :: { any } do
		local model, offset, angle, velocity, angularVelocity = entry[1], entry[2], entry[3], entry[4], entry[5]
		local state = if typeof(model) == "Instance" and model:IsA("Model") then sim.platforms[model] else nil
		if
			state
			and typeof(offset) == "Vector3"
			and typeof(angle) == "number"
			and typeof(velocity) == "Vector3"
			and typeof(angularVelocity) == "number"
		then
			state.offset += (offset - state.offset) * blend
			state.angle += wrapAngle(angle - state.angle) * blend
			state.velocity += (velocity - state.velocity) * blend
			state.angularVelocity += (angularVelocity - state.angularVelocity) * blend
		end
	end
end

return PlatformSim
