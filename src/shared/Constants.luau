--!strict
-- Zentrale Spielwerte. Hier wird das Spielgefühl getunt.

local Constants = {}

-- 2D-Ebene: Alle Köpfe bleiben auf dieser Z-Position.
Constants.PLANE_Z = 0

-- Kopf
Constants.HEAD_RADIUS = 1.5

-- Bewegung (Studs pro Sekunde)
Constants.MOVE_SPEED = 14
Constants.GROUND_ACCEL = 160 -- (früher 110) wie schnell man auf einer Fläche die Zielgeschwindigkeit erreicht
Constants.GROUND_FRICTION = 130 -- (früher 90) wie schnell man ohne Eingabe auf einer Fläche abbremst (gleiten)
Constants.AIR_ACCEL = 95 -- (früher 70) weniger Kontrolle in der Luft
Constants.LANDING_KEEP = 0.85 -- so viel vom Schwung entlang der Fläche bleibt beim Landen erhalten

-- Springen (die Schwerkraft rechnet der Client selbst, Workspace.Gravity ist 0)
Constants.GRAVITY = 165 -- (früher 140) schnellere Sprünge bei gleicher Höhe: weniger schwebend
Constants.JUMP_VELOCITY = 57 -- (früher 52) Sprunghöhe ~ v² / (2 * GRAVITY) bleibt gleich
Constants.JUMP_CUT_MULTIPLIER = 0.45 -- Taste früh loslassen = niedriger Sprung
Constants.JUMP_KEEP_ALONG = 0.6 -- so viel Laufgeschwindigkeit nimmt man in den Sprung mit
Constants.MAX_FALL_SPEED = 100
Constants.AIR_JUMPS = 1 -- Doppelsprung: so oft kann man in der Luft nochmal springen
Constants.DOUBLE_JUMP_VELOCITY = 46 -- (früher 42) etwas schwächer als der normale Sprung
Constants.JUMP_BUFFER = 0.12 -- Sprung kurz vor der Landung gedrückt zählt trotzdem
Constants.WALL_JUMP_VELOCITY = 34 -- Absprung von einer Wand (schräg nach oben)
Constants.WALL_JUMP_LIFT = 0.8 -- wie steil man von einer Wand nach oben abspringt
Constants.CEILING_JUMP_VELOCITY = 8 -- von einer Unterseite: nur leicht abstoßen und fallen lassen
Constants.WALL_JUMP_KEEP_ALONG = 0.2 -- Kletterschwung, der in Wand- und Deckensprünge mitgeht
Constants.DETACH_TIME = 0.16 -- nach dem Absprung so lange nicht wieder an derselben Plattform festkleben

-- Dash (Fliegerkappe)
Constants.DASH_SPEED = 80
Constants.DASH_TIME = 0.14
Constants.DASH_COOLDOWN = 2.5
Constants.DASH_END_KEEP = 0.4 -- so viel Schwung bleibt nach dem Dash übrig

-- Thruster (Schweißerbrille): klebt an eine Plattform und schiebt sie von sich weg
Constants.THRUSTER_RANGE = 12 -- so weit darf die Plattform entfernt sein
Constants.THRUSTER_FORCE = 2000 -- Schubkraft; Beschleunigung = Kraft / Masse der Plattform
Constants.THRUSTER_DURATION = 2
Constants.THRUSTER_RAMP = 0.2 -- Sekunden, in denen der Schub weich an- und ausläuft
-- Der Schub beginnt minimal verzögert, aber für Server und alle Clients zur SELBEN Serverzeit. Sonst
-- schiebt jeder Rechner etwas früher oder später an, die Plattform läuft auseinander und wird ständig
-- zurückkorrigiert (sah aus wie Zucken). Der Thruster selbst ist sofort zu sehen.
Constants.THRUSTER_SYNC_DELAY = 0.15
Constants.THRUSTER_COOLDOWN = 5
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
Constants.GRENADE_COOLDOWN = 4
Constants.GRENADE_COLOR = Color3.fromRGB(86, 104, 62)

-- Schwert: Schlag im Bogen vor sich
Constants.SWORD_RANGE = 5 -- Reichweite vom Kopf-Mittelpunkt (Studs)
Constants.SWORD_ARC = 65 -- halber Öffnungswinkel des Schlags in Grad (65 = 130° Bogen)
Constants.SWORD_COOLDOWN = 0.9
Constants.SWORD_SWING_TIME = 0.14 -- Dauer der Schwung-Animation
Constants.SWORD_DEFLECT_SPEED = 55 -- so schnell fliegt eine zurückgeschlagene Granate
Constants.SWORD_COLOR = Color3.fromRGB(196, 204, 214)

-- Lenkrakete: fliegt los und wird mit der Maus gelenkt
Constants.MISSILE_SPEED = 22 -- Fluggeschwindigkeit geradeaus
Constants.MISSILE_STEER_SPEED = 8 -- extra langsam, solange man sie lenkt (Taste gehalten)
Constants.MISSILE_SPEED_CHANGE = 45 -- wie schnell sie zwischen den beiden Tempi wechselt (Studs/s²)
Constants.MISSILE_TURN_RATE = 1.8 -- maximale Drehung beim Lenken in rad/s (ca. 100° pro Sekunde)
Constants.MISSILE_LIFETIME = 6
Constants.MISSILE_LENGTH = 1.6 -- Größe der Rakete = genau ihre Hitbox
Constants.MISSILE_THICKNESS = 0.6
-- Die Rakete erwischt nur, wen sie selbst berührt (kein Flächenschaden). Die Explosion ist reine Optik
-- und schubst Plattformen in diesem Radius ein wenig.
Constants.MISSILE_BLAST_RADIUS = 2
Constants.MISSILE_IMPULSE = 350 -- Stoß auf Plattformen bei der Explosion
Constants.MISSILE_OWNER_GRACE = 0.4 -- so lange trifft die Rakete den Schützen selbst nicht
Constants.MISSILE_COOLDOWN = 7
Constants.MISSILE_COLOR = Color3.fromRGB(205, 60, 50)

-- Plattform-Physik (eigene Feder, siehe PlatformSim.luau)
-- Wie in Bopl Battle: Plattformen hängen weich an einer Feder, sinken unter Figuren spürbar ein, kippen,
-- wenn man am Rand steht, und schwingen nach Landungen und Explosionen ein paar Mal nach.
-- Masse = BEZUG * (Fläche * Dichte / BEZUG) ^ EXPONENT. Große Inseln sind schwerer, aber nicht mehr
-- vielfach so schwer (vorher Fläche * Dichte: die große Insel war ~8x so schwer und bewegte sich kaum).
-- Bezug: eine Plattform mit Fläche*Dichte 28 hat Masse 28; Schub- und Stoßkräfte sind darauf abgestimmt.
-- Gleichgewicht unter vollem Schub: THRUSTER_FORCE / (Masse * PLATFORM_SPRING) Studs vom Startplatz
Constants.PLATFORM_DENSITY = 1 -- Standard-Dichte (im Arena-Layout pro Plattform änderbar)
Constants.PLATFORM_MASS_REFERENCE = 28
Constants.PLATFORM_MASS_EXPONENT = 0.4
-- Rückkehr-Dauer ungefähr 5 / Wurzel(SPRING) Sekunden (1,4 -> gut 4 s)
Constants.PLATFORM_SPRING = 1.4 -- (früher 2) wie stark die Plattform zum Startplatz zurückgezogen wird (kleiner = weicher)
Constants.PLATFORM_DAMPING = 0.9 -- (früher 2,8, dann 1,6) wenig Bremse: schwingt nach wie Wackelpudding
Constants.PLATFORM_MAX_OFFSET = 60 -- nur Notbremse (früher 12 als harte Grenze: wirkte wie eine unsichtbare Wand)
-- Weiche Grenze: ab PLATFORM_SOFT_OFFSET Studs zieht eine zusätzliche, viel stärkere Feder (mit eigener
-- Bremse) zurück. So läuft eine Plattform weich aus, statt anzuschlagen oder aus dem Bild zu fliegen.
-- Kleine Plattformen unter vollem Schub bleiben so bei ~12-14 Studs, große bei ~10.
Constants.PLATFORM_SOFT_OFFSET = 9
Constants.PLATFORM_SOFT_SPRING = 14
Constants.PLATFORM_SOFT_DAMPING = 4
Constants.PLATFORM_ANGULAR_SPRING = 2 -- (früher 8) wie stark eine gekippte Plattform zurückgedreht wird (kleiner = kippt mehr)
Constants.PLATFORM_ANGULAR_DAMPING = 1.15 -- (früher 5,7, dann 3,4) wackelt ein paar Mal nach
Constants.PLATFORM_ANGULAR_SPRING_LIMIT = math.rad(90) -- ab hier wird die Rückdreh-Kraft nicht mehr stärker (Plattformen können sich ganz drehen)
Constants.PLATFORM_BOUNCE = 0.2 -- wie stark Plattformen voneinander abprallen (Knete: wenig)

-- Netzwerk-Abgleich der Plattformen (jeder Rechner simuliert selbst, der Server gleicht ab)
Constants.SIM_RATE = 120 -- feste Physik-Schritte pro Sekunde
Constants.SNAPSHOT_INTERVAL = 0.2 -- so oft schickt der Server einen Abgleich (Sekunden)
Constants.SNAPSHOT_BLEND = 0.25 -- nur noch Rückfall ohne Zeitstempel; sonst gleicht PlatformClient zeitrichtig aus

-- Einfluss der Köpfe auf die Plattformen (siehe HeadWeight.luau)
Constants.HEAD_WEIGHT_FORCE = 170 -- (früher 140, kurz 260; Plattformen sind jetzt leichter) Gewichtskraft eines Kopfes (zieht nach unten, am Ende: kippen)
Constants.HEAD_LANDING_IMPULSE = 4.5 -- (früher 4, kurz 7: kleine Plattformen tauchten beim Landen ~12 Studs ab) Stoß pro Studs/s Aufprall-Geschwindigkeit beim Landen
Constants.HEAD_WALK_FORCE = 5 -- (früher 4,2) Gegenschub pro Studs/s Laufgeschwindigkeit
Constants.PLATFORM_CONTACT_DISTANCE = 0.25 -- so nah muss ein Kopf sein, damit er als "drauf" gilt
-- (klein halten: sonst wird eine Plattform schon weggestoßen, bevor der Kopf sie berührt)

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
Constants.MAP_SELECT_TIME = 3 -- vor jeder Runde: Karte und Hintergrund werden ausgelost (Glücksrad)
Constants.ROUND_END_TIME = 3 -- Pause nach einer Runde (Sieger wird angezeigt)
Constants.MATCH_END_TIME = 6 -- Pause nach einem Match

-- Bots
Constants.BOT_NAMES = { "Knetbert", "Plastilina", "Wurstl", "Klumpi", "Matschka", "Fladen" }
-- Bot-Schwierigkeit (im Startmenü einstellbar). Werte pro Stufe:
--   think        so oft entscheidet ein Bot neu (Sekunden) – kleiner = schnellere Reaktion
--   speed        Laufgeschwindigkeit im Verhältnis zum Spieler
--   aimError     Zielfehler beim Granatenwurf (Studs)
--   lead         wie stark Bots vorhalten (0 = auf die aktuelle Position, 1 = voll vorausberechnet)
--   throwChance  Chance pro Entscheidung, eine sinnvolle Granate zu werfen
--   swordChance  Chance pro Entscheidung zuzuschlagen, wenn ein Gegner in Reichweite ist
--   missileChance, thrusterChance  ebenso für Rakete und Thruster
--   dodgeChance  Chance, einer Gefahr (Granate, Rakete, Schwert) überhaupt auszuweichen
--   dodgeTime    so früh vor dem Einschlag wird ausgewichen (Sekunden)
--   rescueChance Chance, sich beim Fallen per Dash zu retten
--   deflect      schlägt Granaten mit dem Schwert zurück
--   combo        Dash + Schwert, zündet Raketen neben dem Gegner, meidet Schwertkämpfer
Constants.BOT_DIFFICULTIES = {
	{ name = "Leicht", think = 0.32, speed = 0.75, aimError = 5, lead = 0, throwChance = 0.12, swordChance = 0.3, missileChance = 0.03, thrusterChance = 0.03, dodgeChance = 0.4, dodgeTime = 0.45, rescueChance = 0.4, deflect = false, combo = false },
	{ name = "Normal", think = 0.18, speed = 0.9, aimError = 2.5, lead = 0.5, throwChance = 0.28, swordChance = 0.6, missileChance = 0.06, thrusterChance = 0.05, dodgeChance = 0.75, dodgeTime = 0.7, rescueChance = 0.8, deflect = false, combo = false },
	{ name = "Schwer", think = 0.1, speed = 1, aimError = 1.2, lead = 0.85, throwChance = 0.45, swordChance = 0.85, missileChance = 0.1, thrusterChance = 0.06, dodgeChance = 0.9, dodgeTime = 0.9, rescueChance = 1, deflect = true, combo = true },
	{ name = "Profi", think = 0.06, speed = 1, aimError = 0.4, lead = 1, throwChance = 0.6, swordChance = 1, missileChance = 0.14, thrusterChance = 0.07, dodgeChance = 1, dodgeTime = 1.05, rescueChance = 1, deflect = true, combo = true },
}
Constants.BOT_DEFAULT_DIFFICULTY = 2

-- Knet-Look
Constants.STOP_MOTION_FPS = 12
Constants.BOIL_AMOUNT = 0.03 -- wie stark die Form zwischen zwei Bildern "wabert"

-- Charakter-Farben ("Skins"), passend zu den Sprites in SpriteAssets.luau. In dieser Reihenfolge
-- bekommen die Teilnehmer ihre Farbe. color = Farbe für Anzeige, Effekte und den 3D-Ersatzkopf.
Constants.SKINS = {
	{ key = "blue", color = Color3.fromRGB(52, 120, 230) },
	{ key = "red", color = Color3.fromRGB(225, 60, 60) },
	{ key = "green", color = Color3.fromRGB(90, 200, 60) },
	{ key = "yellow", color = Color3.fromRGB(245, 210, 40) },
	{ key = "orange", color = Color3.fromRGB(240, 130, 40) },
	{ key = "purple", color = Color3.fromRGB(140, 90, 220) },
	{ key = "pink", color = Color3.fromRGB(240, 120, 190) },
	{ key = "cyan", color = Color3.fromRGB(60, 210, 230) },
	{ key = "teal", color = Color3.fromRGB(30, 160, 140) },
	{ key = "white", color = Color3.fromRGB(235, 235, 235) },
	{ key = "charcoal", color = Color3.fromRGB(70, 70, 78) },
	{ key = "brown", color = Color3.fromRGB(140, 90, 50) },
}

-- Sprites (2D-Charaktere)
Constants.USE_SPRITES = true -- false = 3D-Knetköpfe statt Sprites
Constants.SPRITE_SIZE = 4.9 -- Kantenlänge des Sprite-Bilds in Studs (Kopf-Durchmesser/Trefferfläche bleibt 3; früher 4,2)
Constants.SPRITE_OFFSET_Y = -0.38 -- Bild verschieben (in Studs, + = weg von der Fläche): auf der Oberseite,
-- die Füße stehen auf der hellen Oberkante
Constants.SPRITE_OFFSET_Y_OTHER = 0.07 -- dasselbe an Wänden und Unterseiten (dort gibt es keine helle Kante)
Constants.SPRITE_PIXELS = 256 -- Pixelgröße der Sprite-Bilder (Breite = Höhe), zum Spiegeln nötig
Constants.SPRITE_FLIP = true -- Figur beim Linkslaufen spiegeln (false, falls SPRITE_PIXELS nicht stimmt)
Constants.SPRITE_FPS = 12 -- Bilder pro Sekunde der Animationen
-- Erscheinen: true = gezeichnete "respawn"-Bilder, false = Figur ploppt aus dem Nichts (Wachsen + Nachfedern)
Constants.USE_RESPAWN_SPRITES = false
Constants.RESPAWN_POP_TIME = 0.35
-- Ebenen nach vorne (Kamera schaut von +Z). Die Kamera steht sehr weit weg, deshalb brauchen Flächen
-- deutliche Abstände, sonst flackern sie ineinander ("Z-Fighting"):
--   Plattformen: Vorderseite bei höchstens 4, Front-Platte 0,25 davor, jede Plattform 0,5 weiter hinten
--   Figuren: SPRITE_Z (+ etwas pro Figur, die eigene ganz vorne), Schwert davor
Constants.SPRITE_Z = 5.5
Constants.SPRITE_LAYER_STEP = 0.1 -- Abstand zwischen überlappenden Figuren
Constants.PLATFORM_LAYER_STEP = 0.5 -- Abstand zwischen überlappenden Plattformen
Constants.PLATFORM_FRONT_GAP = 0.25 -- Front-Platte vor der Plattform

-- Plattform-Look mit Tiefe: oben eine hellere Kante (die "Oberseite"), auf der die Figuren stehen
Constants.PLATFORM_TOP_DEPTH = 0.7 -- Dicke der hellen Oberkante in Studs
Constants.PLATFORM_TOP_LIGHTEN = 0.28 -- wie viel heller die Oberseite ist (0..1)
Constants.COOLDOWN_COLOR = Color3.fromRGB(110, 106, 102) -- Kleidung, deren Fähigkeit gerade abklingt

-- Kamera: sehr kleines Sichtfeld + großer Abstand = wirkt wie echtes 2D (fast keine Perspektive)
Constants.CAMERA_FOV = 8
Constants.CAMERA_MIN_DISTANCE = 300
Constants.CAMERA_MAX_DISTANCE = 3000
Constants.CAMERA_PADDING = 6 -- Rand um Arena und Köpfe (Studs)
Constants.CAMERA_MAX_EXTRA = 14 -- (früher 8) so weit über die Arena hinaus folgt die Kamera einem Kopf höchstens
Constants.CAMERA_SMOOTHNESS = 5

-- Namen im Workspace / ReplicatedStorage
Constants.HEADS_FOLDER = "Heads"
Constants.ARENA_FOLDER = "Arena"
Constants.REMOTES_FOLDER = "Remotes"
Constants.MISSILES_FOLDER = "Missiles"
Constants.ROUND_STATE = "RoundState" -- Ordner in ReplicatedStorage mit Phase, Nachricht, Punkten
Constants.EFFECTS_FOLDER = "Effects" -- nur lokal auf dem Client (Granaten, Explosionen)

return Constants
