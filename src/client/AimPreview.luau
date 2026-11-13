--!strict
-- Zielstreifen für die Granate: gepunktete Flugbahn bis zum ersten Aufprall.
-- Nur auf dem eigenen Client sichtbar. Nutzt dieselbe Rechnung wie der Server (GrenadePhysics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

local DOT_COUNT = 28
local TIME_PER_DOT = 0.035 -- Flugzeit zwischen zwei Punkten
local DOT_SIZE = 0.45
local DOT_COLOR = Color3.fromRGB(255, 244, 214)
local IMPACT_SIZE = 1.1

local AimPreview = {}

local folder: Folder? = nil
local dots: { Part } = {}
local impactMarker: Part? = nil

local function makeDot(name: string, size: number): Part
	local dot = Instance.new("Part")
	dot.Name = name
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * size
	dot.Color = DOT_COLOR
	dot.Material = Enum.Material.SmoothPlastic
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Transparency = 1
	dot.Parent = folder
	return dot
end

local function ensureParts()
	if folder and folder.Parent then
		return
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "AimPreview"
	newFolder.Parent = Workspace
	folder = newFolder
	table.clear(dots)
	for i = 1, DOT_COUNT do
		table.insert(dots, makeDot(`Dot{i}`, DOT_SIZE))
	end
	impactMarker = makeDot("Impact", IMPACT_SIZE)
end

-- Flugbahn zeigen. charge = 0..1
function AimPreview.show(headPosition: Vector3, aim: Vector3, charge: number)
	ensureParts()
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
	local position, velocity = GrenadePhysics.launch(headPosition, aim, charge)

	local hitIndex: number? = nil
	local hitPosition = position
	local substeps = 3
	for i = 1, DOT_COUNT do
		if not hitIndex then
			for _ = 1, substeps do
				local hit
				position, velocity, hit = GrenadePhysics.step(position, velocity, TIME_PER_DOT / substeps, shapes)
				if hit then
					hitIndex = i
					hitPosition = position
					break
				end
			end
		end

		local dot = dots[i]
		local flightTime = i * TIME_PER_DOT
		if hitIndex or flightTime > Constants.GRENADE_FUSE or position.Y < Constants.FALL_LIMIT_Y then
			dot.Transparency = 1
		else
			dot.CFrame = CFrame.new(position)
			-- Punkte werden zum Ende hin kleiner und blasser
			local fade = i / DOT_COUNT
			dot.Size = Vector3.one * DOT_SIZE * (1 - fade * 0.5)
			dot.Transparency = 0.15 + fade * 0.45
		end
	end

	local marker = impactMarker :: Part
	if hitIndex then
		marker.CFrame = CFrame.new(hitPosition)
		marker.Transparency = 0.3
	else
		marker.Transparency = 1
	end
end

function AimPreview.hide()
	for _, dot in dots do
		dot.Transparency = 1
	end
	if impactMarker then
		impactMarker.Transparency = 1
	end
end

return AimPreview
