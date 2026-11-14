--!strict
-- Clay Battle: rein visuelle, clientseitige Item-Animationen.
-- Keine Änderungen an Hitboxen, Cooldowns, RemoteEvents oder Plattformphysik.
-- Alles wird zur Laufzeit aus Roblox-Objekten gebaut: KEINE Decal-IDs erforderlich.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemAnimations = {}

local CREAM = Color3.fromRGB(255, 240, 200)
local GOLD = Color3.fromRGB(255, 194, 53)
local ORANGE = Color3.fromRGB(244, 109, 39)
local PURPLE = Color3.fromRGB(107, 60, 135)
local BLUE = Color3.fromRGB(73, 200, 255)
local YELLOW = Color3.fromRGB(255, 231, 111)

local animatedMissiles: { [BasePart]: { frame: Frame, flame: Frame } } = {}
local started = false

local function blob(name: string, position: Vector3, size: Vector3, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = transparency or 0
	part.Parent = Workspace
	return part
end

local function floatAndFade(part: BasePart, destination: Vector3, seconds: number, size: Vector3?)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goals: { [string]: any } = { Position = destination, Transparency = 1 }
	if size then
		goals.Size = size
	end
	TweenService:Create(part, info, goals):Play()
	Debris:AddItem(part, seconds + 0.12)
end

local function welded(parent: BasePart, name: string, offset: CFrame, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Shape = shape or Enum.PartType.Ball
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = parent.CFrame * offset
	part.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Dash: kleine Kneteschlieren und blaue Puffs, die sichtbar nachziehen.
function ItemAnimations.dash(position: Vector3, direction: Vector3)
	local flat = Vector3.new(direction.X, direction.Y, 0)
	if flat.Magnitude < 0.01 then
		flat = Vector3.xAxis
	else
		flat = flat.Unit
	end
	local side = Vector3.new(-flat.Y, flat.X, 0)
	local z = Constants.SPRITE_Z + 0.75
	local base = Vector3.new(position.X, position.Y, z)
	for i = 1, 7 do
		local travel = (i / 7) * 3.1
		local p = base - flat * travel + side * math.sin(i * 2.2) * 0.48
		local puff = blob("ClayDashPuff", p, Vector3.new(0.45 + i * 0.13, 0.24 + i * 0.04, 0.10), if i % 3 == 0 then CREAM else BLUE, 0.09)
		floatAndFade(puff, p - flat * (1 + i * 0.16), 0.22 + i * 0.022, Vector3.new(0.14, 0.08, 0.06))
	end
	local highlight = blob("ClayDashFlash", base, Vector3.new(2.0, 1.4, 0.09), YELLOW, 0.66)
	floatAndFade(highlight, base + flat * 0.6, 0.16, Vector3.new(3.2, 0.35, 0.07))
end

-- Granate: aus der bisher schlichten Kugel wird eine Knetebombe mit Kappe,
-- gebogener Zündschnur und Funken. Schussbahn und Hitbox bleiben unverändert.
function ItemAnimations.grenade(part: BasePart)
	if part:FindFirstChild("ClayFuse") then
		return
	end
	part.Color = Color3.fromRGB(52, 43, 65)
	part.Material = Enum.Material.SmoothPlastic
	local r = part.Size.Y / 2
	welded(part, "ClayCap", CFrame.new(0, r * 0.88, 0), Vector3.new(r * 0.72, r * 0.32, r * 0.72), PURPLE)
	local fuse = welded(part, "ClayFuse", CFrame.new(0.07, r * 1.28, 0) * CFrame.Angles(0, 0, math.pi / 2 + 0.3), Vector3.new(r * 0.65, 0.14, 0.14), Color3.fromRGB(128, 94, 55), Enum.PartType.Cylinder)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(r * 0.36, 0, 0)
	attachment.Parent = fuse
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ClayFuseSparks"
	sparks.Color = ColorSequence.new(YELLOW, ORANGE)
	sparks.LightEmission = 0.6
	sparks.Size = NumberSequence.new(0.15, 0)
	sparks.Lifetime = NumberRange.new(0.12, 0.27)
	sparks.Speed = NumberRange.new(0.5, 1.5)
	sparks.Rate = 12
	sparks.Parent = attachment
end

-- Farbige Knetbrocken fliegen beim Explodieren nach außen.
function ItemAnimations.explosion(position: Vector3, radius: number?)
	local r = math.min(radius or 6, 12)
	local center = Vector3.new(position.X, position.Y, Constants.SPRITE_Z + 1.1)
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local size = 0.18 + (i % 4) * 0.13
		local p = center + dir * 0.25
		local shard = blob("ClayExplosionChunk", p, Vector3.new(size * 1.1, size, 0.14), if i % 3 == 0 then CREAM elseif i % 2 == 0 then ORANGE else GOLD)
		local distance = r * (0.35 + (i % 5) * 0.075)
		floatAndFade(shard, p + dir * distance, 0.31 + (i % 4) * 0.07, Vector3.new(0.05, 0.05, 0.05))
	end
	for i = 1, 4 do
		local p = center + Vector3.new(math.cos(i * 2.0), math.sin(i * 2.0), 0) * 0.7
		local smoke = blob("ClaySmoke", p, Vector3.new(0.9, 0.75, 0.10), Color3.fromRGB(170, 152, 178), 0.42)
		floatAndFade(smoke, p + Vector3.new(0, 1.2, 0), 0.65, Vector3.new(1.8, 1.4, 0.08))
	end
end

-- Schwert: feine Knete-Splitter zusätzlich zur bereits vorhandenen, kollisionskorrekten Klinge.
function ItemAnimations.sword(position: Vector3, direction: Vector3)
	local d = Vector3.new(direction.X, direction.Y, 0)
	if d.Magnitude < 0.01 then return end
	d = d.Unit
	local side = Vector3.new(-d.Y, d.X, 0)
	local at = Vector3.new(position.X, position.Y, Constants.SPRITE_Z + 1.2)
	for i = 1, 5 do
		local p = at + d * (1.4 + i * 0.35) + side * (i % 2 == 0 and 0.3 or -0.3)
		local fleck = blob("ClaySwordGlint", p, Vector3.new(0.26, 0.26, 0.06), i % 2 == 0 and CREAM or YELLOW, 0.07)
		floatAndFade(fleck, p + side * (i % 2 == 0 and 0.8 or -0.8), 0.22 + i * 0.026, Vector3.new(0.04, 0.04, 0.04))
	end
end

-- Thruster: gerippte Düsenmanschette, warme Lichtpunkte und Rauch. Das vorhandene
-- Feuer und die physikalische Befestigung werden nicht verändert.
function ItemAnimations.thruster(part: BasePart)
	if part:FindFirstChild("ClayNozzleRing") then
		return
	end
	local ring = welded(part, "ClayNozzleRing", CFrame.new(0.66, 0, 0), Vector3.new(0.19, 1.48, 1.48), GOLD, Enum.PartType.Cylinder)
	ring.Material = Enum.Material.SmoothPlastic
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(1.04, 0, 0)
	attachment.Parent = part
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ClayThrusterSmoke"
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.Color = ColorSequence.new(Color3.fromRGB(252, 222, 170), Color3.fromRGB(169, 143, 174))
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Size = NumberSequence.new(0.2, 0.7)
	smoke.Lifetime = NumberRange.new(0.15, 0.3)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.Rate = 10
	smoke.Parent = attachment
end

local function rounded(frame: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 18)
	c.Parent = frame
end

local function uiPiece(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, radius: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	rounded(f, radius)
	f.Parent = parent
	return f
end

-- Lenkrakete: eigenständige 2D-Knetegrafik vor der bestehenden Physik-Hitbox,
-- roter Kopf, weiße Kapsel, gelber Flammenstrahl und kleine Flossen.
local function missile(part: BasePart)
	if animatedMissiles[part] or part:FindFirstChild("ClayMissileArt") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClayMissileArt"
	gui.Size = UDim2.fromScale(3.2, 1.55)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = part
	local display = Instance.new("Frame")
	display.Name = "RocketArt"
	display.BackgroundTransparency = 1
	display.Size = UDim2.fromScale(1, 1)
	display.Parent = gui

	local flame = uiPiece(display, "ThrusterFlame", UDim2.fromScale(0.27, 0.29), UDim2.fromScale(0.05, 0.355), GOLD, 22)
	uiPiece(display, "TailGlow", UDim2.fromScale(0.14, 0.19), UDim2.fromScale(0.12, 0.4), ORANGE, 18)
	uiPiece(display, "RedFinTop", UDim2.fromScale(0.21, 0.15), UDim2.fromScale(0.27, 0.21), ORANGE, 8)
	uiPiece(display, "RedFinBottom", UDim2.fromScale(0.21, 0.15), UDim2.fromScale(0.27, 0.64), ORANGE, 8)
	local hull = uiPiece(display, "CreamBody", UDim2.fromScale(0.54, 0.45), UDim2.fromScale(0.24, 0.275), CREAM, 26)
	local highlight = Instance.new("UIGradient")
	highlight.Rotation = 90
	highlight.Color = ColorSequence.new(Color3.fromRGB(255, 255, 247), Color3.fromRGB(228, 215, 211))
	highlight.Parent = hull
	uiPiece(display, "RedNose", UDim2.fromScale(0.19, 0.44), UDim2.fromScale(0.71, 0.28), Color3.fromRGB(238, 71, 68), 22)
	uiPiece(display, "Porthole", UDim2.fromScale(0.12, 0.24), UDim2.fromScale(0.48, 0.37), BLUE, 24)
	part.LocalTransparencyModifier = 1
	animatedMissiles[part] = { frame = display, flame = flame }
end

function ItemAnimations.start()
	if started then return end
	started = true
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for part, art in animatedMissiles do
			if not part.Parent or not art.frame.Parent then
				animatedMissiles[part] = nil
			else
				local forward = part.CFrame.RightVector
				art.frame.Rotation = -math.deg(math.atan2(forward.Y, forward.X))
				local pulse = 0.2 + math.abs(math.sin(now * 18)) * 0.12
				art.flame.Size = UDim2.fromScale(pulse, 0.29)
				art.flame.Position = UDim2.fromScale(0.27 - pulse, 0.355)
			end
		end
	end)

	task.spawn(function()
		local folder = Workspace:WaitForChild(Constants.MISSILES_FOLDER, 30)
		if not folder then return end
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Missile" then
				missile(child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") and child.Name == "Missile" then
				missile(child)
			end
		end)
	end)
end

return ItemAnimations