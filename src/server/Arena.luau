--!strict
-- Baut eine Arena aus einem Layout auf (graue Klötze für den Prototyp, Knet-Modelle kommen später).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaLayouts = require(ReplicatedStorage.Shared.ArenaLayouts)

local PLATFORM_DEPTH = 8 -- dicker als der Kopf, damit nichts durchrutscht

local Arena = {}

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

	for index, platform in layout.platforms do
		makePart(
			`Platform{index}`,
			Vector3.new(platform.size.X, platform.size.Y, PLATFORM_DEPTH),
			CFrame.new(platform.position.X, platform.position.Y, Constants.PLANE_Z),
			platform.color,
			folder
		)
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
