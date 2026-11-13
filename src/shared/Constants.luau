--!strict
-- Zentrale Spielwerte. Hier wird das Spielgefühl getunt.

local Constants = {}

-- 2D-Ebene: Alle Köpfe bleiben auf dieser Z-Position.
Constants.PLANE_Z = 0

-- Kopf
Constants.HEAD_RADIUS = 1.5

-- Bewegung (Studs pro Sekunde)
Constants.MOVE_SPEED = 22
Constants.GROUND_ACCEL = 140 -- wie schnell man auf einer Fläche die Zielgeschwindigkeit erreicht
Constants.GROUND_FRICTION = 90 -- wie schnell man ohne Eingabe auf einer Fläche abbremst (gleiten)
Constants.AIR_ACCEL = 90 -- weniger Kontrolle in der Luft
Constants.LANDING_KEEP = 0.85 -- so viel vom Schwung entlang der Fläche bleibt beim Landen erhalten

-- Springen (die Schwerkraft rechnet der Client selbst, Workspace.Gravity ist 0)
Constants.GRAVITY = 140
Constants.JUMP_VELOCITY = 52
Constants.JUMP_CUT_MULTIPLIER = 0.45 -- Taste früh loslassen = niedriger Sprung
Constants.JUMP_KEEP_ALONG = 0.6 -- so viel Laufgeschwindigkeit nimmt man in den Sprung mit
Constants.MAX_FALL_SPEED = 90
Constants.JUMP_BUFFER = 0.12 -- Sprung kurz vor der Landung gedrückt zählt trotzdem
Constants.WALL_JUMP_LIFT = 0.8 -- wie steil man von einer Wand nach oben abspringt
Constants.DETACH_TIME = 0.12 -- nach dem Absprung so lange nicht wieder festkleben

-- Dash (Fliegerkappe)
Constants.DASH_SPEED = 80
Constants.DASH_TIME = 0.14
Constants.DASH_COOLDOWN = 3
Constants.DASH_END_KEEP = 0.4 -- so viel Schwung bleibt nach dem Dash übrig

-- Thruster (Schweißerbrille): klebt an eine Plattform und schiebt sie von sich weg
Constants.THRUSTER_RANGE = 12 -- so weit darf die Plattform entfernt sein
Constants.THRUSTER_FORCE = 2000 -- Schubkraft; Beschleunigung = Kraft / Masse der Plattform
Constants.THRUSTER_DURATION = 2
Constants.THRUSTER_RAMP = 0.2 -- Sekunden, in denen der Schub weich an- und ausläuft
Constants.THRUSTER_COOLDOWN = 6
Constants.THRUSTER_COLOR = Color3.fromRGB(222, 96, 48)

-- Granate (Granatengürtel)
Constants.GRENADE_MIN_SPEED = 18 -- Wurfgeschwindigkeit bei kurzem Antippen
Constants.GRENADE_SPEED = 62 -- Wurfgeschwindigkeit voll aufgeladen
Constants.GRENADE_CHARGE_TIME = 0.9 -- so lange halten = volle Wurfkraft
Constants.GRENADE_UPWARD = 0.35 -- leicht nach oben werfen, damit sie im Bogen fliegt
Constants.GRENADE_GRAVITY = 120
Constants.GRENADE_RADIUS = 0.7
Constants.GRENADE_BOUNCE = 0.45 -- wie stark sie abprallt (0 = gar nicht, 1 = voll)
Constants.GRENADE_FUSE = 1.6 -- Sekunden bis zur Explosion (oder früher, wenn sie einen Kopf trifft)
Constants.GRENADE_OWNER_GRACE = 0.3 -- so lange nach dem Wurf trifft die Granate den Werfer selbst nicht
Constants.GRENADE_BLAST_RADIUS = 7 -- Köpfe in diesem Radius scheiden aus
Constants.GRENADE_PUSH_RADIUS = 14 -- Plattformen in diesem Radius werden weggestoßen
Constants.GRENADE_IMPULSE = 800 -- Stoß auf Plattformen; Geschwindigkeitsänderung = Stoß / Masse (nimmt mit Abstand ab)
Constants.GRENADE_COOLDOWN = 5
Constants.GRENADE_COLOR = Color3.fromRGB(86, 104, 62)

-- Plattform-Physik (eigene Feder, siehe PlatformSim.luau)
-- Masse einer Plattform = Fläche (Studs²) * Dichte. Schwere Plattformen bewegen und drehen sich weniger.
-- Bezug: eine Plattform 14 x 2 hat Masse ~28; die Kräfte sind darauf abgestimmt.
-- Gleichgewicht unter vollem Schub: THRUSTER_FORCE / (Masse * PLATFORM_SPRING) Studs vom Startplatz
Constants.PLATFORM_DENSITY = 1 -- Standard-Dichte (im Arena-Layout pro Plattform änderbar)
Constants.PLATFORM_SPRING = 6 -- wie stark die Plattform zum Startplatz zurückgezogen wird
Constants.PLATFORM_DAMPING = 5 -- Bremse; ca. 2 * Wurzel(SPRING) = zurückfedern ohne Nachwackeln
Constants.PLATFORM_MAX_OFFSET = 12 -- weiter als so viele Studs entfernt sich eine Plattform nie
Constants.PLATFORM_ANGULAR_SPRING = 10
Constants.PLATFORM_ANGULAR_DAMPING = 6.3
Constants.PLATFORM_MAX_ANGLE = math.rad(60) -- stärker kippt eine Plattform nie

-- Netzwerk-Abgleich der Plattformen (jeder Rechner simuliert selbst, der Server gleicht ab)
Constants.SIM_RATE = 120 -- feste Physik-Schritte pro Sekunde
Constants.SNAPSHOT_INTERVAL = 0.2 -- so oft schickt der Server einen Abgleich (Sekunden)
Constants.SNAPSHOT_BLEND = 0.25 -- so viel der Abweichung wird pro Abgleich korrigiert (weich, ohne Springen)

-- Einfluss der Köpfe auf die Plattformen (siehe HeadWeight.luau)
Constants.HEAD_WEIGHT_FORCE = 140 -- Gewichtskraft eines Kopfes (zieht nach unten, am Ende: kippen)
Constants.HEAD_LANDING_IMPULSE = 7 -- Stoß pro Studs/s Aufprall-Geschwindigkeit beim Landen
Constants.HEAD_WALK_FORCE = 4.2 -- Gegenschub pro Studs/s Laufgeschwindigkeit
Constants.PLATFORM_CONTACT_DISTANCE = 0.5 -- so nah muss ein Kopf sein, damit er als "drauf" gilt

-- Ausscheiden
Constants.FALL_LIMIT_Y = -40
Constants.RESPAWN_DELAY = 2 -- nur außerhalb von Runden (z. B. allein beim Warten auf Mitspieler)

-- Zerquetschen: Wird der Platz zwischen zwei Plattformen, die von gegenüberliegenden Seiten
-- auf einen Kopf drücken, kleiner als dieser Anteil seines Durchmessers, ist der Kopf zerquetscht.
Constants.CRUSH_GAP_RATIO = 0.75

-- Rundensystem
Constants.MIN_PARTICIPANTS = 2 -- ab so vielen Teilnehmern (Spieler + Bots) wird um Punkte gespielt
Constants.MAX_PARTICIPANTS = 4
Constants.WIN_POINTS = 5 -- so viele Rundensiege gewinnen ein Match
Constants.COUNTDOWN_TIME = 3
Constants.ROUND_END_TIME = 3 -- Pause nach einer Runde (Sieger wird angezeigt)
Constants.MATCH_END_TIME = 6 -- Pause nach einem Match

-- Bots
Constants.BOT_NAMES = { "Knetbert", "Plastilina", "Wurstl", "Klumpi", "Matschka", "Fladen" }
Constants.BOT_THINK_INTERVAL = 0.15 -- so oft entscheidet ein Bot neu (Sekunden)
Constants.BOT_THROW_CHANCE = 0.35 -- Chance pro Entscheidung, eine Granate zu werfen (wenn sinnvoll)
Constants.BOT_AIM_ERROR = 2.5 -- wie ungenau Bots zielen (Studs Abweichung beim Ziel)

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
Constants.COOLDOWN_COLOR = Color3.fromRGB(110, 106, 102) -- Kleidung, deren Fähigkeit gerade abklingt

-- Kamera: sehr kleines Sichtfeld + großer Abstand = wirkt wie echtes 2D (fast keine Perspektive)
Constants.CAMERA_FOV = 8
Constants.CAMERA_MIN_DISTANCE = 300
Constants.CAMERA_MAX_DISTANCE = 3000
Constants.CAMERA_PADDING = 6 -- Rand um Arena und Köpfe (Studs)
Constants.CAMERA_MAX_EXTRA = 8 -- so weit über die Arena hinaus folgt die Kamera einem Kopf höchstens
Constants.CAMERA_SMOOTHNESS = 5

-- Namen im Workspace / ReplicatedStorage
Constants.HEADS_FOLDER = "Heads"
Constants.ARENA_FOLDER = "Arena"
Constants.REMOTES_FOLDER = "Remotes"
Constants.ROUND_STATE = "RoundState" -- Ordner in ReplicatedStorage mit Phase, Nachricht, Punkten
Constants.EFFECTS_FOLDER = "Effects" -- nur lokal auf dem Client (Granaten, Explosionen)

return Constants
