--!strict
-- Knet-Look für alle Köpfe, lokal auf jedem Client:
--   * Position folgt jeden Frame flüssig der unsichtbaren Kugel
--   * Form (Squash & Stretch, "Wabern") und Drehung ändern sich nur 12-mal pro Sekunde -> Stop-Motion-Gefühl
--   * Der Kopf dreht sich so, dass sein "Oben" von der Fläche weg zeigt (an Wand und Decke)
--   * Quetschen beim Aufprall gegen die Fläche
--   * Augen schauen in Laufrichtung
--   * Kleidung (= Fähigkeiten) sitzt an ihrer Stelle (oben, Augen, unten) und wird grau, solange sie abklingt

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)

type HeadState = {
	angle: number, -- Drehung um die Kamera-Achse (0 = aufrecht), nur im Stop-Motion-Takt geändert
	scale: Vector3, -- Form in Kopf-Koordinaten (x = quer, y = von der Fläche weg)
	offset: Vector3, -- Verschiebung, damit die gequetschte Seite an der Fläche bleibt
	eyeJitter: Vector3,
	facing: number,
	previousSpeed: number,
	squashTimer: number,
}

local IMPACT_SQUASH_TIME = 0.15
local IMPACT_SPEED_DROP = 30 -- so stark muss die Geschwindigkeit einbrechen, damit gequetscht wird
local TURN_PER_POSE = 0.6 -- pro Stop-Motion-Bild so viel der restlichen Drehung ausführen
local SURFACE_SEARCH = 0.4 -- so weit darf ein Kopf von der Fläche weg sein und gilt noch als "dran"
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder aufrecht stellen (für Hüte)

local ClayAnimator = {}

local states: { [Model]: HeadState } = {}
local random = Random.new()
local frameTimer = 0
local shapes: { PlatformShapes.Shape } = {}

local function getState(head: Model): HeadState
	local state = states[head]
	if not state then
		state = {
			angle = 0,
			scale = Vector3.one,
			offset = Vector3.zero,
			eyeJitter = Vector3.zero,
			facing = 1,
			previousSpeed = 0,
			squashTimer = 0,
		}
		states[head] = state
	end
	return state
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Wird 12-mal pro Sekunde aufgerufen: neue "Knet-Pose" berechnen
local function stopMotionStep(body: BasePart, state: HeadState, frameTime: number)
	local velocity = body.AssemblyLinearVelocity
	-- Jeder Client rechnet für alle Köpfe selbst aus, an welcher Fläche sie kleben (kein Netzwerk nötig)
	local normal = PlatformShapes.nearestNormal(shapes, body.Position, Constants.HEAD_RADIUS, SURFACE_SEARCH)

	-- Drehen: an einer Fläche zeigt "oben" von ihr weg, in der Luft wieder aufrecht
	local targetAngle = if normal then math.atan2(-normal.X, normal.Y) else 0
	state.angle = wrapAngle(state.angle + wrapAngle(targetAngle - state.angle) * TURN_PER_POSE)

	-- Geschwindigkeit in Kopf-Koordinaten (x = entlang der Fläche, y = von der Fläche weg)
	local rotation = CFrame.Angles(0, 0, state.angle)
	local localVelocity = rotation:VectorToObjectSpace(velocity)
	if math.abs(localVelocity.X) > 1 then
		state.facing = math.sign(localVelocity.X)
	end

	-- Aufprall erkennen: eben noch schnell, jetzt deutlich langsamer, und eine Fläche ist da
	local speed = velocity.Magnitude
	if normal and state.previousSpeed - speed > IMPACT_SPEED_DROP then
		state.squashTimer = IMPACT_SQUASH_TIME
	end
	state.previousSpeed = speed
	state.squashTimer = math.max(0, state.squashTimer - frameTime)

	local sx, sy = 1, 1
	local offset = Vector3.zero
	if state.squashTimer > 0 and normal then
		-- Plattgedrückt gegen die Fläche, die gequetschte Seite bleibt an der Fläche
		local squash = 0.72
		sx, sy = 1.25, squash
		offset = -normal * (1 - squash) * Constants.HEAD_RADIUS
	else
		-- In Bewegungsrichtung in die Länge gezogen (z. B. beim Springen oder Dashen)
		local stretchX = math.clamp(math.abs(localVelocity.X) * 0.003, 0, 0.3)
		local stretchY = math.clamp(math.abs(localVelocity.Y) * 0.004, 0, 0.3)
		sx = 1 + stretchX - stretchY * 0.6
		sy = 1 + stretchY - stretchX * 0.6
	end

	-- "Wabern": jede Pose ist minimal anders, wie echte Knete zwischen zwei Fotos
	local boil = Constants.BOIL_AMOUNT
	sx *= 1 + random:NextNumber(-boil, boil)
	sy *= 1 + random:NextNumber(-boil, boil)
	local sz = 1 + random:NextNumber(-boil, boil)
	state.scale = Vector3.new(sx, sy, sz)
	state.offset = offset

	local eyeBoil = Constants.HEAD_RADIUS * 0.04
	state.eyeJitter = Vector3.new(random:NextNumber(-eyeBoil, eyeBoil), random:NextNumber(-eyeBoil, eyeBoil), 0)
end

-- Kleidung an ihre Stelle setzen. Hüte ("Top") werden gestapelt, alles dreht mit dem Kopf.
-- Neue Stellen (z. B. "Side") hier ergänzen.
local function placeWearables(head: Model, headFrame: CFrame, state: HeadState)
	local radius = Constants.HEAD_RADIUS
	local scale = state.scale
	local now = Workspace:GetServerTimeNow()
	local topHeight = radius * scale.Y * 0.9
	local tilt = CFrame.Angles(0, 0, -state.facing * math.rad(10))

	for slot = 1, Abilities.MAX_SLOTS do
		local item = head:FindFirstChild(`Wear{slot}`) :: BasePart?
		local id = item and item:GetAttribute("Ability")
		local info = if typeof(id) == "string" then Abilities.list[id] else nil
		if item and info then
			if info.wearAt == "Top" then
				item.CFrame = headFrame * tilt * CFrame.new(0, topHeight, 0) * CYLINDER_UPRIGHT
				topHeight += item.Size.X * 0.85
			elseif info.wearAt == "Eyes" then
				-- Band auf Augenhöhe, knapp hinter den Augen: die Augen schauen wie Brillengläser heraus
				item.CFrame = headFrame * CFrame.new(0, radius * 0.25 * scale.Y, 0)
				item.Size = Vector3.new(info.size.X * scale.X, info.size.Y, info.size.Z * scale.Z)
			elseif info.wearAt == "Bottom" then
				-- Band unten am Kopf (Schal, Gürtel)
				item.CFrame = headFrame * CFrame.new(0, -radius * 0.5 * scale.Y, 0)
				item.Size = Vector3.new(info.size.X * scale.X, info.size.Y, info.size.Z * scale.Z)
			end

			local readyAt = head:GetAttribute(Abilities.readyAttribute(info.id))
			local coolingDown = typeof(readyAt) == "number" and now < readyAt
			item.Color = if coolingDown then Constants.COOLDOWN_COLOR else info.color
		end
	end
end

-- Wird jeden Frame aufgerufen: Teile an die aktuelle Position setzen
local function placeParts(head: Model, body: BasePart, state: HeadState)
	local visual = head:FindFirstChild("Visual") :: BasePart?
	if not visual then
		return
	end
	local eyeLeft = head:FindFirstChild("EyeLeft") :: BasePart?
	local eyeRight = head:FindFirstChild("EyeRight") :: BasePart?

	local radius = Constants.HEAD_RADIUS
	local scale = state.scale
	local headFrame = CFrame.new(body.Position + state.offset) * CFrame.Angles(0, 0, state.angle)

	visual.Size = Vector3.one * (radius * 2) * scale
	visual.CFrame = headFrame

	-- Augen vorne (Richtung Kamera = +Z), leicht in Laufrichtung verschoben, drehen mit dem Kopf
	local eyeY = radius * 0.25 * scale.Y
	local eyeZ = radius * 0.9 * scale.Z -- vor dem Kopf und vor einem Brillenband
	local lookOffset = state.facing * radius * 0.25
	local spread = radius * 0.32 * scale.X
	if eyeLeft then
		eyeLeft.CFrame = headFrame * CFrame.new(Vector3.new(lookOffset - spread, eyeY, eyeZ) + state.eyeJitter)
	end
	if eyeRight then
		eyeRight.CFrame = headFrame * CFrame.new(Vector3.new(lookOffset + spread, eyeY, eyeZ) + state.eyeJitter)
	end

	placeWearables(head, headFrame, state)
end

function ClayAnimator.start()
	Workspace:WaitForChild(Constants.ARENA_FOLDER)
	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)
	local frameTime = 1 / Constants.STOP_MOTION_FPS

	headsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			states[child] = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		frameTimer += dt
		local newPose = frameTimer >= frameTime
		if newPose then
			frameTimer %= frameTime
			shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
		end

		for _, child in headsFolder:GetChildren() do
			if child:IsA("Model") then
				local body = child:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					local state = getState(child)
					if newPose then
						stopMotionStep(body, state, frameTime)
					end
					placeParts(child, body, state)
				end
			end
		end
	end)
end

return ClayAnimator
