--!strict
-- Ein Sprite-Bild in der Welt: ein unsichtbares, flaches Teil mit dem Bild auf der Seite zur Kamera.
-- Kann gespiegelt werden (Blickrichtung links/rechts), ohne extra Bilder.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

export type Sprite = {
	part: Part,
	image: ImageLabel,
}

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
	gui.Parent = part

	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Stretch
	image.Parent = gui

	part.Parent = parent
	return { part = part, image = image }
end

-- Bild setzen; flip = nach links schauen (gespiegelt)
function SpriteVisual.setImage(sprite: Sprite, assetId: string?, flip: boolean)
	local image = sprite.image
	if image.Image ~= (assetId or "") then
		image.Image = assetId or ""
	end
	local pixels = Constants.SPRITE_PIXELS
	if flip then
		-- Spiegeln: Bildausschnitt mit negativer Breite
		image.ImageRectOffset = Vector2.new(pixels, 0)
		image.ImageRectSize = Vector2.new(-pixels, pixels)
	else
		image.ImageRectOffset = Vector2.zero
		image.ImageRectSize = Vector2.zero
	end
end

-- Alle Sprites vorladen (verhindert Flackern beim ersten Abspielen).
-- In Roblox Studio werden außerdem kaputte IDs (Tippfehler, gelöschte Bilder) im Output gemeldet.
function SpriteVisual.preload()
	local list = SpriteAssets.allIds()
	local content = {}
	local lookup: { [string]: { skin: string, animation: string, index: number } } = {}
	local missing = 0
	for _, entry in list do
		if entry.id == 0 then
			missing += 1
		else
			local assetId = `rbxassetid://{entry.id}`
			table.insert(content, assetId)
			lookup[assetId] = entry
		end
	end

	local broken = 0
	local isStudio = RunService:IsStudio()
	task.spawn(function()
		ContentProvider:PreloadAsync(content, function(assetId: string, status: Enum.AssetFetchStatus)
			if isStudio and status == Enum.AssetFetchStatus.Failure then
				broken += 1
				local entry = lookup[assetId]
				if entry then
					warn(`[HeadBattle] Sprite lädt nicht: {entry.skin} {entry.animation}_0{entry.index} ({assetId})`)
				end
			end
		end)
		if isStudio then
			print(`[HeadBattle] Sprites geprüft: {#content} geladen, {broken} kaputt, {missing} fehlen noch (Processing)`)
		end
	end)
end

return SpriteVisual
