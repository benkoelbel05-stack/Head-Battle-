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
local PIXELS_PER_STUD = 20 -- Auflösung der Plattform-Bilder (höher = schärfer, aber mehr Speicher)

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

	-- Optik als flaches, gestochen scharfes Bild vor dem (unsichtbaren) Körper: eine SurfaceGui mit
	-- abgerundeten Flächen. So sind Rundungen wirklich rund (Zylinder-Teile wären eckig) und die
	-- Texturen werden in fester Auflösung gezeichnet statt verschwommen gestreckt.
	--   außen: Rand (z. B. Gras rundherum) mit dünner, dunkler Kontur
	--   innen: Fläche (Erde, Stein ...), etwas kleiner
	local topColor = platform.color:Lerp(Color3.new(1, 1, 1), Constants.PLATFORM_TOP_LIGHTEN)
	local material = if platform.material then PlatformTextures[platform.material] else nil
	local rimColor = if material then material.rim else topColor
	for _, part in parts do
		part.Transparency = 1 -- nur noch für Physik-Lage und Raycasts
		part.CastShadow = false
	end

	local rimWidth = math.clamp(radius * 0.22, Constants.PLATFORM_TOP_DEPTH, 1.4)
	local frontZ = depth3D / 2 + Constants.PLATFORM_FRONT_GAP
	local pad = 0.3 -- Platz für die Kontur
	local pps = PIXELS_PER_STUD
	local face = makePart("Face", Vector3.new(width + pad * 2, height + pad * 2, 0.05), center * CFrame.new(0, 0, frontZ), rimColor, model)
	face.Transparency = 1
	local frontParts: { BasePart } = { face }

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- die Kamera schaut von +Z
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	pcall(function()
		(gui :: any).MaxDistance = 1e6
	end)
	gui.Parent = face

	local function tiled(parent: Instance, name: string, position: Vector2, size: Vector2, color: Color3, imageId: number?, tile: number): ImageLabel
		local layer = Instance.new("ImageLabel")
		layer.Name = name
		layer.Position = UDim2.fromOffset(position.X * pps, position.Y * pps)
		layer.Size = UDim2.fromOffset(size.X * pps, size.Y * pps)
		layer.BackgroundColor3 = color
		layer.BorderSizePixel = 0
		if imageId then
			layer.Image = `rbxassetid://{imageId}`
			layer.ScaleType = Enum.ScaleType.Tile
			layer.TileSize = UDim2.fromOffset(tile * pps, tile * pps)
		end
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, math.min(size.X, size.Y) * pps / 2)
		round.Parent = layer
		layer.Parent = parent
		return layer
	end
	local outer = tiled(gui, "Rim", Vector2.new(pad, pad), Vector2.new(width, height), rimColor, if material then material.rimTex else nil, TEXTURE_TILE * 0.7)
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(34, 26, 40)
	outline.Thickness = math.max(2, math.floor(0.14 * pps))
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = outer
	tiled(
		outer,
		"Surface",
		Vector2.new(rimWidth, rimWidth),
		Vector2.new(width - rimWidth * 2, height - rimWidth * 2),
		platform.color,
		if material then material.tex else nil,
		TEXTURE_TILE
	)

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
