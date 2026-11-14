--!strict
-- Plattformen, Thruster und Granaten auf dem Client:
--   * Rechnet die Plattform-Physik selbst (PlatformSim), jeden Frame, ohne Netzwerk-Verzögerung
--   * Eigene Aktionen (Thruster, Granate, Gewicht, Landung) wirken sofort
--   * Aktionen anderer Spieler kommen als Ereignisse vom Server
--   * Der Server schickt regelmäßig einen Abgleich, kleine Abweichungen werden weich korrigiert
--   * Granaten fliegen lokal (flüssig), Explosionen kommen vom Server (er entscheidet, wer ausscheidet)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ArenaInfo = require(ReplicatedStorage.Shared.ArenaInfo)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local HeadWeight = require(ReplicatedStorage.Shared.HeadWeight)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local ThrusterVisual = require(ReplicatedStorage.Shared.ThrusterVisual)
local ItemAnimations = require(script.Parent.ItemAnimations)
local SpriteAssets = require(ReplicatedStorage.Shared.SpriteAssets)
local SpriteVisual = require(script.Parent.SpriteVisual)
local SwordVisual = require(script.Parent.SwordVisual)
local SoundFX = require(script.Parent.SoundFX)
local CameraController = require(script.Parent.CameraController)

type LocalGrenade = {
	id: string,
	part: BasePart,
	position: Vector3,
	velocity: Vector3,
	accumulator: number,
	explodeAt: number,
}

local PlatformClient = {}

local player = Players.LocalPlayer
local sim = PlatformSim.new()

---------------------------------------------------------------------------------------------------
-- Abgleich mit dem Server ohne Zucken
-- Ein Abgleich ist beim Ankommen schon etwas alt. Früher wurde die Plattform direkt in Richtung dieses
-- alten Stands gezogen: schnelle Plattformen (z. B. seitlich mit Thruster) sprangen dadurch alle 0,2 s
-- ein Stück zurück. Jetzt merkt sich der Client seinen eigenen Verlauf, vergleicht den Abgleich mit dem
-- eigenen Stand ZUR SELBEN ZEIT und gleicht nur echte Abweichungen aus, verteilt über ein paar Bilder.
---------------------------------------------------------------------------------------------------

type Sample = { t: number, offset: Vector3, angle: number, velocity: Vector3, angularVelocity: number }
type Fix = { offset: Vector3, angle: number, velocity: Vector3, angularVelocity: number }
local HISTORY_TIME = 1 -- Sekunden Verlauf
local CORRECT_SHARE = 0.7 -- so viel der echten Abweichung wird pro Abgleich ausgeglichen
local CORRECT_TIME = 0.12 -- Sekunden, über die ein Ausgleich verteilt wird
local history: { [Model]: { Sample } } = {}
local pendingFix: { [Model]: Fix } = {}

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function recordHistory(now: number)
	for model, state in sim.platforms do
		local list = history[model]
		if not list then
			list = {}
			history[model] = list
		end
		table.insert(list, {
			t = now,
			offset = state.offset,
			angle = state.angle,
			velocity = state.velocity,
			angularVelocity = state.angularVelocity,
		})
		while #list > 2 and now - list[1].t > HISTORY_TIME do
			table.remove(list, 1)
		end
	end
	for model in history do
		if not sim.platforms[model] then
			history[model] = nil
			pendingFix[model] = nil
		end
	end
end

-- Eigener Stand einer Plattform zur Zeit t (zwischen zwei Aufzeichnungen weich gemischt)
local function sampleAt(model: Model, t: number): Sample?
	local list = history[model]
	if not list or #list == 0 then
		return nil
	end
	if t <= list[1].t then
		return list[1]
	end
	for index = #list, 1, -1 do
		local a = list[index]
		if a.t <= t then
			local b = list[index + 1]
			if not b then
				return a
			end
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-4)
			return {
				t = t,
				offset = a.offset:Lerp(b.offset, alpha),
				angle = a.angle + wrapAngle(b.angle - a.angle) * alpha,
				velocity = a.velocity:Lerp(b.velocity, alpha),
				angularVelocity = a.angularVelocity + (b.angularVelocity - a.angularVelocity) * alpha,
			}
		end
	end
	return list[1]
end

local function onSnapshot(data: unknown, serverTime: unknown)
	if typeof(data) ~= "table" then
		return
	end
	if typeof(serverTime) ~= "number" then
		PlatformSim.correct(sim, data, Constants.SNAPSHOT_BLEND) -- alter Server ohne Zeitstempel
		return
	end
	for _, entry in data :: { any } do
		local model, offset, angle, velocity, angularVelocity = entry[1], entry[2], entry[3], entry[4], entry[5]
		if
			typeof(model) == "Instance"
			and model:IsA("Model")
			and sim.platforms[model]
			and typeof(offset) == "Vector3"
			and typeof(angle) == "number"
			and typeof(velocity) == "Vector3"
			and typeof(angularVelocity) == "number"
		then
			local past = sampleAt(model, serverTime)
			if past then
				-- Ersetzt einen noch laufenden Ausgleich: der neue Vergleich enthält dessen Rest schon
				pendingFix[model] = {
					offset = (offset - past.offset) * CORRECT_SHARE,
					angle = wrapAngle(angle - past.angle) * CORRECT_SHARE,
					velocity = (velocity - past.velocity) * CORRECT_SHARE,
					angularVelocity = (angularVelocity - past.angularVelocity) * CORRECT_SHARE,
				}
			end
		end
	end
end

-- Laufende Ausgleiche ein Stück weiter anwenden (weich über CORRECT_TIME)
local function applyFixes(dt: number)
	local share = 1 - math.exp(-dt / CORRECT_TIME)
	for model, fix in pendingFix do
		local state = sim.platforms[model]
		if not state then
			pendingFix[model] = nil
			continue
		end
		state.offset += fix.offset * share
		state.angle = wrapAngle(state.angle + fix.angle * share)
		state.velocity += fix.velocity * share
		state.angularVelocity += fix.angularVelocity * share
		fix.offset *= 1 - share
		fix.angle *= 1 - share
		fix.velocity *= 1 - share
		fix.angularVelocity *= 1 - share
		if fix.offset.Magnitude < 1e-3 and math.abs(fix.angle) < 1e-4 and fix.velocity.Magnitude < 1e-3 then
			pendingFix[model] = nil
		end
	end
end
local weightTracker = HeadWeight.newTracker()
local grenades: { [string]: LocalGrenade } = {}
local knownExplosions: { [string]: boolean } = {}
local thrusterVisuals: { [Part]: boolean } = {}
local effectsFolder: Folder
local arena: Instance? = nil

---------------------------------------------------------------------------------------------------
-- Effekte
---------------------------------------------------------------------------------------------------

local function makeEffectPart(name: string, size: Vector3, color: Color3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	part.Parent = effectsFolder
	return part
end

-- Knet-Explosion: eine Kugel, die schnell wächst und verblasst
local function explosionEffect(position: Vector3, radius: number?)
	local small = radius ~= nil and radius < Constants.GRENADE_BLAST_RADIUS
	SoundFX.play("explosion", if small then 0.7 else 1)
	CameraController.impact(if small then 0.4 else 0.6)
	local blob = makeEffectPart("Blast", Vector3.one, Color3.fromRGB(255, 196, 92), position)
	ItemAnimations.explosion(position, radius)
	local tween = TweenService:Create(
		blob,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * (radius or Constants.GRENADE_BLAST_RADIUS) * 2, Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		blob:Destroy()
	end)
end

local function fadeAndDestroy(part: BasePart, delay: number, duration: number)
	task.delay(delay, function()
		local tween = TweenService:Create(part, TweenInfo.new(duration), { Transparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			part:Destroy()
		end)
	end)
end

-- Sprite-Treffer-Animation ("hit") an der Stelle des ausgeschiedenen Kopfes, danach ausblenden.
-- Zerquetscht: platt gedrückt quer zur Druckrichtung.
local function hitSprite(position: Vector3, skin: string, cause: string, direction: Vector3)
	local sprite = SpriteVisual.create("HitSprite", effectsFolder)
	local size = Constants.SPRITE_SIZE
	local angle = if cause == "Crush" then math.atan2(-direction.X, direction.Y) else 0
	local squash = if cause == "Crush" then Vector3.new(1.5, 0.35, 1) else Vector3.one
	sprite.part.Size = Vector3.new(size * squash.X, size * squash.Y, 0.05)
	sprite.part.CFrame = CFrame.new(position.X, position.Y, Constants.SPRITE_Z) * CFrame.Angles(0, 0, angle)

	local frames = SpriteAssets.frameCount(skin, "hit")
	task.spawn(function()
		for index = 1, frames do
			SpriteVisual.setImage(sprite, SpriteAssets.frame(skin, "hit", index), direction.X > 0)
			task.wait(1 / Constants.SPRITE_FPS)
		end
		local tween = TweenService:Create(sprite.image, TweenInfo.new(0.4), { ImageTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		sprite.part:Destroy()
	end)
end

-- Ein Kopf ist ausgeschieden: Knetfladen (zerquetscht) oder Knetbrocken (Explosion)
local function eliminationEffect(position: Vector3, color: Color3, cause: string, direction: Vector3, skin: string?)
	SoundFX.play("eliminate")
	CameraController.impact(0.5)
	local R = Constants.HEAD_RADIUS
	if skin and Constants.USE_SPRITES and SpriteAssets.hasImages() and cause ~= "Fall" then
		hitSprite(position, skin, cause, direction)
		if cause == "Crush" then
			return -- der platte Sprite ist der Fladen
		end
	end
	if cause == "Crush" then
		-- Platter Fladen, quer zur Druckrichtung, zur Kamera hin sichtbar
		local pancake = makeEffectPart("Pancake", Vector3.new(0.5, R * 3.2, R * 3.2), color, position)
		pancake.Shape = Enum.PartType.Cylinder
		pancake.CFrame = CFrame.fromMatrix(position, direction, Vector3.zAxis)
		fadeAndDestroy(pancake, 1.2, 0.5)
	elseif cause == "Blast" then
		-- Brocken fliegen in alle Richtungen
		for i = 1, 7 do
			local angle = (i / 7) * math.pi * 2 + math.random() * 0.5
			local outward = Vector3.new(math.cos(angle), math.sin(angle), 0)
			local chunk = makeEffectPart("Chunk", Vector3.one * R * 0.55, color, position)
			local tween = TweenService:Create(
				chunk,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(position + outward * R * 3.5 + direction * 1.5) }
			)
			tween:Play()
			fadeAndDestroy(chunk, 0.5, 0.3)
		end
	end
end

-- Thruster-Aussehen an der Plattform, verschwindet wenn der Schub endet
local function showThruster(model: Model, thruster: PlatformSim.Thruster)
	local state = PlatformSim.get(sim, model)
	if not state then
		return
	end
	local frame = PlatformSim.cframeOf(state)
	local point = frame:PointToWorldSpace(thruster.localPosition)
	local normal = frame:VectorToWorldSpace(-thruster.localDirection)
	state.root.CFrame = frame -- damit die Schweißnaht an der richtigen Stelle sitzt
	local visual = ThrusterVisual.create(state.root, point, normal)
	ItemAnimations.thruster(visual)
	SoundFX.play("thruster")
	thrusterVisuals[visual] = true
	task.delay(math.max(thruster.endTime - Workspace:GetServerTimeNow(), 0), function()
		thrusterVisuals[visual] = nil
		visual:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- Eigene Aktionen (sofort, ohne auf den Server zu warten)
---------------------------------------------------------------------------------------------------

-- Thruster sofort setzen. localPosition/localNormal relativ zur Wurzel der Plattform.
-- Eigene Rakete hat eingeschlagen: Explosion sofort zeigen. Die Meldung vom Server kurz danach
-- zeigt sie dann nicht noch einmal (stößt aber wie immer die Plattformen weg).
local predictedExplosion: { position: Vector3, at: number }? = nil
function PlatformClient.predictExplosion(position: Vector3, radius: number)
	explosionEffect(position, radius)
	predictedExplosion = { position = position, at = os.clock() }
end

function PlatformClient.predictThruster(model: Model, localPosition: Vector3, localNormal: Vector3, id: string)
	local now = Workspace:GetServerTimeNow()
	local thruster: PlatformSim.Thruster = {
		id = `{player.UserId}-{id}`,
		localPosition = localPosition,
		localDirection = -localNormal,
		startTime = now,
		endTime = now + Constants.THRUSTER_DURATION,
	}
	if PlatformSim.addThruster(sim, model, thruster) then
		showThruster(model, thruster)
	end
end

local function spawnGrenade(id: string, start: Vector3, velocity: Vector3, startTime: number)
	if grenades[id] or knownExplosions[id] then
		return
	end
	local part = makeEffectPart("Grenade", Vector3.one * Constants.GRENADE_RADIUS * 2, Constants.GRENADE_COLOR, start)
	ItemAnimations.grenade(part)
	SoundFX.play("grenade_throw")
	grenades[id] = {
		id = id,
		part = part,
		position = start,
		velocity = velocity,
		accumulator = 0,
		explodeAt = startTime + Constants.GRENADE_FUSE,
	}
end

-- Eigene Granate sofort fliegen lassen
function PlatformClient.predictGrenade(id: string, start: Vector3, velocity: Vector3)
	spawnGrenade(`{player.UserId}-{id}`, start, velocity, Workspace:GetServerTimeNow())
end

---------------------------------------------------------------------------------------------------
-- Ereignisse vom Server
---------------------------------------------------------------------------------------------------

local function onEvent(kind: unknown, ...: any)
	if kind == "Thruster" then
		local model, thruster = ...
		if typeof(model) == "Instance" and model:IsA("Model") and typeof(thruster) == "table" then
			-- Eigene Thruster sind schon da (gleiche ID), doppelte werden ignoriert
			if PlatformSim.addThruster(sim, model, thruster) then
				showThruster(model, thruster)
			end
		end
	elseif kind == "GrenadeThrown" then
		local id, start, velocity, startTime = ...
		if typeof(id) == "string" and typeof(start) == "Vector3" and typeof(velocity) == "Vector3" and typeof(startTime) == "number" then
			spawnGrenade(id, start, velocity, startTime)
		end
	elseif kind == "Eliminated" then
		local position, color, cause, direction, skin = ...
		if typeof(position) == "Vector3" and typeof(color) == "Color3" and typeof(cause) == "string" and typeof(direction) == "Vector3" then
			eliminationEffect(position, color, cause, direction, if typeof(skin) == "string" then skin else nil)
		end
	elseif kind == "Reset" then
		-- Neue Runde: Plattformen zurück, Thruster und Granaten weg
		PlatformSim.reset(sim)
		PlatformSim.apply(sim)
		for visual in thrusterVisuals do
			visual:Destroy()
		end
		table.clear(thrusterVisuals)
		for _, grenade in grenades do
			grenade.part:Destroy()
		end
		table.clear(grenades)
	elseif kind == "Slash" then
		local ownerKey, origin, direction = ...
		-- Eigene Schläge wurden schon sofort angezeigt
		if ownerKey ~= tostring(player.UserId) and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
			SwordVisual.play(origin, direction)
		end
	elseif kind == "GrenadeDeflected" then
		local id, position, velocity = ...
		local grenade = if typeof(id) == "string" then grenades[id] else nil
		if grenade and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
			grenade.position = position
			grenade.velocity = velocity
			grenade.accumulator = 0
		end
	elseif kind == "Explosion" then
		local id, position, blastRadius, pushRadius, impulse = ...
		if typeof(id) == "string" and typeof(position) == "Vector3" then
			knownExplosions[id] = true
			local grenade = grenades[id]
			if grenade then
				-- Lokale Granate fliegt noch: jetzt an der Server-Stelle explodieren lassen
				grenade.part:Destroy()
				grenades[id] = nil
			end
			local radius = if typeof(blastRadius) == "number" then blastRadius else nil
			local predicted = predictedExplosion
			if
				predicted
				and os.clock() - predicted.at < 1
				and (Vector3.new(predicted.position.X, predicted.position.Y, 0) - Vector3.new(position.X, position.Y, 0)).Magnitude < 8
			then
				predictedExplosion = nil -- schon gezeigt
			else
				explosionEffect(position, radius)
			end
			GrenadePhysics.applyExplosion(
				sim,
				PlatformShapes.collect(arena),
				position,
				if typeof(pushRadius) == "number" then pushRadius else nil,
				if typeof(impulse) == "number" then impulse else nil
			)
			task.delay(5, function()
				knownExplosions[id] = nil
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Start und jeder Frame
---------------------------------------------------------------------------------------------------

local function registerArena(newArena: Instance)
	arena = newArena
	for _, child in newArena:GetChildren() do
		if child:IsA("Model") and child.PrimaryPart then
			PlatformSim.register(sim, child)
		end
	end
end

function PlatformClient.start()
	local folder = Instance.new("Folder")
	folder.Name = Constants.EFFECTS_FOLDER
	folder.Parent = Workspace
	effectsFolder = folder

	-- Plattform-Formen lesen ihre Lage aus der eigenen Simulation
	PlatformShapes.setFrameProvider(function(model: Model): CFrame?
		local state = PlatformSim.get(sim, model)
		return if state then PlatformSim.cframeOf(state) else nil
	end)

	registerArena(Workspace:WaitForChild(Constants.ARENA_FOLDER))
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == Constants.ARENA_FOLDER then
			task.defer(registerArena, child)
		end
	end)

	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
	local events = remotes:WaitForChild("PlatformEvents") :: RemoteEvent
	local snapshot = remotes:WaitForChild("PlatformSnapshot") :: UnreliableRemoteEvent
	events.OnClientEvent:Connect(onEvent)
	snapshot.OnClientEvent:Connect(onSnapshot)
end

-- Jeden Frame vor der Kopf-Steuerung: Plattformen und Granaten weiterrechnen
function PlatformClient.step(dt: number)
	local now = Workspace:GetServerTimeNow()
	local shapes = PlatformShapes.collect(arena)

	-- Gewicht, Landungen und Laufen aller Köpfe auf die Plattformen
	local heads = {}
	local headsFolder = Workspace:FindFirstChild(Constants.HEADS_FOLDER)
	if headsFolder then
		for _, child in headsFolder:GetChildren() do
			if child:IsA("Model") then
				table.insert(heads, child)
			end
		end
	end
	HeadWeight.step(weightTracker, sim, shapes, heads)

	PlatformSim.step(sim, dt, now)
	applyFixes(dt)
	PlatformSim.apply(sim)
	recordHistory(now)

	-- Granaten fliegen lassen; bei Zündung verschwinden sie (die Explosion kommt vom Server)
	for id, grenade in grenades do
		if now >= grenade.explodeAt + 0.5 or grenade.position.Y < ArenaInfo.fallLimit() then
			grenade.part:Destroy()
			grenades[id] = nil
		elseif now < grenade.explodeAt then
			GrenadePhysics.advance(grenade, dt, shapes)
			grenade.part.CFrame = CFrame.new(grenade.position) * CFrame.Angles(0, 0, (now % 100) * 6)
		end
	end
end

return PlatformClient
