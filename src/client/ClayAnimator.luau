--!strict
-- Knet-Look für alle Köpfe, lokal auf jedem Client:
--   * Position folgt jeden Frame flüssig der Physik-Kugel
--   * Form (Squash & Stretch, "Wabern") ändert sich nur 12-mal pro Sekunde -> Stop-Motion-Gefühl
--   * Quetschen beim Aufprall in jede Richtung (Boden, Wand, Decke)
--   * Augen schauen in Laufrichtung, Hut sitzt oben und wird grau, solange der Dash abklingt

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

type HeadState = {
	scale: Vector3, -- aktuelle Form (x, y, z), nur im Stop-Motion-Takt geändert
	offset: Vector3, -- Verschiebung, damit die gequetschte Seite an der Fläche bleibt
	eyeJitter: Vector3,
	facing: number,
	previousVelocity: Vector3,
	squashTimer: number,
	squashHorizontal: boolean,
	impactDirection: Vector3,
}

local IMPACT_SQUASH_TIME = 0.15
local IMPACT_SPEED_DROP = 30 -- so stark muss die Geschwindigkeit einbrechen, damit gequetscht wird
local HAT_UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder aufrecht stellen

local ClayAnimator = {}

local states: { [Model]: HeadState } = {}
local random = Random.new()
local frameTimer = 0

local function getState(head: Model): HeadState
	local state = states[head]
	if not state then
		state = {
			scale = Vector3.one,
			offset = Vector3.zero,
			eyeJitter = Vector3.zero,
			facing = 1,
			previousVelocity = Vector3.zero,
			squashTimer = 0,
			squashHorizontal = false,
			impactDirection = Vector3.new(0, -1, 0),
		}
		states[head] = state
	end
	return state
end

-- Wird 12-mal pro Sekunde aufgerufen: neue "Knet-Pose" berechnen
local function stopMotionStep(body: BasePart, state: HeadState, frameTime: number)
	local velocity = body.AssemblyLinearVelocity
	local previous = state.previousVelocity

	if math.abs(velocity.X) > 1 then
		state.facing = math.sign(velocity.X)
	end

	-- Aufprall erkennen: eben noch schnell, jetzt deutlich langsamer
	if previous.Magnitude - velocity.Magnitude > IMPACT_SPEED_DROP then
		state.squashTimer = IMPACT_SQUASH_TIME
		state.squashHorizontal = math.abs(previous.X) > math.abs(previous.Y)
		if state.squashHorizontal then
			state.impactDirection = Vector3.new(math.sign(previous.X), 0, 0)
		else
			state.impactDirection = Vector3.new(0, math.sign(previous.Y), 0)
		end
	end
	state.previousVelocity = velocity
	state.squashTimer = math.max(0, state.squashTimer - frameTime)

	local sx, sy = 1, 1
	local offset = Vector3.zero
	if state.squashTimer > 0 then
		-- Plattgedrückt gegen die Fläche, die gequetschte Seite bleibt an der Fläche
		local squash, bulge = 0.72, 1.25
		if state.squashHorizontal then
			sx, sy = squash, bulge
		else
			sx, sy = bulge, squash
		end
		offset = state.impactDirection * (1 - squash) * Constants.HEAD_RADIUS
	else
		-- In Bewegungsrichtung in die Länge gezogen (z. B. beim Springen oder Dashen)
		local stretchX = math.clamp(math.abs(velocity.X) * 0.003, 0, 0.3)
		local stretchY = math.clamp(math.abs(velocity.Y) * 0.004, 0, 0.3)
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

-- Wird jeden Frame aufgerufen: Teile an die aktuelle Position setzen
local function placeParts(head: Model, body: BasePart, state: HeadState)
	local visual = head:FindFirstChild("Visual") :: BasePart?
	if not visual then
		return
	end
	local eyeLeft = head:FindFirstChild("EyeLeft") :: BasePart?
	local eyeRight = head:FindFirstChild("EyeRight") :: BasePart?
	local hat = head:FindFirstChild("Hat1") :: BasePart?

	local radius = Constants.HEAD_RADIUS
	local scale = state.scale
	local center = body.Position + state.offset

	visual.Size = Vector3.one * (radius * 2) * scale
	visual.CFrame = CFrame.new(center)

	-- Augen vorne (Richtung Kamera = +Z), leicht in Laufrichtung verschoben
	local eyeY = radius * 0.25 * scale.Y
	local eyeZ = radius * 0.82 * scale.Z
	local lookOffset = state.facing * radius * 0.25
	local spread = radius * 0.32 * scale.X
	if eyeLeft then
		eyeLeft.CFrame = CFrame.new(center + Vector3.new(lookOffset - spread, eyeY, eyeZ) + state.eyeJitter)
	end
	if eyeRight then
		eyeRight.CFrame = CFrame.new(center + Vector3.new(lookOffset + spread, eyeY, eyeZ) + state.eyeJitter)
	end

	-- Hut oben auf dem Kopf, leicht in Blickrichtung gekippt
	if hat then
		local top = center + Vector3.new(0, radius * scale.Y * 0.9, 0)
		hat.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, -state.facing * math.rad(10)) * HAT_UPRIGHT

		-- Abklingzeit des Dashs (nur beim eigenen Kopf bekannt): Hut grau
		local readyAt = head:GetAttribute("DashReadyAt")
		local coolingDown = typeof(readyAt) == "number" and os.clock() < readyAt
		hat.Color = if coolingDown then Constants.HAT_COOLDOWN_COLOR else Constants.HAT_COLOR
	end
end

function ClayAnimator.start()
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
