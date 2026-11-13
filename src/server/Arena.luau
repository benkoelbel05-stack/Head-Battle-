--!strict
-- Baut eine Arena aus einem Layout auf (graue Klötze für den Prototyp, Knet-Modelle kommen später).

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

-- Baut die Arena und gibt die Spawnpunkte (in 3D) zurück.
function Arena.build(layout: ArenaLayouts.Layout): { Vector3 }
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

	-- Jede Plattform ist eine "Knetwurst": ein Block in der Mitte und zwei runde Enden.
	-- Die runden Enden lassen den Kopf um die Kante herumlaufen.
	for index, platform in layout.platforms do
		local width, height = platform.size.X, platform.size.Y
		local radius = math.min(height, width) / 2
		local center = CFrame.new(platform.position.X, platform.position.Y, Constants.PLANE_Z)
		local middleLength = width - radius * 2

		if middleLength > 0.01 then
			makePart(`Platform{index}`, Vector3.new(middleLength, height, PLATFORM_DEPTH), center, platform.color, folder)
		end

		for side = -1, 1, 2 do
			local capCenter = center * CFrame.new(side * middleLength / 2, 0, 0)
			local cap = makePart(
				`Platform{index}Cap`,
				Vector3.new(PLATFORM_DEPTH, height, height),
				capCenter * CYLINDER_TO_CAMERA,
				platform.color,
				folder
			)
			cap.Shape = Enum.PartType.Cylinder
		end
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
	return spawns
end

return Arena
