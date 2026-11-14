--!strict
-- Bots: computergesteuerte Knetköpfe. Sie bewegen sich mit derselben Physik wie Spieler (HeadMotor)
-- und benutzen dieselben Fähigkeiten. Der Server steuert sie.
-- Wie gut sie sind, bestimmt die Schwierigkeit (Constants.BOT_DIFFICULTIES, im Startmenü einstellbar).
--
-- Verhalten (alle "think" Sekunden neu entschieden, in dieser Reihenfolge):
--   1. Abwehr: Granate in Schwertreichweite -> zurückschlagen (ab "Schwer")
--   2. Ausweichen: Granate, Rakete oder Schwertkämpfer kommt -> wegspringen oder wegdashen
--   3. Rettung: unter die Arena gefallen -> Dash zur nächsten Plattform
--   4. Angriff: Schwert, Rakete (lenkt und zündet neben dem Gegner), vorausberechnete Granate, Thruster
--   5. Bewegung: Abstand passend zur Ausrüstung (Schwert: ran, Granate: Abstand), springen, klettern

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local HeadMotor = require(ReplicatedStorage.Shared.HeadMotor)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

type Participant = Player | string

type Grenade = { id: string, owner: Participant, position: Vector3, velocity: Vector3, explodeAt: number }
type MissileInfo = { id: string, owner: Participant, position: Vector3, direction: Vector3 }

export type Context = {
	getHead: (Participant) -> Model?,
	getHeads: () -> { [Participant]: Model },
	getPhase: () -> string,
	setBotName: (string, string) -> (),
	onAdded: (string) -> (),
	onRemoved: (string) -> (),
	throwGrenade: (Participant, Vector3, number, string, Vector3?) -> boolean,
	grenadeReady: (Participant) -> boolean,
	activeGrenades: () -> { Grenade },
	activeMissiles: () -> { MissileInfo },
	placeThruster: (Participant, Model, Vector3, Vector3, string) -> boolean,
	thrusterReady: (Participant) -> boolean,
	swingSword: (Participant, Vector3) -> boolean,
	swordReady: (Participant) -> boolean,
	fireMissile: (Participant, Vector3, string) -> boolean,
	missileReady: (Participant) -> boolean,
	missileActive: (Participant) -> boolean,
	setLoadout: (Participant, { string }) -> (),
}

type Bot = {
	id: string,
	head: Model?,
	motor: HeadMotor.Motor?,
	input: Vector3,
	nextThink: number,
	nextJump: number,
	dashReadyAt: number,
	wanderDirection: number,
	actionCounter: number,
	nextPlanAt: number,
	rescueDecision: boolean?,
	threats: { [string]: boolean },
	threatCount: number,
}

local BotController = {}

local R = Constants.HEAD_RADIUS
local random = Random.new()
local context: Context
local bots: { Bot } = {}
local nextBotNumber = 1
local difficulty = Constants.BOT_DEFAULT_DIFFICULTY

function BotController.setDifficulty(level: number)
	difficulty = math.clamp(math.floor(level), 1, #Constants.BOT_DIFFICULTIES)
end

function BotController.getDifficulty(): number
	return difficulty
end

---------------------------------------------------------------------------------------------------
-- Hinzufügen / Entfernen
---------------------------------------------------------------------------------------------------

function BotController.list(): { string }
	local ids = {}
	for _, bot in bots do
		table.insert(ids, bot.id)
	end
	return ids
end

function BotController.add(): string?
	local id = `Bot{nextBotNumber}`
	nextBotNumber += 1
	local names = Constants.BOT_NAMES
	context.setBotName(id, names[((nextBotNumber - 2) % #names) + 1])

	-- Zufällige Ausrüstung: 3 verschiedene Fähigkeiten
	local pool = table.clone(Abilities.ORDER)
	local loadout = {}
	for _ = 1, math.min(Abilities.MAX_SLOTS, #pool) do
		table.insert(loadout, table.remove(pool, random:NextInteger(1, #pool)))
	end
	context.setLoadout(id, loadout)
	table.insert(bots, {
		id = id,
		head = nil,
		motor = nil,
		input = Vector3.zero,
		nextThink = 0,
		nextJump = 0,
		dashReadyAt = 0,
		wanderDirection = 1,
		actionCounter = 0,
		nextPlanAt = 0,
		rescueDecision = nil,
		threats = {},
		threatCount = 0,
	})
	context.onAdded(id)
	return id
end

function BotController.removeLast()
	local bot = table.remove(bots)
	if bot then
		context.onRemoved(bot.id)
	end
end

---------------------------------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, v.Y, 0)
end

local function nextId(bot: Bot): string
	bot.actionCounter += 1
	return tostring(bot.actionCounter)
end

-- Nächster Gegner (mit Geschwindigkeit, damit Bots vorhalten können)
local function findTarget(bot: Bot, position: Vector3): { participant: Participant, position: Vector3, velocity: Vector3, head: Model }?
	local best = nil
	local bestDistance = math.huge
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		if participant ~= bot.id and body then
			local distance = flat(body.Position - position).Magnitude
			if distance < bestDistance then
				best = { participant = participant, position = body.Position, velocity = body.AssemblyLinearVelocity, head = head }
				bestDistance = distance
			end
		end
	end
	return best
end

-- Nächster Punkt auf irgendeiner Plattform (für die Rettung beim Fallen)
local function nearestPlatformPoint(shapes: { PlatformShapes.Shape }, position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, shape in shapes do
		local frame = PlatformShapes.frame(shape)
		local _, closest = PlatformShapes.closest(shape.halfLength, frame:PointToObjectSpace(position))
		local point = frame:PointToWorldSpace(closest)
		local distance = (point - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = point, distance
		end
	end
	return best
end

local function lowestPlatformY(shapes: { PlatformShapes.Shape }): number
	local lowest = math.huge
	for _, shape in shapes do
		lowest = math.min(lowest, PlatformShapes.frame(shape).Position.Y - shape.radius)
	end
	return lowest
end

-- Granatenwurf planen: viele Richtungen und Stärken durchrechnen, die nächste Explosion am Ziel nehmen.
-- Würfe, die den Bot selbst treffen würden, werden verworfen.
local function planThrow(from: Vector3, aimPoint: Vector3, shapes: { PlatformShapes.Shape }, fine: boolean): (Vector3?, number, number)
	local bestDirection: Vector3? = nil
	local bestCharge = 1
	local bestError = math.huge
	local dt = 1 / 15
	local selfSafe = Constants.GRENADE_BLAST_RADIUS + R + 1.5

	local angleStep = if fine then 12 else 20
	local charges = if fine then { 0.2, 0.4, 0.6, 0.8, 1 } else { 0.3, 0.65, 1 }
	for angle = 0, 359, angleStep do
		local direction = Vector3.new(math.cos(math.rad(angle)), math.sin(math.rad(angle)), 0)
		for _, charge in charges do
			local p, v = GrenadePhysics.launch(from, direction, charge)
			local t = 0
			while t < Constants.GRENADE_FUSE do
				p, v = GrenadePhysics.step(p, v, dt, shapes)
				t += dt
			end
			local errorDistance = flat(p - aimPoint).Magnitude
			if errorDistance < bestError and flat(p - from).Magnitude > selfSafe then
				bestDirection, bestCharge, bestError = direction, charge, errorDistance
			end
		end
	end
	return bestDirection, bestCharge, bestError
end

local function dashReady(bot: Bot, now: number): boolean
	local head = bot.head
	local equipped = head and table.find(Abilities.parseLoadout(head:GetAttribute("Loadout")), "Dash")
	return equipped ~= nil and now >= bot.dashReadyAt
end

local function dash(bot: Bot, motor: HeadMotor.Motor, now: number, direction: Vector3)
	bot.dashReadyAt = now + Constants.DASH_COOLDOWN
	HeadMotor.startDash(motor, now, direction)
	local head = bot.head
	if head then
		head:SetAttribute(Abilities.readyAttribute("Dash"), Workspace:GetServerTimeNow() + Constants.DASH_COOLDOWN)
	end
end

local function jump(bot: Bot, motor: HeadMotor.Motor, now: number)
	motor.jumpPressedAt = now
	bot.nextJump = now + random:NextNumber(0.6, 1.4)
end

---------------------------------------------------------------------------------------------------
-- Entscheiden
---------------------------------------------------------------------------------------------------

local function profile(): typeof(Constants.BOT_DIFFICULTIES[1])
	return Constants.BOT_DIFFICULTIES[difficulty] or Constants.BOT_DIFFICULTIES[Constants.BOT_DEFAULT_DIFFICULTY]
end

-- Einmal pro Gefahr würfeln, ob der Bot sie bemerkt (sonst würde er bei jeder Entscheidung neu würfeln)
local function notices(bot: Bot, key: string, chance: number): boolean
	local decision = bot.threats[key]
	if decision == nil then
		decision = random:NextNumber() < chance
		bot.threats[key] = decision
		bot.threatCount += 1
		if bot.threatCount > 60 then
			table.clear(bot.threats)
			bot.threatCount = 0
		end
	end
	return decision :: boolean
end

local function equippedOf(head: Model?): { string }
	return if head then Abilities.parseLoadout(head:GetAttribute("Loadout")) else {}
end

local function readyAttribute(head: Model, id: string): boolean
	local readyAt = head:GetAttribute(Abilities.readyAttribute(id))
	return typeof(readyAt) ~= "number" or readyAt <= Workspace:GetServerTimeNow()
end

-- Weg von einer Gefahr: springen (an Wand/Decke löst das) und/oder dashen
local function evade(bot: Bot, motor: HeadMotor.Motor, now: number, away: Vector3, normal: Vector3?)
	local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.yAxis
	bot.input = Vector3.new(if math.abs(direction.X) > 0.2 then math.sign(direction.X) else bot.wanderDirection, 0, 0)
	if dashReady(bot, now) then
		dash(bot, motor, now, (direction + Vector3.new(0, 0.35, 0)).Unit)
	elseif normal then
		jump(bot, motor, now)
	end
end

local function think(bot: Bot, motor: HeadMotor.Motor, now: number, shapes: { PlatformShapes.Shape })
	local level = profile()
	local position = motor.position
	local normal = HeadMotor.attachedNormal(motor)
	local serverNow = Workspace:GetServerTimeNow()
	local head = bot.head
	local equipped = equippedOf(head)
	local hasSword = table.find(equipped, "Sword") ~= nil
	local swordReady = hasSword and context.swordReady(bot.id)

	-- 1. Abwehr: Granate mit dem Schwert zurückschlagen
	if level.deflect and swordReady then
		for _, grenade in context.activeGrenades() do
			local soon = grenade.position + grenade.velocity * 0.08
			local offset = flat(soon - position)
			if grenade.owner ~= bot.id and offset.Magnitude < Constants.SWORD_RANGE + R - 0.5 then
				context.swingSword(bot.id, offset)
				swordReady = false
				break
			end
		end
	end

	-- 2. Ausweichen
	for _, grenade in context.activeGrenades() do
		local away = flat(position - grenade.position)
		local distance = away.Magnitude
		local timeLeft = grenade.explodeAt - serverNow
		-- Fliegt sie auf mich zu? Dann zählt die Zeit bis zum Aufprall
		local approach = if distance > 0.01 then grenade.velocity:Dot(-away.Unit) else 0
		if approach > 1 then
			timeLeft = math.min(timeLeft, (distance - R) / approach)
		end
		local danger = distance < Constants.GRENADE_BLAST_RADIUS + R + 3 or (approach > 1 and distance < 25)
		if danger and timeLeft < level.dodgeTime and notices(bot, `g{grenade.id}`, level.dodgeChance) then
			-- Bei fliegenden Granaten seitlich aus der Flugbahn, sonst einfach weg
			if approach > 1 and distance > Constants.GRENADE_BLAST_RADIUS then
				local v = flat(grenade.velocity).Unit
				local side = Vector3.new(-v.Y, v.X, 0)
				away = if side:Dot(away) >= 0 then side else -side
			end
			evade(bot, motor, now, away, normal)
			return
		end
	end
	for _, missile in context.activeMissiles() do
		if missile.owner ~= bot.id then
			local relative = flat(position - missile.position)
			local along = relative:Dot(missile.direction)
			local miss = (relative - missile.direction * along).Magnitude
			local timeToHit = along / Constants.MISSILE_SPEED
			if along > -2 and miss < Constants.MISSILE_BLAST_RADIUS + R and timeToHit < level.dodgeTime * 1.3 then
				if notices(bot, `m{missile.id}`, level.dodgeChance) then
					local side = Vector3.new(-missile.direction.Y, missile.direction.X, 0)
					evade(bot, motor, now, if side:Dot(relative) >= 0 then side else -side, normal)
					return
				end
			end
		end
	end

	-- 3. Rettung beim Fallen (einmal pro Sturz entscheiden)
	if normal then
		bot.rescueDecision = nil
	end
	if not normal and motor.velocity.Y < 0 and position.Y < lowestPlatformY(shapes) - 3 then
		if bot.rescueDecision == nil then
			bot.rescueDecision = random:NextNumber() < level.rescueChance
		end
		local point = nearestPlatformPoint(shapes, position)
		if point and bot.rescueDecision and dashReady(bot, now) then
			dash(bot, motor, now, flat(point - position))
		end
		bot.input = if point then Vector3.new(math.sign(point.X - position.X), 0, 0) else Vector3.zero
		return
	end

	local target = findTarget(bot, position)
	if not target then
		-- Niemand da: herumschlendern
		if random:NextNumber() < 0.05 then
			bot.wanderDirection = -bot.wanderDirection
		end
		bot.input = Vector3.new(bot.wanderDirection, 0, 0)
		return
	end

	local toTarget = flat(target.position - position)
	local distance = toTarget.Magnitude
	local targetEquipped = equippedOf(target.head)
	local targetSwordReady = table.find(targetEquipped, "Sword") ~= nil and readyAttribute(target.head, "Sword")

	-- Schwertkämpfer in der Nähe meiden (ab "Schwer"), außer man schlägt selbst zuerst
	if
		level.combo
		and targetSwordReady
		and not swordReady
		and distance < Constants.SWORD_RANGE + R + 1.5
		and notices(bot, `s{tostring(target.participant)}{math.floor(serverNow)}`, level.dodgeChance)
	then
		evade(bot, motor, now, -toTarget, normal)
		return
	end

	-- 4a. Schwert: Gegner (vorausberechnet) in Reichweite -> zuschlagen
	local soon = flat(target.position + target.velocity * 0.12 * level.lead - position)
	if swordReady and soon.Magnitude < Constants.SWORD_RANGE + R and random:NextNumber() < level.swordChance then
		context.swingSword(bot.id, soon)
		swordReady = false
	end
	-- Dash + Schwert: heranschießen, der Hieb folgt bei der nächsten Entscheidung
	if
		level.combo
		and swordReady
		and dashReady(bot, now)
		and distance > Constants.SWORD_RANGE + R
		and distance < 13
		and random:NextNumber() < 0.5
	then
		dash(bot, motor, now, soon)
	end

	-- 4b. Lenkrakete: abfeuern (lenkt dann selbst) und neben dem Gegner zünden
	if table.find(equipped, "Missile") then
		local own: MissileInfo? = nil
		for _, missile in context.activeMissiles() do
			if missile.owner == bot.id then
				own = missile
			end
		end
		if own then
			if level.combo and flat(own.position - position).Magnitude > Constants.MISSILE_BLAST_RADIUS + R + 1 then
				for participant, otherHead in context.getHeads() do
					local body = otherHead.PrimaryPart
					if
						participant ~= bot.id
						and body
						and flat(body.Position - own.position).Magnitude < Constants.MISSILE_BLAST_RADIUS * 0.85
					then
						context.fireMissile(bot.id, toTarget, nextId(bot)) -- zündet
						break
					end
				end
			end
		elseif context.missileReady(bot.id) and distance > 8 and distance < 50 and random:NextNumber() < level.missileChance then
			context.fireMissile(bot.id, toTarget, nextId(bot))
		end
	end

	-- 4c. Granate werfen (Ziel vorausberechnet; nach einem verworfenen Plan kurz warten)
	if
		table.find(equipped, "Grenade")
		and context.grenadeReady(bot.id)
		and now >= bot.nextPlanAt
		and distance > 6
		and distance < 40
		and random:NextNumber() < level.throwChance
	then
		local aimError = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0) * level.aimError
		local lead = flat(target.velocity) * 0.5 * level.lead
		local direction, charge, errorDistance = planThrow(position, target.position + lead + aimError, shapes, level.lead >= 0.85)
		if direction and errorDistance < Constants.GRENADE_BLAST_RADIUS * 0.8 then
			context.throwGrenade(bot.id, direction, charge, nextId(bot))
		else
			bot.nextPlanAt = now + 0.3
		end
	end

	-- 4d. Thruster: vor allem, wenn der Gegner auf derselben Plattform steht
	local shape = motor.attachedShape
	if shape and normal and table.find(equipped, "Thruster") and context.thrusterReady(bot.id) then
		local frame = PlatformShapes.frame(shape)
		local targetDistance = PlatformShapes.closest(shape.halfLength, frame:PointToObjectSpace(target.position))
		local sharedPlatform = targetDistance < shape.radius + R + 0.6
		local chance = if sharedPlatform then level.thrusterChance * 4 else level.thrusterChance
		if distance < 20 and random:NextNumber() < chance then
			local contact = position - normal * R
			context.placeThruster(
				bot.id,
				shape.model,
				frame:PointToObjectSpace(contact),
				frame:VectorToObjectSpace(normal),
				nextId(bot)
			)
		end
	end

	-- 5. Bewegung: Wunschabstand je nach Ausrüstung
	local wanted = 10 -- Granate / Rakete: Abstand halten
	if hasSword and (swordReady or not table.find(equipped, "Grenade")) then
		wanted = 2.5 -- Schwert: ran
	elseif not table.find(equipped, "Grenade") and not table.find(equipped, "Missile") then
		wanted = 5
	end
	if level.combo and targetSwordReady and not swordReady then
		wanted = math.max(wanted, Constants.SWORD_RANGE + R + 3)
	end

	local horizontal = math.sign(toTarget.X)
	if distance < wanted - 2 then
		horizontal = -horizontal
	elseif distance < wanted + 3 and random:NextNumber() < 0.3 then
		horizontal = 0
	end

	if normal then
		if normal.Y > 0.5 then
			-- Oben auf einer Plattform
			bot.input = Vector3.new(horizontal, 0, 0)
			local targetAbove = toTarget.Y > 5 and math.abs(toTarget.X) < 20
			if (targetAbove or random:NextNumber() < 0.04) and now >= bot.nextJump then
				jump(bot, motor, now)
			end
			-- Weit oben: Dash hinauf
			if toTarget.Y > 12 and dashReady(bot, now) and random:NextNumber() < 0.2 then
				dash(bot, motor, now, toTarget)
			end
		elseif normal.Y < -0.5 then
			-- Unter einer Plattform: weiterlaufen oder fallen lassen
			bot.input = Vector3.new(horizontal, 0, 0)
			if (toTarget.Y < -3 or random:NextNumber() < 0.08) and now >= bot.nextJump then
				jump(bot, motor, now)
			end
		else
			-- An einer Wand: zum Ziel hoch oder runter klettern
			bot.input = Vector3.new(0, if toTarget.Y >= 0 then 1 else -1, 0)
			if random:NextNumber() < 0.08 and now >= bot.nextJump then
				jump(bot, motor, now)
			end
		end
	else
		-- In der Luft: Richtung Ziel lenken (bzw. weg, wenn zu nah)
		bot.input = Vector3.new(horizontal ~= 0 and horizontal or math.sign(toTarget.X), 0, 0)
	end
end

---------------------------------------------------------------------------------------------------
-- Jeder Frame
---------------------------------------------------------------------------------------------------

function BotController.init(botContext: Context)
	context = botContext
end

function BotController.step(dt: number)
	if #bots == 0 then
		return
	end
	local now = os.clock()
	local frozen = context.getPhase() == "Countdown"
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))

	for _, bot in bots do
		local head = context.getHead(bot.id)
		local body = head and head.PrimaryPart
		if not head or not body then
			bot.head, bot.motor = nil, nil
			continue
		end
		if bot.head ~= head or not bot.motor then
			-- Neu erschienen
			bot.head = head
			bot.motor = HeadMotor.new(body.Position)
			local facing = head:GetAttribute("Facing")
			if typeof(facing) == "number" then
				(bot.motor :: HeadMotor.Motor).facing = facing
			end
			bot.dashReadyAt = 0
			bot.nextThink = now + random:NextNumber(0.2, 0.5) -- nicht alle Bots gleichzeitig
		end
		local motor = bot.motor :: HeadMotor.Motor
		motor.speedScale = profile().speed

		if frozen then
			bot.input = Vector3.zero
			motor.jumpPressedAt = -math.huge
		elseif now >= bot.nextThink then
			bot.nextThink = now + profile().think * random:NextNumber(0.8, 1.2)
			think(bot, motor, now, shapes)
		end

		local others = {}
		for participant, otherHead in context.getHeads() do
			local otherBody = otherHead.PrimaryPart
			if participant ~= bot.id and otherBody then
				table.insert(others, otherBody.Position)
			end
		end
		HeadMotor.update(motor, dt, now, bot.input, shapes, others)
		body.CFrame = CFrame.new(motor.position)
		body.AssemblyLinearVelocity = motor.velocity
		body.AssemblyAngularVelocity = Vector3.zero
	end
end

return BotController
