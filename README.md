# Head Battle

Ein chaotisches 2D-Arena-Duell für 2–4 Spieler auf Roblox: Knetköpfe hüpfen durch Stop-Motion-Arenen und bekämpfen sich mit Hüten, die ihnen Superkräfte geben. Eine Hommage an *Bopl Battle*.

## Stand: Phase 1–2 – Prototyp

- [x] Knetkopf als Spielfigur (eigene Bewegung, keine Roblox-Figur)
- [x] Exakte Bewegung um die Plattformen: an jeder Seite kleben, gleichmäßig um die runden Enden gleiten, nicht herunterfallen
- [x] Landen mit Schwung: man gleitet entlang der Fläche weiter
- [x] Fähigkeiten = Kleidungsstücke, 3 Slots auf den Maustasten
  - Fliegerkappe (Hut): Dash
  - Schweißerbrille (Brille): Thruster an Plattform kleben, schiebt und dreht sie
  - Granatengürtel (Gürtel): Taste halten lädt die Wurfkraft auf (mit Zielstreifen), Loslassen wirft; prallt ab, explodiert nach 1,6 s
- [x] Eigene Plattform-Physik: Feder zurück zum Startplatz, max. 12 Studs Versatz, max. 60° Kippen
- [x] Köpfe beeinflussen Plattformen: Gewicht (Wippe), Landestoß, Gegenschub beim Laufen
- [x] 2D-Kamera, zeigt immer die ganze Arena
- [x] Knet-Look: Squash & Stretch, Stop-Motion-Takt, Kopf dreht sich mit der Fläche
- [ ] Kopfnuss, weitere Fähigkeiten (Phase 2)
- [ ] Runden, Punkte, Auswahl der Kleidung (Phase 3)
- [ ] Touch-Steuerung für Handys (Phase 3)

## Steuerung

| Aktion | Tastatur / Maus | Controller |
| --- | --- | --- |
| Laufen / Klettern | A / D / W / S oder Pfeiltasten | Linker Stick |
| Springen (weg von der Fläche) | Leertaste | A |
| Fähigkeit in Slot 1 | Linke Maustaste (oder 1) | X |
| Fähigkeit in Slot 2 | Mausrad-Klick (oder 2) | Y |
| Fähigkeit in Slot 3 | Rechte Maustaste (oder 3) | B |

Zielen: Fähigkeiten gehen in die gedrückte Richtung (auch schräg), ohne Eingabe in Blickrichtung.
Der Thruster geht ohne Eingabe an die Plattform, an der man gerade klebt.

## Projektstruktur

```
src/
  shared/   Code für Server und Client (ReplicatedStorage.Shared)
    Constants.luau      alle Spielwerte zum Tunen
    ArenaLayouts.luau   Arenen als Daten
    Abilities.luau      alle Fähigkeiten (= Kleidungsstücke), Ausrüstung mit 3 Slots
    PlatformShapes.luau exakte Form der Plattformen (Bewegung, Kollision, Granaten)
    ThrusterVisual.luau Aussehen des Thrusters (Server und Client)
    GrenadePhysics.luau Flugbahn der Granate (Server und Zielstreifen)
  server/   ServerScriptService.Server
    init.server.luau    Einstieg
    Arena.luau          baut die Arena
    HeadSpawner.luau    erzeugt Köpfe, Respawn
    PlatformPhysics.luau  Plattformen schweben, 2D-Ebene, Rückstellfeder
    Thrusters.luau      Fähigkeit Thruster
    Grenades.luau       Fähigkeit Granate
    HeadWeight.luau     Köpfe drücken auf Plattformen (Gewicht, Landen, Laufen)
  client/   StarterPlayerScripts.Client
    init.client.luau    Einstieg
    HeadController.luau Steuerung des eigenen Kopfes
    CameraController.luau
    ClayAnimator.luau   Knet-/Stop-Motion-Animation
    AimPreview.luau     Zielstreifen für die Granate
```

## Einrichtung mit Rojo

Rojo synchronisiert die Dateien aus diesem Repo live mit Roblox Studio.

1. **Rojo-Plugin für Studio installieren:** im Roblox Creator Store nach „Rojo“ suchen (Herausgeber: Rojo) oder über die VS-Code-Erweiterung „Rojo“ installieren lassen.
2. **Rojo-Programm installieren**, eine der Varianten:
   - VS Code: Erweiterung **Rojo** installieren, sie bringt alles mit.
   - Oder [Rokit](https://github.com/rojo-rbx/rokit) installieren und im Projektordner `rokit install` ausführen (die Version steht in `rokit.toml`).
3. Im Projektordner `rojo serve` starten (oder in VS Code: Rojo → Start server).
4. In Roblox Studio eine neue, leere Baseplate öffnen, im Rojo-Plugin auf **Connect** klicken.
5. **Play** drücken. Zum Testen mit mehreren Spielern: Test → Clients and Servers → 2 Spieler → Start.

Tipp: Alle Werte für das Spielgefühl (Geschwindigkeit, Sprunghöhe, Schwerkraft …) stehen in `src/shared/Constants.luau`.
