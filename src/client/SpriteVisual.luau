--!strict
-- Ein Sprite-Bild in der Welt: ein unsichtbares, flaches Teil mit dem Bild auf der Seite zur Kamera.
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
	image: ImageLabel, -- gerade sichtbare Ebene
	back: ImageLabel, -- Ebene, in die das nächste Bild geladen wird
	wanted: string, -- Bild, das gezeigt werden soll
	pendingSince: number, -- seit wann das gewünschte Bild lädt
	flip: boolean,
}

-- Spätestens nach dieser Zeit wird auf das neue Bild gewechselt, auch wenn Roblox es noch nicht als
-- geladen meldet (bei unsichtbaren Ebenen meldet Roblox "geladen" teils gar nicht)
local MAX_WAIT = 0.6
-- Die hintere Ebene ist fast (nicht ganz) unsichtbar: nur dann lädt Roblox ihr Bild zuverlässig
-- und meldet "geladen". So wird nie auf ein noch leeres Bild umgeschaltet (Figur kurz unsichtbar).
local BACK_TRANSPARENCY = 0.985

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

	-- Die Kamera schaut von +Z, also ist die "Back"-Seite des Teils die sichtbare
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0 -- Farben wie im Bild, unabhängig vom Licht
	-- Die Kamera steht sehr weit weg (fast-2D-Ansicht): Bilder nie wegen Entfernung ausblenden
	pcall(function()
		(gui :: any).MaxDistance = 1e6
	end)
	gui.Parent = part

	local function makeLayer(): ImageLabel
		local layer = Instance.new("ImageLabel")
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.ScaleType = Enum.ScaleType.Stretch
		layer.Parent = gui
		return layer
	end
	local image = makeLayer()
	local back = makeLayer()
	back.ImageTransparency = BACK_TRANSPARENCY

	part.Parent = parent
	return { part = part, image = image, back = back, wanted = "", pendingSince = 0, flip = false }
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
	-- ... und tauschen, sobald es geladen ist. Bis dahin bleibt das alte Bild stehen (lieber kurz
	-- eingefroren als unsichtbar), höchstens MAX_WAIT lang – oder sofort, wenn es noch gar keins gibt.
	local frontReady = sprite.image.Image ~= "" and sprite.image.IsLoaded
	if sprite.back.IsLoaded or not frontReady or waited >= MAX_WAIT then
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
