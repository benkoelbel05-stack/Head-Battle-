--!strict
-- Fähigkeiten schweben wie in Bopl Battle als drei runde Symbole im Bogen über jeder Figur
-- (Slot 1 links, Slot 2 oben, Slot 3 rechts). Während der Abklingzeit liegt ein dunkler Kreis über
-- dem Symbol, der zur Mitte hin schrumpft.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)

local AbilityBubbles = {}

local BUBBLE_SIZE = 1.5 -- Durchmesser eines Symbols in Studs
-- Bogen über dem Kopf (Studs, von der Kopfmitte aus, immer "oben" in der Welt)
local OFFSETS = {
	Vector2.new(-1.75, 2.75),
	Vector2.new(0, 3.55),
	Vector2.new(1.75, 2.75),
}
local OUTLINE = Color3.fromRGB(34, 26, 40)

type Bubble = { group: Frame, cooldown: Frame, emoji: TextLabel, image: ImageLabel, ring: UIStroke, id: string?, fraction: number }
type View = { gui: BillboardGui, bubbles: { Bubble }, loadout: string }

local function makeBubble(parent: Instance, index: number): Bubble
	-- Position im Billboard: Mitte bei (BUBBLE/2 + Versatz) relativ zur Fläche
	local holder = Instance.new("Frame")
	holder.Name = `Slot{index}`
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	-- Einfache Frames statt CanvasGroup (die wäre pro Symbol ein eigenes, teures Zwischenbild)
	local group = Instance.new("Frame")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundColor3 = Color3.new(1, 1, 1)
	group.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = group

	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(0.86, 0.86)
	image.Position = UDim2.fromScale(0.07, 0.07)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = group

	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.TextScaled = true
	emoji.Font = Enum.Font.FredokaOne
	emoji.Parent = group

	local cooldown = Instance.new("Frame")
	cooldown.AnchorPoint = Vector2.new(0.5, 0.5)
	cooldown.Position = UDim2.fromScale(0.5, 0.5)
	cooldown.Size = UDim2.fromScale(0, 0)
	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = UDim.new(0.5, 0)
	cooldownCorner.Parent = cooldown
	cooldown.BackgroundColor3 = Color3.fromRGB(20, 14, 30)
	cooldown.BackgroundTransparency = 0.35
	cooldown.BorderSizePixel = 0
	cooldown.ZIndex = 3
	cooldown.Parent = group

	-- Kontur außen (an einem Rahmen ohne Clipping, damit sie ganz sichtbar ist)
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 4
	ring.Parent = holder
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2
	stroke.Parent = ring

	return { group = group, cooldown = cooldown, emoji = emoji, image = image, ring = stroke, id = nil, fraction = 0 }
end

local function build(head: Model, body: BasePart, container: Instance): View
	-- Fläche, die alle drei Symbole umfasst
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, offset in OFFSETS do
		minX, maxX = math.min(minX, offset.X), math.max(maxX, offset.X)
		minY, maxY = math.min(minY, offset.Y), math.max(maxY, offset.Y)
	end
	local width = maxX - minX + BUBBLE_SIZE + 0.2
	local height = maxY - minY + BUBBLE_SIZE + 0.2
	local centerX, centerY = (minX + maxX) / 2, (minY + maxY) / 2

	local gui = Instance.new("BillboardGui")
	gui.Name = `Bubbles_{head.Name}`
	gui.Adornee = body
	gui.Size = UDim2.fromScale(width, height) -- in Studs: wächst und schrumpft mit dem Zoom
	gui.StudsOffsetWorldSpace = Vector3.new(centerX, centerY, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.MaxDistance = 1e6
	gui.Parent = container

	local bubbles = {}
	for index, offset in OFFSETS do
		local bubble = makeBubble(gui, index)
		local holder = bubble.group.Parent :: Frame
		holder.Size = UDim2.fromScale(BUBBLE_SIZE / width, BUBBLE_SIZE / height)
		holder.Position = UDim2.fromScale(
			(offset.X - centerX) / width + 0.5,
			0.5 - (offset.Y - centerY) / height
		)
		bubbles[index] = bubble
	end
	return { gui = gui, bubbles = bubbles, loadout = "" }
end

local function setAbility(bubble: Bubble, id: string?)
	bubble.id = id
	local holder = bubble.group.Parent :: Frame
	local info = if id then Abilities.list[id] else nil
	holder.Visible = info ~= nil
	if not info or not id then
		return
	end
	bubble.group.BackgroundColor3 = info.color:Lerp(Color3.new(1, 1, 1), 0.25)
	local imageId = AbilityIcons[id]
	if imageId and imageId ~= 0 then
		-- Fertiges Abzeichen: eigener Hintergrund und Rand, also nur das Bild zeigen
		bubble.image.Image = `rbxassetid://{imageId}`
		bubble.image.Size = UDim2.fromScale(1, 1)
		bubble.image.Position = UDim2.fromScale(0, 0)
		bubble.image.Visible = true
		bubble.emoji.Visible = false
		bubble.group.BackgroundTransparency = 1
		bubble.ring.Enabled = false
	else
		bubble.image.Visible = false
		bubble.emoji.Visible = true
		bubble.emoji.Text = info.icon
		bubble.group.BackgroundTransparency = 0
		bubble.ring.Enabled = true
	end
end

function AbilityBubbles.start()
	local player = Players.LocalPlayer
	local container = Instance.new("Folder")
	container.Name = "ClayBattleAbilityBubbles"
	container.Parent = player:WaitForChild("PlayerGui")
	local headsFolder = Workspace:WaitForChild(Constants.HEADS_FOLDER)
	local views: { [Model]: View } = {}

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for head, view in views do
			if not head.Parent then
				view.gui:Destroy()
				views[head] = nil
			end
		end
		for _, child in headsFolder:GetChildren() do
			local body = if child:IsA("Model") then child.PrimaryPart else nil
			if child:IsA("Model") and body then
				local view = views[child]
				if not view then
					view = build(child, body, container)
					views[child] = view
				end
				local loadoutText = child:GetAttribute("Loadout")
				local key = if typeof(loadoutText) == "string" then loadoutText else ""
				if key ~= view.loadout then
					view.loadout = key
					local loadout = Abilities.parseLoadout(loadoutText)
					for index, bubble in view.bubbles do
						setAbility(bubble, loadout[index])
					end
				end
				for _, bubble in view.bubbles do
					local id = bubble.id
					if id then
						local readyAt = child:GetAttribute(Abilities.readyAttribute(id))
						local remaining = if typeof(readyAt) == "number" then readyAt - now else 0
						local total = Abilities.list[id].cooldown
						local fraction = if remaining > 0 and total > 0 then math.clamp(remaining / total, 0, 1) else 0
						-- Nur bei sichtbarer Änderung setzen
						if math.abs(fraction - bubble.fraction) > 0.01 or (fraction == 0) ~= (bubble.fraction == 0) then
							bubble.fraction = fraction
							bubble.cooldown.Size = UDim2.fromScale(fraction, fraction)
						end
					end
				end
			end
		end
	end)
end

return AbilityBubbles
