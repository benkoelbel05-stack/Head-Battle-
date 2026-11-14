--!strict
-- Fähigkeiten schweben wie in Bopl Battle als drei runde Symbole im Bogen über jeder Figur
-- (Slot 1 links, Slot 2 oben, Slot 3 rechts). Über der eigenen Figur zeigt zusätzlich ein kleiner,
-- leicht durchsichtiger Pfeil, wer man selbst ist. Während der Abklingzeit liegt ein dunkler Kreis über
-- dem Symbol, der zur Mitte hin schrumpft.
-- Wer im Match die meisten Runden gewonnen hat (allein vorne, mindestens 1 Punkt), trägt eine Krone
-- auf dem Kopf.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)
local UIAssets = require(ReplicatedStorage.Shared.UIAssets)
local Settings = require(script.Parent.Settings)
local TweenService = game:GetService("TweenService")

local AbilityBubbles = {}

local BUBBLE_SIZE = 2.1 -- Durchmesser eines Symbols in Studs
-- Bogen über dem Kopf (Studs, von der Kopfmitte aus, immer "oben" in der Welt)
local OFFSETS = {
	Vector2.new(-2.3, 3.45),
	Vector2.new(0, 4.45),
	Vector2.new(2.3, 3.45),
}
-- Pfeil über der eigenen Figur (über dem Bogen)
local ARROW_SIZE = 1.1
local ARROW_HEIGHT = 4.45 + BUBBLE_SIZE / 2 + 0.85
local OUTLINE = Color3.fromRGB(34, 26, 40)
-- Krone des Führenden: sitzt leicht schräg auf dem Kopf, unter dem mittleren Symbol
local CROWN_SIZE = 1.45
local CROWN_HEIGHT = 2.6 -- Mitte der Krone über der Kopfmitte (Figur ist etwas größer als der Kopf-Radius 1,5)
local CROWN_TILT = -12

type Bubble = { group: Frame, cooldown: Frame, emoji: TextLabel, image: ImageLabel, ring: UIStroke, id: string?, fraction: number }
type View = { gui: BillboardGui, bubbles: { Bubble }, loadout: string, arrow: BillboardGui?, crown: BillboardGui? }

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
		-- Das Abzeichen hat im Bild einen durchsichtigen Rand: etwas größer, damit es den Kreis füllt
		bubble.image.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.image.Size = UDim2.fromScale(1.2, 1.2)
		bubble.image.Position = UDim2.fromScale(0.5, 0.5)
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

	-- Kleiner Pfeil nach unten in der eigenen Farbe
	local function makeArrow(head: Model, body: BasePart): BillboardGui
		local arrow = Instance.new("BillboardGui")
		arrow.Name = "OwnArrow"
		arrow.Adornee = body
		arrow.Size = UDim2.fromScale(ARROW_SIZE, ARROW_SIZE)
		arrow.StudsOffsetWorldSpace = Vector3.new(0, ARROW_HEIGHT, 0)
		arrow.AlwaysOnTop = true
		arrow.LightInfluence = 0
		arrow.ResetOnSpawn = false
		arrow.MaxDistance = 1e6
		arrow.Parent = container
		local skin = head:GetAttribute("Skin")
		local color = Color3.fromRGB(255, 255, 255)
		for _, entry in Constants.SKINS do
			if entry.key == skin then
				color = entry.color
			end
		end
		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.FredokaOne
		glyph.Text = "▼"
		glyph.TextScaled = true
		glyph.TextColor3 = color
		glyph.TextTransparency = 0.3
		glyph.TextStrokeColor3 = OUTLINE
		glyph.TextStrokeTransparency = 0.5
		glyph.Parent = arrow
		return arrow
	end

	-- Krone über dem Führenden (Bild noch nicht da: keine Krone)
	local function makeCrown(body: BasePart): BillboardGui
		local crown = Instance.new("BillboardGui")
		crown.Name = "LeaderCrown"
		crown.Adornee = body
		crown.Size = UDim2.fromScale(CROWN_SIZE, CROWN_SIZE)
		crown.StudsOffsetWorldSpace = Vector3.new(0, CROWN_HEIGHT, 0)
		crown.AlwaysOnTop = true
		crown.LightInfluence = 0
		crown.ResetOnSpawn = false
		crown.MaxDistance = 1e6
		crown.Enabled = false
		crown.Parent = container
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = `rbxassetid://{UIAssets.icon_crown}`
		image.Rotation = CROWN_TILT
		image.Parent = crown
		local scale = Instance.new("UIScale")
		scale.Parent = image
		return crown
	end

	-- Schlüssel einer Figur wie in RoundState.Scores: Bot-Name oder UserId als Text
	local function keyOf(head: Model): string?
		local botId = head:GetAttribute("BotId")
		if typeof(botId) == "string" then
			return botId
		end
		local userId = head:GetAttribute("UserId")
		return if typeof(userId) == "number" then tostring(userId) else nil
	end

	-- Wer liegt allein vorne (mindestens 1 gewonnene Runde)?
	local function leaderKey(): string?
		local state = ReplicatedStorage:FindFirstChild(Constants.ROUND_STATE)
		local scores = state and state:FindFirstChild("Scores")
		if not scores then
			return nil
		end
		local best, bestKey, tied = 0, nil :: string?, false
		for _, entry in scores:GetChildren() do
			if entry:IsA("IntValue") then
				if entry.Value > best then
					best, bestKey, tied = entry.Value, entry.Name, false
				elseif entry.Value == best and best > 0 then
					tied = true
				end
			end
		end
		return if tied then nil else bestKey
	end

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for head, view in views do
			if not head.Parent then
				view.gui:Destroy()
				if view.arrow then
					view.arrow:Destroy()
				end
				if view.crown then
					view.crown:Destroy()
				end
				views[head] = nil
			end
		end
		local leader = if UIAssets.icon_crown ~= 0 then leaderKey() else nil
		-- Optionen: Symbole über allen / nur über mir / aus; Pfeil über mir ein/aus
		local bubbleMode = Settings.get("bubbles")
		local showArrow = Settings.get("ownArrow") == true
		for _, child in headsFolder:GetChildren() do
			local body = if child:IsA("Model") then child.PrimaryPart else nil
			if child:IsA("Model") and body then
				local view = views[child]
				if not view then
					view = build(child, body, container)
					if child:GetAttribute("UserId") == player.UserId then
						view.arrow = makeArrow(child, body)
					end
					views[child] = view
				end
				local own = view.arrow ~= nil
				local bubblesOn = bubbleMode == "Alle" or (bubbleMode == "Nur eigene" and own)
				if view.gui.Enabled ~= bubblesOn then
					view.gui.Enabled = bubblesOn
				end
				local arrow = view.arrow
				if arrow and arrow.Enabled ~= showArrow then
					arrow.Enabled = showArrow
				end
				-- Krone: nur beim alleinigen Führenden, mit kleinem Aufploppen beim Erscheinen
				local wearsCrown = leader ~= nil and keyOf(child) == leader
				if wearsCrown and not view.crown then
					view.crown = makeCrown(body)
				end
				local crown = view.crown
				if crown and crown.Enabled ~= wearsCrown then
					crown.Enabled = wearsCrown
					if wearsCrown then
						local icon = crown:FindFirstChild("Icon")
						local scale = if icon then icon:FindFirstChildOfClass("UIScale") else nil
						if scale then
							scale.Scale = 0.2
							TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
						end
					end
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
