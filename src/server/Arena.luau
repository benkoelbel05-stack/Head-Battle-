--!strict
-- Baut eine Arena aus einem Layout auf (Knet-Modelle kommen später).
-- Jede Plattform ist ein eigenes, bewegliches Model ("Knetwurst" aus Mittelteil + zwei runden Enden).
-- Die Physik der Plattformen steckt in PlatformSim.luau (läuft auf Server und Clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)
local PlatformTextures = require(ReplicatedStorage.Shared.PlatformTextures)

local TEXTURE_TILE = 6 -- so viele Studs ist eine Kachel der Flächen-Textur breit

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
		* CFrame.Angles(0, 0, math.rad(platform.rotation or 0))
	local middleLength = width - radius * 2
	-- Kreis (Breite = Höhe): nur ein rundes Teil statt Mittelstück + zwei Enden
	local sides = if middleLength > 0.01 then { -1, 1 } else { 1 }

	-- Jede Plattform ist vorne etwas weiter hinten als die vorige: überlappen sich zwei (z. B. nach
	-- einer Explosion), flackern ihre Flächen nicht ineinander. Die Mitte bleibt bei PLANE_Z (Physik ist 2D).
	local depth3D = PLATFORM_DEPTH - (index - 1) * Constants.PLATFORM_LAYER_STEP * 2
	local parts: { BasePart } = {}
	if middleLength > 0.01 then
		table.insert(
			parts,
			makePart("Middle", Vector3.new(middleLength, height, depth3D), center, platform.color, model)
		)
	end
	for _, side in sides do
		local capCenter = center * CFrame.new(side * middleLength / 2, 0, 0)
		local cap = makePart(
			"Cap",
			Vector3.new(depth3D, height, height),
			capCenter * CYLINDER_TO_CAMERA,
			platform.color,
			model
		)
		cap.Shape = Enum.PartType.Cylinder
		table.insert(parts, cap)
	end

	-- Look wie im Vorbild: Die Plattform selbst ist der Rand (z. B. Gras rundherum). Davor liegt eine
	-- etwas kleinere, flache Front mit der Flächen-Textur (Erde, Stein ...). So bleibt rundherum ein
	-- gleichmäßiger Rand sichtbar. Die Front ist reine Optik: keine Kollision, keine Raycasts.
	local topColor = platform.color:Lerp(Color3.new(1, 1, 1), Constants.PLATFORM_TOP_LIGHTEN)
	for _, part in parts do
		part.Color = topColor
	end
	local rimWidth = math.clamp(radius * 0.22, Constants.PLATFORM_TOP_DEPTH, 1.4)
	local frontRadius = radius - rimWidth
	local frontZ = depth3D / 2 + Constants.PLATFORM_FRONT_GAP
	local frontCenter = center * CFrame.new(0, 0, frontZ)
	local frontParts: { BasePart } = {}
	if middleLength > 0.01 then
		table.insert(
			frontParts,
			makePart("Front", Vector3.new(middleLength, frontRadius * 2, 0.1), frontCenter, platform.color, model)
		)
	end
	for _, side in sides do
		local cap = makePart(
			"FrontCap",
			Vector3.new(0.1, frontRadius * 2, frontRadius * 2),
			frontCenter * CFrame.new(side * middleLength / 2, 0, 0) * CYLINDER_TO_CAMERA,
			platform.color,
			model
		)
		cap.Shape = Enum.PartType.Cylinder
		table.insert(frontParts, cap)
	end
	for _, front in frontParts do
		front.CanCollide = false
		front.CanQuery = false
		front.CanTouch = false
		front.CastShadow = false
	end

	-- Knet-Texturen: Fläche auf die Vorderseite (Front-Platte), Rand-Textur (z. B. Gras) rundherum auf
	-- die Plattform selbst. Die Kamera schaut von +Z: bei Blöcken ist das die "Back"-Seite, bei den
	-- gedrehten Zylindern "Left".
	local material = if platform.material then PlatformTextures[platform.material] else nil
	local rimColor = if material then material.rim else topColor
	local function addTexture(part: BasePart, id: number, tileU: number, tileV: number)
		local texture = Instance.new("Texture")
		texture.Texture = `rbxassetid://{id}`
		texture.Face = if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder
			then Enum.NormalId.Left
			else Enum.NormalId.Back
		texture.StudsPerTileU = tileU
		texture.StudsPerTileV = tileV
		texture.Parent = part
	end
	if material then
		for _, part in parts do
			part.Color = rimColor
			if material.rimTex then
				addTexture(part, material.rimTex, TEXTURE_TILE * 0.7, TEXTURE_TILE * 0.7)
			end
		end
		for _, front in frontParts do
			addTexture(front, material.tex, TEXTURE_TILE, TEXTURE_TILE)
		end
	end

	-- Kontur: dieselbe Form etwas größer, hinter der Vorderseite.
	-- Sichtbar ist nur, was über die Plattform hinausragt. (Abstände so gewählt, dass keine Fläche
	-- genau auf der Höhe einer anderen Plattform liegt, sonst flackert es.)
	local bodyFront = depth3D / 2
	local function silhouette(name: string, grow: number, offset: Vector2, z: number, color: Color3, transparency: number)
		local base = center * CFrame.new(offset.X, offset.Y, z)
		local size = height + grow * 2
		local shapeParts: { BasePart } = {}
		if middleLength > 0.01 then
			table.insert(shapeParts, makePart(name, Vector3.new(middleLength, size, 0.1), base, color, model))
		end
		for _, side in sides do
			local cap = makePart(name, Vector3.new(0.1, size, size), base * CFrame.new(side * middleLength / 2, 0, 0) * CYLINDER_TO_CAMERA, color, model)
			cap.Shape = Enum.PartType.Cylinder
			table.insert(shapeParts, cap)
		end
		for _, part in shapeParts do
			part.Transparency = transparency
			part.CastShadow = false
			table.insert(frontParts, part)
		end
	end
	-- Dünne, fast schwarze Kontur wie im Vorbild (ein versetzter Schatten sah wie eine doppelte Plattform aus)
	silhouette("Outline", 0.12, Vector2.zero, bodyFront - 0.6, Color3.fromRGB(34, 26, 40), 0)
	for _, decor in frontParts do
		decor.CanCollide = false
		decor.CanQuery = false
		decor.CanTouch = false
		decor.CastShadow = false
	end

	-- Alle Teile fest zu einem Körper verbinden, das erste Teil ist die Wurzel
	local root = parts[1]
	for _, front in frontParts do
		table.insert(parts, front)
	end
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
	model:SetAttribute("Density", platform.density or Constants.PLATFORM_DENSITY)
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

	-- Wasser am unteren Rand (wie im Vorbild): halb durchsichtig vor den unteren Inseln, mit hellem
	-- Saum an der Oberfläche. Wer hineinfällt, scheidet aus (ArenaInfo.fallLimit).
	if layout.waterLevel then
		local level = layout.waterLevel
		local waterZ = Constants.SPRITE_Z - 0.7 -- vor den Plattformen, hinter den Figuren
		local water = makePart("Water", Vector3.new(900, 140, 0.2), CFrame.new(0, level - 70, waterZ), Color3.fromRGB(52, 146, 226), folder)
		water.Transparency = 0.32
		local line = makePart("WaterLine", Vector3.new(900, 0.35, 0.2), CFrame.new(0, level - 0.17, waterZ + 0.15), Color3.fromRGB(214, 240, 255), folder)
		line.Transparency = 0.1
		for _, part in { water, line } do
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
		folder:SetAttribute("WaterLevel", level)
	end

	folder.Parent = Workspace

	local spawns = {}
	for _, point in layout.spawns do
		table.insert(spawns, Vector3.new(point.X, point.Y, Constants.PLANE_Z))
	end
	return spawns, platforms
end

return Arena
