--!strict
-- Physik der Plattformen. Läuft gleich auf dem Server UND auf jedem Client:
-- Ausgetauscht werden nur Ereignisse (Thruster gesetzt, Explosion) und ab und zu ein Abgleich.
-- So sieht jeder Spieler die Plattformen ohne Netzwerk-Verzögerung, und eigene Aktionen wirken sofort.
--
--   * Jede Plattform hängt an einer weichen Feder an ihrem Startplatz (Position und Drehung)
--   * Thruster schieben die Plattform; sitzt der Thruster am Rand, dreht sie sich
--   * Stöße (Explosionen, Landungen) und Kräfte (Gewicht der Köpfe)
--   * Versatz: Feder, ab PLATFORM_SOFT_OFFSET eine weiche, starke Zusatzfeder (PLATFORM_MAX_OFFSET nur Notbremse); drehen ganz (360°)
--   * Plattformen stoßen exakt (als Knetwürste) aneinander, mit Masse, Drehung und leichtem Abprallen
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
	halfLength: number, -- Form (Knetwurst) für Zusammenstöße
	radius: number,
	shapeFrame: CFrame, -- Lage der Form relativ zur Wurzel
	offset: Vector3, -- Versatz vom Startplatz (x, y)
	angle: number, -- Drehung um Z gegenüber dem Startplatz
	prevOffset: Vector3, -- Stand vor dem letzten festen Schritt (zum weichen Zeichnen zwischen Schritten)
	prevAngle: number,
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
	-- Drehung um die Bild-Achse der Welt (Z), NICHT um die eigene Z-Achse der Wurzel: bei Kreisen ist die
	-- Wurzel der zur Kamera gedrehte Zylinder, dessen eigene Z-Achse zur Seite zeigt. Sonst kippt der
	-- Kreis aus dem Bild heraus und wird zur flachen Ellipse (und die Köpfe darauf laufen falsch).
	return CFrame.new(state.home.Position + state.offset) * CFrame.Angles(0, 0, state.angle) * state.home.Rotation
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
		mass = (function()
			local raw = area * (if typeof(density) == "number" then density else Constants.PLATFORM_DENSITY)
			local reference = Constants.PLATFORM_MASS_REFERENCE
			return math.max(reference * (math.max(raw, 0.1) / reference) ^ Constants.PLATFORM_MASS_EXPONENT, 0.5)
		end)(),
		inertiaPerMass = (width ^ 2 + height ^ 2) / 12,
		halfLength = L,
		radius = r,
		shapeFrame = (function()
			local frame = model:GetAttribute("ShapeFrame")
			return if typeof(frame) == "CFrame" then frame else CFrame.identity
		end)(),
		offset = Vector3.zero,
		angle = 0,
		prevOffset = Vector3.zero,
		prevAngle = 0,
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
			-- Schon bekannt (eigene Vorhersage): Zeiten auf die des Servers setzen, damit alle gleich schieben
			existing.startTime = thruster.startTime
			existing.endTime = thruster.endTime
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
	-- Weiche Grenze: weiter draußen zieht eine viel stärkere Feder zurück und bremst zusätzlich
	local distance = state.offset.Magnitude
	if distance > Constants.PLATFORM_SOFT_OFFSET then
		local outward = state.offset / distance
		acceleration += -outward * (distance - Constants.PLATFORM_SOFT_OFFSET) * Constants.PLATFORM_SOFT_SPRING
			- state.velocity * Constants.PLATFORM_SOFT_DAMPING
	end
	-- Die Rückdreh-Kraft wächst nur bis PLATFORM_ANGULAR_SPRING_LIMIT: darüber reicht ein kräftiger Schub,
	-- um die Plattform ganz herumzudrehen (360°). Zurück geht es immer auf dem kürzeren Weg.
	local springAngle = math.clamp(state.angle, -Constants.PLATFORM_ANGULAR_SPRING_LIMIT, Constants.PLATFORM_ANGULAR_SPRING_LIMIT)
	angularAcceleration += -springAngle * Constants.PLATFORM_ANGULAR_SPRING
		- state.angularVelocity * Constants.PLATFORM_ANGULAR_DAMPING

	state.velocity += acceleration * dt
	state.angularVelocity += angularAcceleration * dt

	-- Grenze: Versatz (Drehen geht dagegen frei um 360°)
	local nextOffset = state.offset + state.velocity * dt
	if nextOffset.Magnitude > Constants.PLATFORM_MAX_OFFSET then
		local outward = nextOffset.Unit
		local outwardSpeed = state.velocity:Dot(outward)
		if outwardSpeed > 0 then
			state.velocity -= outward * outwardSpeed
		end
	end
	state.offset += state.velocity * dt
	state.offset = Vector3.new(state.offset.X, state.offset.Y, 0)
	state.angle = wrapAngle(state.angle + state.angularVelocity * dt)
end

---------------------------------------------------------------------------------------------------
-- Zusammenstöße zwischen Plattformen
---------------------------------------------------------------------------------------------------

-- Nächste Punkte zweier Strecken (2D). Gibt beide Punkte zurück.
local function closestPointsOnSegments(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (Vector3, Vector3)
	local d1, d2 = q1 - p1, q2 - p2
	local r = p1 - p2
	local a, e = d1:Dot(d1), d2:Dot(d2)
	local f = d2:Dot(r)
	local s, t
	if a <= 1e-6 and e <= 1e-6 then
		return p1, p2
	end
	if a <= 1e-6 then
		s, t = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= 1e-6 then
			s, t = math.clamp(-c / a, 0, 1), 0
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			s = if denom > 1e-6 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then
				t, s = 0, math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t, s = 1, math.clamp((b - c) / a, 0, 1)
			end
		end
	end
	return p1 + d1 * s, p2 + d2 * t
end

local function segmentOf(state: PlatformState): (Vector3, Vector3, Vector3)
	local frame = PlatformSim.cframeOf(state)
	local shape = frame * state.shapeFrame
	local a = shape:PointToWorldSpace(Vector3.new(-state.halfLength, 0, 0))
	local b = shape:PointToWorldSpace(Vector3.new(state.halfLength, 0, 0))
	return Vector3.new(a.X, a.Y, 0), Vector3.new(b.X, b.Y, 0), Vector3.new(frame.X, frame.Y, 0)
end

local function cross2(a: Vector3, b: Vector3): number
	return a.X * b.Y - a.Y * b.X
end

-- Zwei Plattformen, die sich überlappen: auseinanderschieben und Stoß austauschen
local function resolvePair(a: PlatformState, b: PlatformState)
	local a1, a2, centerA = segmentOf(a)
	local b1, b2, centerB = segmentOf(b)
	local pa, pb = closestPointsOnSegments(a1, a2, b1, b2)
	local offset = pb - pa
	local distance = offset.Magnitude
	local penetration = a.radius + b.radius - distance
	if penetration <= 0 then
		return
	end
	local normal = if distance > 1e-4 then offset / distance else Vector3.yAxis -- von a nach b
	local contact = (pa + normal * a.radius + pb - normal * b.radius) / 2

	local inverseMassA, inverseMassB = 1 / a.mass, 1 / b.mass
	local inertiaA, inertiaB = a.mass * a.inertiaPerMass, b.mass * b.inertiaPerMass

	-- Auseinanderschieben, schwere Plattformen bewegen sich weniger
	local share = penetration / (inverseMassA + inverseMassB)
	a.offset -= normal * share * inverseMassA
	b.offset += normal * share * inverseMassB

	-- Stoß an der Berührstelle (mit Drehung)
	local ra, rb = contact - centerA, contact - centerB
	local velocityA = a.velocity + Vector3.new(-a.angularVelocity * ra.Y, a.angularVelocity * ra.X, 0)
	local velocityB = b.velocity + Vector3.new(-b.angularVelocity * rb.Y, b.angularVelocity * rb.X, 0)
	local approach = (velocityB - velocityA):Dot(normal)
	if approach >= 0 then
		return -- bewegen sich schon auseinander
	end
	local raN, rbN = cross2(ra, normal), cross2(rb, normal)
	local impulse = -(1 + Constants.PLATFORM_BOUNCE) * approach
		/ (inverseMassA + inverseMassB + raN * raN / inertiaA + rbN * rbN / inertiaB)
	a.velocity -= normal * impulse * inverseMassA
	a.angularVelocity -= raN * impulse / inertiaA
	b.velocity += normal * impulse * inverseMassB
	b.angularVelocity += rbN * impulse / inertiaB
end

local function resolveCollisions(states: { PlatformState })
	for i = 1, #states do
		for j = i + 1, #states do
			resolvePair(states[i], states[j])
		end
	end
end

-- Simulation um dt weiterrechnen (in festen Schritten). now = aktuelle Serverzeit.
function PlatformSim.step(sim: Sim, dt: number, now: number)
	sim.accumulator = math.min(sim.accumulator + dt, 0.25)
	local steps = math.floor(sim.accumulator / SIM_STEP)
	sim.accumulator -= steps * SIM_STEP

	-- Feste Reihenfolge (nach Name), damit alle Rechner Zusammenstöße gleich auflösen
	local states: { PlatformState } = {}
	for model, state in sim.platforms do
		if not model.Parent then
			sim.platforms[model] = nil
		else
			table.insert(states, state)
		end
	end
	table.sort(states, function(a, b)
		return a.model.Name < b.model.Name
	end)

	-- Kräfte der Köpfe gelten für alle Teilschritte dieses Frames
	local pending: { [PlatformState]: { acceleration: Vector3, angular: number } } = {}
	for _, state in states do
		pending[state] = { acceleration = state.pendingAcceleration, angular = state.pendingAngular }
		state.pendingAcceleration, state.pendingAngular = Vector3.zero, 0
	end

	for i = 1, steps do
		local stepTime = now - (steps - i) * SIM_STEP
		for _, state in states do
			state.prevOffset = state.offset
			state.prevAngle = state.angle
		end
		for _, state in states do
			local forces = pending[state]
			stepPlatform(state, SIM_STEP, stepTime, forces.acceleration, forces.angular)
		end
		resolveCollisions(states)
	end
end

-- Alle Plattformen zurück an ihren Startplatz (neue Runde)
function PlatformSim.reset(sim: Sim)
	for _, state in sim.platforms do
		state.offset = Vector3.zero
		state.angle = 0
		state.prevOffset = Vector3.zero
		state.prevAngle = 0
		state.velocity = Vector3.zero
		state.angularVelocity = 0
		state.pendingAcceleration = Vector3.zero
		state.pendingAngular = 0
		table.clear(state.thrusters)
	end
end

-- Lage zum Zeichnen: zwischen den letzten beiden festen Schritten gemischt. Die Physik rechnet in
-- festen Schritten (SIM_RATE pro Sekunde), der Bildschirm zeigt aber 60, 144 ... Bilder pro Sekunde.
-- Ohne Mischen bewegt sich eine schnelle Plattform mal einen, mal zwei, mal keinen Schritt pro Bild
-- und ruckelt. (Liegt höchstens einen Schritt hinter der Physik.)
function PlatformSim.renderFrameOf(sim: Sim, state: PlatformState): CFrame
	local alpha = math.clamp(sim.accumulator / SIM_STEP, 0, 1)
	local offset = state.prevOffset:Lerp(state.offset, alpha)
	local angle = state.prevAngle + wrapAngle(state.angle - state.prevAngle) * alpha
	return CFrame.new(state.home.Position + offset) * CFrame.Angles(0, 0, angle) * state.home.Rotation
end

-- Wurzel-Parts an die (weich gemischte) Lage setzen (nur Client, lokal)
function PlatformSim.apply(sim: Sim)
	for _, state in sim.platforms do
		state.root.CFrame = PlatformSim.renderFrameOf(sim, state)
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
			local shift = (offset - state.offset) * blend
			local turn = wrapAngle(angle - state.angle) * blend
			state.offset += shift
			state.prevOffset += shift
			state.angle += turn
			state.prevAngle += turn
			state.velocity += (velocity - state.velocity) * blend
			state.angularVelocity += (angularVelocity - state.angularVelocity) * blend
		end
	end
end

return PlatformSim
