--!strict
-- Zielstreifen für die Granate: gepunktete Flugbahn bis zum ersten Aufprall (Plattform oder Kopf).
-- Nur auf dem eigenen Client sichtbar. Nutzt dieselbe Rechnung wie der Server (GrenadePhysics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

local STEPS_PER_DOT = 4 -- feste Physik-Schritte zwischen zwei Punkten
local DOT_COUNT = math.ceil(Constants.GRENADE_FUSE / (GrenadePhysics.STEP * STEPS_PER_DOT))
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

-- Flugbahn zeigen. charge = 0..1. others = Mittelpunkte der anderen Köpfe (dort explodiert sie)
function AimPreview.show(headPosition: Vector3, aim: Vector3, charge: number, others: { Vector3 })
	ensureParts()
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))
	local position, velocity = GrenadePhysics.launch(headPosition, aim, charge)
	local headReach = Constants.HEAD_RADIUS + Constants.GRENADE_RADIUS

	local stopped = false
	local stopPosition = position
	local flightTime = 0
	for i = 1, DOT_COUNT do
		if not stopped then
			for _ = 1, STEPS_PER_DOT do
				local hit
				position, velocity, hit = GrenadePhysics.step(position, velocity, GrenadePhysics.STEP, shapes)
				flightTime += GrenadePhysics.STEP
				local hitsHead = false
				for _, other in others do
					if Vector3.new(position.X - other.X, position.Y - other.Y, 0).Magnitude <= headReach then
						hitsHead = true
						break
					end
				end
				if hit or hitsHead or flightTime >= Constants.GRENADE_FUSE or position.Y < Constants.FALL_LIMIT_Y then
					stopped = true
					stopPosition = position
					break
				end
			end
		end

		local dot = dots[i]
		if stopped then
			dot.Transparency = 1
		else
			dot.CFrame = CFrame.new(position)
			-- Punkte werden zum Ende hin kleiner und blasser
			local fade = i / DOT_COUNT
			dot.Size = Vector3.one * DOT_SIZE * (1 - fade * 0.5)
			dot.Transparency = 0.15 + fade * 0.45
		end
	end

	-- Markierung am Ende: Aufprall oder Explosionsort
	local marker = impactMarker :: Part
	marker.CFrame = CFrame.new(stopPosition)
	marker.Transparency = 0.3
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
