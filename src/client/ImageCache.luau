--!strict
-- Hält die Bilder, die im Spiel plötzlich gebraucht werden, die ganze Zeit geladen:
--   * alle Bilder der Item-Animationen (Dash, Granate, Explosion, Schwert, Rakete, Thruster)
--   * die Figuren-Bilder aller Farben, die gerade im Spiel sind (und die eigene Farbe)
-- Warum: Roblox lädt ein Bild oft erst, wenn es angezeigt wird, und wirft selten gezeigte Bilder
-- wieder aus dem Speicher. Dann blieb eine Animation die ersten 2-3 Male leer (unsichtbar), bis alle
-- Einzelbilder einmal geladen waren. Hier hängt jedes dieser Bilder als winziges, fast durchsichtiges
-- Bild (2 % sichtbar, unten links hinter allem) im Bildschirm – das hält es geladen.
-- ImageCache.isLoaded(bild) sagt, ob ein Bild schon bereit ist (Animationen warten sonst darauf).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)
local ItemSpriteIds = require(ReplicatedStorage.Shared.ItemSpriteIds)

local ImageCache = {}

local CELL = 12 -- Pixel pro Bild (groß genug, dass Roblox eine brauchbare Schärfe-Stufe hält)
local COLUMNS = 24
local HOLD_TRANSPARENCY = 0.985 -- fast unsichtbar; ganz unsichtbare Bilder lädt Roblox nicht zuverlässig

local holder: Frame? = nil
local labels: { [string]: ImageLabel } = {}
local count = 0
local keptSkins: { [string]: boolean } = {}

-- Ein Bild dauerhaft geladen halten (content = "rbxassetid://...")
function ImageCache.keep(content: string?)
	local frame = holder
	if not frame or not content or content == "" or labels[content] then
		return
	end
	local label = Instance.new("ImageLabel")
	label.Name = "Keep"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromOffset(CELL, CELL)
	label.Position = UDim2.fromOffset((count % COLUMNS) * CELL, -((count // COLUMNS) + 1) * CELL)
	label.ImageTransparency = HOLD_TRANSPARENCY
	label.Image = content
	label.Parent = frame
	labels[content] = label
	count += 1
end

-- Ist das Bild geladen? (unbekannte Bilder: nicht prüfbar, dann "ja", damit nichts hängen bleibt)
function ImageCache.isLoaded(content: string): boolean
	local label = labels[content]
	return label == nil or label.IsLoaded
end

-- Alle Figuren-Bilder einer Farbe geladen halten
function ImageCache.keepSkin(skin: unknown)
	if typeof(skin) ~= "string" or keptSkins[skin] then
		return
	end
	keptSkins[skin] = true
	for _, entry in SpriteAssets.allIds() do
		if entry.skin == skin and entry.id ~= 0 then
			ImageCache.keep(`rbxassetid://{entry.id}`)
		end
	end
end

function ImageCache.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleImageCache"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -50 -- hinter jeder anderen Oberfläche
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Name = "Holder"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.fromScale(0, 1) -- unten links; die Bilder liegen darüber
	frame.Size = UDim2.fromOffset(COLUMNS * CELL, 0)
	frame.Parent = gui
	holder = frame

	-- Item-Animationen
	for _, frames in ItemSpriteIds do
		for _, id in frames do
			if id ~= 0 then
				ImageCache.keep(`rbxassetid://{id}`)
			end
		end
	end

	-- Eigene Farbe und alle Farben im Spiel (auch später dazukommende und Farbwechsel)
	ImageCache.keepSkin(player:GetAttribute("Skin"))
	player:GetAttributeChangedSignal("Skin"):Connect(function()
		ImageCache.keepSkin(player:GetAttribute("Skin"))
	end)
	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)
	local function watchHead(head: Instance)
		ImageCache.keepSkin(head:GetAttribute("Skin"))
		head:GetAttributeChangedSignal("Skin"):Connect(function()
			ImageCache.keepSkin(head:GetAttribute("Skin"))
		end)
	end
	for _, head in headsFolder:GetChildren() do
		watchHead(head)
	end
	headsFolder.ChildAdded:Connect(watchHead)
end

return ImageCache
