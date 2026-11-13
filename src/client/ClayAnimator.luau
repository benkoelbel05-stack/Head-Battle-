--!strict
-- Knet-Look für alle Köpfe, lokal auf jedem Client:
--   * Position folgt jeden Frame flüssig der Physik-Kugel
--   * Form (Squash & Stretch, "Wabern") ändert sich nur 12-mal pro Sekunde -> Stop-Motion-Gefühl
--   * Augen schauen in Laufrichtung

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

type HeadState = {
	scale: Vector3, -- aktuelle Form (x, y, z), nur im Stop-Motion-Takt geändert
	eyeJitter: Vector3,
	facing: number,
	previousVY: number,
	squashTimer: number,
}

local LANDING_SQUASH_TIME = 0.15
local LANDING_SPEED = 30 -- ab dieser Fallgeschwindigkeit wird beim Landen gequetscht

local ClayAnimator = {}

local states: { [Model]: HeadState } = {}
local random = Random.new()
local frameTimer = 0

local function getState(head: Model): HeadState
	local state = states[head]
	if not state then
		state = {
			scale = Vector3.one,
			eyeJitter = Vector3.zero,
			facing = 1,
			previousVY = 0,
			squashTimer = 0,
		}
		states[head] = state
	end
	return state
end

-- Wird 12-mal pro Sekunde aufgerufen: neue "Knet-Pose" berechnen
local function stopMotionStep(head: Model, body: BasePart, state: HeadState, frameTime: number)
	local velocity = body.AssemblyLinearVelocity

	if math.abs(velocity.X) > 1 then
		state.facing = math.sign(velocity.X)
	end

	-- Landung erkennen: eben noch schnell gefallen, jetzt fast still
	if state.previousVY < -LANDING_SPEED and math.abs(velocity.Y) < 5 then
		state.squashTimer = LANDING_SQUASH_TIME
	end
	state.previousVY = velocity.Y
	state.squashTimer = math.max(0, state.squashTimer - frameTime)

	local sx, sy
	if state.squashTimer > 0 then
		-- Plattgedrückt nach der Landung
		sx, sy = 1.25, 0.72
	else
		-- In die Länge gezogen beim Steigen/Fallen
		local stretch = math.clamp(math.abs(velocity.Y) * 0.004, 0, 0.25)
		sx, sy = 1 - stretch * 0.6, 1 + stretch
	end

	-- "Wabern": jede Pose ist minimal anders, wie echte Knete zwischen zwei Fotos
	local boil = Constants.BOIL_AMOUNT
	sx *= 1 + random:NextNumber(-boil, boil)
	sy *= 1 + random:NextNumber(-boil, boil)
	local sz = 1 + random:NextNumber(-boil, boil)
	state.scale = Vector3.new(sx, sy, sz)

	local eyeBoil = Constants.HEAD_RADIUS * 0.04
	state.eyeJitter = Vector3.new(random:NextNumber(-eyeBoil, eyeBoil), random:NextNumber(-eyeBoil, eyeBoil), 0)
end

-- Wird jeden Frame aufgerufen: Teile an die aktuelle Position setzen
local function placeParts(head: Model, body: BasePart, state: HeadState)
	local visual = head:FindFirstChild("Visual") :: BasePart?
	local eyeLeft = head:FindFirstChild("EyeLeft") :: BasePart?
	local eyeRight = head:FindFirstChild("EyeRight") :: BasePart?
	if not visual then
		return
	end

	local radius = Constants.HEAD_RADIUS
	local scale = state.scale
	local position = body.Position

	-- Unterkante bleibt am Boden, auch wenn der Kopf plattgedrückt wird
	local center = position + Vector3.new(0, (scale.Y - 1) * radius, 0)
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
						stopMotionStep(child, body, state, frameTime)
					end
					placeParts(child, body, state)
				end
			end
		end
	end)
end

return ClayAnimator
