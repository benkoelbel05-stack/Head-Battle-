--!strict
-- Lädt alle Bilder und Klänge WIRKLICH vollständig vor, bevor das Hauptmenü erscheint.
--
-- Warum nicht einfach ContentProvider:PreloadAsync({"rbxassetid://…"})?
--   * Mit reinen ID-Texten lädt Roblox Bilder nicht zuverlässig vor (nur über ein Bild-Element).
--   * Roblox streamt Bilder in Stufen: erst eine kleine, unscharfe Fassung, die scharfe erst, wenn das
--     Bild groß genug auf dem Bildschirm zu sehen ist. Deshalb wirkten Icons anfangs unscharf.
--
-- Darum zeigt dieser Lader jedes Bild einmal echt an, ungefähr so groß wie später im Spiel, direkt
-- unter dem Ladebildschirm (der deckt alles ab, man sieht es also nicht). Er wartet, bis jedes Bild
-- "IsLoaded" meldet, lässt es noch einen Moment stehen (dann lädt Roblox die scharfe Stufe nach) und
-- macht mit dem nächsten Paket weiter. Was nicht lädt, wird am Ende noch einmal versucht.
-- Klänge werden als echte Sound-Objekte geladen und ebenfalls bis "IsLoaded" abgewartet.
--
-- Reihenfolge: 1. Hauptmenü  2. Bedienung und Klänge  3. Arena  4. Figuren

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MenuAssetIds = require(script.Parent.MenuAssetIds)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local ArenaAssets = require(ReplicatedStorage.Shared.ArenaAssets)
local PlatformTextures = require(ReplicatedStorage.Shared.PlatformTextures)
local OceanAssets = require(ReplicatedStorage.Shared.OceanAssets)
local SoundIds = require(ReplicatedStorage.Shared.SoundIds)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)

local AssetPreloader = {}

-- Anzeigegröße beim Vorladen (Anteil der Bildschirmbreite/-höhe). Mindestens so groß wie später im
-- Spiel, damit Roblox gleich die scharfe Stufe holt.
type SizeClass = "full" | "large" | "tall" | "medium" | "small"
local CELLS: { [SizeClass]: { w: number, h: number, square: boolean } } = {
	full = { w = 1, h = 1, square = false }, -- Hintergründe: ganzer Bildschirm
	large = { w = 0.5, h = 0.5, square = false }, -- Logo, Figuren, große Knöpfe, Wolken
	tall = { w = 0.25, h = 1, square = false }, -- hohe Tafeln der Ausrüstungs-Wahl
	medium = { w = 0.2, h = 0.2, square = true }, -- Icons, Abzeichen, Plattform-Texturen
	small = { w = 0.15, h = 0.15, square = true }, -- Figuren-Bilder (Sprites)
}
local MAX_PER_BATCH = 80
local BATCH_TIMEOUT = 5 -- Sekunden pro Paket, danach weiter (Rest wird am Ende nochmal versucht)
local RETRY_TIMEOUT = 6
local MIN_SHOW = 0.25 -- so lange bleibt ein fertiges Paket noch stehen (scharfe Stufe nachladen)
local SOUND_TIMEOUT = 10

-- Überspringen (Knopf im Ladebildschirm): alle Schleifen hören auf, die Bühne verschwindet sofort
local cancelled = false
local currentStage: ScreenGui? = nil

function AssetPreloader.cancel()
	cancelled = true
	local stage = currentStage
	if stage then
		stage:Destroy()
		currentStage = nil
	end
end

-- Nicht benutzte große Bilder (sparen Ladezeit). Wird eins davon eingebaut: hier entfernen.
local SKIP: { [string]: boolean } = {
	settings_background = true,
	button_start_prompt = true,
	arena_sunset = true,
	arena_night = true,
	bot_control_bar_static = true,
}

type Item = { name: string, content: string, class: SizeClass }
type Section = { name: string, images: { Item }, sounds: { Item } }

local function collect(): { Section }
	local seen: { [string]: boolean } = {}
	local function add(target: { Item }, name: string, id: unknown, class: SizeClass)
		if SKIP[name] or typeof(id) ~= "number" or id == 0 then
			return
		end
		local content = `rbxassetid://{id}`
		if seen[content] then
			return
		end
		seen[content] = true
		table.insert(target, { name = name, content = content, class = class })
	end

	-- 1. Hauptmenü
	local menu: Section = { name = "Hauptmenü", images = {}, sounds = {} }
	for name, id in MenuAssetIds do
		if name == "menu_theme" then
			add(menu.sounds, name, id, "small")
		elseif name == "menu_background" then
			add(menu.images, name, id, "full")
		else
			add(menu.images, name, id, "large")
		end
	end

	-- 2. Bedienung (Ausrüstungs-Wahl, Icons, Fähigkeiten) und Soundeffekte
	local ui: Section = { name = "Bedienung und Klänge", images = {}, sounds = {} }
	for name, id in UIAssets do
		local class: SizeClass = if string.sub(name, 1, 6) == "panel_" then "tall"
			elseif string.sub(name, 1, 7) == "button_" or name == "player_slot_empty" then "large"
			else "medium"
		add(ui.images, name, id, class)
	end
	for name, id in AbilityIcons do
		add(ui.images, `ability_{name}`, id, "medium")
	end
	for name, id in SoundIds do
		add(ui.sounds, `sound_{name}`, id, "small")
	end

	-- 3. Arena: Hintergründe, Plattform-Texturen, Wolken und Wasser
	local arena: Section = { name = "Arena", images = {}, sounds = {} }
	for name, id in ArenaAssets do
		add(arena.images, `arena_{name}`, id, "full")
	end
	for name, material in PlatformTextures do
		add(arena.images, `platform_{name}`, material.tex, "medium")
		add(arena.images, `platform_{name}_trim`, material.trim, "medium")
		add(arena.images, `platform_{name}_rim`, material.rimTex, "medium")
	end
	for _, key in { "clouds_left", "clouds_right", "clouds_distant", "water_base", "water_shimmer" } do
		add(arena.images, key, (OceanAssets :: any)[key], "large")
	end
	for index, id in OceanAssets.small do
		add(arena.images, `cloud_small_{index}`, id, "medium")
	end

	-- 4. Figuren
	local sprites: Section = { name = "Figuren", images = {}, sounds = {} }
	for _, entry in SpriteAssets.allIds() do
		add(sprites.images, `sprite_{entry.skin}_{entry.animation}_{entry.index}`, entry.id, "small")
	end

	return { menu, ui, arena, sprites }
end

-- Bühne direkt unter dem Ladebildschirm; dort werden die Bilder kurz echt angezeigt
local function makeStage(): ScreenGui
	local stage = Instance.new("ScreenGui")
	stage.Name = "ClayBattleWarmup"
	stage.IgnoreGuiInset = true
	stage.ResetOnSpawn = false
	stage.DisplayOrder = 999 -- Ladebildschirm hat 1000 und liegt deckend darüber
	stage.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return stage
end

local function screenSize(stage: ScreenGui): Vector2
	local started = os.clock()
	while stage.AbsoluteSize.X < 2 and os.clock() - started < 2 do
		RunService.RenderStepped:Wait()
	end
	if stage.AbsoluteSize.X >= 2 then
		return stage.AbsoluteSize
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Ein Paket Bilder anzeigen und warten, bis alle geladen sind. Gibt die nicht geladenen zurück.
local function showBatch(stage: ScreenGui, items: { Item }, class: SizeClass, screen: Vector2, timeout: number, onStep: (number) -> ()): { Item }
	local cell = CELLS[class]
	local cellW = math.max(32, math.floor(if cell.square then screen.Y * cell.h else screen.X * cell.w))
	local cellH = math.max(32, math.floor(screen.Y * cell.h))
	local columns = math.max(1, math.floor(screen.X / cellW))

	local labels: { ImageLabel } = {}
	for index, item in items do
		local label = Instance.new("ImageLabel")
		label.Name = item.name
		label.BackgroundTransparency = 1
		label.ScaleType = Enum.ScaleType.Fit
		label.Size = UDim2.fromOffset(cellW, cellH)
		label.Position = UDim2.fromOffset(((index - 1) % columns) * cellW, ((index - 1) // columns) * cellH)
		label.Image = item.content
		label.Parent = stage
		labels[index] = label
	end

	-- Roblox meldet Fehlschläge (z. B. Decal- statt Image-ID) sofort: dann nicht bis zum Timeout warten
	local failed: { [string]: boolean } = {}
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(labels :: { any }, function(content: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					failed[content] = true
				end
			end)
		end)
	end)

	local started = os.clock()
	local reported = 0
	while true do
		local finished = 0
		for index, label in labels do
			if label.IsLoaded or failed[items[index].content] then
				finished += 1
			end
		end
		if finished > reported then
			onStep(finished - reported)
			reported = finished
		end
		if finished >= #labels or os.clock() - started > timeout or cancelled then
			break
		end
		RunService.RenderStepped:Wait()
	end
	if reported < #labels then
		onStep(#labels - reported) -- Fortschritt auch für die Nachzügler weiterzählen
	end

	-- Noch kurz stehen lassen: Roblox lädt jetzt die scharfe Stufe der angezeigten Bilder
	local shownSince = os.clock()
	local frames = 0
	while (frames < 3 or os.clock() - shownSince < MIN_SHOW) and not cancelled do
		RunService.RenderStepped:Wait()
		frames += 1
	end

	local missing: { Item } = {}
	for index, label in labels do
		if not label.IsLoaded then
			table.insert(missing, items[index])
		end
		label:Destroy()
	end
	return missing
end

-- Bilder nach Größenklasse in Pakete aufteilen und nacheinander anzeigen
local function showImages(stage: ScreenGui, images: { Item }, screen: Vector2, timeout: number, onStep: (number) -> ()): { Item }
	local byClass: { [SizeClass]: { Item } } = {}
	local order: { SizeClass } = { "full", "large", "tall", "medium", "small" }
	for _, item in images do
		local list = byClass[item.class]
		if not list then
			list = {}
			byClass[item.class] = list
		end
		table.insert(list, item)
	end
	local missing: { Item } = {}
	for _, class in order do
		local list = byClass[class]
		if list then
			local cell = CELLS[class]
			local cellW = math.max(32, math.floor(if cell.square then screen.Y * cell.h else screen.X * cell.w))
			local cellH = math.max(32, math.floor(screen.Y * cell.h))
			local perBatch = math.clamp(math.floor(screen.X / cellW) * math.floor(screen.Y / cellH), 1, MAX_PER_BATCH)
			for first = 1, #list, perBatch do
				if cancelled then
					break
				end
				local batch = table.move(list, first, math.min(first + perBatch - 1, #list), 1, {})
				for _, item in showBatch(stage, batch, class, screen, timeout, onStep) do
					table.insert(missing, item)
				end
			end
		end
	end
	return missing
end

-- Klänge als echte Sound-Objekte laden; wartet erst bei waitSounds() auf das Ende
local function startSounds(stage: ScreenGui, items: { Item }): () -> { Item }
	local sounds: { Sound } = {}
	for index, item in items do
		local sound = Instance.new("Sound")
		sound.Name = item.name
		sound.SoundId = item.content
		sound.Volume = 0
		sound.Parent = stage
		sounds[index] = sound
	end
	local failed: { [string]: boolean } = {}
	if #sounds > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(sounds :: { any }, function(content: string, status: Enum.AssetFetchStatus)
					if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
						failed[content] = true
					end
				end)
			end)
		end)
	end
	local started = os.clock()
	return function(): { Item }
		while os.clock() - started < SOUND_TIMEOUT and not cancelled do
			local open = false
			for index, sound in sounds do
				if not sound.IsLoaded and not failed[items[index].content] then
					open = true
					break
				end
			end
			if not open then
				break
			end
			task.wait(0.05)
		end
		local missing: { Item } = {}
		for index, sound in sounds do
			if not sound.IsLoaded then
				table.insert(missing, items[index])
			end
			sound:Destroy()
		end
		return missing
	end
end

-- Alles laden. onProgress(fertig, gesamt, Abschnitt) meldet den Fortschritt.
-- Gibt die Namen der Bilder/Klänge zurück, die auch nach dem zweiten Versuch nicht geladen haben.
function AssetPreloader.run(onProgress: ((number, number, string) -> ())?): { string }
	local sections = collect()
	local total = 0
	for _, section in sections do
		total += #section.images + #section.sounds
	end
	local done = 0
	local currentSection = ""
	local function step(count: number)
		done = math.min(total, done + count)
		if onProgress then
			onProgress(done, total, currentSection)
		end
	end

	local started = os.clock()
	cancelled = false
	local stage = makeStage()
	currentStage = stage
	local screen = screenSize(stage)
	local missing: { Item } = {}
	for _, section in sections do
		if cancelled then
			break
		end
		currentSection = section.name
		step(0)
		local waitSounds = startSounds(stage, section.sounds)
		for _, item in showImages(stage, section.images, screen, BATCH_TIMEOUT, step) do
			table.insert(missing, item)
		end
		local soundsMissing = waitSounds()
		step(#section.sounds)
		for _, item in soundsMissing do
			table.insert(missing, item)
		end
	end

	-- Zweiter Versuch für alles, was nicht geladen hat
	local failedNames: { string } = {}
	if #missing > 0 and not cancelled then
		currentSection = "Nachzügler"
		local images: { Item } = {}
		local sounds: { Item } = {}
		for _, item in missing do
			table.insert(if string.sub(item.name, 1, 6) == "sound_" or item.name == "menu_theme" then sounds else images, item)
		end
		local waitSounds = startSounds(stage, sounds)
		for _, item in showImages(stage, images, screen, RETRY_TIMEOUT, function() end) do
			table.insert(failedNames, `{item.name} ({item.content})`)
		end
		for _, item in waitSounds() do
			table.insert(failedNames, `{item.name} ({item.content})`)
		end
	end
	if stage.Parent then
		stage:Destroy()
	end
	currentStage = nil
	if cancelled then
		return failedNames -- übersprungen: der Rest lädt im Spiel nach
	end

	if RunService:IsStudio() then
		print(`[ClayBattle] Vorgeladen: {total - #failedNames}/{total} in {string.format("%.1f", os.clock() - started)} s`)
		if #failedNames > 0 then
			warn(
				`[ClayBattle] Nicht geladen ({#failedNames}): {table.concat(failedNames, ", ")}\n`
					.. "Meist ist das eine Decal-ID statt einer Image-ID (umwandeln mit tools/ConvertArenaDecals.luau) "
					.. "oder das Bild ist noch nicht freigegeben bzw. gehört einem anderen Konto."
			)
		end
	end
	return failedNames
end

return AssetPreloader
