# Clay Battle – Item-Animationen + Schrift (Stand 14.11.2026)

## Jetzt in GitHub eingebaut
- src/client/ItemAnimations.luau ist eine neue **rein visuelle** clientseitige Animationsschicht.
- init.client.luau startet sie; HeadController.luau und PlatformClient.luau rufen die passenden Animationen auf.
- **Dash:** blaue Kneteschlieren/Puffs und Lichtimpuls.
- **Granate:** sichtbare Kappe, Zündschnur, Funken und Rotation; Explosion erzeugt orange/gelbe Brocken und Rauch.
- **Thruster:** leuchtende Knetedüsenmanschette, Rauch plus bestehende Flamme.
- **Schwert:** zusätzliche cremefarbene Funken zum bestehenden animierten Bogen-Schlag.
- **Lenkrakete:** animierte, drehbare 2D-Kneterakete über der bestehenden Treffer-Quader-Hitbox und pulsierende Flamme.

**Wichtig:** Das sind prozedural erzeugte erste Item-Animationen, **keine neuen hochauflösenden PNG-Sprites**. Es werden keine neuen Roblox-Image-IDs benötigt. Bestehende Hitboxen, Fähigkeiten und Soundeffekte bleiben wie zuvor. Bitte in Roblox Studio testen.

## Schrift in der UI
Die generierten KI-Conceptarts enthalten keine eindeutig identifizierbare, reproduzierbare Font-Datei. Roblox lässt einen eigenen Font nicht einfach wie ein PNG hochladen. Stattdessen **Fredoka One** aus der Roblox-Bibliothek nutzen:

    label.Font = Enum.Font.FredokaOne
    label.TextColor3 = Color3.fromRGB(255, 246, 224)
    label.TextStrokeColor3 = Color3.fromRGB(64, 30, 83)
    label.TextStrokeTransparency = 0.24

Alternative als FontFace:

    label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")

Die Textkontur, Cremefarbe und farbigen Knete-Panels schaffen den Stil, nicht ein extern hochgeladenes Font. 
MainMenu.luau verwendet jetzt Fredoka One auch für die bisherigen Gotham-Fallbacks; übrige Menümodule verwendeten Fredoka One bereits.

## Claude – Bitte prüfen
1. GitHub pull und Rojo-/Studio-Synchronisation durchführen.
2. In Studio Test Play drücken; Server + mindestens ein lokaler Spieler.
3. Dash: Lichtspuren beim Auslösen sichtbar, ohne Einfluss auf Bewegung.
4. Granate: Zündschnur an Kugel, Rotation, Explosionsbrocken; keine doppelten Explosionen.
5. Thruster: Düse und Rauch auf Plattform, ohne Änderungen an deren Simulation.
6. Schwert: Schwung und Funken vor der Figur, Treffer unverändert.
7. Rakete: animierte Knetehülle mit rotierendem Flugkörper; keine unsichtbare Rakete/versetzte Hitbox.
8. Schrift und responsive UI prüfen (Handy/Desktop), besonders textbasierte Fallbacks.
9. Roblox Studio Output auf Luau-/Asset-/RenderStepped-Fehler prüfen. Falls nötig z.B. GUI-Skalierung optimieren.
10. Ohne neue Image-/Decal-IDs. Wenn später echte Item-Sprites hochgeladen werden, müssen die echten IMAGE-IDs verwendet werden. Nicht die alten Decal-IDs als UI-Sprites behandeln.

## GitHub
https://github.com/benkoelbel05-stack/Head-Battle-

## Sicherheit
API-Keys niemals ins Repository oder in Claude-Nachrichten kopieren. Den früher im Chat veröffentlichten Roblox-Key austauschen.
