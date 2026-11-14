--!strict
-- Steuert den eigenen Kopf: Eingaben lesen, Bewegung (HeadMotor), Fähigkeiten auslösen.
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
local HeadMotor = require(ReplicatedStorage.Shared.HeadMotor)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local AimPreview = require(script.Parent.AimPreview)
local PlatformClient = require(script.Parent.PlatformClient)
local SwordVisual = require(script.Parent.SwordVisual)

local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
local placeThrusterRemote = remotes:WaitForChild("PlaceThruster") :: RemoteEvent
local throwGrenadeRemote = remotes:WaitForChild("ThrowGrenade") :: RemoteEvent
local swingSwordRemote = remotes:WaitForChild("SwingSword") :: RemoteEvent
local fireMissileRemote = remotes:WaitForChild("FireMissile") :: RemoteEvent
local roundState = ReplicatedStorage:WaitForChild(Constants.ROUND_STATE)

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

local HeadController = {}

local myHead: Model? = nil
local motor: HeadMotor.Motor = HeadMotor.new(Vector3.zero)
local jumpHeld = false

-- Fähigkeiten
type PendingAbility = { id: string, charge: number }
local pendingAbilities: { PendingAbility } = {}
local chargingId: string? = nil -- aufladbare Fähigkeit (Granate): gehalten, beim Loslassen ausgelöst
local chargingSlot = 0
local chargingSince = 0
local dashReadyAt = 0
local actionCounter = 0 -- für eindeutige IDs von Thrustern und Granaten

-- Eigene Lenkraketen: aktuelle Flugrichtung und Tempo pro Rakete
local missileDirections: { [BasePart]: Vector3 } = {}
local missileSpeeds: { [BasePart]: number } = {}
local missileHeldSlot: number? = nil -- solange diese Taste gehalten wird, lenkt man die Rakete

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------------------------------------
-- Eingabe
---------------------------------------------------------------------------------------------------

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

-- Während des Countdowns stehen alle still
local function isFrozen(): boolean
	return roundState:GetAttribute("Phase") == "Countdown"
end

---------------------------------------------------------------------------------------------------
-- Zielen
---------------------------------------------------------------------------------------------------

-- Zielrichtung: gedrückte Richtung; ohne Eingabe auf die eigene Fläche (falls gewünscht) oder in Blickrichtung
local function aimDirection(input: Vector3, preferSurface: boolean): Vector3
	if input.Magnitude > 0.1 then
		return input.Unit
	end
	local normal = HeadMotor.attachedNormal(motor)
	if preferSurface and normal then
		return -normal
	end
	return Vector3.new(motor.facing, 0, 0)
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
			local toMouse = Vector3.new(point.X - motor.position.X, point.Y - motor.position.Y, 0)
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

---------------------------------------------------------------------------------------------------
-- Fähigkeiten
---------------------------------------------------------------------------------------------------

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

	local shape = motor.attachedShape
	local surfaceNormal = HeadMotor.attachedNormal(motor)
	if shape and surfaceNormal then
		model = shape.model
		normal = surfaceNormal
		contactPoint = motor.position - surfaceNormal * R
	else
		local arena = Workspace:FindFirstChild(Constants.ARENA_FOLDER)
		if not arena then
			return
		end
		raycastParams.FilterDescendantsInstances = { arena }
		local aim = aimDirection(input, true)
		local hit = Workspace:Raycast(motor.position, aim * (R + Constants.THRUSTER_RANGE), raycastParams)
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
			dashReadyAt = now + Constants.DASH_COOLDOWN
			-- In Mausrichtung (bzw. rechter Stick), sonst gedrückte Richtung oder Blickrichtung
			HeadMotor.startDash(motor, now, freeAim() or aimDirection(input, false))
			head:SetAttribute(Abilities.readyAttribute("Dash"), Workspace:GetServerTimeNow() + Constants.DASH_COOLDOWN)
		end
	elseif id == "Thruster" then
		useThruster(head, input)
	elseif id == "Sword" then
		if abilityReady(head, "Sword") then
			-- In Mausrichtung schlagen; sofort anzeigen, Treffer entscheidet der Server
			local direction = freeAim() or aimDirection(input, false)
			head:SetAttribute(Abilities.readyAttribute("Sword"), Workspace:GetServerTimeNow() + Constants.SWORD_COOLDOWN)
			SwordVisual.play(motor.position, direction)
			swingSwordRemote:FireServer(direction, motor.position)
		end
	elseif id == "Missile" then
		-- Abfeuern, wenn noch keine eigene fliegt. Lenken geschieht durch Halten der Taste (siehe step).
		local flying = next(missileDirections) ~= nil
		if not flying and abilityReady(head, "Missile") then
			actionCounter += 1
			head:SetAttribute(Abilities.readyAttribute("Missile"), Workspace:GetServerTimeNow() + Constants.MISSILE_COOLDOWN)
			fireMissileRemote:FireServer(freeAim() or aimDirection(input, false), tostring(actionCounter))
		end
	elseif id == "Grenade" then
		if abilityReady(head, "Grenade") then
			local aim = throwAim(input)
			actionCounter += 1
			local actionId = tostring(actionCounter)
			-- Sofort selbst fliegen lassen, der Server rechnet die echte Granate
			local start, launchVelocity = GrenadePhysics.launch(motor.position, aim, charge)
			head:SetAttribute(Abilities.readyAttribute("Grenade"), Workspace:GetServerTimeNow() + Constants.GRENADE_COOLDOWN)
			PlatformClient.predictGrenade(actionId, start, launchVelocity)
			throwGrenadeRemote:FireServer(aim, charge, actionId, motor.position)
		end
	end
end

-- Slot-Taste gedrückt: Fähigkeit merken (ausgelöst im nächsten Frame, mit der aktuellen Eingabe).
-- Aufladbare Fähigkeiten starten stattdessen das Aufladen.
local function pressSlot(slot: number)
	local head = myHead
	if not head or isFrozen() then
		return
	end
	local id = Abilities.parseLoadout(head:GetAttribute("Loadout"))[slot]
	if not id then
		return
	end
	if id == "Missile" then
		missileHeldSlot = slot
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
	if missileHeldSlot == slot then
		missileHeldSlot = nil
	end
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
	local frozen = isFrozen()
	local input = if frozen then Vector3.zero else readInput()
	local shapes = PlatformShapes.collect(Workspace:FindFirstChild(Constants.ARENA_FOLDER))

	for _, pending in pendingAbilities do
		useAbility(pending.id, pending.charge, input, now)
	end
	table.clear(pendingAbilities)

	if frozen then
		motor.jumpPressedAt = -math.huge
	end

	-- Andere Köpfe als feste Kugeln (Spieler und Bots)
	local others = {}
	local headsFolder = Workspace:FindFirstChild(Constants.HEADS_FOLDER)
	if headsFolder then
		for _, other in headsFolder:GetChildren() do
			local otherBody = if other ~= head and other:IsA("Model") then other.PrimaryPart else nil
			if otherBody then
				table.insert(others, otherBody.Position)
			end
		end
	end

	local alpha = HeadMotor.update(motor, dt, now, input, shapes, others)

	body.CFrame = CFrame.new(HeadMotor.renderPosition(motor, alpha))
	body.AssemblyLinearVelocity = motor.velocity
	body.AssemblyAngularVelocity = Vector3.zero

	-- Eigene Lenkraketen: Taste gehalten = langsam zur Maus lenken (ohne Maus: Richtungstasten),
	-- losgelassen = geradeaus mit vollem Tempo
	local missiles = Workspace:FindFirstChild(Constants.MISSILES_FOLDER)
	local myKey = tostring(player.UserId)
	local steering = missileHeldSlot ~= nil
	for part in missileDirections do
		if not part.Parent then
			missileDirections[part] = nil
			missileSpeeds[part] = nil
		end
	end
	if missiles then
		for _, part in missiles:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("OwnerKey") == myKey then
				local direction = missileDirections[part] or part.CFrame.RightVector
				local position = Vector3.new(part.Position.X, part.Position.Y, Constants.PLANE_Z)
				local wanted: Vector3? = nil
				local mouseAim = freeAim()
				if not steering then
					-- losgelassen: geradeaus weiter
				elseif mouseAim then
					-- Zum Mauszeiger hin (freeAim zeigt vom Kopf aus, deshalb hier vom Raketen-Punkt neu rechnen)
					local camera = Workspace.CurrentCamera
					local mouse = UserInputService:GetMouseLocation()
					local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
					if math.abs(ray.Direction.Z) > 0.0001 then
						local point = ray.Origin + ray.Direction * ((Constants.PLANE_Z - ray.Origin.Z) / ray.Direction.Z)
						local toMouse = Vector3.new(point.X - position.X, point.Y - position.Y, 0)
						wanted = if toMouse.Magnitude > 0.5 then toMouse.Unit else nil
					end
				elseif input.Magnitude > 0.1 then
					wanted = input.Unit
				end
				if wanted then
					local current = math.atan2(direction.Y, direction.X)
					local desired = math.atan2(wanted.Y, wanted.X)
					local difference = (desired - current + math.pi) % (2 * math.pi) - math.pi
					local maxTurn = Constants.MISSILE_TURN_RATE * dt
					local angle = current + math.clamp(difference, -maxTurn, maxTurn)
					direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
				end
				missileDirections[part] = direction
				local speed = missileSpeeds[part] or Constants.MISSILE_SPEED
				local wantedSpeed = if steering then Constants.MISSILE_STEER_SPEED else Constants.MISSILE_SPEED
				local change = Constants.MISSILE_SPEED_CHANGE * dt
				speed += math.clamp(wantedSpeed - speed, -change, change)
				missileSpeeds[part] = speed
				local nextPosition = position + direction * speed * dt
				part.CFrame = CFrame.fromMatrix(nextPosition, direction, Vector3.zAxis)
				part.AssemblyLinearVelocity = direction * speed
			end
		end
	end

	-- Zielstreifen, solange eine Granate aufgeladen wird
	if chargingId == "Grenade" then
		AimPreview.show(motor.position, throwAim(input), GrenadePhysics.chargeFromHold(now - chargingSince), others)
	end
end

---------------------------------------------------------------------------------------------------
-- Eingabe-Ereignisse und Start
---------------------------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if JUMP_KEYS[input.KeyCode] then
		jumpHeld = true
		motor.jumpPressedAt = os.clock()
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
		motor.jumpReleased = true
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
		motor = HeadMotor.new(if body then body.Position else Vector3.zero)
		local facing = child:GetAttribute("Facing")
		if typeof(facing) == "number" then
			motor.facing = facing
		end
		dashReadyAt = 0
		table.clear(pendingAbilities)
		chargingId = nil
		AimPreview.hide()
		print("[ClayBattle] Eigener Kopf gefunden")
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
	RunService:BindToRenderStep("ClayBattleMovement", Enum.RenderPriority.Input.Value + 1, function(dt: number)
		PlatformClient.step(dt)
		step(dt)
	end)
end

return HeadController
