--!strict
-- Lädt alle Bilder und Klänge gleich beim Start vor, in der Reihenfolge, in der man sie braucht:
--   1. Hauptmenü (Bilder + Musik)   2. Ausrüstungs-Wahl (Tafeln, Icons)
--   3. Arena (Hintergründe, Plattform-Texturen, Wolken, Wasser)   4. Figuren-Sprites (die meisten)
-- So ist beim Öffnen eines Bildschirms schon alles da, statt erst dann nachzuladen.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MenuAssetIds = require(script.Parent.MenuAssetIds)
local SpriteVisual = require(script.Parent.SpriteVisual)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)
local PlatformTextures = require(ReplicatedStorage.Shared.PlatformTextures)
local OceanAssets = require(ReplicatedStorage.Shared.OceanAssets)
local SoundIds = require(ReplicatedStorage.Shared.SoundIds)

local AssetPreloader = {}

local function add(list: { string }, id: unknown)
	if typeof(id) == "number" and id ~= 0 then
		table.insert(list, `rbxassetid://{id}`)
	end
end

local function preload(name: string, list: { string })
	if #list == 0 then
		return
	end
	local started = os.clock()
	local failed = 0
	ContentProvider:PreloadAsync(list, function(_content: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			failed += 1
		end
	end)
	if RunService:IsStudio() then
		print(`[ClayBattle] Vorgeladen: {name} – {#list - failed}/{#list} in {string.format("%.1f", os.clock() - started)} s`)
	end
end

function AssetPreloader.start()
	-- 1. Hauptmenü
	local menu = {}
	for _, id in MenuAssetIds do
		add(menu, id)
	end
	preload("Hauptmenü", menu)

	-- 2. Ausrüstungs-Wahl und Anzeigen
	local ui = {}
	for _, id in UIAssets do
		add(ui, id)
	end
	for _, id in AbilityIcons do
		add(ui, id)
	end
	for _, id in SoundIds do
		add(ui, id)
	end
	preload("Bedienelemente", ui)

	-- 3. Arena
	local arena = {}
	for _, id in ArenaAssets do
		add(arena, id)
	end
	for _, material in PlatformTextures do
		add(arena, material.tex)
		add(arena, material.trim)
		add(arena, material.rimTex)
	end
	add(arena, OceanAssets.clouds_left)
	add(arena, OceanAssets.clouds_right)
	add(arena, OceanAssets.clouds_distant)
	add(arena, OceanAssets.water_base)
	add(arena, OceanAssets.water_shimmer)
	for _, id in OceanAssets.small do
		add(arena, id)
	end
	preload("Arena", arena)

	-- 4. Figuren (viele Einzelbilder)
	SpriteVisual.preload()
end

return AssetPreloader
