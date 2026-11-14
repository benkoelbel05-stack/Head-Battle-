--!strict
-- Rundensystem.
--   Waiting    weniger als MIN_PARTICIPANTS Teilnehmer: frei spielen, nach dem Ausscheiden Respawn
--   Countdown  alle erscheinen an ihren Startplätzen und stehen still (COUNTDOWN_TIME Sekunden)
--   Playing    ein Treffer reicht: wer ausscheidet, ist bis zum Rundenende raus
--   RoundEnd   der letzte Überlebende bekommt einen Punkt
--   MatchEnd   wer zuerst WIN_POINTS Punkte hat, gewinnt das Match; danach geht es von vorne los
--
-- Der Zustand liegt für alle Clients sichtbar in ReplicatedStorage.RoundState:
--   Attribute: Phase, Message, EndsAt (Serverzeit), Round, WinPoints
--   Scores/<Schlüssel> (IntValue): Punkte, mit Attributen DisplayName, Color, Alive, IsBot

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

type Participant = Player | string

export type Context = {
	spawn: (Participant) -> (),
	despawn: (Participant) -> (),
	keyOf: (Participant) -> string,
	displayName: (Participant) -> string,
	getColor: (Participant) -> Color3,
	isBot: (Participant) -> boolean,
	getBots: () -> { string },
	resetArena: () -> (), -- Plattformen, Granaten, Thruster und Abklingzeiten zurücksetzen
}

local RoundManager = {}

local context: Context
local stateFolder: Folder
local scoresFolder: Folder

local phase = "Waiting"
local round = 0
local alive: { [Participant]: boolean } = {}
local scores: { [Participant]: number } = {}

---------------------------------------------------------------------------------------------------
-- Zustand für die Clients
---------------------------------------------------------------------------------------------------

local function setPhase(newPhase: string, message: string, duration: number?)
	phase = newPhase
	stateFolder:SetAttribute("Phase", newPhase)
	stateFolder:SetAttribute("Message", message)
	stateFolder:SetAttribute("EndsAt", if duration then Workspace:GetServerTimeNow() + duration else 0)
	stateFolder:SetAttribute("Round", round)
end

local function participants(): { Participant }
	local list: { Participant } = {}
	for _, player in Players:GetPlayers() do
		-- Spieler im Startmenü spielen noch nicht mit
		if player:GetAttribute("InGame") == true then
			table.insert(list, player)
		end
	end
	for _, botId in context.getBots() do
		table.insert(list, botId)
	end
	return list
end

-- Punkte-Anzeige aktualisieren
local function updateScoreboard()
	local current: { [string]: boolean } = {}
	for _, participant in participants() do
		local key = context.keyOf(participant)
		current[key] = true
		local value = scoresFolder:FindFirstChild(key) :: IntValue?
		if not value then
			local newValue = Instance.new("IntValue")
			newValue.Name = key
			newValue.Parent = scoresFolder
			value = newValue
		end
		local scoreValue = value :: IntValue
		scoreValue.Value = scores[participant] or 0
		scoreValue:SetAttribute("DisplayName", context.displayName(participant))
		scoreValue:SetAttribute("Color", context.getColor(participant))
		scoreValue:SetAttribute("IsBot", context.isBot(participant))
		scoreValue:SetAttribute("Alive", phase ~= "Playing" and phase ~= "Countdown" or alive[participant] == true)
	end
	for _, child in scoresFolder:GetChildren() do
		if not current[child.Name] then
			child:Destroy()
		end
	end
end

local function aliveList(): { Participant }
	local list: { Participant } = {}
	for participant, isAlive in alive do
		if isAlive then
			table.insert(list, participant)
		end
	end
	return list
end

---------------------------------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------------------------------

-- Ein Kopf ist ausgeschieden (HeadSpawner meldet das)
function RoundManager.onEliminated(participant: Participant)
	if phase == "Playing" or phase == "Countdown" then
		alive[participant] = false
		updateScoreboard()
	elseif phase == "Waiting" then
		-- Freies Spiel: kurz danach wieder erscheinen
		task.delay(Constants.RESPAWN_DELAY, function()
			if phase == "Waiting" and table.find(participants(), participant) then
				context.spawn(participant)
			end
		end)
	end
end

-- Neuer Teilnehmer (Spieler kommt, Bot wird hinzugefügt)
function RoundManager.addParticipant(participant: Participant)
	scores[participant] = scores[participant] or 0
	if phase == "Waiting" then
		context.spawn(participant)
	end
	-- Während einer Runde: zuschauen bis zur nächsten Runde
	updateScoreboard()
end

function RoundManager.removeParticipant(participant: Participant)
	alive[participant] = nil
	scores[participant] = nil
	context.despawn(participant)
	updateScoreboard()
end

function RoundManager.getPhase(): string
	return phase
end

---------------------------------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------------------------------

-- Um Punkte wird erst gespielt, wenn mindestens ein echter Spieler eingestiegen ist
-- (Bots spielen nicht allein, solange alle noch im Menü sind)
local function enoughParticipants(): boolean
	local list = participants()
	if #list < Constants.MIN_PARTICIPANTS then
		return false
	end
	for _, participant in list do
		if typeof(participant) ~= "string" then
			return true
		end
	end
	return false
end

function RoundManager.enoughParticipants(): boolean
	return enoughParticipants()
end

-- Freies Spiel, bis genug Teilnehmer da sind
local function waitForParticipants()
	if enoughParticipants() then
		return
	end
	setPhase("Waiting", "Warte auf Mitspieler – füge einen Bot hinzu!")
	table.clear(alive)
	for _, participant in participants() do
		context.spawn(participant)
	end
	updateScoreboard()
	repeat
		task.wait(0.1)
	until enoughParticipants()
end

-- Eine Runde spielen. Gibt den Sieger zurück (nil = unentschieden oder abgebrochen).
local function playRound(): Participant?
	round += 1
	context.resetArena()
	table.clear(alive)
	for _, participant in participants() do
		context.despawn(participant)
	end
	for _, participant in participants() do
		alive[participant] = true
		context.spawn(participant)
	end

	-- Jede Runde ein anderer Hintergrund (Tag, Sonnenuntergang, Nacht)
	local backgrounds = { "day", "sunset", "night" }
	local current = stateFolder:GetAttribute("Background")
	local options = {}
	for _, key in backgrounds do
		if key ~= current then
			table.insert(options, key)
		end
	end
	stateFolder:SetAttribute("Background", options[math.random(1, #options)])

	setPhase("Countdown", `Runde {round}`, Constants.COUNTDOWN_TIME)
	updateScoreboard()
	task.wait(Constants.COUNTDOWN_TIME)

	setPhase("Playing", "")
	updateScoreboard()
	repeat
		task.wait(0.1)
	until #aliveList() <= 1 or not enoughParticipants()

	local survivors = aliveList()
	return if #survivors == 1 then survivors[1] else nil
end

local function runMatch()
	table.clear(scores)
	for _, participant in participants() do
		scores[participant] = 0
	end
	round = 0
	stateFolder:SetAttribute("WinPoints", Constants.WIN_POINTS)

	while enoughParticipants() do
		local winner = playRound()
		if not enoughParticipants() then
			return
		end

		if winner then
			scores[winner] = (scores[winner] or 0) + 1
			setPhase("RoundEnd", `{context.displayName(winner)} gewinnt die Runde!`, Constants.ROUND_END_TIME)
		else
			setPhase("RoundEnd", "Unentschieden!", Constants.ROUND_END_TIME)
		end
		updateScoreboard()
		task.wait(Constants.ROUND_END_TIME)

		if winner and (scores[winner] or 0) >= Constants.WIN_POINTS then
			setPhase("MatchEnd", `{context.displayName(winner)} gewinnt das Match!`, Constants.MATCH_END_TIME)
			updateScoreboard()
			task.wait(Constants.MATCH_END_TIME)
			return
		end
	end
end

function RoundManager.init(roundContext: Context)
	context = roundContext

	stateFolder = Instance.new("Folder")
	stateFolder.Name = Constants.ROUND_STATE
	scoresFolder = Instance.new("Folder")
	scoresFolder.Name = "Scores"
	scoresFolder.Parent = stateFolder
	stateFolder.Parent = ReplicatedStorage
	stateFolder:SetAttribute("Background", "day")
	setPhase("Waiting", "")

	task.spawn(function()
		while true do
			waitForParticipants()
			runMatch()
		end
	end)
end

return RoundManager
