# Automatische Neuinstallation

Mit dem kostenlosen Apple-Account läuft das Provisioning-Profil nach 7 Tagen ab. `refresh-install.sh` baut die App ab Tag 5 neu und installiert sie per Kabel oder WLAN auf das iPhone. Die Daten in der App bleiben dabei erhalten.

## Funktionsweise

- Ein LaunchAgent startet das Skript stündlich und beim Anmelden. Steht keine Installation an, endet es sofort.
- Gebaut wird aus einem eigenen Klon außerhalb von iCloud (`~/Library/Developer/Tagwerk/src`). Prozesse, die launchd startet, dürfen iCloud Drive nicht ohne Weiteres lesen, außerdem kann iCloud Dateien auslagern.
- Das Protokoll steht in `~/Library/Logs/Tagwerk/refresh.log`, die Build-Ausgabe in `build.log`.
- Ist das iPhone ab Tag 6 nicht erreichbar, erscheint eine Mitteilung auf dem Mac.

## Voraussetzungen

- Der Mac ist wach und angemeldet, das iPhone im selben WLAN.
- In Xcode → Window → Devices and Simulators ist beim iPhone „Connect via network“ aktiv.
- Die Apple-ID ist in Xcode → Settings → Accounts angemeldet.

## Einrichten

```zsh
git clone https://github.com/melvinmng/tagwerk ~/Library/Developer/Tagwerk/src
cp scripts/de.tagwerk.refresh.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.tagwerk.refresh.plist
```

## Prüfen

```zsh
~/Library/Developer/Tagwerk/src/scripts/refresh-install.sh --dry-run
launchctl print gui/$(id -u)/de.tagwerk.refresh | grep -E "state|last exit code"
tail ~/Library/Logs/Tagwerk/refresh.log
```

Sofort neu installieren, im echten launchd-Kontext:

```zsh
launchctl setenv TAGWERK_FORCE 1
launchctl kickstart -k gui/$(id -u)/de.tagwerk.refresh
launchctl unsetenv TAGWERK_FORCE
```

Fragt der Schlüsselbund beim ersten Lauf nach `codesign`, auf „Immer erlauben“ klicken.

## Entfernen

```zsh
launchctl bootout gui/$(id -u)/de.tagwerk.refresh
rm ~/Library/LaunchAgents/de.tagwerk.refresh.plist
```

## Exit-Codes

| Code | Bedeutung |
|---|---|
| 0 | installiert oder noch nicht fällig |
| 1 | Build fehlgeschlagen |
| 2 | iPhone nicht erreichbar oder Installation fehlgeschlagen |
| 3 | Signierung fehlgeschlagen, meist muss man sich in Xcode neu anmelden |
