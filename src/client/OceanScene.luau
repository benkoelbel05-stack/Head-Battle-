--!strict
-- Lebendige, ruhige Meer-Szene im Spiel (nur auf dem Client):
--   * Wolken in drei Tiefen (bei jedem Hintergrund, passend eingefärbt): ferne Wolkenbank (am langsamsten), kleine Wolken (mittel) und die großen
--     Wolkenbänke links (driften nach rechts) und rechts (driften nach links). Jede Wolke schwebt
--     zusätzlich minimal auf und ab. Verlässt eine Wolke das Bild, taucht sie außerhalb auf der
--     anderen Seite wieder auf – nie mitten im Bild.
--   * Wasser: Wasser-Textur und Glanz-Textur ziehen langsam gegeneinander (Texturen auf der
--     Wasserfläche, nur ihr Versatz wird bewegt – kein Neuzeichnen), der Glanz schimmert sanft;
--     helle Wellenbänder ziehen waagerecht, Glitzerpunkte blenden weich ein und aus, die Wasserlinie
--     hebt und senkt sich kaum merklich.
--
-- Technik: Jede Wolke ist eine flache Fläche mit einem festen Bild (SurfaceGui). Bewegt wird nur die
-- Fläche, das Bild wird nicht neu gezeichnet – das ist deutlich schneller als bewegte ImageLabels in
-- einer großen Oberfläche. Positionen werden in Bildschirm-Anteilen gerechnet (0..1), so passt alles
-- zu jeder Bildschirmgröße und jedem Zoom. Läuft nur, solange die Arena sichtbar ist (kein
-- Vollbild-Menü davor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local OceanAssets = require(ReplicatedStorage.Shared.OceanAssets)

local OceanScene = {}

type Cloud = {
	part: Part,
	u: number, -- waagerechte Mitte (Bildschirm-Anteil)
	v: number, -- senkrechte Mitte (Bildschirm-Anteil, 0 = oben)
	width: number, -- Breite (Bildschirm-Anteil)
	ratio: number, -- Höhe / Breite des Bildes
	speed: number, -- Bildschirm-Anteile pro Sekunde (+ = nach rechts)
	bob: number, -- Auf-und-ab-Weite (Bildschirm-Anteil)
	bobSpeed: number,
	phase: number,
	z: number,
}

type WaterFx = { part: Part, x: number, y: number, speed: number, width: number, phase: number, kind: string, life: number, age: number }

local random = Random.new()

-- Flache Fläche mit festem Bild (zeigt zur Kamera)
local function imagePart(name: string, imageId: number, ratio: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(10, 10 * ratio, 0.05)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(384, math.max(math.floor(384 * ratio), 1))
	gui.LightInfluence = 0
	pcall(function()
		(gui :: any).MaxDistance = 1e6
	end)
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = `rbxassetid://{imageId}`
	image.Parent = gui
	part.Parent = parent
	return part
end

-- Sichtbarer Ausschnitt in einer bestimmten Tiefe z: Mitte, Breite, Höhe (in Studs)
local function view(camera: Camera, z: number): (Vector3, number, number)
	local position = camera.CFrame.Position
	local distance = math.max(position.Z - z, 1)
	local height = 2 * distance * math.tan(math.rad(camera.FieldOfView) / 2)
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	return position, height * aspect, height
end

function OceanScene.start()
	local player = Players.LocalPlayer
	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)

	local folder = Instance.new("Folder")
	folder.Name = "ClayBattleOceanScene"
	folder.Parent = Workspace

	---------------------------------------------------------------------------------------------
	-- Wolken
	---------------------------------------------------------------------------------------------

	local clouds: { Cloud } = {}
	local function addCloud(name: string, id: number, u: number, v: number, width: number, ratio: number, speed: number, z: number)
		if id == 0 then
			return
		end
		table.insert(clouds, {
			part = imagePart(name, id, ratio, folder),
			u = u,
			v = v,
			width = width,
			ratio = ratio,
			speed = speed,
			bob = random:NextNumber(0.003, 0.007),
			bobSpeed = random:NextNumber(0.5, 0.9),
			phase = random:NextNumber(0, math.pi * 2),
			z = z,
		})
	end

	-- Tiefen: alles hinter der Arena, vor dem Himmel (BackgroundController liegt bei PLANE_Z - 60)
	local Z_DISTANT = Constants.PLANE_Z - 56
	local Z_SMALL = Constants.PLANE_Z - 52
	local Z_BANKS = Constants.PLANE_Z - 48

	-- Ferne Wolkenbank am Horizont: zwei Kopien nebeneinander, die gemeinsam ganz langsam ziehen
	addCloud("DistantA", OceanAssets.clouds_distant, 0.5, 0.6, 1.05, 0.22, 0.0025, Z_DISTANT)
	addCloud("DistantB", OceanAssets.clouds_distant, -0.55, 0.6, 1.05, 0.22, 0.0025, Z_DISTANT)
	-- Kleine Wolken verteilt, je eigenes Tempo und eigene Richtung
	for index, id in OceanAssets.small do
		local direction = if index % 2 == 0 then 1 else -1
		addCloud(
			`Small{index}`,
			id,
			random:NextNumber(0, 1),
			random:NextNumber(0.08, 0.48),
			random:NextNumber(0.07, 0.13),
			0.6,
			direction * random:NextNumber(0.004, 0.008),
			Z_SMALL + index * 0.1
		)
	end
	-- Große Wolkenbänke an den Rändern
	addCloud("BankLeft", OceanAssets.clouds_left, 0.1, 0.3, 0.42, 0.8, 0.005, Z_BANKS)
	addCloud("BankRight", OceanAssets.clouds_right, 0.9, 0.32, 0.42, 0.8, -0.005, Z_BANKS + 0.2)

	---------------------------------------------------------------------------------------------
	-- Wasser-Effekte (auf dem Wasser der Arena)
	---------------------------------------------------------------------------------------------

	local waterFx: { WaterFx } = {}
	local function makeFxPart(name: string, size: Vector3, shape: Enum.PartType): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(235, 248, 255)
		part.Shape = shape
		part.Size = size
		part.Transparency = 1
		part.Parent = folder
		return part
	end
	for index = 1, 6 do
		local width = random:NextNumber(30, 70)
		table.insert(waterFx, {
			part = makeFxPart(`Wave{index}`, Vector3.new(width, random:NextNumber(0.12, 0.22), 0.05), Enum.PartType.Block),
			x = random:NextNumber(-60, 60),
			y = random:NextNumber(0.8, 7),
			speed = (if index % 2 == 0 then 1 else -1) * random:NextNumber(0.5, 1.2),
			width = width,
			phase = random:NextNumber(0, math.pi * 2),
			kind = "wave",
			life = 0,
			age = 0,
		})
	end
	for index = 1, 12 do
		local size = random:NextNumber(0.22, 0.4)
		table.insert(waterFx, {
			part = makeFxPart(`Sparkle{index}`, Vector3.one * size, Enum.PartType.Ball),
			x = 0,
			y = 0,
			speed = 0,
			width = size,
			phase = 0,
			kind = "sparkle",
			life = random:NextNumber(1.6, 3),
			age = random:NextNumber(0, 3), -- versetzt starten
		})
	end

	---------------------------------------------------------------------------------------------
	-- Animation
	---------------------------------------------------------------------------------------------

	-- Texturen auf der Wasserfläche der aktuellen Arena (bei jeder neuen Karte neu angelegt)
	local waterBase: Texture? = nil
	local waterShimmer: Texture? = nil
	local texturedWater: BasePart? = nil
	local function textureWater(water: BasePart)
		if texturedWater == water then
			return
		end
		texturedWater = water
		local function make(id: number, tileU: number, tileV: number, transparency: number): Texture?
			if id == 0 then
				return nil
			end
			local texture = Instance.new("Texture")
			texture.Texture = `rbxassetid://{id}`
			texture.Face = Enum.NormalId.Back -- zur Kamera
			texture.StudsPerTileU = tileU
			texture.StudsPerTileV = tileV
			texture.Transparency = transparency
			texture.Parent = water
			return texture
		end
		waterBase = make(OceanAssets.water_base, 48, 24, 0.15)
		waterShimmer = make(OceanAssets.water_shimmer, 36, 18, 0.45)
	end

	local clock = 0
	local cloudTintKey: unknown = false -- noch keine Färbung gesetzt
	local CLOUD_TINTS: { [string]: Color3 } = {
		ocean = Color3.new(1, 1, 1),
		day = Color3.new(1, 1, 1),
		sunset = Color3.fromRGB(255, 205, 175),
		night = Color3.fromRGB(120, 130, 185),
	}
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not folder.Parent then
			connection:Disconnect()
			return
		end
		local camera = Workspace.CurrentCamera
		-- Vollbild-Menü davor: nichts zu sehen, nichts zu tun
		if not camera or player:GetAttribute("MenuOpen") == true then
			return
		end
		dt = math.min(dt, 0.1)
		clock += dt

		-- Wolken bei jedem Hintergrund, passend eingefärbt (Sonnenuntergang warm, Nacht dunkel)
		local tintKey = roundState:GetAttribute("Background")
		if tintKey ~= cloudTintKey then
			cloudTintKey = tintKey
			local tint = CLOUD_TINTS[if typeof(tintKey) == "string" then tintKey else "ocean"] or CLOUD_TINTS.ocean
			for _, cloud in clouds do
				local gui = cloud.part:FindFirstChildOfClass("SurfaceGui")
				local image = gui and gui:FindFirstChildOfClass("ImageLabel")
				if image then
					image.ImageColor3 = tint
				end
			end
		end
		do
			for _, cloud in clouds do
				local center, viewWidth, viewHeight = view(camera, cloud.z)
				cloud.u += cloud.speed * dt
				-- Weich herum: erst wenn die Wolke ganz draußen ist, auf der anderen Seite (draußen) neu
				local half = cloud.width / 2
				if cloud.speed > 0 and cloud.u - half > 1.02 then
					cloud.u = -half - 0.02 - (cloud.u - half - 1.02)
				elseif cloud.speed < 0 and cloud.u + half < -0.02 then
					cloud.u = 1 + half + 0.02 + (cloud.u + half + 0.02)
				end
				local v = cloud.v + math.sin(clock * cloud.bobSpeed + cloud.phase) * cloud.bob
				local widthStuds = cloud.width * viewWidth
				local size = Vector3.new(widthStuds, widthStuds * cloud.ratio, 0.05)
				-- Feste Pixelgröße der Zeichenfläche: Größe darf sich jedes Bild weich ändern (kein Neuzeichnen)
				cloud.part.Size = size
				cloud.part.CFrame = CFrame.new(
					center.X + (cloud.u - 0.5) * viewWidth,
					center.Y + (0.5 - v) * viewHeight,
					cloud.z
				)
			end
		end

		-- Wasser
		local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
		local level = arena and arena:GetAttribute("WaterLevel")
		local water = arena and arena:FindFirstChild("Water")
		if typeof(level) ~= "number" or not water or not water:IsA("BasePart") then
			for _, fx in waterFx do
				fx.part.Transparency = 1
			end
			return
		end
		textureWater(water)
		local base = waterBase
		if base then
			base.OffsetStudsU = (clock * 0.6) % base.StudsPerTileU
			base.OffsetStudsV = math.sin(clock * 0.25) * 0.4
		end
		local shimmer = waterShimmer
		if shimmer then
			shimmer.OffsetStudsU = (-clock * 1.0) % shimmer.StudsPerTileU
			shimmer.Transparency = 0.45 + 0.15 * math.sin(clock * 0.5)
		end
		local fxZ = water.Position.Z + 0.12
		local center, viewWidth = view(camera, fxZ)
		local left, right = center.X - viewWidth / 2, center.X + viewWidth / 2
		for _, fx in waterFx do
			if fx.kind == "wave" then
				-- Helles Wellenband: zieht langsam, schimmert sanft; außerhalb des Bildes auf die andere Seite
				fx.x += fx.speed * dt
				local half = fx.width / 2
				if fx.speed > 0 and fx.x - half > right then
					fx.x = left - half
				elseif fx.speed < 0 and fx.x + half < left then
					fx.x = right + half
				elseif fx.x + half < left - viewWidth or fx.x - half > right + viewWidth then
					fx.x = random:NextNumber(left, right) -- nach Kartenwechsel / großem Kamerasprung
				end
				local shimmer = 0.5 + 0.5 * math.sin(clock * 0.6 + fx.phase)
				fx.part.Transparency = 0.86 - 0.08 * shimmer
				fx.part.CFrame = CFrame.new(fx.x, level - fx.y + math.sin(clock * 0.8 + fx.phase) * 0.08, fxZ)
			else
				-- Glitzerpunkt: blendet weich ein und aus, springt nur unsichtbar an eine neue Stelle
				fx.age += dt
				if fx.age >= fx.life then
					fx.age = 0
					fx.life = random:NextNumber(1.6, 3)
					fx.x = random:NextNumber(left + 2, right - 2)
					fx.y = random:NextNumber(0.4, 5)
				end
				local t = fx.age / fx.life
				local glow = math.sin(t * math.pi) -- 0 -> 1 -> 0
				fx.part.Transparency = 1 - 0.75 * glow * glow
				fx.part.CFrame = CFrame.new(fx.x, level - fx.y, fxZ + 0.02)
			end
		end

		-- Wasserlinie hebt und senkt sich kaum merklich (nur Optik)
		local line = arena:FindFirstChild("WaterLine")
		if line and line:IsA("BasePart") then
			line.CFrame = CFrame.new(line.Position.X, level - 0.17 + math.sin(clock * 0.7) * 0.06, line.Position.Z)
		end
	end)

	folder.Destroying:Connect(function()
		connection:Disconnect()
	end)
end

return OceanScene
