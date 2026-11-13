--!strict
-- Seitliche Kamera, die sanft so zoomt und schwenkt, dass alle Köpfe im Bild sind.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local DEFAULT_FOCUS = Vector3.new(0, 10, Constants.PLANE_Z)

local CameraController = {}

local currentFocus = DEFAULT_FOCUS
local currentDistance = Constants.CAMERA_MIN_DISTANCE

-- Die Kamera zeigt immer die ganze Arena (alle Plattformen) und zusätzlich alle Köpfe,
-- auch wenn einer z. B. hoch über die Arena springt.
local function getTarget(headsFolder: Instance): (Vector3, number)
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local count = 0

	local function include(minPoint: Vector3, maxPoint: Vector3)
		minX, maxX = math.min(minX, minPoint.X), math.max(maxX, maxPoint.X)
		minY, maxY = math.min(minY, minPoint.Y), math.max(maxY, maxPoint.Y)
		count += 1
	end

	local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	if arena then
		for _, part in arena:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Background" and part.Name ~= "Thruster" then
				local half = part.Size / 2
				include(part.Position - half, part.Position + half)
			end
		end
	end

	for _, head in headsFolder:GetChildren() do
		local body = head:FindFirstChild("Body")
		if body and body:IsA("BasePart") and body.Position.Y > Constants.FALL_LIMIT_Y + 10 then
			local r = Vector3.one * Constants.HEAD_RADIUS
			include(body.Position - r, body.Position + r)
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

	RunService:BindToRenderStep("HeadBattleCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FOV

		local targetFocus, targetDistance = getTarget(headsFolder)
		local alpha = 1 - math.exp(-Constants.CAMERA_SMOOTHNESS * dt)
		currentFocus = currentFocus:Lerp(targetFocus, alpha)
		currentDistance += (targetDistance - currentDistance) * alpha

		-- Kamera steht vor der Arena (+Z) und schaut nach hinten: +X ist rechts im Bild
		local cameraPosition = currentFocus + Vector3.new(0, 0, currentDistance)
		camera.CFrame = CFrame.lookAt(cameraPosition, currentFocus)
	end)
end

return CameraController
