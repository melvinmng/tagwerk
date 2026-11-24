# Tagwerk installieren und erneuern

Die vollständige Einrichtung für neue Nutzer steht in der [Tagwerk-README](../README.md#tagwerk-auf-deinem-iphone-installieren). Dort findest du die Xcode-Installation, die lokale Konfiguration und die Registrierung des LaunchAgents.

## So arbeitet die Erneuerung

- `de.tagwerk.refresh` ruft `refresh-install.sh` beim Anmelden und stündlich auf. Jeder Lauf holt zuerst per `git fetch` den Stand von `origin/main` (ohne Checkout oder Build) und installiert dann in zwei Fällen:
  1. **Profil-Erneuerung:** Es fehlt ein gespeichertes Ablaufdatum oder das Profil hat weniger als drei Tage Restlaufzeit.
  2. **Neuer Commit:** `origin/main` enthält einen Commit, der nicht auf dem iPhone ist. Es gibt keine Begrenzung auf einen Lauf pro Nacht.
- Die Regel für neue Commits (`should_install`): Ist der Commit von `origin/main` schon installiert, passiert nichts. Ist er der zuletzt gescheiterte Commit (`last-failed-commit.<Bundle-ID>`), wartet das Skript, bis sich `origin/main` ändert, statt ihn stündlich erneut zu bauen. Ist der Gerätestand unbekannt (`last-installed` ist `dev` nach `install-dev.sh` oder fehlt), installiert das Skript nur, wenn `origin/main` vom Commit der letzten Refresh-Installation (`last-good-commit`) abweicht. Ein mit `install-dev.sh` installierter Entwicklungsstand bleibt also bis zum nächsten neuen Commit auf `main`, bis zur fälligen Profil-Erneuerung oder bis zu `--force` auf dem iPhone. Ist das Profil fällig, installiert das Skript immer.
- Lastbremse: Liegt die Load Average der letzten 5 Minuten über dem Dreifachen der CPU-Anzahl (`LOAD_SKIP_PER_CPU` im Skript) und ist das Profil nicht fällig, überspringt der Lauf die Installation mit einem Logeintrag; der nächste stündliche Lauf versucht es erneut.
- Ist das Gerät nicht erreichbar oder schlägt der `git fetch` fehl und das Profil ist nicht fällig, beendet sich der Lauf ohne Mitteilung. Der Grund steht einmal pro Phase im Log (`skip-note.<Bundle-ID>` merkt sich den letzten Grund). Mitteilungen gibt es nur kurz vor Ablauf, beim Rückfall und einmal, wenn die Installation eines neuen Commits scheitert.
- Das Skript baut das Scheme `Tagwerk` aus `~/Library/Developer/Tagwerk/src`. Es aktualisiert den dortigen Branch `main` per Fast-forward von `origin`, sobald eine Installation ansteht. Mit `TAGWERK_BRANCH` lässt sich der Branch für einen Skriptaufruf auswählen.
- Team-ID, Geräte-ID, Bundle-ID und gegebenenfalls GitHub-Client-ID kommen aus `~/Library/Application Support/Tagwerk/config`. Vor einem Build zur Profil-Erneuerung legt das Skript zwischengespeicherte Profile für das konfigurierte Team und die konfigurierte Bundle-ID nach `~/Library/Developer/Tagwerk/profiles-aside` beiseite. Gelingt der Build, verwirft es sie; scheitert er, legt es sie zurück, damit `install-dev.sh` weiter signieren kann. Bei einer Installation wegen eines neuen Commits, solange das Profil noch gültig ist, bleibt das zwischengespeicherte Profil unangetastet und das Ablaufdatum unverändert. Es liest das neue Ablaufdatum nach der Installation aus der gebauten App und legt es unter `profile-expiry.<Bundle-ID>` im selben Ordner ab.
- Das Protokoll liegt unter `~/Library/Logs/Tagwerk/refresh.log`. In `build.log` im selben Ordner stehen die Details von Build und Installation. Bei Fehlern mit weniger als zwei Tagen Restlaufzeit versucht das Skript eine macOS-Mitteilung anzuzeigen.

## Widget-Extension, Merker und Rückfall

- Die App enthält die Widget-Extension `TagwerkWidget` mit der Bundle-ID `<Bundle-ID>.widget` (eingebettet unter `PlugIns/TagwerkWidget.appex`) und eine App Group. Das kostenlose Konto stellt dafür ein eigenes Profil aus; es läuft ebenfalls nach sieben Tagen ab. Vor dem Build entfernt das Skript die zwischengespeicherten Profile von App und Extension (Team-ID plus exakt die Bundle-ID oder `<Bundle-ID>.<Suffix>`; ähnlich beginnende fremde Bundle-IDs bleiben unberührt).
- Die Share-Erweiterung `TagwerkShare` (Bundle-ID `<Bundle-ID>.share`, eingebettet unter `PlugIns/TagwerkShare.appex`) braucht ebenfalls eine eigene App-ID mit App Group und ein eigenes Profil. Kostenlose Konten dürfen nur wenige neue App-IDs je 7 Tage registrieren; bricht die Profilerstellung mit einem Limit- oder Capability-Fehler ab, lässt sich die App erst nach Ablauf der Frist (oder mit einem bezahlten Konto) installieren. Das Skript behandelt die Erweiterung wie das Widget.
- `profile-expiry.<Bundle-ID>` enthält das früheste Ablaufdatum aus App-Profil und allen Extension-Profilen der installierten App. Lässt sich ein vorhandenes Extension-Profil nicht lesen, schreibt das Skript einen Logeintrag und speichert kein neues Ablaufdatum, damit der Wert nicht zu optimistisch ausfällt.
- Fehlt die Apple-ID in Xcode (Build-Log „No Accounts“), meldet das Skript das schon beim ersten Verlängerungsversuch (drei Tage vor Ablauf) mit dem Ablaufdatum, nicht erst zwei Tage vorher, höchstens alle 12 Stunden (Zeitstempel in `account-notice.<Bundle-ID>`). Der Rückfall auf den letzten funktionierenden Commit entfällt dann, weil auch er das Profil nicht verlängern könnte.
- Fehler bei der Signierung der Extension (zum Beispiel zur App Group) gelten wie App-Fehler als Signierfehler (Exit-Code 3).
- Nach jeder erfolgreichen Installation schreibt das Skript den installierten Commit nach `last-good-commit.<Bundle-ID>` und `last-installed.<Bundle-ID>`. `scripts/install-dev.sh` setzt `last-installed.<Bundle-ID>` auf `dev`, weil der Stand des Arbeitsverzeichnisses unbekannt ist. Scheitert Build oder Signierung eines Commits, schreibt das Skript ihn nach `last-failed-commit.<Bundle-ID>`; die nächste erfolgreiche Installation löscht den Merker.
- Scheitern Build oder Signierung des neuen Stands bei fälligem Profil, baut das Skript einmal den Commit aus `last-good-commit`, aber nur wenn `last-installed` diesem Commit entspricht und er vom aktuellen Stand abweicht. Der Build läuft in einem eigenen `git worktree` unter `~/Library/Developer/Tagwerk/fallback` mit eigenem DerivedData-Ordner und eigenem Log (`build-fallback.log`); der Arbeitsbaum von `src` bleibt unverändert und der Worktree wird danach entfernt. Bei Erfolg aktualisiert das Skript das Ablaufdatum aus dem installierten Rückfall-Build, meldet es immer per Mitteilung und im Log und endet mit Exit-Code 4. Scheitert auch der Rückfall, bleibt das Ablaufdatum unverändert und das Skript meldet den ursprünglichen Fehler (Exit-Code 1 oder 3). Fehler bei Git-Update und Geräteinstallation lösen keinen Rückfall aus. Ist das Profil nicht fällig, entfällt der Rückfall: Der letzte funktionierende Stand ist dann ohnehin auf dem iPhone und die Neuinstallation würde nichts ändern.
- Nach dem Git-Update (nur wenn eine Installation ansteht) startet sich das Skript einmal mit der frisch geholten Version neu (`TAGWERK_REEXECED=1` verhindert eine Schleife), damit Änderungen am Skript sofort gelten. Ist die neue Version nicht ausführbar oder syntaktisch fehlerhaft, läuft die bisherige weiter. Der Hintergrund-Klon führt das Skript aus `~/Library/Developer/Tagwerk/src` aus: Eine ältere Version dort holt `origin/main` erst, wenn das Profil fällig ist. Nach dem Merge dieser Änderung einmal `git -C "$HOME/Library/Developer/Tagwerk/src" pull --ff-only` ausführen (oder `refresh-install.sh --force` aufrufen), damit der stündliche Lauf neue Commits sofort erkennt.

## Status prüfen und manuell erneuern

```zsh
cd "$HOME/Library/Developer/Tagwerk/src"
scripts/refresh-install.sh --dry-run
launchctl print "gui/$(id -u)/de.tagwerk.refresh"
tail "$HOME/Library/Logs/Tagwerk/refresh.log"
```

`--dry-run` zeigt Ablaufdatum, Fälligkeit, die Installationsentscheidung (auf Basis des zuletzt geholten `origin/main`, ohne `git fetch`), Load Average und Erreichbarkeit des Geräts an, ohne zu bauen oder zu installieren. `signing identity: present` zeigt ein vorhandenes Apple-Development-Zertifikat an. Ob das konfigurierte Team tatsächlich signieren kann, zeigt der Build.

Sofort neu installieren, zum Beispiel nach einer Änderung der GitHub-Client-ID oder nach Ablauf des Profils (ignoriert Fälligkeit, installierten Commit und den Merker des zuletzt gescheiterten Commits):

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
| 0 | Installation erfolgreich, nichts zu installieren oder Lauf übersprungen (Last, Gerät nicht erreichbar bei nicht fälligem Profil) |
| 1 | Quellcode konnte nicht aktualisiert werden, Projektgenerierung oder Build fehlgeschlagen |
| 2 | iPhone nicht erreichbar oder Installation fehlgeschlagen |
| 3 | Signierung fehlgeschlagen (auch bei der Widget-Extension) |
| 4 | Der neue Stand ließ sich bei fälligem Profil nicht bauen oder signieren; der letzte funktionierende Stand wurde stattdessen neu installiert |
| 64 | Konfiguration oder Skriptargument ungültig |

Entscheidungslogik und lokale Konfiguration testen:

```zsh
zsh scripts/tests/refresh-decisions.zsh
```


## Testdaten im Simulator

Debug-Builds im Simulator legen mit dem Startargument `-TagwerkDemoData` Beispieldaten an (`app/Tagwerk/App/DemoData.swift`): Kalender „Demo Termine“, „Demo Freigabe“, „Demo Uni“ (Deadline-Kalender), Plan-Kalender „Demo Tagwerk“ und die Erinnerungsliste „Demo Aufgaben“ mit wiederkehrenden Erinnerungen. Bei jedem Start mit dem Argument werden genau diese Kalender gelöscht und neu angelegt; die Einrichtung gilt danach als abgeschlossen. Auf einem echten Gerät ist der Code nicht enthalten.

Kalender- und Erinnerungszugriff vorher im Simulator erteilen, dann mit dem Argument starten (z. B. über die T3-Geräte-Tools: `settings permission grant calendar full`, `settings permission grant reminders`, `open local.tagwerk.app --relaunch --launch-args=-TagwerkDemoData`; ohne lokale Konfiguration nutzt der Simulator-Build die Standard-Bundle-ID `local.tagwerk.app`).

## UI-Audits auf Stabilität prüfen

`scripts/stress-audits.sh [--collect] [Wiederholungen] [Testauswahl …]` wiederholt die sechs Audit-Klassen der UI-Tests (Standard, AX5, Rezepte, Rezepte AX5, Abend, Abend AX5) (jede Wiederholung ein eigener Lauf, ohne Wiederholen bei Fehlschlag) und gibt je Test die Zahl der Läufe und Fehlschläge, die gruppierten Fehlermeldungen und die Zahl der Audit-Timeout-Wiederholungen aus. Mit `--collect` schlagen die Audits nicht fehl; stattdessen steht jeder Befund, der nicht auf der Allowlist steht, mit der Zahl der Wiederholungen im Bericht, in denen er auftrat (nicht in jeder Wiederholung = flackernd). Das Skript nimmt dieselbe Sperre wie `app/test-all.sh`: je Arbeitskopie läuft nur ein Testlauf. Ohne künstliche Last: Die Läufe der anderen Arbeitskopien sind die natürliche Last. Nötig bei Änderungen an den Audits, an `UITestMode`, an `DemoData` oder am Start-Task, nicht vor jedem Merge.

## String-Kataloge

Die elf `.xcstrings`-Kataloge sind JSON im festen Format `json.dumps(…, ensure_ascii=False, indent=2, sort_keys=True)`: Schlüssel auf jeder Ebene nach Codepunkt sortiert, leere Objekte als `{}`. Je Datei unterscheiden sich nur der Trenner nach dem Schlüssel (`": "` oder `" : "`) und das Zeilenende am Dateiende. `scripts/catalog_format.py` erkennt das und schreibt Kataloge in genau dem Stil der Datei, sodass sich nur die Zeilen der geänderten Einträge ändern.

- `scripts/sync-strings.sh [--check] [--no-build]` gleicht die Kataloge mit dem Quelltext ab. `xcstringstool` schreibt nur in eine Kopie, übernommen wird der Inhalt im Stil des Katalogs; ohne inhaltliche Änderung bleibt die Datei unberührt.
- `scripts/apply-translations.py` schreibt Übersetzungen aus `scripts/translations/en.json` ebenso im Stil der Datei.
- `scripts/check-strings.py` (Stufe „string catalogs“ von `app/test-all.sh`) meldet einen Katalog, der nicht im Repository-Format steht, mit der ersten abweichenden Zeile. Das passiert zum Beispiel, wenn ein Eintrag von Hand an der falschen Stelle eingefügt wurde oder Xcode die Datei in der Oberfläche neu geschrieben hat; `scripts/sync-strings.sh` stellt das Format wieder her.
- `scripts/check-colors.py` (ebenfalls Stufe „string catalogs“) schlägt fehl, wenn im App-Target `.foregroundStyle(.secondary)`, `Color.secondary` oder `.red`, `.orange`, `.green`, `.purple` auf einem `Text(` oder `Label(` als Schriftfarbe steht; Text nutzt die Töne aus `Common/TextTones.swift` (`.secondaryText`, `.redText`, …). Eine Zeile mit `// system-colour: <Grund>` ist ausgenommen. `--report` zählt nur. Test: `scripts/tests/test_check_colors.py`.
- `scripts/merge-xcstrings.py` ist der Git-Merge-Treiber für die String Catalogs und `scripts/translations/en.json` (schlüsselweiser Drei-Wege-Merge im Format der Datei); `scripts/setup-git-merge-drivers.sh` trägt ihn in die lokale Git-Konfiguration ein (einmal je Klon, wiederholbar, `--unset` entfernt ihn). Details im Abschnitt „Merge-Treiber“ der [README](../README.md). Test: `scripts/tests/test_merge_xcstrings.py` (braucht `git` und `zsh`).
- `scripts/ui-hang-sampler.py` und `scripts/ui-test-log.py` gehören zur UI-Stufe von `app/test-all.sh`: der erste schreibt bei einem Hänger der App ein `sample` des Prozesses nach `hang-*.txt` im Log-Ordner, der zweite liest fehlgeschlagene und wiederholte UI-Tests aus den Logs (Grundlage der gezielten Wiederholung). Tests: `scripts/tests/test_ui_hang_sampler.py`, `scripts/tests/test-all-ui-selection.zsh`, `scripts/tests/test-all-ui-retry.zsh`.
- `scripts/ui-watchdog.py` startet jeden `xcodebuild`-Aufruf von `app/test-all.sh`, folgt dessen Log und zeigt den Testfortschritt (`Test Case … started/passed/failed`) und alle 300 s eine Herzschlag-Zeile. Bleibt das Log stumm (`--silence`, in `test-all.sh` `TAGWERK_UI_SILENCE_SECONDS` 600 s bzw. `TAGWERK_STAGE_SILENCE_SECONDS` 900 s) oder dauert der Aufruf zu lange (`--max-seconds`), schreibt er Diagnosen nach `<Log-Ordner>/watchdog-<Phase>-<Zeit>/` (`summary.txt`, `ps.txt`, `simctl-booted.txt`, `sample-*.txt` von App, UI-Test-Runner, xcodebuild und testmanagerd, `simulator-log.txt` der letzten 10 Minuten), beendet die Prozessgruppe samt Nachkommen (TERM, nach `--grace` KILL), fährt mit `--shutdown-simulator` den Simulator herunter und endet mit Status 124. `scripts/test-env.sh` begrenzt außerdem `simctl boot`, `simctl bootstatus -b` (`TAGWERK_BOOT_TIMEOUT_SECONDS`, 300 s), das Auslesen der Bundle-ID (180 s) und die Berechtigungen (120 s) und zeigt die Ausgabe. Die Laufzeitlimits (`--max-seconds`) sind in `test-all.sh` ohne Umgebungsvariable aus; die Stille-Limits gelten immer. Tests: `scripts/tests/test_ui_watchdog.py` (Attrappen, die stumm bleiben oder endlos schreiben), `scripts/tests/test-all-watchdog.zsh` (der Ablauf in `test-all.sh`: Meldung, Diagnoseordner, keine Wiederholung).
- `scripts/ui-test-shards.py` verteilt die UI-Testklassen (aus den Quellen von `app/TagwerkUITests`) nach den gemessenen Dauern in `app/TagwerkUITests/ui-test-durations.txt` auf Shards (`TAGWERK_UI_SHARD=I/N` in `app/test-all.sh`; `scripts/ui-test-shards.py plan 2 --set pr` zeigt die Aufteilung und die Summen). Eine Klasse ohne Eintrag bekommt das mittlere Gewicht und wird gemeldet. Der letzte Shard läuft als Rest der anderen (`others`, in `test-all.sh` als `-skip-testing`), damit eine Klasse, die der Quelltext-Scan nicht erkennt, trotzdem läuft. Test: `scripts/tests/test_ui_test_shards.py` (jede Klasse in genau einem Shard, Ausgewogenheit der echten Aufteilung, jede Klasse hat eine Dauer).
- `scripts/ci-changes.py` entscheidet im Job `Changes` des Workflows aus den geänderten Dateien, ob `Fast tests`, die `UI shard`-Jobs und `Script tests` laufen (nur Doku: nichts; Skripte der String-Catalog-Stufe: ohne UI; übrige Skripte: nur Skript-Tests; unbekannte Pfade: alles). Test: `scripts/tests/test_ci_changes.py`, darunter die Prüfung, dass jedes von `test-all.sh`, `test-env.sh`, `sync-strings.sh` und dem Workflow aufgerufene Skript in den Listen steht.
- `scripts/ci-collect-artifacts.sh` (nur CI) beendet nach einem Zeitlimit oder Abbruch die zurückgelassenen Testprozesse und packt Logs und Ergebnisbündel in ein `tar.gz` für den Artefakt-Upload; außerhalb von GitHub Actions beendet es ohne `--force` nichts. Test: `scripts/tests/ci-collect-artifacts.zsh`.
- `scripts/run-script-tests.sh` führt alle Tests unter `scripts/tests` aus (Python-Unit-Tests und jedes `*.zsh`, rund eine Minute, ohne Build und Simulator); es ist die Prüfung für Änderungen unter `scripts/` und an `app/test-all.sh` und läuft in CI als Job `Script tests`.
- Tests: `scripts/run-script-tests.sh` führt alles aus; einzeln `/usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v` und `zsh scripts/tests/<Name>.zsh` (z. B. `sync-strings-format.zsh`, braucht `xcrun xcstringstool`; keiner braucht einen Build oder Simulator).
