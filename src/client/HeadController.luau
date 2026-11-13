--!strict
-- Steuert den eigenen Kopf: Laufen, Springen und an Boden, Wand und Decke haften.
-- Die Physik-Kugel gehört dem Client (Network Ownership), daher fühlt sich die Bewegung ohne Verzögerung an.
-- Die Schwerkraft rechnen wir selbst (Workspace.Gravity = 0), damit Haften an Wand und Decke sauber funktioniert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local player = Players.LocalPlayer

local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }
local UP_KEYS = { Enum.KeyCode.W, Enum.KeyCode.Up }
local DOWN_KEYS = { Enum.KeyCode.S, Enum.KeyCode.Down }
local JUMP_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}
-- Hut 1 (Fliegerkappe = Dash)
local DASH_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.One] = true,
	[Enum.KeyCode.K] = true,
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.ButtonL1] = true,
}
local STICK_DEADZONE = 0.25

-- In diese acht Richtungen wird nach Flächen gesucht (diagonal, damit man um runde Kanten herumläuft)
local DIAGONAL = math.sqrt(0.5)
local DIRECTIONS = {
	Vector3.new(0, -1, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(1, 0, 0),
	Vector3.new(DIAGONAL, DIAGONAL, 0),
	Vector3.new(-DIAGONAL, DIAGONAL, 0),
	Vector3.new(DIAGONAL, -DIAGONAL, 0),
	Vector3.new(-DIAGONAL, -DIAGONAL, 0),
}

local HeadController = {}

local myHead: Model? = nil
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include -- nur die Arena zählt als Fläche

local surfaceNormal: Vector3? = nil -- nil = in der Luft
local lastSurfaceNormal = Vector3.yAxis
local lastAttached = -math.huge
local detachUntil = 0

local facing = 1

local dashPressed = false
local dashUntil = 0
local dashReadyAt = 0
local dashDirection = Vector3.xAxis

local jumpHeld = false
local jumpReleased = false
local lastJumpPressed = -math.huge

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- Eingabe als Richtung in der 2D-Ebene (X = rechts, Y = oben)
local function readInput(): Vector3
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end

	local x, y = 0, 0
	if anyKeyDown(LEFT_KEYS) then
		x -= 1
	end
	if anyKeyDown(RIGHT_KEYS) then
		x += 1
	end
	if anyKeyDown(UP_KEYS) then
		y += 1
	end
	if anyKeyDown(DOWN_KEYS) then
		y -= 1
	end

	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local stick = Vector3.new(input.Position.X, input.Position.Y, 0)
				if stick.Magnitude > STICK_DEADZONE then
					x, y = stick.X, stick.Y
				end
			end
		end
	end

	-- TODO (Phase 3): Touch-Steuerung für Handys

	local direction = Vector3.new(x, y, 0)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	return direction
end

-- Flächennormale auf die 2D-Ebene drücken
local function flatNormal(normal: Vector3): Vector3
	local flat = Vector3.new(normal.X, normal.Y, 0)
	if flat.Magnitude < 0.01 then
		return Vector3.yAxis
	end
	return flat.Unit
end

-- Sucht die Fläche, an der der Kopf haften soll.
-- moveDir: Richtung, in die sich der Spieler bewegen will (bevorzugt z. B. die Wand, auf die man zuläuft).
local function findSurface(position: Vector3, moveDir: Vector3): Vector3?
	local length = Constants.HEAD_RADIUS + Constants.STICK_DISTANCE
	local best: Vector3? = nil
	local bestScore = -math.huge

	for _, direction in DIRECTIONS do
		local hit = Workspace:Raycast(position, direction * length, raycastParams)
		if hit then
			local normal = flatNormal(hit.Normal)
			local score = -hit.Distance + moveDir:Dot(-normal) * 10
			-- Die aktuelle Fläche leicht bevorzugen, damit es nicht hin- und herspringt
			if surfaceNormal and normal:Dot(surfaceNormal) > 0.9 then
				score += 2
			end
			if score > bestScore then
				best, bestScore = normal, score
			end
		end
	end

	return best
end

local function step(rawDt: number)
	local head = myHead
	if not head or not head.Parent then
		return
	end
	local body = head.PrimaryPart
	if not body then
		return
	end

	local dt = math.min(rawDt, 1 / 20)
	local now = os.clock()
	local input = readInput()
	local velocity = body.AssemblyLinearVelocity
	local position = body.Position
	if math.abs(input.X) > 0.1 then
		facing = math.sign(input.X)
	end

	-- Dash starten (in Eingaberichtung, ohne Eingabe in Blickrichtung)
	if dashPressed then
		dashPressed = false
		if now >= dashReadyAt then
			dashDirection = if input.Magnitude > 0.1 then input.Unit else Vector3.new(facing, 0, 0)
			dashUntil = now + Constants.DASH_TIME
			dashReadyAt = now + Constants.DASH_COOLDOWN
			detachUntil = dashUntil
			surfaceNormal = nil
			head:SetAttribute("DashReadyAt", dashReadyAt)
		end
	end

	-- Während des Dashs: gerade Linie, keine Schwerkraft
	if now < dashUntil then
		body.AssemblyLinearVelocity = dashDirection * Constants.DASH_SPEED
		body.CFrame = CFrame.new(position.X, position.Y, Constants.PLANE_Z)
		body.AssemblyAngularVelocity = Vector3.zero
		return
	elseif dashUntil > 0 then
		-- Dash gerade vorbei: etwas Schwung behalten
		dashUntil = 0
		velocity = dashDirection * Constants.DASH_SPEED * Constants.DASH_END_KEEP
	end

	-- 1. Fläche suchen (kurz nach einem Absprung nicht, sonst klebt man sofort wieder fest)
	if now >= detachUntil then
		local moveDir = input
		if not surfaceNormal and velocity.Magnitude > 1 then
			moveDir = velocity.Unit
		end
		surfaceNormal = findSurface(position, moveDir)
	else
		surfaceNormal = nil
	end
	if surfaceNormal then
		lastAttached = now
		lastSurfaceNormal = surfaceNormal
	end

	local jumpBuffered = now - lastJumpPressed <= Constants.JUMP_BUFFER
	local canJump = now - lastAttached <= Constants.COYOTE_TIME
	local newVelocity: Vector3

	if jumpBuffered and canJump then
		-- 2a. Absprung: weg von der Fläche
		local normal = lastSurfaceNormal
		local jumpDir = normal
		if math.abs(normal.X) > 0.5 then
			-- Von der Wand: schräg nach oben weg
			jumpDir = (normal + Vector3.new(0, Constants.WALL_JUMP_LIFT, 0)).Unit
		end
		newVelocity = jumpDir * Constants.JUMP_VELOCITY
		surfaceNormal = nil
		detachUntil = now + Constants.DETACH_TIME
		lastJumpPressed = -math.huge
		lastAttached = -math.huge
	elseif surfaceNormal then
		-- 2b. Haften: an der Fläche entlang laufen, leicht an sie gedrückt
		local normal = surfaceNormal
		local tangent = Vector3.new(normal.Y, -normal.X, 0)
		local along = velocity:Dot(tangent)
		local target = input:Dot(tangent) * Constants.MOVE_SPEED
		along = moveTowards(along, target, Constants.GROUND_ACCEL * dt)
		newVelocity = tangent * along - normal * Constants.STICK_SPEED
	else
		-- 2c. In der Luft: eigene Schwerkraft, etwas Luftsteuerung
		local vx = moveTowards(velocity.X, input.X * Constants.MOVE_SPEED, Constants.AIR_ACCEL * dt)
		local vy = velocity.Y - Constants.GRAVITY * dt
		if jumpReleased and vy > 0 then
			vy *= Constants.JUMP_CUT_MULTIPLIER -- früh loslassen = niedriger Sprung
		end
		vy = math.max(vy, -Constants.MAX_FALL_SPEED)
		newVelocity = Vector3.new(vx, vy, 0)
	end
	jumpReleased = false

	body.AssemblyLinearVelocity = newVelocity

	-- Auf der 2D-Ebene halten und nicht rollen lassen
	body.CFrame = CFrame.new(position.X, position.Y, Constants.PLANE_Z)
	body.AssemblyAngularVelocity = Vector3.zero
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if JUMP_KEYS[input.KeyCode] then
		jumpHeld = true
		lastJumpPressed = os.clock()
	elseif DASH_KEYS[input.KeyCode] then
		dashPressed = true
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if JUMP_KEYS[input.KeyCode] and jumpHeld then
		jumpHeld = false
		jumpReleased = true
	end
end

local function trackHead(child: Instance)
	if child:IsA("Model") and child:GetAttribute("UserId") == player.UserId then
		myHead = child
		surfaceNormal = nil
		detachUntil = 0
		dashUntil = 0
		dashReadyAt = 0
		print("[HeadBattle] Eigener Kopf gefunden")
	end
end

local function trackArena(child: Instance)
	if child.Name == Constants.ARENA_FOLDER then
		raycastParams.FilterDescendantsInstances = { child }
	end
end

function HeadController.start()
	Workspace.ChildAdded:Connect(trackArena)
	trackArena(Workspace:WaitForChild(Constants.ARENA_FOLDER))

	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)
	headsFolder.ChildAdded:Connect(trackHead)
	for _, child in headsFolder:GetChildren() do
		trackHead(child)
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.Heartbeat:Connect(step)
end

return HeadController
