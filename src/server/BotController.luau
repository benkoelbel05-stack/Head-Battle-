--!strict
-- Bots: computergesteuerte Knetköpfe. Sie bewegen sich mit derselben Physik wie Spieler (HeadMotor)
-- und benutzen dieselben Fähigkeiten (Dash, Thruster, Granate). Der Server steuert sie.
--
-- Verhalten (alle BOT_THINK_INTERVAL Sekunden neu entschieden, in dieser Reihenfolge):
--   1. Ausweichen: Granate in der Nähe kurz vor der Explosion -> wegspringen oder wegdashen
--   2. Rettung: unter die Arena gefallen -> Dash zur nächsten Plattform
--   3. Angriff: Granate werfen; die beste Richtung und Stärke wird vorher durchgerechnet
--   4. Chaos: ab und zu ein Thruster unter sich
--   5. Bewegung: zum nächsten Gegner, Granaten-Abstand halten, springen und klettern

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local HeadMotor = require(ReplicatedStorage.Shared.HeadMotor)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)

type Participant = Player | string

type Grenade = { position: Vector3, explodeAt: number }

export type Context = {
	getHead: (Participant) -> Model?,
	getHeads: () -> { [Participant]: Model },
	getPhase: () -> string,
	setBotName: (string, string) -> (),
	onAdded: (string) -> (),
	onRemoved: (string) -> (),
	throwGrenade: (Participant, Vector3, number, string) -> boolean,
	grenadeReady: (Participant) -> boolean,
	activeGrenades: () -> { Grenade },
	placeThruster: (Participant, Model, Vector3, Vector3, string) -> boolean,
	thrusterReady: (Participant) -> boolean,
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
}

local BotController = {}

local R = Constants.HEAD_RADIUS
local random = Random.new()
local context: Context
local bots: { Bot } = {}
local nextBotNumber = 1

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

-- Nächster Gegner (Position)
local function findTarget(bot: Bot, position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for participant, head in context.getHeads() do
		local body = head.PrimaryPart
		if participant ~= bot.id and body then
			local distance = flat(body.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = body.Position, distance
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
local function planThrow(from: Vector3, aimPoint: Vector3, shapes: { PlatformShapes.Shape }): (Vector3?, number, number)
	local bestDirection: Vector3? = nil
	local bestCharge = 1
	local bestError = math.huge
	local dt = 1 / 15
	local selfSafe = Constants.GRENADE_BLAST_RADIUS + R + 1.5

	for angle = 0, 340, 20 do
		local direction = Vector3.new(math.cos(math.rad(angle)), math.sin(math.rad(angle)), 0)
		for _, charge in { 0.3, 0.65, 1 } do
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
	return now >= bot.dashReadyAt
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

local function think(bot: Bot, motor: HeadMotor.Motor, now: number, shapes: { PlatformShapes.Shape })
	local position = motor.position
	local normal = HeadMotor.attachedNormal(motor)
	local serverNow = Workspace:GetServerTimeNow()

	-- 1. Ausweichen
	for _, grenade in context.activeGrenades() do
		local away = flat(position - grenade.position)
		local timeLeft = grenade.explodeAt - serverNow
		if away.Magnitude < Constants.GRENADE_BLAST_RADIUS + R + 3 and timeLeft < 0.9 then
			local fleeDirection = if away.Magnitude > 0.01 then away.Unit else Vector3.yAxis
			bot.input = Vector3.new(math.sign(fleeDirection.X), 0, 0)
			if dashReady(bot, now) then
				dash(bot, motor, now, (fleeDirection + Vector3.new(0, 0.4, 0)).Unit)
			elseif normal then
				jump(bot, motor, now)
			end
			return
		end
	end

	-- 2. Rettung beim Fallen
	if not normal and motor.velocity.Y < 0 and position.Y < lowestPlatformY(shapes) - 3 then
		local point = nearestPlatformPoint(shapes, position)
		if point and dashReady(bot, now) then
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

	local toTarget = flat(target - position)
	local distance = toTarget.Magnitude

	-- 3. Granate werfen
	if context.grenadeReady(bot.id) and distance > 6 and distance < 40 and random:NextNumber() < Constants.BOT_THROW_CHANCE then
		local aimError = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0) * Constants.BOT_AIM_ERROR
		local direction, charge, errorDistance = planThrow(position, target + aimError, shapes)
		if direction and errorDistance < Constants.GRENADE_BLAST_RADIUS * 0.8 then
			context.throwGrenade(bot.id, direction, charge, nextId(bot))
		end
	end

	-- 4. Thruster unter sich (Chaos auf der eigenen Plattform, wenn der Gegner in der Nähe ist)
	local shape = motor.attachedShape
	if shape and normal and context.thrusterReady(bot.id) and distance < 18 and random:NextNumber() < 0.06 then
		local root = shape.model.PrimaryPart
		if root then
			local frame = PlatformShapes.frame(shape)
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

	-- 5. Bewegung: Granaten-Abstand halten (zu nah: weg, zu weit: hin)
	local horizontal = math.sign(toTarget.X)
	if distance < 7 then
		horizontal = -horizontal
	elseif distance < 14 and random:NextNumber() < 0.3 then
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
		-- In der Luft: Richtung Ziel lenken
		bot.input = Vector3.new(math.sign(toTarget.X), 0, 0)
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
			bot.dashReadyAt = 0
			bot.nextThink = now + random:NextNumber(0.2, 0.5) -- nicht alle Bots gleichzeitig
		end
		local motor = bot.motor :: HeadMotor.Motor

		if frozen then
			bot.input = Vector3.zero
			motor.jumpPressedAt = -math.huge
		elseif now >= bot.nextThink then
			bot.nextThink = now + Constants.BOT_THINK_INTERVAL
			think(bot, motor, now, shapes)
		end

		HeadMotor.step(motor, math.min(dt, 1 / 20), now, bot.input, shapes)
		body.CFrame = CFrame.new(motor.position)
		body.AssemblyLinearVelocity = motor.velocity
		body.AssemblyAngularVelocity = Vector3.zero
	end
end

return BotController
