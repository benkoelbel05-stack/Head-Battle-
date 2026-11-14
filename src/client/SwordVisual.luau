--!strict
-- Optik eines Schwertschlags: eine Klinge schwingt im Bogen um den Kopf und verblasst.
-- Wird für den eigenen Schlag sofort gezeigt und für fremde Schläge, wenn der Server sie meldet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SwordVisual = {}

local function makePart(name: string, size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

-- origin = Kopf-Mittelpunkt, direction = Schlagrichtung
function SwordVisual.play(origin: Vector3, direction: Vector3)
	local range = Constants.SWORD_RANGE
	local arc = math.rad(Constants.SWORD_ARC)
	local center = math.atan2(direction.Y, direction.X)
	-- Von oben nach unten schwingen (bei Blick nach links gespiegelt, damit es natürlich aussieht)
	local sweep = if direction.X >= 0 then -1 else 1
	local startAngle = center - sweep * arc
	local pivot = Vector3.new(origin.X, origin.Y, Constants.SPRITE_Z + 0.2)

	local blade = makePart("SwordBlade", Vector3.new(range - 1, 0.35, 0.1), Constants.SWORD_COLOR, 0)
	local hilt = makePart("SwordHilt", Vector3.new(0.9, 0.55, 0.12), Color3.fromRGB(120, 78, 50), 0)
	local trail = makePart("SwordTrail", Vector3.new(range, 0.9, 0.05), Color3.new(1, 1, 1), 0.6)

	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / Constants.SWORD_SWING_TIME
		local swingT = math.clamp(t, 0, 1)
		local eased = 1 - (1 - swingT) ^ 2 -- schnell rein, weich aus
		local angle = startAngle + sweep * 2 * arc * eased
		local rotation = CFrame.new(pivot) * CFrame.Angles(0, 0, angle)
		blade.CFrame = rotation * CFrame.new(1 + (range - 1) / 2, 0, 0)
		hilt.CFrame = rotation * CFrame.new(0.8, 0, 0.02)
		-- Wischspur etwas hinter der Klinge
		trail.CFrame = CFrame.new(pivot) * CFrame.Angles(0, 0, angle - sweep * 0.35) * CFrame.new(range / 2, 0, -0.05)

		-- Nach dem Schwung kurz ausblenden
		local fade = math.clamp((t - 1) / 0.6, 0, 1)
		blade.Transparency = fade
		hilt.Transparency = fade
		trail.Transparency = 0.6 + 0.4 * math.clamp(t / 1.2, 0, 1)
		if t >= 1.6 then
			connection:Disconnect()
			blade:Destroy()
			hilt:Destroy()
			trail:Destroy()
		end
	end)
end

return SwordVisual
