--!strict
-- Lädt alle Bilder und Klänge vor, in der Reihenfolge, in der man sie braucht:
--   1. Hauptmenü (Bilder + Musik)   2. Ausrüstungs-Wahl (Tafeln, Icons, Soundeffekte)
--   3. Arena (Hintergründe, Plattform-Texturen, Wolken, Wasser)   4. Figuren-Sprites
-- Der Ladebildschirm ruft run() mit einer Fortschrittsanzeige auf.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MenuAssetIds = require(script.Parent.MenuAssetIds)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)
local PlatformTextures = require(ReplicatedStorage.Shared.PlatformTextures)
local OceanAssets = require(ReplicatedStorage.Shared.OceanAssets)
local SoundIds = require(ReplicatedStorage.Shared.SoundIds)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

local AssetPreloader = {}

local BATCH = 12 -- so viele auf einmal (für eine flüssige Fortschrittsanzeige)

local function collect(): { { name: string, items: { string } } }
	local seen: { [string]: boolean } = {}
	local function list(): { string }
		return {}
	end
	local function add(target: { string }, id: unknown)
		if typeof(id) == "number" and id ~= 0 then
			local content = `rbxassetid://{id}`
			if not seen[content] then
				seen[content] = true
				table.insert(target, content)
			end
		end
	end

	local menu = list()
	for _, id in MenuAssetIds do
		add(menu, id)
	end

	local ui = list()
	for _, id in UIAssets do
		add(ui, id)
	end
	for _, id in AbilityIcons do
		add(ui, id)
	end
	for _, id in SoundIds do
		add(ui, id)
	end

	local arena = list()
	for _, id in ArenaAssets do
		add(arena, id)
	end
	for _, material in PlatformTextures do
		add(arena, material.tex)
		add(arena, material.trim)
		add(arena, material.rimTex)
	end
	for _, key in { "clouds_left", "clouds_right", "clouds_distant", "water_base", "water_shimmer" } do
		add(arena, (OceanAssets :: any)[key])
	end
	for _, id in OceanAssets.small do
		add(arena, id)
	end

	local sprites = list()
	for _, entry in SpriteAssets.allIds() do
		add(sprites, entry.id)
	end

	return {
		{ name = "Hauptmenü", items = menu },
		{ name = "Bedienung und Klänge", items = ui },
		{ name = "Arena", items = arena },
		{ name = "Figuren", items = sprites },
	}
end

-- Alles laden. onProgress(fertig, gesamt, Abschnitt) wird nach jedem kleinen Paket aufgerufen.
function AssetPreloader.run(onProgress: ((number, number, string) -> ())?)
	local groups = collect()
	local total = 0
	for _, group in groups do
		total += #group.items
	end
	local done = 0
	local failed = 0
	local started = os.clock()
	for _, group in groups do
		for first = 1, #group.items, BATCH do
			local batch = {}
			for i = first, math.min(first + BATCH - 1, #group.items) do
				table.insert(batch, group.items[i])
			end
			ContentProvider:PreloadAsync(batch, function(_content: string, status: Enum.AssetFetchStatus)
				if status ~= Enum.AssetFetchStatus.Success then
					failed += 1
				end
			end)
			done += #batch
			if onProgress then
				onProgress(done, total, group.name)
			end
		end
	end
	if RunService:IsStudio() then
		print(`[ClayBattle] Vorgeladen: {total - failed}/{total} in {string.format("%.1f", os.clock() - started)} s`)
	end
end

return AssetPreloader
