# Automatische Neuinstallation

Mit dem kostenlosen Apple-Account läuft das Provisioning-Profil nach 7 Tagen ab. `refresh-install.sh` baut die App neu, sobald das installierte Profil weniger als 3 Tage gültig ist. Vor jedem Build löscht es das zwischengespeicherte Profil, damit Xcode ein frisches 7-Tage-Profil ausstellt. Danach installiert es die App und installiert sie per Kabel oder WLAN auf das iPhone. Die Daten in der App bleiben dabei erhalten.

## Funktionsweise

- Ein LaunchAgent startet das Skript stündlich und beim Anmelden. Steht keine Installation an, endet es sofort.
- Gebaut wird aus einem eigenen Klon außerhalb von iCloud (`~/Library/Developer/Tagwerk/src`). Prozesse, die launchd startet, dürfen iCloud Drive nicht ohne Weiteres lesen, außerdem kann iCloud Dateien auslagern.
- Das Protokoll steht in `~/Library/Logs/Tagwerk/refresh.log`, die Build-Ausgabe in `build.log`.
- Gebaut wird der Branch `main` (`TAGWERK_BRANCH` überschreibt das).
- Jeder Fehler (Gerät nicht erreichbar, Git, Build, Signierung, Installation) erzeugt eine Mitteilung auf dem Mac, sobald das Profil weniger als 2 Tage gültig ist.
- Gebaut wird die App unter `app/` (Scheme `Tagwerk`, Bundle-ID `com.melvinmng.tagwerk`).
- Zustand: `~/Library/Application Support/Tagwerk/profile-expiry.<Bundle-ID>` (Ablauf des installierten Profils, Unix-Zeit). Der Zustand gilt pro App, eine neue Bundle-ID startet deshalb als fällig.
- Tests der Entscheidungslogik: `zsh scripts/tests/refresh-decisions.zsh`.

## Voraussetzungen

- Der Mac ist wach und angemeldet, das iPhone im selben WLAN.
- In Xcode → Window → Devices and Simulators ist beim iPhone „Connect via network“ aktiv.
- Die Apple-ID ist in Xcode → Settings → Accounts angemeldet.

## Einrichten

```zsh
# UDID des iPhones ermitteln und lokal ablegen (nicht im Repo)
xcrun devicectl list devices
mkdir -p ~/Library/Application\ Support/Tagwerk
echo 'DEVICE_ID=<UDID>' > ~/Library/Application\ Support/Tagwerk/config
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

## Umstieg vom Spike auf die App (einmalig)

Seit dem Merge von Phase 2a baut der LaunchAgent die echte App statt `TagwerkSpike`.

1. Nach dem Merge auf `main` installiert der nächste stündliche Lauf die App, weil für `com.melvinmng.tagwerk` noch kein Ablaufdatum gespeichert ist. Sofort geht es so:
   ```zsh
   launchctl setenv TAGWERK_FORCE 1
   launchctl kickstart -k gui/$(id -u)/de.tagwerk.refresh
   launchctl unsetenv TAGWERK_FORCE
   ```
2. In `refresh.log` muss `install: ok` stehen.
3. Die Spike-App vom iPhone löschen. Das gibt einen der drei App-Plätze frei.
4. Die alte Datei `profile-expiry` (ohne Bundle-ID) wird nicht mehr gelesen und kann gelöscht werden.

Zum Entwickeln installiert `scripts/install-dev.sh` den aktuellen Stand des Arbeitsverzeichnisses, ohne den Zustand des LaunchAgents zu verändern.

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
