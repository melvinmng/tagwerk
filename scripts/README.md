# Tagwerk installieren und erneuern

Die vollständige Einrichtung für neue Nutzer steht in der [Tagwerk-README](../README.md#tagwerk-auf-deinem-iphone-installieren). Dort findest du die Xcode-Installation, die lokale Konfiguration und die Registrierung des LaunchAgents.

## So arbeitet die Erneuerung

- `de.tagwerk.refresh` ruft `refresh-install.sh` beim Anmelden und stündlich auf. Fehlt ein gespeichertes Ablaufdatum oder hat das Profil weniger als drei Tage Restlaufzeit, versucht das Skript die Neuinstallation.
- Das Skript baut das Scheme `Tagwerk` aus `~/Library/Developer/Tagwerk/src`. Es aktualisiert den dortigen Branch `main` per Fast-forward von `origin`. Mit `TAGWERK_BRANCH` lässt sich der Branch für einen Skriptaufruf auswählen.
- Team-ID, Geräte-ID, Bundle-ID und gegebenenfalls GitHub-Client-ID kommen aus `~/Library/Application Support/Tagwerk/config`. Vor dem Build legt das Skript zwischengespeicherte Profile für das konfigurierte Team und die konfigurierte Bundle-ID nach `~/Library/Developer/Tagwerk/profiles-aside` beiseite. Gelingt der Build, verwirft es sie; scheitert er, legt es sie zurück, damit `install-dev.sh` weiter signieren kann. Es liest das neue Ablaufdatum nach der Installation aus der gebauten App und legt es unter `profile-expiry.<Bundle-ID>` im selben Ordner ab.
- Das Protokoll liegt unter `~/Library/Logs/Tagwerk/refresh.log`. In `build.log` im selben Ordner stehen die Details von Build und Installation. Bei Fehlern mit weniger als zwei Tagen Restlaufzeit versucht das Skript eine macOS-Mitteilung anzuzeigen.

## Widget-Extension, Merker und Rückfall

- Die App enthält die Widget-Extension `TagwerkWidget` mit der Bundle-ID `<Bundle-ID>.widget` (eingebettet unter `PlugIns/TagwerkWidget.appex`) und eine App Group. Das kostenlose Konto stellt dafür ein eigenes Profil aus; es läuft ebenfalls nach sieben Tagen ab. Vor dem Build entfernt das Skript die zwischengespeicherten Profile von App und Extension (Team-ID plus exakt die Bundle-ID oder `<Bundle-ID>.<Suffix>`; ähnlich beginnende fremde Bundle-IDs bleiben unberührt).
- `profile-expiry.<Bundle-ID>` enthält das früheste Ablaufdatum aus App-Profil und allen Extension-Profilen der installierten App. Lässt sich ein vorhandenes Extension-Profil nicht lesen, schreibt das Skript einen Logeintrag und speichert kein neues Ablaufdatum, damit der Wert nicht zu optimistisch ausfällt.
- Fehlt die Apple-ID in Xcode (Build-Log „No Accounts“), meldet das Skript das schon beim ersten Verlängerungsversuch (drei Tage vor Ablauf) mit dem Ablaufdatum, nicht erst zwei Tage vorher, höchstens alle 12 Stunden (Zeitstempel in `account-notice.<Bundle-ID>`). Der Rückfall auf den letzten funktionierenden Commit entfällt dann, weil auch er das Profil nicht verlängern könnte.
- Fehler bei der Signierung der Extension (zum Beispiel zur App Group) gelten wie App-Fehler als Signierfehler (Exit-Code 3).
- Nach jeder erfolgreichen Installation schreibt das Skript den installierten Commit nach `last-good-commit.<Bundle-ID>` und `last-installed.<Bundle-ID>`. `scripts/install-dev.sh` setzt `last-installed.<Bundle-ID>` auf `dev`, weil der Stand des Arbeitsverzeichnisses unbekannt ist.
- Scheitern Build oder Signierung des neuen Stands, baut das Skript einmal den Commit aus `last-good-commit`, aber nur wenn `last-installed` diesem Commit entspricht und er vom aktuellen Stand abweicht. Der Build läuft in einem eigenen `git worktree` unter `~/Library/Developer/Tagwerk/fallback` mit eigenem DerivedData-Ordner und eigenem Log (`build-fallback.log`); der Arbeitsbaum von `src` bleibt unverändert und der Worktree wird danach entfernt. Bei Erfolg aktualisiert das Skript das Ablaufdatum aus dem installierten Rückfall-Build, meldet es immer per Mitteilung und im Log und endet mit Exit-Code 4. Scheitert auch der Rückfall, bleibt das Ablaufdatum unverändert und das Skript meldet den ursprünglichen Fehler (Exit-Code 1 oder 3). Fehler bei Git-Update und Geräteinstallation lösen keinen Rückfall aus.
- Nach dem Git-Update startet sich das Skript einmal mit der frisch geholten Version neu (`TAGWERK_REEXECED=1` verhindert eine Schleife), damit Änderungen am Skript sofort gelten. Ist die neue Version nicht ausführbar oder syntaktisch fehlerhaft, läuft die bisherige weiter.

## Status prüfen und manuell erneuern

```zsh
cd "$HOME/Library/Developer/Tagwerk/src"
scripts/refresh-install.sh --dry-run
launchctl print "gui/$(id -u)/de.tagwerk.refresh"
tail "$HOME/Library/Logs/Tagwerk/refresh.log"
```

`--dry-run` zeigt Ablaufdatum, Fälligkeit und Erreichbarkeit des Geräts an, ohne zu bauen oder zu installieren. `signing identity: present` zeigt ein vorhandenes Apple-Development-Zertifikat an. Ob das konfigurierte Team tatsächlich signieren kann, zeigt der Build.

Sofort neu installieren, zum Beispiel nach einer Änderung der GitHub-Client-ID oder nach Ablauf des Profils:

```zsh
"$HOME/Library/Developer/Tagwerk/src/scripts/refresh-install.sh" --force
```

`scripts/install-dev.sh` installiert aus dem aktuellen Arbeitsverzeichnis mit derselben lokalen Konfiguration. Der Befehl aktualisiert den gespeicherten Profilablauf des LaunchAgents nicht.

| Meldung | Was du prüfen kannst |
|---|---|
| `device: unreachable` | iPhone entsperren, per USB verbinden und den Gerätestatus in Xcode prüfen. Für WLAN Mac und iPhone in dasselbe Netz bringen und die Kopplung prüfen. |
| `No Accounts` oder `signing failed` | In **Xcode → Settings → Accounts** die Anmeldung prüfen. Kontrolliere die Team-ID in der lokalen Konfiguration. Wenn ein Schlüsselbunddialog offen ist, bestätige den Zugriff für `codesign`. |
| Bundle-ID ist nicht verfügbar | Bei einer Erstinstallation eine eigene ID wählen. Bei einer bestehenden Installation prüfen, ob du noch dasselbe Team und dieselbe App-ID verwendest. |
| Das iPhone meldet das App-Limit | Ein kostenloses Personal Team kann bis zu drei Entwicklungs-Apps pro Gerät installieren. Prüfe, welche deiner anderen Entwicklungs-Apps einen Platz belegt. |
| `build: git update failed` | Internetverbindung und `origin` im Hintergrund-Klon prüfen. Der zu bauende Branch muss sich per Fast-forward aktualisieren lassen. |
| LaunchAgent startet nicht | `launchctl print "gui/$(id -u)/de.tagwerk.refresh"` und `/tmp/de.tagwerk.refresh.err` prüfen. Code 64 weist auf die lokale Konfiguration hin. |

## Bestehende Installation übernehmen

Falls deine lokale Konfiguration bisher nur `DEVICE_ID` enthält, ergänze `DEVELOPMENT_TEAM` und `TAGWERK_BUNDLE_ID` mit den Werten deiner bestehenden Installation. Wenn du bisher mit der Bundle-ID `com.melvinmng.tagwerk` signiert hast, trage diesen Wert ein, damit iOS die App beim Refresh als Update installiert. Bei einem Wechsel auf eine eigene OAuth App melde dich anschließend in Tagwerk neu bei GitHub an.

`TagwerkSpike` aus Phase 1 ist eine eigene App. Eine Neuinstallation von `Tagwerk` ersetzt den Spike nicht. Entferne ihn auf dem iPhone, wenn du den Entwicklungs-App-Platz freigeben möchtest.

## Hintergrundbetrieb abschalten

```zsh
launchctl bootout "gui/$(id -u)/de.tagwerk.refresh"
rm "$HOME/Library/LaunchAgents/de.tagwerk.refresh.plist"
```

## Exit-Codes des Refresh-Skripts

| Code | Bedeutung |
|---|---|
| 0 | Installation erfolgreich, Prüfung abgeschlossen oder Neuinstallation noch nicht fällig |
| 1 | Quellcode konnte nicht aktualisiert werden, Projektgenerierung oder Build fehlgeschlagen |
| 2 | iPhone nicht erreichbar oder Installation fehlgeschlagen |
| 3 | Signierung fehlgeschlagen (auch bei der Widget-Extension) |
| 4 | Der neue Stand ließ sich nicht bauen oder signieren; der letzte funktionierende Stand wurde stattdessen neu installiert |
| 64 | Konfiguration oder Skriptargument ungültig |

Entscheidungslogik und lokale Konfiguration testen:

```zsh
zsh scripts/tests/refresh-decisions.zsh
```


## Testdaten im Simulator

Debug-Builds im Simulator legen mit dem Startargument `-TagwerkDemoData` Beispieldaten an (`app/Tagwerk/App/DemoData.swift`): Kalender „Demo Termine“, „Demo Freigabe“, „Demo Uni“ (Deadline-Kalender), Plan-Kalender „Demo Tagwerk“ und die Erinnerungsliste „Demo Aufgaben“ mit wiederkehrenden Erinnerungen. Bei jedem Start mit dem Argument werden genau diese Kalender gelöscht und neu angelegt; die Einrichtung gilt danach als abgeschlossen. Auf einem echten Gerät ist der Code nicht enthalten.

Kalender- und Erinnerungszugriff vorher im Simulator erteilen, dann mit dem Argument starten (z. B. über die T3-Geräte-Tools: `settings permission grant calendar full`, `settings permission grant reminders`, `open local.tagwerk.app --relaunch --launch-args=-TagwerkDemoData`; ohne lokale Konfiguration nutzt der Simulator-Build die Standard-Bundle-ID `local.tagwerk.app`).
