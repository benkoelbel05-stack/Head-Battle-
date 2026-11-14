--!strict
-- Anzeige der 3 ausgerüsteten Fähigkeiten unten in der Mitte:
-- Kleidungsstück, Taste (Maus) und Abklingzeit als sich leerender Balken mit Sekunden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local UIStyle = require(script.Parent.UIStyle)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)

local AbilityHUD = {}

local FONT = Enum.Font.FredokaOne
local TEXT_COLOR = Color3.fromRGB(255, 244, 226)
local PANEL_COLOR = Color3.fromRGB(58, 48, 44)
local KEY_NAMES = { "Linke Maus", "Mausrad", "Rechte Maus" }

type SlotView = {
	frame: Frame,
	icon: ImageLabel,
	name: TextLabel,
	key: TextLabel,
	cooldown: Frame,
	seconds: TextLabel,
}

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Size = size
	text.Position = position
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextSize = textSize
	text.TextColor3 = TEXT_COLOR
	text.Text = ""
	text.ZIndex = 3
	text.Parent = parent
	return text
end

local function makeSlot(parent: Instance, index: number): SlotView
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(150, 70)
	frame.LayoutOrder = index
	UIStyle.panel(frame)

	-- Farbbalken des Kleidungsstücks oben
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.new(1, -16, 0, 6)
	stripe.Position = UDim2.fromOffset(8, 6)
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 2
	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(1, 0)
	stripeCorner.Parent = stripe
	stripe.Parent = frame

	-- Symbol links, Name und Taste rechts daneben
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(42, 42)
	icon.Position = UDim2.fromOffset(6, 18)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 3
	icon.Parent = frame
	local name = label(frame, UDim2.new(1, -56, 0, 26), UDim2.fromOffset(50, 16), 18)
	name.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MaxTextSize = 18
	nameLimit.Parent = name
	local key = label(frame, UDim2.new(1, -56, 0, 20), UDim2.fromOffset(50, 44), 14)
	key.TextTransparency = 0.35

	-- Abklingzeit: dunkle Fläche, die von oben nach unten schrumpft
	local cooldown = Instance.new("Frame")
	cooldown.AnchorPoint = Vector2.new(0, 1)
	cooldown.Position = UDim2.fromScale(0, 1)
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = 0.45
	cooldown.ZIndex = 4
	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = UDim.new(0, 14)
	cooldownCorner.Parent = cooldown
	cooldown.Parent = frame

	local seconds = label(frame, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 30)
	seconds.ZIndex = 5

	frame.Parent = parent
	return { frame = frame, icon = icon, name = name, key = key, cooldown = cooldown, seconds = seconds }
end

local function findOwnHead(): Model?
	local headsFolder = Workspace:FindFirstChild(Constants.HEADS_FOLDER)
	if not headsFolder then
		return nil
	end
	local userId = Players.LocalPlayer.UserId
	for _, head in headsFolder:GetChildren() do
		if head:GetAttribute("UserId") == userId then
			return head :: Model
		end
	end
	return nil
end

function AbilityHUD.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleAbilities"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.fromOffset(3 * 150 + 2 * 10, 70)
	bar.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	bar.Parent = gui

	local slots: { SlotView } = {}
	for index = 1, Abilities.MAX_SLOTS do
		table.insert(slots, makeSlot(bar, index))
	end

	while true do
		local head = findOwnHead()
		bar.Visible = head ~= nil
		if head then
			local loadout = Abilities.parseLoadout(head:GetAttribute("Loadout"))
			local now = Workspace:GetServerTimeNow()
			for index, view in slots do
				local id = loadout[index]
				local info = if id then Abilities.list[id] else nil
				view.frame.Visible = info ~= nil
				if info then
					view.name.Text = info.label
					local iconId = AbilityIcons[info.id]
					view.icon.Image = if iconId and iconId ~= 0 then `rbxassetid://{iconId}` else ""
					view.key.Text = KEY_NAMES[index] or ""
					local stripe = view.frame:FindFirstChild("Stripe") :: Frame
					stripe.BackgroundColor3 = info.color

					local readyAt = head:GetAttribute(Abilities.readyAttribute(info.id))
					local remaining = if typeof(readyAt) == "number" then math.max(readyAt - now, 0) else 0
					local fraction = math.clamp(remaining / info.cooldown, 0, 1)
					view.cooldown.Size = UDim2.fromScale(1, fraction)
					view.seconds.Text = if remaining > 0 then string.format("%.1f", remaining) else ""
				end
			end
		end
		task.wait(0.05)
	end
end

return AbilityHUD
