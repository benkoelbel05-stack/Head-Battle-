--!strict
-- Steuert den eigenen Kopf: Laufen, Springen, an Plattformen kleben und Fähigkeiten auslösen.
--
-- Bewegung ohne Roblox-Kollisionen, exakt gegen die Plattform-Formen (PlatformShapes):
--   * Klebt der Kopf an einer Plattform, läuft er auf einem geschlossenen Ring um sie herum
--     (oben, Rundung, unten, Rundung). Herunterfallen beim Entlanglaufen ist so unmöglich,
--     um die Ecken geht es gleichmäßig, und bewegt sich die Plattform, fährt der Kopf mit.
--   * In der Luft: eigene Schwerkraft. Berührt der Kopf eine Plattform, klebt er an und
--     behält seinen Schwung entlang der Fläche (gleitet weiter).
-- Die Kugel gehört dem Client (Network Ownership), daher gibt es keine Eingabe-Verzögerung.
-- Alles läuft direkt vor dem Rendern: erst die Plattformen (PlatformClient), dann der Kopf.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local AimPreview = require(script.Parent.AimPreview)
local PlatformClient = require(script.Parent.PlatformClient)

local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
local placeThrusterRemote = remotes:WaitForChild("PlaceThruster") :: RemoteEvent
local throwGrenadeRemote = remotes:WaitForChild("ThrowGrenade") :: RemoteEvent

local player = Players.LocalPlayer
local R = Constants.HEAD_RADIUS

local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }
local UP_KEYS = { Enum.KeyCode.W, Enum.KeyCode.Up }
local DOWN_KEYS = { Enum.KeyCode.S, Enum.KeyCode.Down }
local JUMP_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}
-- Fähigkeiten-Slots: linke Maustaste = 1, Mausrad-Klick = 2, rechte Maustaste = 3
local SLOT_MOUSE: { [Enum.UserInputType]: number } = {
	[Enum.UserInputType.MouseButton1] = 1,
	[Enum.UserInputType.MouseButton3] = 2,
	[Enum.UserInputType.MouseButton2] = 3,
}
-- Alternativ Zahlentasten und Controller
local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
}
local STICK_DEADZONE = 0.25
local MAX_SUBSTEP = 0.4 -- so weit bewegt sich der Kopf pro Kollisionsprüfung höchstens (Studs)
local SWITCH_COOLDOWN = 0.2 -- Mindestzeit zwischen zwei Plattform-Wechseln beim Entlanglaufen

local HeadController = {}

-- Kopf
local myHead: Model? = nil
local position = Vector3.zero
local velocity = Vector3.zero
local facing = 1

-- Kleben
local attachedShape: PlatformShapes.Shape? = nil
local attachedU = 0 -- Position auf dem Ring um die Plattform
local alongSpeed = 0 -- Geschwindigkeit entlang des Rings
local lastShapeFrame: CFrame? = nil -- Lage der Plattform im letzten Frame (zum Mitfahren)
local crawlDirection = 0 -- Laufrichtung entlang des Rings (+1 / -1), bleibt um Ecken erhalten
local detachUntil = 0
local detachedShape: PlatformShapes.Shape? = nil -- von dieser Plattform hat man sich gerade gelöst
local lastSwitch = 0

-- Springen
local jumpHeld = false
local jumpReleased = false
local lastJumpPressed = -math.huge

-- Fähigkeiten
type PendingAbility = { id: string, charge: number }
local pendingAbilities: { PendingAbility } = {}
-- Aufladbare Fähigkeit (Granate): wird gehalten, beim Loslassen ausgelöst
local chargingId: string? = nil
local chargingSlot = 0
local chargingSince = 0
local dashUntil = 0
local dashReadyAt = 0
local dashDirection = Vector3.xAxis

local actionCounter = 0 -- für eindeutige IDs von Thrustern und Granaten

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------------------------------

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- Eingabe als Richtung in der 2D-Ebene (X = rechts, Y = oben)
local function readInput(): Vector3
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end

	local x, y = 0, 0
	if anyKeyDown(LEFT_KEYS) then
		x -= 1
	end
	if anyKeyDown(RIGHT_KEYS) then
		x += 1
	end
	if anyKeyDown(UP_KEYS) then
		y += 1
	end
	if anyKeyDown(DOWN_KEYS) then
		y -= 1
	end

	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local stick = Vector3.new(input.Position.X, input.Position.Y, 0)
				if stick.Magnitude > STICK_DEADZONE then
					x, y = stick.X, stick.Y
				end
			end
		end
	end

	-- TODO (Phase 3): Touch-Steuerung für Handys

	local direction = Vector3.new(x, y, 0)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	return direction
end

local function getArena(): Instance?
	return Workspace:FindFirstChild(Constants.ARENA_FOLDER)
end

-- Ring-Radius um eine Plattform (Bahn des Kopf-Mittelpunkts)
local function ringRadius(shape: PlatformShapes.Shape): number
	return shape.radius + R
end

-- Normale (Welt) an der aktuellen Klebestelle
local function attachedNormal(): Vector3?
	local shape = attachedShape
	if not shape then
		return nil
	end
	local _, localNormal = PlatformShapes.boundaryPoint(shape.halfLength, ringRadius(shape), attachedU)
	return PlatformShapes.frame(shape):VectorToWorldSpace(localNormal)
end

---------------------------------------------------------------------------------------------------
-- Kleben und Lösen
---------------------------------------------------------------------------------------------------

local function attachTo(shape: PlatformShapes.Shape, now: number)
	local frame = PlatformShapes.frame(shape)
	local rho = ringRadius(shape)
	local localPoint = frame:PointToObjectSpace(position)
	local u = PlatformShapes.boundaryParam(shape.halfLength, rho, localPoint)
	local ringPoint, localNormal = PlatformShapes.boundaryPoint(shape.halfLength, rho, u)
	local localTangent = PlatformShapes.tangent(localNormal)

	-- Schwung entlang der Fläche behalten: so gleitet man nach der Landung weiter
	local localVelocity = frame:VectorToObjectSpace(velocity)
	alongSpeed = (localVelocity.X * localTangent.X + localVelocity.Y * localTangent.Y) * Constants.LANDING_KEEP
	crawlDirection = 0

	attachedShape = shape
	attachedU = u
	lastShapeFrame = frame
	lastSwitch = now
	position = frame:PointToWorldSpace(ringPoint)
end

-- Lösen. Für lockTime Sekunden klebt man nicht wieder an DIESER Plattform an (sonst würde man beim
-- Absprung sofort wieder festkleben). Andere Plattformen greifen sofort.
local function detach(now: number, lockTime: number)
	detachedShape = attachedShape
	attachedShape = nil
	lastShapeFrame = nil
	detachUntil = now + lockTime
end

-- Kopf bewegen und dabei auf Plattformen prüfen. Gibt true zurück, wenn er angeklebt ist.
local function moveWithCollisions(dt: number, shapes: { PlatformShapes.Shape }, now: number): boolean
	local delta = velocity * dt
	local steps = math.max(1, math.ceil(delta.Magnitude / MAX_SUBSTEP))

	for _ = 1, steps do
		position += delta / steps
		for _, shape in shapes do
			local frame = PlatformShapes.frame(shape)
			local localPoint = frame:PointToObjectSpace(position)
			local distance, closest = PlatformShapes.closest(shape.halfLength, localPoint)
			local rho = ringRadius(shape)
			if distance < rho then
				if now >= detachUntil or shape ~= detachedShape then
					attachTo(shape, now)
					return true
				end
				-- Kurz nach dem Absprung von genau dieser Plattform: nur herausschieben, nicht ankleben
				local localNormal = if distance > 0.001
					then (Vector3.new(localPoint.X, localPoint.Y, 0) - closest) / distance
					else Vector3.yAxis
				position = frame:PointToWorldSpace(closest + localNormal * rho)
				local normal = frame:VectorToWorldSpace(localNormal)
				local into = velocity:Dot(normal)
				if into < 0 then
					velocity -= normal * into
				end
			end
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Bewegung
---------------------------------------------------------------------------------------------------

local function stepAttached(dt: number, input: Vector3, now: number, shapes: { PlatformShapes.Shape })
	local shape = attachedShape :: PlatformShapes.Shape
	local frame = PlatformShapes.frame(shape)
	local rho = ringRadius(shape)
	local L = shape.halfLength

	-- Laufrichtung: Zeigt die Eingabe klar entlang der Fläche, gilt sie. Steht sie quer zur Fläche
	-- (z. B. "rechts" an einer senkrechten Seite nach dem Herumlaufen um eine Ecke), läuft der Kopf
	-- in seiner bisherigen Richtung weiter.
	local _, currentNormal = PlatformShapes.boundaryPoint(L, rho, attachedU)
	local tangent = PlatformShapes.tangent(currentNormal)
	local localInput = frame:VectorToObjectSpace(input)
	local inputAlong = localInput.X * tangent.X + localInput.Y * tangent.Y
	if input.Magnitude < 0.1 then
		crawlDirection = 0
	elseif math.abs(inputAlong) > 0.7 then
		crawlDirection = math.sign(inputAlong)
	elseif crawlDirection == 0 and math.abs(inputAlong) > 0.1 then
		crawlDirection = math.sign(inputAlong)
	end

	-- Beschleunigen bzw. ohne Eingabe weich ausgleiten
	local target = crawlDirection * Constants.MOVE_SPEED
	local rate = if crawlDirection ~= 0 then Constants.GROUND_ACCEL else Constants.GROUND_FRICTION
	alongSpeed = moveTowards(alongSpeed, target, rate * dt)
	attachedU += alongSpeed * dt

	local ringPoint, localNormal = PlatformShapes.boundaryPoint(L, rho, attachedU)
	local newPosition = frame:PointToWorldSpace(ringPoint)

	-- Mitfahren: wie weit hat sich dieser Punkt der Plattform seit dem letzten Frame bewegt?
	local platformVelocity = Vector3.zero
	if lastShapeFrame and dt > 0 then
		local moved = newPosition - (lastShapeFrame :: CFrame):PointToWorldSpace(ringPoint)
		platformVelocity = Vector3.new(moved.X, moved.Y, 0) / dt
	end
	lastShapeFrame = frame

	local worldNormal = frame:VectorToWorldSpace(localNormal)
	local worldTangent = frame:VectorToWorldSpace(PlatformShapes.tangent(localNormal))
	position = newPosition
	velocity = worldTangent * alongSpeed + platformVelocity

	-- Absprung: weg von der Fläche, etwas Laufschwung mitnehmen
	if now - lastJumpPressed <= Constants.JUMP_BUFFER then
		lastJumpPressed = -math.huge
		local jumpDirection = worldNormal
		if math.abs(worldNormal.X) > 0.5 then
			jumpDirection = (worldNormal + Vector3.new(0, Constants.WALL_JUMP_LIFT, 0)).Unit
		end
		velocity = jumpDirection * Constants.JUMP_VELOCITY
			+ worldTangent * alongSpeed * Constants.JUMP_KEEP_ALONG
			+ platformVelocity
		detach(now, Constants.DETACH_TIME)
		return
	end

	-- Ragt eine andere Plattform in den Weg (z. B. weggeschobene Plattform), auf sie umsteigen
	if now - lastSwitch > SWITCH_COOLDOWN then
		for _, other in shapes do
			if other ~= shape then
				local otherFrame = PlatformShapes.frame(other)
				local distance = PlatformShapes.closest(other.halfLength, otherFrame:PointToObjectSpace(position))
				if distance < ringRadius(other) - 0.15 then
					attachTo(other, now)
					break
				end
			end
		end
	end
end

local function stepAir(dt: number, input: Vector3, now: number, shapes: { PlatformShapes.Shape })
	local vx = moveTowards(velocity.X, input.X * Constants.MOVE_SPEED, Constants.AIR_ACCEL * dt)
	local vy = velocity.Y - Constants.GRAVITY * dt
	if jumpReleased and vy > 0 then
		vy *= Constants.JUMP_CUT_MULTIPLIER -- früh loslassen = niedriger Sprung
	end
	vy = math.max(vy, -Constants.MAX_FALL_SPEED)
	velocity = Vector3.new(vx, vy, 0)
	moveWithCollisions(dt, shapes, now)
end

---------------------------------------------------------------------------------------------------
-- Fähigkeiten
---------------------------------------------------------------------------------------------------

-- Zielrichtung: gedrückte Richtung; ohne Eingabe auf die eigene Fläche (falls gewünscht) oder in Blickrichtung
local function aimDirection(input: Vector3, preferSurface: boolean): Vector3
	if input.Magnitude > 0.1 then
		return input.Unit
	end
	local normal = attachedNormal()
	if preferSurface and normal then
		return -normal
	end
	return Vector3.new(facing, 0, 0)
end

-- Freies Zielen (360°): rechter Stick am Controller, sonst Mauszeiger (Richtung vom Kopf zum Zeiger).
-- nil, wenn weder Stick noch Maus benutzt werden.
local function freeAim(): Vector3?
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 then
				local stick = Vector3.new(state.Position.X, state.Position.Y, 0)
				if stick.Magnitude > STICK_DEADZONE then
					return stick.Unit
				end
			end
		end
	end

	local lastInput = UserInputService:GetLastInputType()
	local usingGamepad = lastInput.Name:sub(1, 7) == "Gamepad"
	if UserInputService.MouseEnabled and not usingGamepad then
		-- Mauszeiger auf die Spielebene (Z = PLANE_Z) projizieren
		local camera = Workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		if math.abs(ray.Direction.Z) > 0.0001 then
			local t = (Constants.PLANE_Z - ray.Origin.Z) / ray.Direction.Z
			local point = ray.Origin + ray.Direction * t
			local toMouse = Vector3.new(point.X - position.X, point.Y - position.Y, 0)
			if toMouse.Magnitude > 0.5 then
				return toMouse.Unit
			end
		end
	end
	return nil
end

-- Zielen für Würfe: frei (Maus/Stick), sonst Tasten-Richtung leicht angehoben (Bogen)
local function throwAim(input: Vector3): Vector3
	return freeAim() or GrenadePhysics.liftKeyboardAim(aimDirection(input, false))
end

local function abilityReady(head: Model, id: string): boolean
	local readyAt = head:GetAttribute(Abilities.readyAttribute(id))
	return typeof(readyAt) ~= "number" or Workspace:GetServerTimeNow() >= readyAt
end

-- Thruster setzen:
--   * Klebt man an einer Plattform: genau an der Stelle, wo man steht (Berührpunkt unter dem Kopf)
--   * In der Luft: an die nächste Plattform in Zielrichtung
local function useThruster(head: Model, input: Vector3)
	if not abilityReady(head, "Thruster") then
		return
	end

	local model: Model? = nil
	local contactPoint: Vector3
	local normal: Vector3

	local shape = attachedShape
	local surfaceNormal = attachedNormal()
	if shape and surfaceNormal then
		model = shape.model
		normal = surfaceNormal
		contactPoint = position - surfaceNormal * R
	else
		local arena = getArena()
		if not arena then
			return
		end
		raycastParams.FilterDescendantsInstances = { arena }
		local aim = aimDirection(input, true)
		local hit = Workspace:Raycast(position, aim * (R + Constants.THRUSTER_RANGE), raycastParams)
		if not hit then
			return
		end
		local flatNormal = Vector3.new(hit.Normal.X, hit.Normal.Y, 0)
		if flatNormal.Magnitude < 0.01 then
			return
		end
		-- Plattform-Model zum getroffenen Teil finden
		local candidate: Instance? = hit.Instance
		while candidate and candidate.Parent ~= arena do
			candidate = candidate.Parent
		end
		if candidate and candidate:IsA("Model") then
			model = candidate
		end
		normal = flatNormal.Unit
		contactPoint = hit.Position
	end

	local root = model and model.PrimaryPart
	if not model or not root then
		return
	end

	-- Relativ zur Plattform: so ist es auf jedem Rechner dieselbe Stelle, auch wenn sie sich bewegt
	local localPosition = root.CFrame:PointToObjectSpace(contactPoint)
	local localNormal = root.CFrame:VectorToObjectSpace(normal)
	actionCounter += 1
	local id = tostring(actionCounter)

	-- Sofort in der eigenen Simulation wirken lassen, dann an den Server schicken
	head:SetAttribute(Abilities.readyAttribute("Thruster"), Workspace:GetServerTimeNow() + Constants.THRUSTER_COOLDOWN)
	PlatformClient.predictThruster(model, localPosition, localNormal, id)
	placeThrusterRemote:FireServer(model, localPosition, localNormal, id)
end

local function useAbility(id: string, charge: number, input: Vector3, now: number)
	local head = myHead
	if not head then
		return
	end

	if id == "Dash" then
		if now >= dashReadyAt then
			-- In Mausrichtung (bzw. rechter Stick), sonst gedrückte Richtung oder Blickrichtung
			dashDirection = freeAim() or aimDirection(input, false)
			dashUntil = now + Constants.DASH_TIME
			dashReadyAt = now + Constants.DASH_COOLDOWN
			-- Kurz nicht ankleben, damit man sich von der eigenen Fläche lösen kann
			detach(now, 0.05)
			head:SetAttribute(Abilities.readyAttribute("Dash"), Workspace:GetServerTimeNow() + Constants.DASH_COOLDOWN)
		end
	elseif id == "Thruster" then
		useThruster(head, input)
	elseif id == "Grenade" then
		if abilityReady(head, "Grenade") then
			local aim = throwAim(input)
			actionCounter += 1
			local id = tostring(actionCounter)
			-- Sofort selbst fliegen lassen, der Server rechnet die echte Granate
			local start, launchVelocity = GrenadePhysics.launch(position, aim, charge)
			head:SetAttribute(Abilities.readyAttribute("Grenade"), Workspace:GetServerTimeNow() + Constants.GRENADE_COOLDOWN)
			PlatformClient.predictGrenade(id, start, launchVelocity)
			throwGrenadeRemote:FireServer(aim, charge, id)
		end
	end
end

-- Slot-Taste gedrückt: Fähigkeit merken (ausgelöst im nächsten Frame, mit der aktuellen Eingabe).
-- Aufladbare Fähigkeiten starten stattdessen das Aufladen.
local function pressSlot(slot: number)
	local head = myHead
	if not head then
		return
	end
	local id = Abilities.parseLoadout(head:GetAttribute("Loadout"))[slot]
	if not id then
		return
	end
	if Abilities.list[id].chargeable then
		if abilityReady(head, id) and not chargingId then
			chargingId = id
			chargingSlot = slot
			chargingSince = os.clock()
		end
	else
		table.insert(pendingAbilities, { id = id, charge = 1 })
	end
end

-- Slot-Taste losgelassen: aufgeladene Fähigkeit auslösen
local function releaseSlot(slot: number)
	if chargingId and chargingSlot == slot then
		local charge = GrenadePhysics.chargeFromHold(os.clock() - chargingSince)
		table.insert(pendingAbilities, { id = chargingId, charge = charge })
		chargingId = nil
		AimPreview.hide()
	end
end

---------------------------------------------------------------------------------------------------
-- Hauptschleife
---------------------------------------------------------------------------------------------------

local function step(rawDt: number)
	local head = myHead
	local body = head and head.PrimaryPart
	if not head or not head.Parent or not body then
		return
	end

	local dt = math.min(rawDt, 1 / 20)
	local now = os.clock()
	local input = readInput()
	if math.abs(input.X) > 0.1 then
		facing = math.sign(input.X)
	end
	local shapes = PlatformShapes.collect(getArena())

	-- Angeklebte Plattform verschwunden (z. B. Arena neu gebaut)
	if attachedShape and not table.find(shapes, attachedShape) then
		detach(now, 0)
	end

	for _, pending in pendingAbilities do
		useAbility(pending.id, pending.charge, input, now)
	end
	table.clear(pendingAbilities)

	if now < dashUntil then
		-- Dash: gerade Linie, keine Schwerkraft; klebt an, sobald er eine Plattform trifft
		velocity = dashDirection * Constants.DASH_SPEED
		if moveWithCollisions(dt, shapes, now) then
			dashUntil = 0
		end
	else
		if dashUntil > 0 then
			-- Dash gerade vorbei: etwas Schwung behalten
			dashUntil = 0
			velocity = dashDirection * Constants.DASH_SPEED * Constants.DASH_END_KEEP
		end
		if attachedShape then
			stepAttached(dt, input, now, shapes)
		else
			stepAir(dt, input, now, shapes)
		end
	end
	jumpReleased = false

	position = Vector3.new(position.X, position.Y, Constants.PLANE_Z)
	body.CFrame = CFrame.new(position)

	-- Zielstreifen, solange eine Granate aufgeladen wird
	if chargingId == "Grenade" then
		AimPreview.show(position, throwAim(input), GrenadePhysics.chargeFromHold(now - chargingSince))
	end
	body.AssemblyLinearVelocity = velocity
	body.AssemblyAngularVelocity = Vector3.zero
end

---------------------------------------------------------------------------------------------------
-- Eingabe und Start
---------------------------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if JUMP_KEYS[input.KeyCode] then
		jumpHeld = true
		lastJumpPressed = os.clock()
		return
	end
	local slot = SLOT_MOUSE[input.UserInputType] or SLOT_KEYS[input.KeyCode]
	if slot then
		pressSlot(slot)
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if JUMP_KEYS[input.KeyCode] and jumpHeld then
		jumpHeld = false
		jumpReleased = true
	end
	local slot = SLOT_MOUSE[input.UserInputType] or SLOT_KEYS[input.KeyCode]
	if slot then
		releaseSlot(slot)
	end
end

local function trackHead(child: Instance)
	if child:IsA("Model") and child:GetAttribute("UserId") == player.UserId then
		myHead = child
		local body = child.PrimaryPart
		position = if body then body.Position else Vector3.zero
		velocity = Vector3.zero
		attachedShape = nil
		detachedShape = nil
		lastShapeFrame = nil
		detachUntil = 0
		dashUntil = 0
		dashReadyAt = 0
		table.clear(pendingAbilities)
		chargingId = nil
		AimPreview.hide()
		print("[HeadBattle] Eigener Kopf gefunden")
	end
end

function HeadController.start()
	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)
	headsFolder.ChildAdded:Connect(trackHead)
	for _, child in headsFolder:GetChildren() do
		trackHead(child)
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Direkt vor dem Rendern (nicht danach): Eingaben wirken im selben Bild.
	-- Reihenfolge: Plattformen weiterrechnen, dann den Kopf darauf bewegen.
	RunService:BindToRenderStep("HeadBattleMovement", Enum.RenderPriority.Input.Value + 1, function(dt: number)
		PlatformClient.step(dt)
		step(dt)
	end)
end

return HeadController
