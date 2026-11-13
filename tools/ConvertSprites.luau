-- Wandelt die Decal-IDs aus SpriteAssets.luau in Image-IDs um und legt das Ergebnis als ModuleScript
-- "SpriteImages_Ergebnis" in ServerStorage ab.
--
-- Benutzung (einmalig, und immer wenn neue Sprites dazukommen):
--   1. Roblox Studio mit Rojo verbinden (damit ReplicatedStorage.Shared.SpriteAssets da ist)
--   2. Dieses ganze Skript kopieren und in die Befehlsleiste (Ansicht -> Befehlsleiste) einfügen, Enter
--   3. Warten, bis im Output "FERTIG" steht (dauert etwas, ca. 450 Bilder)
--   4. ServerStorage -> SpriteImages_Ergebnis öffnen, alles kopieren und in die Datei
--      src/shared/SpriteImages.luau einfügen (alten Inhalt ersetzen), speichern, git commit + push
--
-- Funktioniert nur für Bilder, die deinem eigenen Konto gehören (du musst in Studio angemeldet sein).

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

local ANIMATIONS = { "idle", "run", "jump", "land", "hit", "stun", "respawn" }
local failed = 0
local converted = 0

local function toImageId(decalId: number): number
	if decalId == 0 then
		return 0
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(decalId)
	end)
	if not ok then
		failed += 1
		warn(`[ConvertSprites] Konnte {decalId} nicht laden: {result}`)
		return 0
	end
	local model = result :: Model
	local decal = model:FindFirstChildWhichIsA("Decal", true)
	local imageId = if decal then tonumber(string.match(decal.Texture, "%d+")) else nil
	model:Destroy()
	if not imageId then
		failed += 1
		warn(`[ConvertSprites] Keine Bild-ID in Decal {decalId} gefunden`)
		return 0
	end
	converted += 1
	return imageId
end

local skinNames = {}
for skin in SpriteAssets.skins do
	table.insert(skinNames, skin)
end
table.sort(skinNames)

local lines = {
	"--!strict",
	"-- Image-IDs der Charakter-Sprites. ERZEUGT von tools/ConvertSprites.luau – nicht von Hand ändern.",
	"return {",
	"\tskins = {",
}

for _, skin in skinNames do
	print(`[ConvertSprites] {skin} ...`)
	table.insert(lines, `\t\t{skin} = \{`)
	local sprites = SpriteAssets.skins[skin]
	for _, animation in ANIMATIONS do
		local frames = sprites[animation] or {}
		local ids = {}
		local overrides = (SpriteAssets.imageOverrides[skin] or {})[animation] or {}
		for index, decalId in frames do
			ids[index] = tostring(overrides[index] or toImageId(decalId))
		end
		table.insert(lines, `\t\t\t{animation} = \{ {table.concat(ids, ", ")} \},`)
	end
	table.insert(lines, "\t\t},")
end
table.insert(lines, "\t},")

table.insert(lines, "\tportraits = {")
for _, skin in skinNames do
	local decalId = SpriteAssets.portraits[skin] or 0
	table.insert(lines, `\t\t{skin} = {toImageId(decalId)},`)
end
table.insert(lines, "\t},")
table.insert(lines, "}")

local old = ServerStorage:FindFirstChild("SpriteImages_Ergebnis")
if old then
	old:Destroy()
end
local result = Instance.new("ModuleScript")
result.Name = "SpriteImages_Ergebnis"
result.Source = table.concat(lines, "\n") .. "\n"
result.Parent = ServerStorage

print(`[ConvertSprites] FERTIG: {converted} umgewandelt, {failed} fehlgeschlagen. Ergebnis: ServerStorage.SpriteImages_Ergebnis`)
