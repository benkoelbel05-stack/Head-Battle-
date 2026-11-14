# Clay Battle

Ein chaotisches 2D-Arena-Duell für 2–4 Spieler auf Roblox: Knetköpfe hüpfen durch Stop-Motion-Arenen und bekämpfen sich mit Hüten, die ihnen Superkräfte geben. Eine Hommage an *Bopl Battle*.

## Stand: Phase 1–3 – Prototyp

- [x] Knetkopf als Spielfigur (eigene Bewegung, keine Roblox-Figur)
- [x] Exakte Bewegung um die Plattformen: an jeder Seite kleben, gleichmäßig um die runden Enden gleiten, nicht herunterfallen
- [x] Landen mit Schwung: man gleitet entlang der Fläche weiter
- [x] Fähigkeiten = Kleidungsstücke, 3 Slots auf den Maustasten
  - Fliegerkappe (Hut): Dash
  - Schweißerbrille (Brille): Thruster an Plattform kleben, schiebt und dreht sie
  - Granatengürtel (Gürtel): Taste halten lädt die Wurfkraft auf (mit Zielstreifen), Loslassen wirft; prallt an Plattformen ab, explodiert beim Aufprall auf einen Kopf oder nach 1,6 s
  - Schwert (Rücken): Hieb im Bogen (±65°) Richtung Maus, Reichweite 5; trifft alle Köpfe darin und schlägt Granaten zurück
  - Raketenrucksack (Rücken): Lenkrakete: Taste halten = sie fliegt extra langsam zum Mauszeiger, loslassen = geradeaus mit vollem Tempo; explodiert bei Plattform/Kopf oder nach 6 s
- [x] Startmenü: 3 von 5 Fähigkeiten wählen (Klick-Reihenfolge = Taste), Bot-Stärke und Bot-Anzahl einstellen, „Spielen“; im Spiel öffnet „Ausrüstung“ (unten links) das Menü wieder
- [x] Bot-Stärke Leicht / Normal / Schwer / Profi: Reaktionszeit, Tempo, Zielgenauigkeit, Ausweichen; ab „Schwer“ schlagen Bots Granaten zurück, kombinieren Dash + Schwert, zünden Raketen neben dem Gegner und meiden Schwertkämpfer
- [x] Eigene Plattform-Physik: Feder zurück zum Startplatz, max. 12 Studs Versatz, max. 60° Kippen
- [x] Köpfe beeinflussen Plattformen: Gewicht (Wippe), Landestoß, Gegenschub beim Laufen
- [x] Masse je nach Größe und Dichte: große/schwere Plattformen bewegen und drehen sich weniger
- [x] 2D-Kamera, zeigt immer die ganze Arena
- [x] Knet-Look: Squash & Stretch, Stop-Motion-Takt, Kopf dreht sich mit der Fläche
- [x] Rundensystem: Countdown, ein Treffer = raus, letzter Überlebender bekommt einen Punkt, 5 Punkte gewinnen das Match
- [x] Zerquetschen: Wer zwischen zwei Plattformen eingeklemmt wird, scheidet aus (Knetfladen-Effekt)
- [x] Exakte Physik: feste 120-Hz-Schritte für Köpfe, Plattformen und Granaten (unabhängig von der Bildrate), Überblenden für flüssige Anzeige
- [x] Hitboxen: Köpfe stoßen sich ab, Plattformen stoßen exakt aneinander (Masse, Drehung, leichtes Abprallen)
- [x] An Decken bleibt man immer kleben
- [x] 2D-Charakter-Sprites (12 Farben, Animationen idle/run/jump/land/hit/respawn), Fallback auf 3D-Knetköpfe
- [x] Anzeige der Fähigkeiten mit Abklingzeit unten in der Mitte
- [x] Bots (Knöpfe „+ Bot“ / „– Bot“ unten rechts): verfolgen, springen, werfen gezielte Granaten, weichen aus, retten sich per Dash
- [ ] Kopfnuss, weitere Fähigkeiten (Bogen, Mine, Schild …)
- [ ] Auswahl der Kleidung vor der Runde
- [ ] Touch-Steuerung für Handys (Phase 3)

## Steuerung

| Aktion | Tastatur / Maus | Controller |
| --- | --- | --- |
| Laufen / Klettern | A / D / W / S oder Pfeiltasten | Linker Stick |
| Springen (weg von der Fläche) | Leertaste | A |
| Doppelsprung | Leertaste in der Luft | A in der Luft |
| Fähigkeit in Slot 1 | Linke Maustaste (oder 1) | X |
| Fähigkeit in Slot 2 | Mausrad-Klick (oder 2) | Y |
| Fähigkeit in Slot 3 | Rechte Maustaste (oder 3) | B |

Zielen: Fähigkeiten gehen in die gedrückte Richtung (auch schräg), ohne Eingabe in Blickrichtung.
Dash, Granate, Schwert und Rakete zielt man frei in alle Richtungen (360°): mit dem Mauszeiger oder dem rechten Stick.
Die Lenkrakete lenkt man, solange man die Taste hält: dann fliegt sie langsam zum Mauszeiger (ohne Maus: Richtungstasten).
Der Thruster klebt genau dort an die Plattform, wo man gerade steht. In der Luft geht er an die nächste Plattform in Zielrichtung.

## Projektstruktur

```
src/
  shared/   Code für Server und Client (ReplicatedStorage.Shared)
    Constants.luau      alle Spielwerte zum Tunen
    ArenaLayouts.luau   Arenen als Daten
    Abilities.luau      alle Fähigkeiten (= Kleidungsstücke), Ausrüstung mit 3 Slots
    PlatformShapes.luau exakte Form der Plattformen (Bewegung, Kollision, Granaten)
    PlatformSim.luau    Physik der Plattformen (läuft auf Server UND jedem Client)
    HeadWeight.luau     Köpfe drücken auf Plattformen (Gewicht, Landen, Laufen)
    HeadMotor.luau      Bewegung eines Kopfes (Spieler auf dem Client, Bots auf dem Server)
    GrenadePhysics.luau Flugbahn und Explosion der Granate
    ThrusterVisual.luau Aussehen des Thrusters
    SpriteAssets.luau   Sprite-IDs (Decals) pro Farbe und Animation
    SpriteImages.luau   Image-IDs, erzeugt mit tools/ConvertSprites.luau
  server/   ServerScriptService.Server
    init.server.luau    Einstieg, Netzwerk-Events, Abgleich der Plattformen
    Arena.luau          baut die Arena
    HeadSpawner.luau    erzeugt Köpfe aller Teilnehmer (Spieler + Bots), meldet Ausscheiden
    RoundManager.luau   Rundensystem, Punkte
    BotController.luau  Bot-KI
    Thrusters.luau      Fähigkeit Thruster (prüfen und verteilen)
    Grenades.luau       Fähigkeit Granate (echte Granate, entscheidet wer ausscheidet)
    Swords.luau         Fähigkeit Schwert (Treffer im Bogen, Granaten zurückschlagen)
    Missiles.luau       Fähigkeit Lenkrakete (Flug, Treffer, Explosion)
  client/   StarterPlayerScripts.Client
    init.client.luau    Einstieg (Reihenfolge pro Bild)
    PlatformClient.luau Plattformen lokal rechnen, Thruster/Granaten/Explosionen anzeigen
    HeadController.luau Steuerung des eigenen Kopfes, Fähigkeiten
    CameraController.luau
    ClayAnimator.luau   Animation aller Köpfe (Sprites oder Knet), Kleidung
    SpriteVisual.luau   Sprite-Bild in der Welt (Spiegeln, Vorladen, ID-Prüfung)
    AbilityHUD.luau     Anzeige der Fähigkeiten und Abklingzeiten
    AimPreview.luau     Zielstreifen für die Granate
    StartScreen.luau    Startmenü (Fähigkeiten, Bot-Stärke, Bots, Spielen)
    SwordVisual.luau    Schwerthieb-Animation
    RoundUI.luau        Anzeige: Nachricht, Countdown, Punkte, Bot-Knöpfe
```

### Netzwerk-Prinzip

Jeder Rechner simuliert die Plattformen selbst (`PlatformSim`). Ausgetauscht werden nur Ereignisse
(„Thruster gesetzt“, „Granate geworfen“, „Explosion“) und alle 0,2 s ein Abgleich, an den sich die Clients weich angleichen.
Eigene Aktionen wirken sofort, ohne auf den Server zu warten. Der Server entscheidet, wer ausscheidet.

## Sprites einrichten (Decal-IDs -> Image-IDs)

Roblox legt beim Hochladen pro Bild ein **Decal** und ein **Image** an. `src/shared/SpriteAssets.luau` enthält die
Decal-IDs; das Spiel braucht die Image-IDs. Die werden einmalig automatisch erzeugt:

1. Studio mit Rojo verbinden.
2. Inhalt von `tools/ConvertSprites.luau` in die **Befehlsleiste** (Ansicht → Befehlsleiste) einfügen, Enter.
3. Warten bis im Output `FERTIG` steht.
4. `ServerStorage → SpriteImages_Ergebnis` öffnen, alles kopieren, in `src/shared/SpriteImages.luau` einfügen (ersetzen), speichern.
5. `git add -A`, `git commit -m "Sprite-Image-IDs"`, `git push`.

Beim Spielstart in Studio prüft der Client alle Sprites und meldet kaputte im Output.
Neue oder fehlende Sprites: Decal-ID in `SpriteAssets.luau` eintragen und Schritte 2–5 wiederholen.

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
