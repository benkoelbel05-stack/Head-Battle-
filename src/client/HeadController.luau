--!strict
-- Steuert den eigenen Kopf: Laufen, Springen, 2D-Ebene halten.
-- Die Physik-Kugel gehört dem Client (Network Ownership), daher fühlt sich die Bewegung ohne Verzögerung an.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local player = Players.LocalPlayer

local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }
local JUMP_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.ButtonA] = true,
}
local STICK_DEADZONE = 0.25

local HeadController = {}

local myHead: Model? = nil
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local jumpHeld = false
local jumpReleased = false
local lastJumpPressed = -math.huge
local lastGrounded = -math.huge

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

local function readMoveInput(): number
	-- Nicht bewegen, während im Chat getippt wird
	if UserInputService:GetFocusedTextBox() then
		return 0
	end

	local x = 0
	if anyKeyDown(LEFT_KEYS) then
		x -= 1
	end
	if anyKeyDown(RIGHT_KEYS) then
		x += 1
	end

	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(input.Position.X) > STICK_DEADZONE then
				x = input.Position.X
			end
		end
	end

	-- TODO (Phase 3): Touch-Steuerung für Handys

	return math.clamp(x, -1, 1)
end

local function isGrounded(body: BasePart): boolean
	local radius = Constants.HEAD_RADIUS
	local rayLength = radius + 0.3
	-- Drei Strahlen nach unten, damit man auch auf Kanten als "am Boden" zählt
	for _, offset in { 0, -0.7, 0.7 } do
		local origin = body.Position + Vector3.new(offset * radius, 0, 0)
		if Workspace:Raycast(origin, Vector3.new(0, -rayLength, 0), raycastParams) then
			return true
		end
	end
	return false
end

local function step(_dt: number)
	local head = myHead
	if not head or not head.Parent then
		return
	end
	local body = head.PrimaryPart
	if not body then
		return
	end
	local dt = math.min(_dt, 1 / 20)

	local now = os.clock()
	local grounded = isGrounded(body)
	if grounded then
		lastGrounded = now
	end

	local velocity = body.AssemblyLinearVelocity

	-- Laufen
	local target = readMoveInput() * Constants.MOVE_SPEED
	local accel = if grounded then Constants.GROUND_ACCEL else Constants.AIR_ACCEL
	local vx = moveTowards(velocity.X, target, accel * dt)
	local vy = velocity.Y

	-- Springen (mit Coyote Time und Sprung-Puffer)
	local jumpBuffered = now - lastJumpPressed <= Constants.JUMP_BUFFER
	local canJump = now - lastGrounded <= Constants.COYOTE_TIME
	if jumpBuffered and canJump then
		vy = Constants.JUMP_VELOCITY
		lastJumpPressed = -math.huge
		lastGrounded = -math.huge
	end

	-- Variable Sprunghöhe: früh loslassen = niedriger Sprung
	if jumpReleased then
		jumpReleased = false
		if vy > 0 then
			vy *= Constants.JUMP_CUT_MULTIPLIER
		end
	end

	vy = math.max(vy, -Constants.MAX_FALL_SPEED)
	body.AssemblyLinearVelocity = Vector3.new(vx, vy, 0)

	-- Auf der 2D-Ebene halten und nicht rollen lassen
	local position = body.Position
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
		raycastParams.FilterDescendantsInstances = { child }
	end
end

function HeadController.start()
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
