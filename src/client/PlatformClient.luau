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
local PlatformShapes = require(ReplicatedStorage.Shared.PlatformShapes)
local PlatformSim = require(ReplicatedStorage.Shared.PlatformSim)
local HeadWeight = require(ReplicatedStorage.Shared.HeadWeight)
local GrenadePhysics = require(ReplicatedStorage.Shared.GrenadePhysics)
local ThrusterVisual = require(ReplicatedStorage.Shared.ThrusterVisual)

type LocalGrenade = {
	id: string,
	part: BasePart,
	position: Vector3,
	velocity: Vector3,
	explodeAt: number,
}

local PlatformClient = {}

local player = Players.LocalPlayer
local sim = PlatformSim.new()
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
local function explosionEffect(position: Vector3)
	local blob = makeEffectPart("Blast", Vector3.one, Color3.fromRGB(255, 196, 92), position)
	local tween = TweenService:Create(
		blob,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * Constants.GRENADE_BLAST_RADIUS * 2, Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Once(function()
		blob:Destroy()
	end)
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
	grenades[id] = {
		id = id,
		part = part,
		position = start,
		velocity = velocity,
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
	elseif kind == "Explosion" then
		local id, position = ...
		if typeof(id) == "string" and typeof(position) == "Vector3" then
			knownExplosions[id] = true
			local grenade = grenades[id]
			if grenade then
				-- Lokale Granate fliegt noch: jetzt an der Server-Stelle explodieren lassen
				grenade.part:Destroy()
				grenades[id] = nil
			end
			explosionEffect(position)
			GrenadePhysics.applyExplosion(sim, PlatformShapes.collect(arena), position)
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
	snapshot.OnClientEvent:Connect(function(data: unknown)
		PlatformSim.correct(sim, data, Constants.SNAPSHOT_BLEND)
	end)
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
	PlatformSim.apply(sim)

	-- Granaten fliegen lassen; bei Zündung verschwinden sie (die Explosion kommt vom Server)
	for id, grenade in grenades do
		if now >= grenade.explodeAt + 0.5 or grenade.position.Y < Constants.FALL_LIMIT_Y then
			grenade.part:Destroy()
			grenades[id] = nil
		elseif now < grenade.explodeAt then
			grenade.position, grenade.velocity = GrenadePhysics.step(grenade.position, grenade.velocity, dt, shapes)
			grenade.part.CFrame = CFrame.new(grenade.position)
		end
	end
end

return PlatformClient
