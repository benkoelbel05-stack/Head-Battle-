--!strict
-- Hintergrundbild im Spiel: eine Bildfläche weit hinter der Arena, die immer genau den ganzen
-- Bildschirm ausfüllt (wächst mit dem Kamera-Zoom und folgt der Kamera).
-- Welches Bild, steht im RoundState-Attribut "Background" (day / sunset / night).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)

local BackgroundController = {}

local BACKGROUND_Z = Constants.PLANE_Z - 60 -- weit hinter allem anderen
local OVERSIZE = 1.06 -- etwas größer als der Bildschirm, damit nie ein Rand zu sehen ist

function BackgroundController.start()
	local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)
	local arena = Workspace:WaitForChild(Constants.ARENA_FOLDER)

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
	gui.CanvasSize = Vector2.new(1600, 900)
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

	-- Bild setzen. Die alte einfarbige Wand bleibt sichtbar, bis das Bild wirklich geladen ist.
	local function setWall(hidden: boolean)
		local wall = arena:FindFirstChild("Background")
		if wall and wall:IsA("BasePart") then
			wall.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
	local requestId = 0
	local function refreshImage()
		requestId += 1
		local myRequest = requestId
		local key = roundState:GetAttribute("Background")
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
	arena.ChildAdded:Connect(function(child)
		if child.Name == "Background" then
			setWall(image.IsLoaded and image.Image ~= "")
		end
	end)
	refreshImage()

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
		part.Size = Vector3.new(height * aspect, height, 0.1)
		part.CFrame = CFrame.new(position.X, position.Y, BACKGROUND_Z)
	end)
end

return BackgroundController
