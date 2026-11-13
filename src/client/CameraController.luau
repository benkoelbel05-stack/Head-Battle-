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
		if part:IsA("BasePart") and part.Name ~= "Background" and part.Name ~= "Thruster" then
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
