--!strict
-- Runtime for individual transparent PNG frames uploaded as Image assets.
-- No Decal objects. If a sequence has zero/unapproved IDs, callers keep
-- using the procedural fallback in ItemAnimations.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local IDs = require(ReplicatedStorage.Shared.ItemSpriteIds)
local ImageCache = require(script.Parent.ImageCache)
local Constants = require(ReplicatedStorage.Shared.Constants)

local ItemSpriteOverlay = {}
local FPS: { [string]: number } = {
	grenade_spin = 10, grenade_explosion = 12,
	thruster_burst = 12, sword_swing = 28, -- Schwert schnell: der echte Treffer dauert nur 0,14 s
	missile_flight = 10, dash_burst = 14,
}
local LOOPS: { [string]: boolean } = {
	grenade_spin = true, thruster_burst = true, missile_flight = true,
}
local active: { [BasePart]: boolean } = {}

local function valid(seq: string): boolean
	local frames: { number }? = IDs[seq]
	if not frames or #frames ~= 8 then return false end
	for _, id in frames do
		if typeof(id) ~= "number" or id <= 0 then return false end
	end
	return true
end
function ItemSpriteOverlay.has(seq: string): boolean return valid(seq) end

local function buildImage(part: BasePart, size: number): (BillboardGui, ImageLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClayItemSprite"
	gui.Adornee = part
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(size, size)
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.Name = "Frame"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.ImageTransparency = 0
	image.Parent = gui
	return gui, image
end

-- update (optional): wird jedes Bild aufgerufen und richtet Bild und Lage aus (Drehung, Versatz).
-- shown = Nummer des Bildes, das gerade wirklich angezeigt wird
local function animate(part: BasePart, seq: string, size: number, update: ((BillboardGui, ImageLabel, number) -> ())?): boolean
	if not valid(seq) then return false end
	if active[part] then return true end
	active[part] = true
	local frames: { number } = IDs[seq]
	local gui, image = buildImage(part, size)
	local elapsed = 0
	local fps = FPS[seq] or 12
	local looping = LOOPS[seq] == true
	local connection: RBXScriptConnection?
	local died: RBXScriptConnection?
	local function cleanup()
		if connection then connection:Disconnect(); connection = nil end
		if died then died:Disconnect(); died = nil end
		active[part] = nil
		if gui.Parent then gui:Destroy() end
	end
	died = part.Destroying:Connect(cleanup)
	image.Image = "rbxassetid://" .. tostring(frames[1])
	local shown = 1
	if update then
		update(gui, image, shown) -- gleich richtig ausgerichtet, nicht erst ab dem nächsten Bild
	end
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not part.Parent then cleanup(); return end
		elapsed += math.min(dt, 0.1)
		local index = math.floor(elapsed * fps) + 1
		if looping then
			index = ((index - 1) % #frames) + 1
		elseif index > #frames then
			cleanup()
			return
		end
		local uri = "rbxassetid://" .. tostring(frames[index])
		-- Nur auf ein fertig geladenes Bild wechseln, sonst das vorige stehen lassen (nie leer)
		if image.Image ~= uri and (ImageCache.isLoaded(uri) or image.Image == "") then
			image.Image = uri
			shown = index
		end
		if update then
			update(gui, image, shown)
		end
	end)
	return true
end

function ItemSpriteOverlay.attach(part: BasePart, seq: string, size: number, angleFromPart: boolean?): boolean
	if angleFromPart ~= true then
		return animate(part, seq, size, nil)
	end
	return animate(part, seq, size, function(_gui: BillboardGui, image: ImageLabel, _shown: number)
		-- The original missile art points about 35 degrees above horizontal.
		-- Frame.Rotation increases clockwise; horizontal right is 0.
		local v = part.CFrame.RightVector
		image.Rotation = 35 - math.deg(math.atan2(v.Y, v.X))
	end)
end

-- An einer Fläche festgemacht (Thruster): part.RightVector zeigt aus der Fläche heraus, der Teil sitzt
-- partOffset Studs vor dem Klebepunkt. Das Bild (Flammen unten) wird so gedreht, dass die Flammen von
-- der Fläche weg zeigen, und so weit nach außen gesetzt, dass seine Oberkante auf der Fläche sitzt.
-- Dreht sich die Plattform, dreht es jedes Bild mit. Etwas vor die Plattform (zur Kamera) gesetzt,
-- damit es nicht hinter ihrer Vorderseite verschwindet. Der Versatz wird in Weltkoordinaten
-- berechnet und dann in die Achsen des Teils umgerechnet (so erwartet es StudsOffsetWorldSpace).
local SURFACE_TOP = 0.42 -- Abstand Bildmitte bis Oberkante des Packs (Anteil der Bildgröße)
function ItemSpriteOverlay.attachToSurface(part: BasePart, seq: string, size: number, partOffset: number): boolean
	return animate(part, seq, size, function(gui: BillboardGui, image: ImageLabel, _shown: number)
		local outward = part.CFrame.RightVector
		local flat = Vector3.new(outward.X, outward.Y, 0)
		if flat.Magnitude < 1e-3 then
			return
		end
		flat = flat.Unit
		local along = size * SURFACE_TOP - partOffset
		local worldOffset = flat * along + Vector3.new(0, 0, (Constants.SPRITE_Z - 0.4) - part.Position.Z)
		-- StudsOffsetWorldSpace gilt trotz des Namens in den Achsen des Adornee (hier: X = aus der Fläche,
		-- Z = entlang der Fläche). Ohne Umrechnung landete der Z-Versatz (5 Studs) entlang der Fläche:
		-- das Bild stand neben der Figur statt unter ihr. Deshalb in Teil-Koordinaten umrechnen.
		gui.StudsOffsetWorldSpace = part.CFrame:VectorToObjectSpace(worldOffset)
		image.Rotation = -(math.deg(math.atan2(flat.Y, flat.X)) + 90)
	end)
end

-- Unsichtbarer Haltepunkt ohne Drehung (dann gelten Versätze in Weltachsen)
local function makeAnchor(position: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Name = "ClayItemEffectAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = Vector3.new(position.X, position.Y, Constants.SPRITE_Z + 1.9)
	anchor.Parent = Workspace
	return anchor
end

function ItemSpriteOverlay.burst(position: Vector3, seq: string, size: number, rotationDegrees: number?): boolean
	if not valid(seq) then return false end
	local anchor = makeAnchor(position)
	local success = animate(anchor, seq, size, nil)
	if success and rotationDegrees then
		local sprite = anchor:FindFirstChild("ClayItemSprite")
		local image = sprite and sprite:FindFirstChild("Frame")
		if image and image:IsA("ImageLabel") then image.Rotation = rotationDegrees end
	end
	Debris:AddItem(anchor, 8 / (FPS[seq] or 12) + 0.12)
	return success
end

-- Schwertschlag. Die Bilder zeigen ein Schwert, das sich um die eigene Mitte dreht: Klinge von 1° bis 111°
-- (gegen den Uhrzeigersinn, 0° = nach rechts), der Griff sitzt 0,21 Bildgrößen hinter der Bildmitte.
-- Werte aus den 8 Bildern gemessen. Damit der Schlag aus der Hand kommt, wird das Bild jedes Bild so
-- verschoben, dass der Griff knapp vor dem Kopf liegt, und so gedreht, dass die Mitte des Schwungs
-- (56°) in Schlagrichtung zeigt. getOrigin liefert die aktuelle Kopfmitte (Schlag läuft beim Laufen mit).
local SWING_ANGLES = { 1, 19, 42, 65, 88, 111, 99, 66 }
local SWING_CENTER = 56
local SWING_GRIP = 0.21 -- Anteil der Bildgröße: Bildmitte bis Griff
local SWING_HAND = 0.8 -- Studs: Kopfmitte bis Griff (Parierstange schaut am Rand der Figur heraus)
-- Hinter der Figur (die liegt ab SPRITE_Z + 0,3), aber vor den Plattformen (Vorderseite höchstens ~4,5):
-- vorher lag das Schwert davor und der Griff verdeckte Gesicht und Körper der Figur
local SWING_Z = Constants.SPRITE_Z - 0.3
function ItemSpriteOverlay.swing(getOrigin: () -> Vector3, aimDegrees: number, size: number): boolean
	if not valid("sword_swing") then return false end
	local turn = aimDegrees - SWING_CENTER
	local anchor = makeAnchor(getOrigin())
	local function place(shown: number)
		local blade = math.rad((SWING_ANGLES[shown] or SWING_CENTER) + turn)
		local direction = Vector3.new(math.cos(blade), math.sin(blade), 0)
		local center = getOrigin() + direction * (SWING_HAND + size * SWING_GRIP)
		anchor.Position = Vector3.new(center.X, center.Y, SWING_Z)
	end
	place(1)
	local success = animate(anchor, "sword_swing", size, function(_gui: BillboardGui, image: ImageLabel, shown: number)
		image.Rotation = -turn -- Rotation dreht im Uhrzeigersinn
		place(shown)
	end)
	Debris:AddItem(anchor, 8 / FPS.sword_swing + 0.12)
	return success
end

return ItemSpriteOverlay