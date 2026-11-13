--!strict
-- Bewegung eines Kopfes. Wird vom Client (eigener Kopf) und vom Server (Bots) gleich benutzt.
--
-- Bewegung ohne Roblox-Kollisionen, exakt gegen die Plattform-Formen (PlatformShapes):
--   * Klebt der Kopf an einer Plattform, läuft er auf einem geschlossenen Ring um sie herum
--     (oben, Rundung, unten, Rundung). Herunterfallen beim Entlanglaufen ist so unmöglich,
--     um die Ecken geht es gleichmäßig, und bewegt sich die Plattform, fährt der Kopf mit.
--   * In der Luft: eigene Schwerkraft. Berührt der Kopf eine Plattform, klebt er an und
--     behält seinen Schwung entlang der Fläche (gleitet weiter).
--   * Dash: gerade Linie, klebt an, sobald er eine Plattform trifft.
--
--   * Andere Köpfe sind feste Kugeln: man prallt an ihnen ab bzw. wird an der Fläche gebremst.
--
-- Gerechnet wird in festen Schritten (SIM_RATE pro Sekunde), damit Sprunghöhen und Wege nicht von der
-- Bildrate abhängen. Für die Anzeige wird in der Luft zwischen den Schritten überblendet.
--
-- Eingaben: input (Richtung), jumpPressedAt (Zeitpunkt des letzten Sprung-Drucks), jumpReleased.
-- Zeit: beliebige gleichmäßige Uhr (os.clock), Hauptsache immer dieselbe.

local Constants = require(script.Parent.Constants)
local PlatformShapes = require(script.Parent.PlatformShapes)

local R = Constants.HEAD_RADIUS
local MAX_SUBSTEP = 0.4 -- so weit bewegt sich der Kopf pro Kollisionsprüfung höchstens (Studs)
local SWITCH_COOLDOWN = 0.2 -- Mindestzeit zwischen zwei Plattform-Wechseln beim Entlanglaufen
local STEP = 1 / Constants.SIM_RATE
local HEAD_DISTANCE = R * 2 -- so nah kommen sich zwei Kopf-Mittelpunkte höchstens

export type Motor = {
	position: Vector3,
	previousPosition: Vector3, -- Position vor dem letzten Schritt (zum Überblenden)
	accumulator: number,
	velocity: Vector3,
	facing: number,

	-- Kleben
	attachedShape: PlatformShapes.Shape?,
	attachedU: number, -- Position auf dem Ring um die Plattform
	alongSpeed: number, -- Geschwindigkeit entlang des Rings
	lastShapeFrame: CFrame?, -- Lage der Plattform im letzten Frame (zum Mitfahren)
	crawlDirection: number, -- Laufrichtung entlang des Rings (+1 / -1), bleibt um Ecken erhalten
	detachUntil: number,
	detachedShape: PlatformShapes.Shape?, -- von dieser Plattform hat man sich gerade gelöst
	detachedNormal: Vector3, -- ... und zwar von dieser Seite
	attachedAt: number, -- wann man zuletzt angeklebt ist
	lastSwitch: number,

	-- Springen (vom Steuernden gesetzt)
	jumpPressedAt: number,
	jumpReleased: boolean,

	-- Dash
	dashUntil: number,
	dashDirection: Vector3,
}

local HeadMotor = {}

function HeadMotor.new(position: Vector3): Motor
	local start = Vector3.new(position.X, position.Y, Constants.PLANE_Z)
	return {
		position = start,
		previousPosition = start,
		accumulator = 0,
		velocity = Vector3.zero,
		facing = 1,
		attachedShape = nil,
		attachedU = 0,
		alongSpeed = 0,
		lastShapeFrame = nil,
		crawlDirection = 0,
		detachUntil = 0,
		detachedShape = nil,
		detachedNormal = Vector3.yAxis,
		attachedAt = 0,
		lastSwitch = 0,
		jumpPressedAt = -math.huge,
		jumpReleased = false,
		dashUntil = 0,
		dashDirection = Vector3.xAxis,
	}
end

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

-- Ring-Radius um eine Plattform (Bahn des Kopf-Mittelpunkts)
local function ringRadius(shape: PlatformShapes.Shape): number
	return shape.radius + R
end

-- Normale (Welt) an der aktuellen Klebestelle, oder nil in der Luft
function HeadMotor.attachedNormal(motor: Motor): Vector3?
	local shape = motor.attachedShape
	if not shape then
		return nil
	end
	local _, localNormal = PlatformShapes.boundaryPoint(shape.halfLength, ringRadius(shape), motor.attachedU)
	return PlatformShapes.frame(shape):VectorToWorldSpace(localNormal)
end

local function attachTo(motor: Motor, shape: PlatformShapes.Shape, now: number)
	local frame = PlatformShapes.frame(shape)
	local rho = ringRadius(shape)
	local localPoint = frame:PointToObjectSpace(motor.position)
	local u = PlatformShapes.boundaryParam(shape.halfLength, rho, localPoint)
	local ringPoint, localNormal = PlatformShapes.boundaryPoint(shape.halfLength, rho, u)
	local localTangent = PlatformShapes.tangent(localNormal)

	-- Schwung entlang der Fläche behalten: so gleitet man nach der Landung weiter
	local localVelocity = frame:VectorToObjectSpace(motor.velocity)
	motor.alongSpeed = (localVelocity.X * localTangent.X + localVelocity.Y * localTangent.Y) * Constants.LANDING_KEEP
	motor.crawlDirection = 0

	motor.attachedShape = shape
	motor.attachedU = u
	motor.lastShapeFrame = frame
	motor.lastSwitch = now
	motor.attachedAt = now
	motor.position = frame:PointToWorldSpace(ringPoint)
end

-- Lösen. Für lockTime Sekunden klebt man nicht wieder an DIESER Seite DIESER Plattform an (sonst würde
-- man beim Absprung sofort wieder festkleben). Andere Plattformen und andere Seiten greifen sofort.
function HeadMotor.detach(motor: Motor, now: number, lockTime: number)
	motor.detachedNormal = HeadMotor.attachedNormal(motor) or Vector3.yAxis
	motor.detachedShape = motor.attachedShape
	motor.attachedShape = nil
	motor.lastShapeFrame = nil
	motor.detachUntil = now + lockTime
end

-- Dash starten
function HeadMotor.startDash(motor: Motor, now: number, direction: Vector3)
	local flat = Vector3.new(direction.X, direction.Y, 0)
	motor.dashDirection = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(motor.facing, 0, 0)
	motor.dashUntil = now + Constants.DASH_TIME
	HeadMotor.detach(motor, now, 0.05)
end

function HeadMotor.isDashing(motor: Motor, now: number): boolean
	return now < motor.dashUntil
end

-- Überlappt der Kopf an dieser Stelle einen anderen Kopf? Gibt die Richtung weg vom anderen zurück.
local function headOverlap(position: Vector3, others: { Vector3 }): (Vector3?, number)
	for _, other in others do
		local offset = Vector3.new(position.X - other.X, position.Y - other.Y, 0)
		local distance = offset.Magnitude
		if distance < HEAD_DISTANCE then
			local away = if distance > 0.001 then offset / distance else Vector3.yAxis
			return away, HEAD_DISTANCE - distance
		end
	end
	return nil, 0
end

-- In der Luft: aus anderen Köpfen herausschieben und die Bewegung in sie hinein stoppen
local function pushOutOfHeads(motor: Motor, others: { Vector3 })
	local away, depth = headOverlap(motor.position, others)
	if away then
		motor.position += away * depth
		local into = motor.velocity:Dot(away)
		if into < 0 then
			motor.velocity -= away * into
		end
	end
end

-- Kopf bewegen und dabei auf Plattformen prüfen. Gibt true zurück, wenn er angeklebt ist.
local function moveWithCollisions(motor: Motor, dt: number, shapes: { PlatformShapes.Shape }, now: number, others: { Vector3 }): boolean
	local delta = motor.velocity * dt
	local steps = math.max(1, math.ceil(delta.Magnitude / MAX_SUBSTEP))

	for _ = 1, steps do
		motor.position += delta / steps
		pushOutOfHeads(motor, others)
		for _, shape in shapes do
			local frame = PlatformShapes.frame(shape)
			local localPoint = frame:PointToObjectSpace(motor.position)
			local distance, closest = PlatformShapes.closest(shape.halfLength, localPoint)
			local rho = ringRadius(shape)
			if distance < rho then
				local localNormal = if distance > 0.001
					then (Vector3.new(localPoint.X, localPoint.Y, 0) - closest) / distance
					else Vector3.yAxis
				local sameSide = frame:VectorToWorldSpace(localNormal):Dot(motor.detachedNormal) > 0.5
				if now >= motor.detachUntil or shape ~= motor.detachedShape or not sameSide then
					attachTo(motor, shape, now)
					return true
				end
				-- Kurz nach dem Absprung von genau dieser Seite: nur herausschieben, nicht ankleben
				motor.position = frame:PointToWorldSpace(closest + localNormal * rho)
				local normal = frame:VectorToWorldSpace(localNormal)
				local into = motor.velocity:Dot(normal)
				if into < 0 then
					motor.velocity -= normal * into
				end
			end
		end
	end
	return false
end

local function stepAttached(motor: Motor, dt: number, input: Vector3, now: number, shapes: { PlatformShapes.Shape }, others: { Vector3 })
	local shape = motor.attachedShape :: PlatformShapes.Shape
	local frame = PlatformShapes.frame(shape)
	local rho = ringRadius(shape)
	local L = shape.halfLength

	-- Laufrichtung: Zeigt die Eingabe klar entlang der Fläche, gilt sie. Steht sie quer zur Fläche
	-- (z. B. "rechts" an einer senkrechten Seite nach dem Herumlaufen um eine Ecke), läuft der Kopf
	-- in seiner bisherigen Richtung weiter.
	local _, currentNormal = PlatformShapes.boundaryPoint(L, rho, motor.attachedU)
	local tangent = PlatformShapes.tangent(currentNormal)
	local localInput = frame:VectorToObjectSpace(input)
	local inputAlong = localInput.X * tangent.X + localInput.Y * tangent.Y
	if input.Magnitude < 0.1 then
		motor.crawlDirection = 0
	elseif math.abs(inputAlong) > 0.7 then
		motor.crawlDirection = math.sign(inputAlong)
	elseif motor.crawlDirection == 0 and math.abs(inputAlong) > 0.1 then
		motor.crawlDirection = math.sign(inputAlong)
	end

	-- Beschleunigen bzw. ohne Eingabe weich ausgleiten
	local target = motor.crawlDirection * Constants.MOVE_SPEED
	local rate = if motor.crawlDirection ~= 0 then Constants.GROUND_ACCEL else Constants.GROUND_FRICTION
	motor.alongSpeed = moveTowards(motor.alongSpeed, target, rate * dt)
	local previousU = motor.attachedU
	motor.attachedU += motor.alongSpeed * dt

	local ringPoint, localNormal = PlatformShapes.boundaryPoint(L, rho, motor.attachedU)
	local newPosition = frame:PointToWorldSpace(ringPoint)

	-- Anderer Kopf im Weg: nicht hineinlaufen (zurück auf die alte Stelle, Schwung weg)
	local blockedBy = headOverlap(newPosition, others)
	if blockedBy and motor.alongSpeed ~= 0 then
		local oldPoint, oldNormal = PlatformShapes.boundaryPoint(L, rho, previousU)
		local oldPosition = frame:PointToWorldSpace(oldPoint)
		local stillOverlap = headOverlap(oldPosition, others)
		-- Nur blockieren, wenn man sich dem anderen Kopf nähert (sonst kann man sich wegbewegen)
		if not stillOverlap or (newPosition - oldPosition):Dot(blockedBy) < 0 then
			motor.attachedU = previousU
			motor.alongSpeed = 0
			ringPoint, localNormal = oldPoint, oldNormal
			newPosition = oldPosition
		end
	end

	-- Mitfahren: wie weit hat sich dieser Punkt der Plattform seit dem letzten Frame bewegt?
	local platformVelocity = Vector3.zero
	local lastFrame = motor.lastShapeFrame
	if lastFrame and dt > 0 then
		local moved = newPosition - lastFrame:PointToWorldSpace(ringPoint)
		platformVelocity = Vector3.new(moved.X, moved.Y, 0) / dt
	end
	motor.lastShapeFrame = frame

	local worldNormal = frame:VectorToWorldSpace(localNormal)
	local worldTangent = frame:VectorToWorldSpace(PlatformShapes.tangent(localNormal))
	motor.position = newPosition
	motor.velocity = worldTangent * motor.alongSpeed + platformVelocity

	-- Absprung: weg von der Fläche, etwas Laufschwung mitnehmen.
	-- An einer Decke zählt nur ein Druck NACH dem Ankleben (sonst fällt man sofort wieder herunter).
	local onCeiling = worldNormal.Y < -0.5
	local pressedInTime = now - motor.jumpPressedAt <= Constants.JUMP_BUFFER
	if pressedInTime and (not onCeiling or motor.jumpPressedAt >= motor.attachedAt) then
		motor.jumpPressedAt = -math.huge
		local jumpDirection = worldNormal
		if math.abs(worldNormal.X) > 0.5 then
			jumpDirection = (worldNormal + Vector3.new(0, Constants.WALL_JUMP_LIFT, 0)).Unit
		end
		motor.velocity = jumpDirection * Constants.JUMP_VELOCITY
			+ worldTangent * motor.alongSpeed * Constants.JUMP_KEEP_ALONG
			+ platformVelocity
		HeadMotor.detach(motor, now, Constants.DETACH_TIME)
		return
	end

	-- Ragt eine andere Plattform in den Weg (z. B. weggeschobene Plattform), auf sie umsteigen
	if now - motor.lastSwitch > SWITCH_COOLDOWN then
		for _, other in shapes do
			if other ~= shape then
				local otherFrame = PlatformShapes.frame(other)
				local distance = PlatformShapes.closest(other.halfLength, otherFrame:PointToObjectSpace(motor.position))
				if distance < ringRadius(other) - 0.15 then
					attachTo(motor, other, now)
					break
				end
			end
		end
	end
end

local function stepAir(motor: Motor, dt: number, input: Vector3, now: number, shapes: { PlatformShapes.Shape }, others: { Vector3 })
	local velocity = motor.velocity
	local vx = moveTowards(velocity.X, input.X * Constants.MOVE_SPEED, Constants.AIR_ACCEL * dt)
	local vy = velocity.Y - Constants.GRAVITY * dt
	if motor.jumpReleased and vy > 0 then
		vy *= Constants.JUMP_CUT_MULTIPLIER -- früh loslassen = niedriger Sprung
	end
	vy = math.max(vy, -Constants.MAX_FALL_SPEED)
	motor.velocity = Vector3.new(vx, vy, 0)
	moveWithCollisions(motor, dt, shapes, now, others)
end

-- Einen festen Schritt weiterrechnen. others = Mittelpunkte der anderen Köpfe.
function HeadMotor.step(motor: Motor, dt: number, now: number, input: Vector3, shapes: { PlatformShapes.Shape }, others: { Vector3 })
	if math.abs(input.X) > 0.1 then
		motor.facing = math.sign(input.X)
	end

	-- Angeklebte Plattform verschwunden (z. B. Arena neu gebaut)
	if motor.attachedShape and not table.find(shapes, motor.attachedShape) then
		HeadMotor.detach(motor, now, 0)
	end

	if now < motor.dashUntil then
		-- Dash: gerade Linie, keine Schwerkraft; klebt an, sobald er eine Plattform trifft
		motor.velocity = motor.dashDirection * Constants.DASH_SPEED
		if moveWithCollisions(motor, dt, shapes, now, others) then
			motor.dashUntil = 0
		end
	else
		if motor.dashUntil > 0 then
			-- Dash gerade vorbei: etwas Schwung behalten
			motor.dashUntil = 0
			motor.velocity = motor.dashDirection * Constants.DASH_SPEED * Constants.DASH_END_KEEP
		end
		if motor.attachedShape then
			stepAttached(motor, dt, input, now, shapes, others)
		else
			stepAir(motor, dt, input, now, shapes, others)
		end
	end
	motor.jumpReleased = false
	motor.position = Vector3.new(motor.position.X, motor.position.Y, Constants.PLANE_Z)
end

-- Um dt weiterrechnen, in festen Schritten. Gibt den Überblend-Anteil (0..1) für die Anzeige zurück.
function HeadMotor.update(motor: Motor, dt: number, now: number, input: Vector3, shapes: { PlatformShapes.Shape }, others: { Vector3 }): number
	motor.accumulator = math.min(motor.accumulator + dt, 0.25)
	local steps = math.floor(motor.accumulator / STEP)
	motor.accumulator -= steps * STEP
	for i = 1, steps do
		motor.previousPosition = motor.position
		HeadMotor.step(motor, STEP, now - (steps - i) * STEP, input, shapes, others)
	end
	return motor.accumulator / STEP
end

-- Position für die Anzeige. In der Luft weich zwischen den Schritten überblendet; an einer Plattform
-- genau auf dem letzten Schritt, damit der Kopf exakt auf der (ebenfalls schrittweise bewegten) Plattform sitzt.
function HeadMotor.renderPosition(motor: Motor, alpha: number): Vector3
	if motor.attachedShape then
		return motor.position
	end
	return motor.previousPosition:Lerp(motor.position, alpha)
end

return HeadMotor
