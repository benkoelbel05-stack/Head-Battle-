# Head Battle

Ein chaotisches 2D-Arena-Duell für 2–4 Spieler auf Roblox: Knetköpfe hüpfen durch Stop-Motion-Arenen und bekämpfen sich mit Hüten, die ihnen Superkräfte geben. Eine Hommage an *Bopl Battle*.

## Stand: Phase 1 – Prototyp

- [x] Knetkopf als Spielfigur (eigene Physik, keine Roblox-Figur)
- [x] Laufen und Springen auf einer 2D-Ebene (mit Coyote Time, Sprung-Puffer, variabler Sprunghöhe)
- [x] An Boden, Wand und Decke haften, an ihnen entlanglaufen und abspringen
- [x] Erster Hut: Fliegerkappe = Dash (Abklingzeit 3 s, Hut wird solange grau)
- [x] 2D-Kamera (kleines Sichtfeld, große Entfernung), zeigt immer die ganze Arena
- [x] Runde Plattformen („Knetwürste“), um deren Enden man herumlaufen kann
- [x] Plattform-Physik: Plattformen schweben, lassen sich schieben und drehen, eine Feder zieht sie langsam zurück
- [x] Zweiter Hut: Thruster, klebt an eine Plattform und schiebt sie 3 s lang weg (Abklingzeit 6 s)
- [x] Mitfahren auf bewegten Plattformen
- [x] Knet-Look: Squash & Stretch, „Wabern“ im 12-fps-Stop-Motion-Takt, Augen in Laufrichtung
- [x] Erste Arena „Basteltisch“ (graue Klötze)
- [x] Absturz = Respawn nach 2 Sekunden
- [ ] Kopfnuss und die nächsten 3 Hüte (Phase 2)
- [ ] Runden, Punkte, Hutwahl (Phase 3)
- [ ] Touch-Steuerung für Handys (Phase 3)

## Steuerung

| Aktion | Tastatur | Controller |
| --- | --- | --- |
| Laufen / Klettern | A / D / W / S oder Pfeiltasten | Linker Stick |
| Springen (weg von der Fläche) | Leertaste | A |
| Fähigkeit in Slot 1 | Linke Maustaste (oder 1) | X |
| Fähigkeit in Slot 2 | Mausrad-Klick (oder 2) | Y |
| Fähigkeit in Slot 3 | Rechte Maustaste (oder 3) | B |

Jeder Spieler hat höchstens 3 Fähigkeiten (Hüte) ausgerüstet. Vorerst: Slot 1 = Dash, Slot 2 = Thruster, Slot 3 frei.

Kurz drücken = kleiner Sprung, lang drücken = hoher Sprung. An Wänden klettert man mit W/S, an der Decke läuft man mit A/D. Der Dash geht in die gedrückte Richtung (auch schräg), ohne Eingabe in Blickrichtung.
Der Thruster geht in die gedrückte Richtung; ohne Eingabe an die Plattform, auf der man gerade klebt. Er schiebt die Plattform von sich weg – sitzt er am Ende, dreht sie sich.

## Projektstruktur

```
src/
  shared/   Code für Server und Client (ReplicatedStorage.Shared)
    Constants.luau      alle Spielwerte zum Tunen
    ArenaLayouts.luau   Arenen als Daten
    Abilities.luau      alle Fähigkeiten/Hüte, Ausrüstung mit 3 Slots
  server/   ServerScriptService.Server
    init.server.luau    Einstieg
    Arena.luau          baut die Arena
    HeadSpawner.luau    erzeugt Köpfe, Respawn
    PlatformPhysics.luau  Plattformen schweben, 2D-Ebene, Rückstellfeder
    Thrusters.luau      Hut 2: Thruster an Plattformen kleben
  client/   StarterPlayerScripts.Client
    init.client.luau    Einstieg
    HeadController.luau Steuerung des eigenen Kopfes
    CameraController.luau
    ClayAnimator.luau   Knet-/Stop-Motion-Animation
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
