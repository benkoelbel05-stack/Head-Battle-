--!strict
-- Ein Sprite-Bild in der Welt. Das unsichtbare, flache Teil gibt Lage, Größe und Drehung vor
-- (ClayAnimator und Effekte setzen part.CFrame und part.Size wie bisher); gezeichnet wird das Bild
-- aber mit einer BillboardGui statt einer SurfaceGui.
-- Warum: SurfaceGuis malt Roblox in ein Zwischenbild, und davon gibt es nur ein begrenztes Budget.
-- Mit Plattformen, Wolken und Hintergrund wurde es knapp, dann ließ Roblox einzelne Figuren einfach
-- weg (Figur unsichtbar). BillboardGuis haben dieses Budget nicht und sind außerdem schärfer.
-- Kann gespiegelt werden (Blickrichtung links/rechts), ohne extra Bilder.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

-- Zwei Bildebenen ("Doppelpuffer"): Ein neues Bild wird erst gezeigt, wenn es fertig geladen ist.
-- So blinkt die Figur beim Wechsel auf ein noch nicht geladenes Bild nicht kurz unsichtbar.
export type Sprite = {
	part: Part,
	gui: BillboardGui,
	image: ImageLabel, -- gerade sichtbare Ebene
	back: ImageLabel, -- Ebene, in die das nächste Bild geladen wird
	wanted: string, -- Bild, das gezeigt werden soll
	pendingSince: number, -- seit wann das gewünschte Bild lädt
	flip: boolean,
}

-- Spätestens nach dieser Zeit wird auf das neue Bild gewechselt, auch wenn Roblox es noch nicht als
-- geladen meldet. Bis dahin bleibt das alte Bild stehen (lieber kurz eingefroren als unsichtbar).
local MAX_WAIT = 1.5
-- Die hintere Ebene ist fast (nicht ganz) unsichtbar: nur dann lädt Roblox ihr Bild zuverlässig
-- und meldet "geladen".
local BACK_TRANSPARENCY = 0.985
-- Bild ein kleines Stück zur Kamera hin, damit es nie mit Flächen dahinter um die Tiefe streitet
local TOWARD_CAMERA = 0.3

local SpriteVisual = {}

function SpriteVisual.create(name: string, parent: Instance): Sprite
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(Constants.SPRITE_SIZE, Constants.SPRITE_SIZE, 0.05)

	local gui = Instance.new("BillboardGui")
	gui.Name = "SpriteGui"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(part.Size.X, part.Size.Y) -- in Studs
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, TOWARD_CAMERA)
	gui.LightInfluence = 0 -- Farben wie im Bild, unabhängig vom Licht
	gui.AlwaysOnTop = false -- verdeckt sich korrekt mit anderen Figuren und Effekten
	gui.ClipsDescendants = false
	gui.MaxDistance = 1e6 -- die Kamera steht sehr weit weg: nie wegen Entfernung ausblenden
	gui.Parent = part

	local function makeLayer(): ImageLabel
		local layer = Instance.new("ImageLabel")
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.fromScale(0.5, 0.5)
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.ScaleType = Enum.ScaleType.Stretch
		layer.Parent = gui
		return layer
	end
	local image = makeLayer()
	local back = makeLayer()
	back.ImageTransparency = BACK_TRANSPARENCY

	local sprite: Sprite = { part = part, gui = gui, image = image, back = back, wanted = "", pendingSince = 0, flip = false }

	-- Größe und Drehung des Teils auf das Bild übertragen (Quetschen, Aufploppen, Kleben an Wänden)
	part:GetPropertyChangedSignal("Size"):Connect(function()
		gui.Size = UDim2.fromScale(part.Size.X, part.Size.Y)
	end)
	local lastRotation = 0
	part:GetPropertyChangedSignal("CFrame"):Connect(function()
		local right = part.CFrame.RightVector
		local rotation = -math.deg(math.atan2(right.Y, right.X))
		if math.abs(rotation - lastRotation) > 0.05 then
			lastRotation = rotation
			sprite.image.Rotation = rotation
			sprite.back.Rotation = rotation
		end
	end)

	part.Parent = parent
	return sprite
end

local function applyFlip(layer: ImageLabel, flip: boolean)
	local pixels = Constants.SPRITE_PIXELS
	if flip then
		-- Spiegeln: Bildausschnitt mit negativer Breite
		layer.ImageRectOffset = Vector2.new(pixels, 0)
		layer.ImageRectSize = Vector2.new(-pixels, pixels)
	else
		layer.ImageRectOffset = Vector2.zero
		layer.ImageRectSize = Vector2.zero
	end
end

-- Bild setzen; flip = nach links schauen (gespiegelt). Wird jeden Frame aufgerufen.
function SpriteVisual.setImage(sprite: Sprite, assetId: string?, flip: boolean)
	local wanted = assetId or ""
	-- Fehlt ein Einzelbild (ID 0), bleibt das letzte Bild stehen statt einer leeren Figur
	if wanted == "" and sprite.image.Image ~= "" then
		wanted = sprite.image.Image
	end
	if sprite.flip ~= flip then
		sprite.flip = flip
		applyFlip(sprite.image, flip)
		applyFlip(sprite.back, flip)
	end
	if sprite.image.Image == wanted then
		return
	end
	-- Neues Bild in die hintere Ebene laden ...
	if sprite.back.Image ~= wanted then
		sprite.back.Image = wanted
		sprite.pendingSince = os.clock()
	end
	sprite.wanted = wanted
	local waited = os.clock() - sprite.pendingSince
	-- ... und tauschen, sobald es geladen ist (oder sofort, wenn vorne noch gar nichts ist)
	if sprite.back.IsLoaded or sprite.image.Image == "" or waited >= MAX_WAIT then
		local front = sprite.image
		sprite.image = sprite.back
		sprite.back = front
		sprite.image.ImageTransparency = 0
		sprite.back.ImageTransparency = BACK_TRANSPARENCY
	end
end

-- Alle Sprites vorladen (verhindert Flackern beim ersten Abspielen).
-- In Roblox Studio steht im Output, wie viele bereit sind.
function SpriteVisual.preload()
	local list = SpriteAssets.allIds()
	local content = {}
	local missing = 0
	for _, entry in list do
		if entry.id == 0 then
			missing += 1
		else
			local assetId = `rbxassetid://{entry.id}`
			table.insert(content, assetId)
		end
	end

	local loaded, failed = 0, 0
	local isStudio = RunService:IsStudio()
	task.spawn(function()
		ContentProvider:PreloadAsync(content, function(_assetId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Success then
				loaded += 1
			else
				failed += 1
			end
		end)
		if isStudio then
			print(`[ClayBattle] Sprites vorgeladen: {loaded} bereit, {failed} (noch) nicht, {missing} fehlen noch`)
		end
	end)
end

return SpriteVisual
