--!strict
-- Physik für die Plattformen:
--   * Plattformen schweben (Workspace.Gravity = 0) und lassen sich durch Kräfte (z. B. Thruster) bewegen
--   * Sie bleiben in der 2D-Ebene und drehen sich nur um die Kamera-Achse (Z)
--   * Eine weiche Feder zieht sie langsam an ihren Platz zurück
--   * Bewegung und Drehung werden gedämpft, damit nichts ewig weitertreibt
-- Der Server rechnet die Plattformen (Network Owner = Server), damit alle Spieler dasselbe sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

type PlatformInfo = {
	root: BasePart,
	home: CFrame,
}

local PlatformPhysics = {}

local platforms: { PlatformInfo } = {}

-- Muss aufgerufen werden, nachdem die Plattform im Workspace ist.
function PlatformPhysics.register(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end

	root:SetNetworkOwner(nil) -- Server rechnet, nicht der Spieler, der gerade darauf steht

	local home = root.CFrame
	local mass = root.AssemblyMass
	local size = model:GetExtentsSize()
	local inertia = mass * (size.X ^ 2 + size.Y ^ 2) / 12 -- Trägheit einer Platte, grob

	local attachment = Instance.new("Attachment")
	attachment.Name = "HomeAttachment"
	attachment.Parent = root

	-- Feder zurück zur Startposition (mit begrenzter Kraft, damit Thruster stärker sind)
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.Position = home.Position
	alignPosition.MaxForce = mass * Constants.PLATFORM_HOME_ACCEL
	alignPosition.Responsiveness = Constants.PLATFORM_HOME_RESPONSIVENESS
	alignPosition.Parent = root

	-- Feder zurück zur Startdrehung
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.CFrame = home.Rotation
	alignOrientation.MaxTorque = inertia * Constants.PLATFORM_HOME_ANGULAR_ACCEL
	alignOrientation.Responsiveness = Constants.PLATFORM_HOME_RESPONSIVENESS
	alignOrientation.Parent = root

	table.insert(platforms, { root = root, home = home })
end

function PlatformPhysics.clear()
	table.clear(platforms)
end

-- Jeden Frame: dämpfen und in der 2D-Ebene halten
function PlatformPhysics.step(dt: number)
	local linearKeep = math.exp(-Constants.PLATFORM_LINEAR_DAMPING * dt)
	local angularKeep = math.exp(-Constants.PLATFORM_ANGULAR_DAMPING * dt)

	for _, info in platforms do
		local root = info.root
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			local w = root.AssemblyAngularVelocity

			-- Nur eingreifen, wenn sich die Plattform bewegt. Ruhende Plattformen nicht anfassen,
			-- sonst wird die Roblox-Physik ständig geweckt und die Plattformen zittern.
			if v.Magnitude > 0.05 or w.Magnitude > 0.005 then
				root.AssemblyLinearVelocity = Vector3.new(v.X * linearKeep, v.Y * linearKeep, 0)
				root.AssemblyAngularVelocity = Vector3.new(0, 0, w.Z * angularKeep)
			end

			-- Größere Abweichung aus der Ebene korrigieren (nur Drehung um Z ist erlaubt)
			local cframe = root.CFrame
			local relative = info.home.Rotation:ToObjectSpace(cframe.Rotation)
			local tilted = math.abs(relative.LookVector.Z + 1) > 0.002 -- LookVector sollte (0, 0, -1) bleiben
			if tilted or math.abs(cframe.Z - Constants.PLANE_Z) > 0.05 then
				local right = relative.RightVector
				local angle = math.atan2(right.Y, right.X)
				root.CFrame = CFrame.new(cframe.X, cframe.Y, Constants.PLANE_Z)
					* info.home.Rotation
					* CFrame.Angles(0, 0, angle)
			end
		end
	end
end

return PlatformPhysics
