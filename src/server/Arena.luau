--!strict
-- Baut eine Arena aus einem Layout auf (Knet-Modelle kommen später).
-- Jede Plattform ist ein eigenes, bewegliches Model ("Knetwurst" aus Mittelteil + zwei runden Enden).
-- Die Physik der Plattformen steckt in PlatformSim.luau (läuft auf Server und Clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)

local PLATFORM_DEPTH = 8 -- dicker als der Kopf, damit nichts durchrutscht

local Arena = {}

-- Zylinder liegen in Roblox entlang der X-Achse. So gedreht zeigt ihre runde Seite zur Kamera.
local CYLINDER_TO_CAMERA = CFrame.Angles(0, math.rad(90), 0)

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic -- matt wie Knete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildPlatform(index: number, platform: ArenaLayouts.Platform, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = `Platform{index}`

	local width, height = platform.size.X, platform.size.Y
	local radius = math.min(height, width) / 2
	local center = CFrame.new(platform.position.X, platform.position.Y, Constants.PLANE_Z)
	local middleLength = width - radius * 2

	local parts: { BasePart } = {}
	if middleLength > 0.01 then
		table.insert(
			parts,
			makePart("Middle", Vector3.new(middleLength, height, PLATFORM_DEPTH), center, platform.color, model)
		)
	end
	for side = -1, 1, 2 do
		local capCenter = center * CFrame.new(side * middleLength / 2, 0, 0)
		local cap = makePart(
			"Cap",
			Vector3.new(PLATFORM_DEPTH, height, height),
			capCenter * CYLINDER_TO_CAMERA,
			platform.color,
			model
		)
		cap.Shape = Enum.PartType.Cylinder
		table.insert(parts, cap)
	end

	-- Alle Teile fest zu einem Körper verbinden, das erste Teil ist die Wurzel
	local root = parts[1]
	for i = 2, #parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = parts[i]
		weld.Parent = root
	end
	for _, part in parts do
		-- Nur die Wurzel ist verankert, der Rest hängt per Schweißnaht daran. Bewegt wird die Plattform
		-- über die Wurzel: auf jedem Client lokal durch die Plattform-Simulation (PlatformSim).
		-- Der Server bewegt die Parts nie, er rechnet nur mit.
		part.Anchored = part == root
		-- Keine Roblox-Kollisionen: Köpfe und Granaten rechnen mit der exakten Form (PlatformShapes).
		-- Raycasts treffen die Plattformen trotzdem.
		part.CanCollide = false
		part.CanTouch = false
	end
	model.PrimaryPart = root
	model:SetAttribute("HomeCFrame", root.CFrame)

	-- Exakte Form für PlatformShapes: Strecke entlang X mit Radius, relativ zur Wurzel
	model:SetAttribute("HalfLength", math.max(middleLength, 0) / 2)
	model:SetAttribute("Radius", radius)
	model:SetAttribute("ShapeFrame", root.CFrame:ToObjectSpace(center))
	model.Parent = parent
	return model
end

-- Baut die Arena. Gibt die Spawnpunkte (in 3D) und die Plattform-Models zurück.
-- Die Plattformen sind danach noch nicht bei der Simulation angemeldet.
function Arena.build(layout: ArenaLayouts.Layout): ({ Vector3 }, { Model })
	local old = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
	if old then
		old:Destroy()
	end

	-- Standard-Teile der Roblox-Vorlage entfernen (Baseplate, SpawnLocation)
	for _, name in { "Baseplate", "SpawnLocation" } do
		local part = Workspace:FindFirstChild(name)
		if part then
			part:Destroy()
		end
	end

	-- Ein Model mit "Persistent", damit die Arena trotz StreamingEnabled immer bei allen Clients ankommt
	local folder = Instance.new("Model")
	folder.Name = Constants.ARENA_FOLDER
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local platforms = {}
	for index, platform in layout.platforms do
		table.insert(platforms, buildPlatform(index, platform, folder))
	end

	-- Hintergrund-Wand hinter der Arena
	local background = makePart(
		"Background",
		Vector3.new(400, 200, 2),
		CFrame.new(0, 20, Constants.PLANE_Z - 30),
		layout.backgroundColor,
		folder
	)
	background.CanCollide = false
	background.CanQuery = false
	background.CanTouch = false

	folder.Parent = Workspace

	local spawns = {}
	for _, point in layout.spawns do
		table.insert(spawns, Vector3.new(point.X, point.Y, Constants.PLANE_Z))
	end
	return spawns, platforms
end

return Arena
