--!strict
-- Runtime for individual transparent PNG frames uploaded as Image assets.
-- No Decal objects. If a sequence has zero/unapproved IDs, callers keep
-- using the procedural fallback in ItemAnimations.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local IDs = require(ReplicatedStorage.Shared.ItemSpriteIds)
local Constants = require(ReplicatedStorage.Shared.Constants)

local ItemSpriteOverlay = {}
local FPS: { [string]: number } = {
	grenade_spin = 10, grenade_explosion = 12,
	thruster_burst = 12, sword_swing = 15,
	missile_flight = 10, dash_burst = 14,
}
local LOOPS: { [string]: boolean } = {
	grenade_spin = true, thruster_burst = true, missile_flight = true,
}
local active: { [BasePart]: boolean } = {}

local function valid(seq: string): boolean
	local frames: { number }? = IDs[seq]
	if not frames or #frames ~= 8 then return false end
	for _, id in frames do
		if typeof(id) ~= "number" or id <= 0 then return false end
	end
	return true
end
function ItemSpriteOverlay.has(seq: string): boolean return valid(seq) end

local function buildImage(part: BasePart, size: number): (BillboardGui, ImageLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClayItemSprite"
	gui.Adornee = part
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(size, size)
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.Name = "Frame"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.ImageTransparency = 0
	image.Parent = gui
	return gui, image
end

local function animate(part: BasePart, seq: string, size: number, angleFromPart: boolean): boolean
	if not valid(seq) then return false end
	if active[part] then return true end
	active[part] = true
	local frames: { number } = IDs[seq]
	local gui, image = buildImage(part, size)
	local elapsed = 0
	local fps = FPS[seq] or 12
	local looping = LOOPS[seq] == true
	local connection: RBXScriptConnection?
	local died: RBXScriptConnection?
	local function cleanup()
		if connection then connection:Disconnect(); connection = nil end
		if died then died:Disconnect(); died = nil end
		active[part] = nil
		if gui.Parent then gui:Destroy() end
	end
	died = part.Destroying:Connect(cleanup)
	image.Image = "rbxassetid://" .. tostring(frames[1])
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not part.Parent then cleanup(); return end
		elapsed += math.min(dt, 0.1)
		local index = math.floor(elapsed * fps) + 1
		if looping then
			index = ((index - 1) % #frames) + 1
		elseif index > #frames then
			cleanup()
			return
		end
		local uri = "rbxassetid://" .. tostring(frames[index])
		if image.Image ~= uri then image.Image = uri end
		if angleFromPart then
			-- The original missile art points about 35 degrees above horizontal.
			-- Frame.Rotation increases clockwise; horizontal right is 0.
			local v = part.CFrame.RightVector
			image.Rotation = 35 - math.deg(math.atan2(v.Y, v.X))
		end
	end)
	return true
end

function ItemSpriteOverlay.attach(part: BasePart, seq: string, size: number, angleFromPart: boolean?): boolean
	return animate(part, seq, size, angleFromPart == true)
end

function ItemSpriteOverlay.burst(position: Vector3, seq: string, size: number, rotationDegrees: number?): boolean
	if not valid(seq) then return false end
	local anchor = Instance.new("Part")
	anchor.Name = "ClayItemEffectAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = Vector3.new(position.X, position.Y, Constants.SPRITE_Z + 1.9)
	anchor.Parent = Workspace
	local success = animate(anchor, seq, size, false)
	if success and rotationDegrees then
		local sprite = anchor:FindFirstChild("ClayItemSprite")
		local image = sprite and sprite:FindFirstChild("Frame")
		if image and image:IsA("ImageLabel") then image.Rotation = rotationDegrees end
	end
	Debris:AddItem(anchor, 8 / (FPS[seq] or 12) + 0.12)
	return success
end

return ItemSpriteOverlay