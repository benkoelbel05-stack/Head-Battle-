--!strict
-- Zentrale Spielwerte. Hier wird das Spielgefühl getunt.

local Constants = {}

-- 2D-Ebene: Alle Köpfe bleiben auf dieser Z-Position.
Constants.PLANE_Z = 0

-- Kopf
Constants.HEAD_RADIUS = 1.5

-- Bewegung (Studs pro Sekunde)
Constants.MOVE_SPEED = 22
Constants.GROUND_ACCEL = 160 -- wie schnell man auf einer Fläche die Zielgeschwindigkeit erreicht
Constants.AIR_ACCEL = 90 -- weniger Kontrolle in der Luft

-- Springen (die Schwerkraft rechnet der Client selbst, Workspace.Gravity ist 0)
Constants.GRAVITY = 140
Constants.JUMP_VELOCITY = 52
Constants.JUMP_CUT_MULTIPLIER = 0.45 -- Taste früh loslassen = niedriger Sprung
Constants.MAX_FALL_SPEED = 90
Constants.COYOTE_TIME = 0.1 -- kurz nach dem Verlassen einer Fläche darf man noch springen
Constants.JUMP_BUFFER = 0.12 -- Sprung kurz vor der Landung gedrückt zählt trotzdem
Constants.WALL_JUMP_LIFT = 0.8 -- wie steil man von einer Wand nach oben abspringt

-- Haften an Boden, Wand und Decke
Constants.STICK_DISTANCE = 0.5 -- so nah muss eine Fläche sein, damit man klebt (zusätzlich zum Radius)
Constants.STICK_SPEED = 2 -- wie stark der Kopf an die Fläche gedrückt wird (klein, sonst schiebt er Plattformen weg)
Constants.DETACH_TIME = 0.15 -- nach dem Absprung so lange nicht wieder festkleben

-- Dash (Hut: Fliegerkappe)
Constants.DASH_SPEED = 80
Constants.DASH_TIME = 0.14
Constants.DASH_COOLDOWN = 3
Constants.DASH_END_KEEP = 0.4 -- so viel Schwung bleibt nach dem Dash übrig

-- Thruster (Hut 2): klebt an eine Plattform und schiebt sie von sich weg
Constants.THRUSTER_RANGE = 12 -- so weit darf die Plattform entfernt sein
Constants.THRUSTER_ACCEL = 70 -- Schub (Beschleunigung der Plattform in Studs/s²)
Constants.THRUSTER_DURATION = 2
Constants.THRUSTER_COOLDOWN = 6

-- Plattform-Physik
Constants.PLATFORM_HOME_ACCEL = 12 -- wie stark die Feder die Plattform zurück an ihren Platz zieht
Constants.PLATFORM_HOME_RESPONSIVENESS = 4
Constants.PLATFORM_HOME_ANGULAR_ACCEL = 2 -- wie stark die Feder die Drehung zurückstellt (rad/s²)
Constants.PLATFORM_LINEAR_DAMPING = 1 -- bremst Bewegung ab
Constants.PLATFORM_ANGULAR_DAMPING = 1.5 -- bremst Drehung ab

-- Ausscheiden
Constants.FALL_LIMIT_Y = -40
Constants.RESPAWN_DELAY = 2 -- nur im Prototyp; später gibt es Runden

-- Knet-Look
Constants.STOP_MOTION_FPS = 12
Constants.BOIL_AMOUNT = 0.03 -- wie stark die Form zwischen zwei Bildern "wabert"

-- Spielerfarben (Knet-Palette)
Constants.PLAYER_COLORS = {
	Color3.fromRGB(214, 110, 72), -- Terrakotta
	Color3.fromRGB(226, 182, 64), -- Senfgelb
	Color3.fromRGB(42, 122, 132), -- Petrol
	Color3.fromRGB(214, 146, 160), -- Altrosa
}
Constants.HAT_COLOR = Color3.fromRGB(120, 78, 50) -- Leder-Braun der Fliegerkappe
Constants.HAT2_COLOR = Color3.fromRGB(222, 96, 48) -- Thruster-Hut: Raketen-Orange
Constants.HAT_COOLDOWN_COLOR = Color3.fromRGB(110, 106, 102)

-- Kamera: sehr kleines Sichtfeld + großer Abstand = wirkt wie echtes 2D (fast keine Perspektive)
Constants.CAMERA_FOV = 8
Constants.CAMERA_MIN_DISTANCE = 300
Constants.CAMERA_MAX_DISTANCE = 3000
Constants.CAMERA_PADDING = 6 -- Rand um Arena und Köpfe (Studs)
Constants.CAMERA_SMOOTHNESS = 5

-- Namen im Workspace
Constants.HEADS_FOLDER = "Heads"
Constants.ARENA_FOLDER = "Arena"
Constants.REMOTES_FOLDER = "Remotes"

return Constants
