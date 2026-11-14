--!strict
-- Soundeffekte abspielen. Alle laufen über die SoundGroup "SFX" (Lautstärke in den Optionen).
--   SoundFX.play("jump")                    normal
--   SoundFX.play("land", 0.5)               leiser (z. B. für andere Figuren)
-- Jeder Aufruf spielt eine eigene Kopie (Klänge können sich überlagern), mit leicht zufälliger
-- Tonhöhe, damit oft gehörte Klänge nicht eintönig wirken. Ohne Audio-ID passiert nichts.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SoundIds = require(ReplicatedStorage.Shared.SoundIds)

local SoundFX = {}

-- Grundlautstärke und Tonhöhen-Streuung je Klang
local SETTINGS: { [string]: { volume: number, variance: number } } = {
	ui_click = { volume = 0.6, variance = 0.05 },
	ui_hover = { volume = 0.25, variance = 0.08 },
	jump = { volume = 0.5, variance = 0.08 },
	double_jump = { volume = 0.5, variance = 0.06 },
	land = { volume = 0.45, variance = 0.1 },
	dash = { volume = 0.55, variance = 0.06 },
	respawn_pop = { volume = 0.5, variance = 0.08 },
	eliminate = { volume = 0.7, variance = 0.06 },
	thruster = { volume = 0.55, variance = 0.05 },
	grenade_throw = { volume = 0.5, variance = 0.08 },
	explosion = { volume = 0.8, variance = 0.08 },
	sword = { volume = 0.6, variance = 0.08 },
	missile_launch = { volume = 0.6, variance = 0.05 },
	countdown_tick = { volume = 0.6, variance = 0 },
	countdown_go = { volume = 0.7, variance = 0 },
	map_tick = { volume = 0.35, variance = 0.05 },
	map_select = { volume = 0.6, variance = 0 },
	round_win = { volume = 0.7, variance = 0 },
}

local MIN_GAP = 0.04 -- derselbe Klang höchstens so oft (verhindert Knattern)

local folder: Folder? = nil
local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local random = Random.new()

local function soundGroup(): SoundGroup
	local group = SoundService:FindFirstChild("SFX")
	if group and group:IsA("SoundGroup") then
		return group
	end
	local newGroup = Instance.new("SoundGroup")
	newGroup.Name = "SFX"
	newGroup.Parent = SoundService
	return newGroup
end

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "ClayBattleSFX"
	newFolder.Parent = SoundService
	folder = newFolder
	return newFolder
end

local function template(name: string): Sound?
	local existing = templates[name]
	if existing then
		return existing
	end
	local id = SoundIds[name]
	if not id or id == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = `rbxassetid://{id}`
	sound.SoundGroup = soundGroup()
	sound.Parent = getFolder()
	templates[name] = sound
	return sound
end

function SoundFX.play(name: string, volumeScale: number?)
	local base = template(name)
	if not base then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < MIN_GAP then
		return
	end
	lastPlayed[name] = now
	local settings = SETTINGS[name] or { volume = 0.5, variance = 0 }
	local sound = base:Clone()
	sound.Volume = settings.volume * (volumeScale or 1)
	sound.PlaybackSpeed = 1 + random:NextNumber(-settings.variance, settings.variance)
	sound.Parent = getFolder()
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- Raketen hören, sobald sie auftauchen (eigene und fremde)
function SoundFX.start()
	for name in SoundIds do
		template(name) -- Vorlagen anlegen, damit die Klänge vorladen
	end
	local missiles = Workspace:WaitForChild(Constants.MISSILES_FOLDER, 30)
	if missiles then
		missiles.ChildAdded:Connect(function()
			SoundFX.play("missile_launch")
		end)
	end
end

return SoundFX
