--!strict
-- Hintergrundbild im Spiel: eine Bildfläche weit hinter der Arena, die immer genau den ganzen
-- Bildschirm ausfüllt (wächst mit dem Kamera-Zoom und folgt der Kamera).
-- Welches Bild, steht im RoundState-Attribut "Background" (ocean / day / sunset / night).
-- "ocean" ist gezeichnet statt eines Bildes: Himmel mit Verlauf und Meer bis zum Horizont; die
-- Wolken und das Glitzern davor kommen aus OceanScene.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)
local PlatformTextures = require(ReplicatedStorage.Shared.PlatformTextures)
local ContentProvider = game:GetService("ContentProvider")

local BackgroundController = {}

local BACKGROUND_Z = Constants.PLANE_Z - 60 -- weit hinter allem anderen
local OVERSIZE = Constants.BACKGROUND_OVERSIZE -- etwas größer als der Bildschirm, damit nie ein Rand zu sehen ist
-- Die Zeichenfläche hat eine feste Pixelgröße: die Teil-Größe darf sich jedes Bild ändern, ohne dass
-- neu gezeichnet wird (nur bei anderem Seitenverhältnis des Bildschirms)
local CANVAS_HEIGHT = 720

-- Nur in Studio: melden, welche Arena-Bilder (Hintergründe, Plattform-Texturen) nicht laden
local function checkAssets()
	local names: { [string]: string } = {}
	local list = {}
	for key, id in ArenaAssets do
		local content = `rbxassetid://{id}`
		names[content] = `Hintergrund {key}`
		table.insert(list, content)
	end
	for key, material in PlatformTextures do
		for kind, id in { tex = material.tex, trim = material.trim } do
			if id then
				local content = `rbxassetid://{id}`
				names[content] = `Textur {key} ({kind})`
				table.insert(list, content)
			end
		end
	end
	local failed = {}
	ContentProvider:PreloadAsync(list, function(content: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			table.insert(failed, `{names[content] or content} = {content} ({status.Name})`)
		end
	end)
	if #failed > 0 then
		warn(`[ClayBattle] Arena-Bilder laden nicht:\n  {table.concat(failed, "\n  ")}`)
	else
		print("[ClayBattle] Alle Arena-Bilder geladen")
	end
end

function BackgroundController.start()
	if RunService:IsStudio() then
		task.spawn(checkAssets)
	end

	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)
	Workspace:WaitForChild(Constants.ARENA_FOLDER)

	local part = Instance.new("Part")
	part.Name = "ArenaBackdrop"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(100, 60, 0.1)
	part.Parent = Workspace

	-- Die Kamera schaut von +Z: die "Back"-Seite des Teils ist die sichtbare
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1280, CANVAS_HEIGHT)
	local canvasAspect = 16 / 9
	gui.LightInfluence = 0
	pcall(function()
		(gui :: any).MaxDistance = 1e6
	end)
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Crop -- füllt die Fläche, ohne zu verzerren
	image.Parent = gui

	-- Meer-Hintergrund: Himmel (Verlauf) und ferne See bis zum Horizont, mit hellem Horizontstreifen
	local HORIZON = Constants.BACKGROUND_HORIZON -- Anteil der Bildhöhe von oben
	local ocean = Instance.new("Frame")
	ocean.Name = "Ocean"
	ocean.Size = UDim2.fromScale(1, 1)
	ocean.BackgroundTransparency = 1
	ocean.Visible = false
	ocean.Parent = gui
	local sky = Instance.new("Frame")
	sky.Name = "Sky"
	sky.Size = UDim2.fromScale(1, HORIZON)
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.BorderSizePixel = 0
	sky.Parent = ocean
	local skyGradient = Instance.new("UIGradient")
	skyGradient.Rotation = 90
	skyGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 128, 226)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(96, 170, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 222, 250)),
	})
	skyGradient.Parent = sky
	local sea = Instance.new("Frame")
	sea.Name = "Sea"
	sea.Position = UDim2.fromScale(0, HORIZON)
	sea.Size = UDim2.fromScale(1, 1 - HORIZON)
	sea.BackgroundColor3 = Color3.new(1, 1, 1)
	sea.BorderSizePixel = 0
	sea.Parent = ocean
	local seaGradient = Instance.new("UIGradient")
	seaGradient.Rotation = 90
	seaGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 190, 240)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(56, 150, 226)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 104, 196)),
	})
	seaGradient.Parent = sea
	local horizon = Instance.new("Frame")
	horizon.Name = "HorizonGlow"
	horizon.AnchorPoint = Vector2.new(0, 0.5)
	horizon.Position = UDim2.fromScale(0, HORIZON)
	horizon.Size = UDim2.fromScale(1, 0.006)
	horizon.BackgroundColor3 = Color3.fromRGB(235, 248, 255)
	horizon.BackgroundTransparency = 0.35
	horizon.BorderSizePixel = 0
	horizon.Parent = ocean

	-- Bild setzen. Die alte einfarbige Wand bleibt sichtbar, bis das Bild wirklich geladen ist.
	local function setWall(hidden: boolean)
		local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
		local wall = arena and arena:FindFirstChild("Background")
		if wall and wall:IsA("BasePart") then
			wall.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
	local requestId = 0
	local function refreshImage()
		requestId += 1
		local myRequest = requestId
		local key = roundState:GetAttribute("Background")
		-- Meer: gezeichnet, nichts zu laden
		if key == "ocean" or key == nil then
			ocean.Visible = true
			image.Image = ""
			setWall(true)
			return
		end
		ocean.Visible = false
		local id = (if typeof(key) == "string" then ArenaAssets[key] else nil) or ArenaAssets.day
		if not id then
			image.Image = ""
			setWall(false)
			return
		end
		image.Image = `rbxassetid://{id}`
		task.spawn(function()
			local started = os.clock()
			while os.clock() - started < 8 and myRequest == requestId do
				if image.IsLoaded then
					setWall(true)
					return
				end
				task.wait(0.1)
			end
			if myRequest ~= requestId then
				return
			end
			if myRequest == requestId then
				warn(`[ClayBattle] Hintergrundbild {key} ({id}) lädt gar nicht: einfarbige Wand bleibt`)
				setWall(false)
			end
		end)
	end
	roundState:GetAttributeChangedSignal("Background"):Connect(refreshImage)
	-- Neue Karte geladen: deren Wand ebenfalls ausblenden, wenn das Bild da ist
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == Constants.ARENA_FOLDER then
			task.defer(function()
				setWall(ocean.Visible or (image.IsLoaded and image.Image ~= ""))
			end)
		end
	end)
	refreshImage()

	-- (Keine Tiefenunschärfe: Roblox kann höchstens 200 Studs scharf stellen, die Kamera steht aber
	-- weiter weg – dadurch wurde die ganze Arena verschwommen.)

	-- Nach der Kamera (Camera+1)
	RunService:BindToRenderStep("ClayBattleBackground", Enum.RenderPriority.Camera.Value + 2, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position
		local distance = math.max(position.Z - BACKGROUND_Z, 1)
		local height = 2 * distance * math.tan(math.rad(camera.FieldOfView) / 2) * OVERSIZE
		local viewport = camera.ViewportSize
		local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
		-- Weich mit dem Zoom mitwachsen (jedes Bild, ohne Sprünge)
		part.Size = Vector3.new(height * aspect, height, 0.1)
		if math.abs(aspect - canvasAspect) > 0.01 then
			-- Zeichenfläche im selben Seitenverhältnis, sonst würden Bild und Verläufe verzerrt
			canvasAspect = aspect
			gui.CanvasSize = Vector2.new(math.floor(CANVAS_HEIGHT * aspect), CANVAS_HEIGHT)
		end
		part.CFrame = CFrame.new(position.X, position.Y, BACKGROUND_Z)
	end)
end

return BackgroundController
