--!strict
-- Zentrale Spielwerte. Hier wird das Spielgefühl getunt.

local Constants = {}

-- 2D-Ebene: Alle Köpfe bleiben auf dieser Z-Position.
Constants.PLANE_Z = 0

-- Kopf
Constants.HEAD_RADIUS = 1.5

-- Bewegung (Studs pro Sekunde)
Constants.MOVE_SPEED = 22
Constants.GROUND_ACCEL = 160 -- wie schnell man am Boden die Zielgeschwindigkeit erreicht
Constants.AIR_ACCEL = 90 -- weniger Kontrolle in der Luft

-- Springen
Constants.GRAVITY = 140
Constants.JUMP_VELOCITY = 52
Constants.JUMP_CUT_MULTIPLIER = 0.45 -- Taste früh loslassen = niedriger Sprung
Constants.MAX_FALL_SPEED = 90
Constants.COYOTE_TIME = 0.1 -- kurz nach dem Verlassen einer Kante darf man noch springen
Constants.JUMP_BUFFER = 0.12 -- Sprung kurz vor der Landung gedrückt zählt trotzdem

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

-- Kamera
-- Kleines Sichtfeld + großer Abstand = fast flaches 2D-Bild ohne starke Perspektive
Constants.CAMERA_FOV = 18
Constants.CAMERA_MIN_DISTANCE = 120
Constants.CAMERA_MAX_DISTANCE = 400
Constants.CAMERA_PADDING = 6 -- Rand um Arena und Köpfe (Studs)
Constants.CAMERA_SMOOTHNESS = 5

-- Namen im Workspace
Constants.HEADS_FOLDER = "Heads"
Constants.ARENA_FOLDER = "Arena"

return Constants
