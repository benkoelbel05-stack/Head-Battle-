--!strict
-- Kleine Anzeige oben links: Bilder pro Sekunde und Ping. Ein-/ausschaltbar in den Optionen
-- (Grafik -> "FPS und Ping anzeigen"). Wird zweimal pro Sekunde aktualisiert.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Settings)

local StatsDisplay = {}

local UPDATE_EVERY = 0.5

function StatsDisplay.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClayBattleStats"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = Settings.get("showStats") == true
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(14, 6)
	label.Size = UDim2.fromOffset(170, 26)
	label.BackgroundColor3 = Color3.fromRGB(40, 24, 64)
	label.BackgroundTransparency = 0.35
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 242, 219)
	label.Text = "– FPS · – ms"
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label

	Settings.changed:Connect(function(name: string, value: any)
		if name == "showStats" then
			gui.Enabled = value == true
		end
	end)

	local frames, elapsed = 0, 0
	RunService.RenderStepped:Connect(function(dt: number)
		if not gui.Enabled then
			frames, elapsed = 0, 0
			return
		end
		frames += 1
		elapsed += dt
		if elapsed >= UPDATE_EVERY then
			local fps = math.floor(frames / elapsed + 0.5)
			local ping = math.floor(player:GetNetworkPing() * 1000 + 0.5)
			label.Text = `{fps} FPS · {ping} ms`
			frames, elapsed = 0, 0
		end
	end)
end

return StatsDisplay
