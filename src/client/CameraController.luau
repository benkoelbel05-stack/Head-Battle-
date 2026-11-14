--!strict
-- Seitliche Kamera, die sanft so zoomt und schwenkt, dass alle Köpfe im Bild sind.
-- CameraController.impact(stärke) lässt bei Explosionen und Ausscheiden kurz das Bild wackeln
-- (Option "Bildschirmwackeln") und den Controller vibrieren (Option "Controller-Vibration").

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Settings = require(script.Parent.Settings)

-- Wackeln: Ausschlag als Anteil der sichtbaren Bildhöhe (die Kamera ist sehr weit weg), klingt schnell ab
local SHAKE_SCALE = 0.012
local SHAKE_DECAY = 9
local SHAKE_SPEED = 38

local DEFAULT_FOCUS = Vector3.new(0, 10, Constants.PLANE_Z)

local CameraController = {}

local currentFocus = DEFAULT_FOCUS
local currentDistance = Constants.CAMERA_MIN_DISTANCE
local shakeStrength = 0
local shakeClock = 0
local vibrationToken = 0

-- Kurzer Stoß: 0..1 (Explosion ~0,6, eigenes Ausscheiden 1)
function CameraController.impact(strength: number)
	if Settings.get("shake") == true then
		shakeStrength = math.max(shakeStrength, math.clamp(strength, 0, 1))
	end
	if Settings.get("vibration") == true and UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		local gamepad = Enum.UserInputType.Gamepad1
		local ok = pcall(function()
			if HapticService:IsMotorSupported(gamepad, Enum.VibrationMotor.Large) then
				HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, math.clamp(strength, 0, 1))
			end
		end)
		if ok then
			vibrationToken += 1
			local token = vibrationToken
			task.delay(0.12 + 0.18 * strength, function()
				if token == vibrationToken then
					pcall(function()
						HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, 0)
					end)
				end
			end)
		end
	end
end

-- Grenzen der Arena an den Startplätzen der Plattformen. Werden einmal pro Arena gemerkt,
-- damit weggeschobene Plattformen die Kamera nicht mitziehen.
local cachedArena: Instance? = nil
local arenaMin = Vector3.zero
local arenaMax = Vector3.zero

local function updateArenaBounds(arena: Instance)
	if cachedArena == arena then
		return
	end
	local minPoint = Vector3.one * math.huge
	local maxPoint = -Vector3.one * math.huge
	for _, part in arena:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Background" and part.Name ~= "Thruster" and part.Name ~= "Water" and part.Name ~= "WaterLine" then
			local half = part.Size / 2
			minPoint = minPoint:Min(part.Position - half)
			maxPoint = maxPoint:Max(part.Position + half)
		end
	end
	if minPoint.X < math.huge then
		cachedArena = arena
		arenaMin, arenaMax = minPoint, maxPoint
	end
end

-- Die Kamera zeigt immer die ganze Arena. Köpfe außerhalb ziehen sie nur ein kleines Stück mit
-- (höchstens CAMERA_MAX_EXTRA Studs), damit sie beim Runterfallen nicht weit herauszoomt.
local function getTarget(headsFolder: Instance): (Vector3, number)
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local count = 0

	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	if arena then
		updateArenaBounds(arena)
		if cachedArena == arena then
			minX, maxX = arenaMin.X, arenaMax.X
			minY, maxY = arenaMin.Y, arenaMax.Y
			count += 1
		end
	end

	local extra = Constants.CAMERA_MAX_EXTRA
	local hasArena = count > 0
	for _, head in headsFolder:GetChildren() do
		local body = head:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			local p = body.Position
			if hasArena then
				p = Vector3.new(
					math.clamp(p.X, arenaMin.X - extra, arenaMax.X + extra),
					math.clamp(p.Y, arenaMin.Y - extra, arenaMax.Y + extra),
					0
				)
			end
			local r = Constants.HEAD_RADIUS
			minX, maxX = math.min(minX, p.X - r), math.max(maxX, p.X + r)
			minY, maxY = math.min(minY, p.Y - r), math.max(maxY, p.Y + r)
			count += 1
		end
	end

	if count == 0 then
		return DEFAULT_FOCUS, Constants.CAMERA_MIN_DISTANCE
	end

	local padding = Constants.CAMERA_PADDING
	local halfWidth = (maxX - minX) / 2 + padding
	local halfHeight = (maxY - minY) / 2 + padding
	local focus = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, Constants.PLANE_Z)

	-- Abstand so wählen, dass Breite und Höhe ins Bild passen
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanHalfFov = math.tan(math.rad(Constants.CAMERA_FOV) / 2)
	local distance = math.max(halfHeight / tanHalfFov, halfWidth / (tanHalfFov * aspect))
	distance = math.clamp(distance, Constants.CAMERA_MIN_DISTANCE, Constants.CAMERA_MAX_DISTANCE)

	return focus, distance
end

function CameraController.start()
	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)

	RunService:BindToRenderStep("ClayBattleCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FOV

		local targetFocus, targetDistance = getTarget(headsFolder)
		local alpha = 1 - math.exp(-Constants.CAMERA_SMOOTHNESS * dt)
		currentFocus = currentFocus:Lerp(targetFocus, alpha)
		currentDistance += (targetDistance - currentDistance) * alpha

		-- Wackeln: Kamera und Blickpunkt gemeinsam verschieben (kein Kippen), weich abklingend
		local shake = Vector3.zero
		if shakeStrength > 0.001 then
			shakeClock += dt * SHAKE_SPEED
			local viewHeight = 2 * currentDistance * math.tan(math.rad(Constants.CAMERA_FOV) / 2)
			local amount = shakeStrength * shakeStrength * SHAKE_SCALE * viewHeight
			shake = Vector3.new(math.noise(shakeClock, 0.3) * 2, math.noise(0.7, shakeClock) * 2, 0) * amount
			shakeStrength *= math.exp(-SHAKE_DECAY * dt)
		else
			shakeStrength = 0
		end

		-- Kamera steht vor der Arena (+Z) und schaut nach hinten: +X ist rechts im Bild
		local focus = currentFocus + shake
		local cameraPosition = focus + Vector3.new(0, 0, currentDistance)
		camera.CFrame = CFrame.lookAt(cameraPosition, focus)
	end)
end

return CameraController
