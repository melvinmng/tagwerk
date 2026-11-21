# Tagwerk

Tagwerk ist eine iPhone-App für lokale Aufgaben, Apple Erinnerungen und GitHub-Issues. Kalenderintegration und KI-Tagesplanung werden in Phase 2 ausgebaut. Ernährung und Training sind geplant. Den Entwicklungsstand findest du in [TODO.md](TODO.md).

## Tagwerk auf deinem iPhone installieren

Du brauchst einen Mac mit Apple-Chip und **macOS Tahoe 26.6 oder neuer**, ein iPhone mit **iOS 27.0 oder neuer**, ein USB-Datenkabel und einen eigenen kostenlosen **Apple Account**. Die Anleitung verwendet **Xcode 27.2**. Für die lokale Installation genügt das **Personal Team** in Xcode. Eine Mitgliedschaft im kostenpflichtigen Apple Developer Program ist dafür nicht erforderlich. [Xcode-Systemanforderungen](https://developer.apple.com/xcode/system-requirements/) · [Apple-Account und Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account/)

### 1. Xcode und XcodeGen auf dem Mac installieren

1. Lade **Xcode 27.2** aus dem Mac App Store oder von Apple Developer. Lege die App als **Xcode.app** unter **Programme** ab. Die Skripte verwenden den Pfad `/Applications/Xcode.app`. [Xcode-Downloads](https://developer.apple.com/xcode/)
2. Öffne Xcode, akzeptiere die Lizenz und installiere beim ersten Start die benötigten Komponenten für **iOS**. Falls der Dialog bereits geschlossen ist, findest du sie unter **Xcode → Settings → Components**. [Xcode-Komponenten installieren](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
3. Öffne **Xcode → Settings → Accounts** und füge deinen eigenen Apple Account hinzu. In **Xcode → Settings → Locations** wählst du unter **Command Line Tools** deine Xcode-Version aus.
4. Installiere **Homebrew**, falls `brew --version` noch nicht funktioniert. Übernimm die angezeigten **Next steps** des Installers, damit `brew` im Terminal verfügbar ist. [Homebrew installieren](https://brew.sh/)
5. Öffne **Terminal** und führe diese Befehle aus. Der letzte Befehl sollte die installierte Xcode-Version anzeigen.

   ```zsh
   brew install xcodegen
   xcodegen --version
   xcodebuild -version
   ```

### 2. Quellcode laden und iPhone koppeln

Kopiere die Befehle ins Terminal. Der Klon liegt außerhalb von iCloud Drive, damit der Hintergrundprozess später darauf zugreifen kann. GitHub erlaubt den Download aus dem öffentlichen Repository ohne Anmeldung. Wenn du auch die Quelle für künftige Builds selbst verwalten möchtest, kannst du die URL durch die HTTPS-URL deines eigenen öffentlichen Forks ersetzen.

```zsh
mkdir -p "$HOME/Library/Developer/Tagwerk"
git clone --branch main https://github.com/melvinmng/tagwerk.git "$HOME/Library/Developer/Tagwerk/src"
cd "$HOME/Library/Developer/Tagwerk/src"
(cd app && xcodegen)
open app/Tagwerk.xcodeproj
```

1. Verbinde dein entsperrtes iPhone per USB mit dem Mac. Bestätige eventuelle Rückfragen auf dem Mac und auf dem iPhone **Diesem Computer vertrauen**.
2. Öffne in Xcode **Xcode → Open Developer Tool → Device Hub** und wähle das iPhone. Folge den Anweisungen zur Kopplung und warte, bis das Gerät einsatzbereit ist. [Geräte in Xcode koppeln](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)
3. Aktiviere auf dem iPhone **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus**. Starte das iPhone über den Dialog neu und bestätige anschließend die Aktivierung. Falls der Menüpunkt fehlt, beginne zuerst die Kopplung in Xcode. [Entwicklermodus aktivieren](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

### 3. App zum ersten Mal starten

1. Wähle im Xcode-Projektnavigator das Projekt **Tagwerk** und unter **Targets** den Eintrag **Tagwerk**. Öffne **Signing & Capabilities** und trage unter **Bundle Identifier** eine eigene eindeutige App-ID ein, zum Beispiel `local.tagwerk.anna-47f2`. Verwende in deinem Wert nur Buchstaben, Ziffern, Punkte und Bindestriche. Falls Xcode meldet, dass die ID schon vergeben ist, wähle einen anderen Suffix.
2. Aktiviere **Automatically manage signing** und wähle unter **Team** deinen eigenen Eintrag **Personal Team**.
3. Wähle oben in Xcode das Scheme **Tagwerk** und dein **physisches iPhone** als Ziel. Starte den Build über ▶ oder **⌘R**. Xcode erstellt das Signierzertifikat und das Installationsprofil für dein Team. Falls das iPhone dem Entwickler erst vertrauen muss, wähle deinen Eintrag unter **Einstellungen → Allgemein → VPN & Geräteverwaltung** und folge dem Dialog.
4. Öffne Tagwerk auf dem iPhone und folge der Einrichtung. Erlaube den Zugriff auf Erinnerungen und Kalender nach Bedarf. Wähle bei GitHub zunächst **Überspringen**. Sobald die Aufgabenansicht erscheint, kannst du eine lokale Aufgabe anlegen und damit die Installation prüfen.

### 4. Geräte-ID und Signierung für den Hintergrundbetrieb speichern

Xcode hat deine Auswahl im erzeugten Projekt gespeichert. Lies die Werte aus, **bevor du XcodeGen erneut ausführst**. Führe diesen Block mit angeschlossenem iPhone im Terminal aus.

```zsh
cd "$HOME/Library/Developer/Tagwerk/src"
xcodebuild -project app/Tagwerk.xcodeproj -target Tagwerk -configuration Debug -showBuildSettings \
  | awk '$1 == "DEVELOPMENT_TEAM" || $1 == "PRODUCT_BUNDLE_IDENTIFIER"'
xcrun xctrace list devices
```

- `DEVELOPMENT_TEAM` ist die zehnstellige ID deines Personal Teams.
- `PRODUCT_BUNDLE_IDENTIFIER` ist die App-ID, die du in Xcode eingetragen hast.
- `DEVICE_ID` ist die Geräte-ID (UDID) deines iPhones. Kopiere in der Ausgabe unter **Devices** die Kennung in der letzten Klammer hinter dem Namen deines iPhones.

Lege die lokale Konfiguration an.

```zsh
mkdir -p "$HOME/Library/Application Support/Tagwerk"
nano "$HOME/Library/Application Support/Tagwerk/config"
```

Füge die drei Zeilen ein und ersetze **alle Beispielwerte** durch deine eigenen Werte. Die Werte stehen direkt hinter dem Gleichheitszeichen. Speichere mit **Ctrl+O**, bestätige mit **Enter** und beende den Editor mit **Ctrl+X**.

```zsh
DEVICE_ID=DEINE_IPHONE_UDID
DEVELOPMENT_TEAM=DEINE_TEAM_ID
TAGWERK_BUNDLE_ID=local.tagwerk.anna-47f2
```

Behalte bei Neuinstallationen dasselbe Team und dieselbe Bundle-ID bei. Unter dieser Identität installiert iOS neue Builds als Update, sodass deine lokalen App-Daten erhalten bleiben. Die Konfiguration liegt in deinem Benutzerordner außerhalb des Git-Klons.

### 5. Automatische Erneuerung aktivieren

Das Installationsprofil eines kostenlosen Personal Teams gilt **sieben Tage**. Das mitgelieferte Skript prüft die Restlaufzeit bei der Mac-Anmeldung und anschließend einmal pro Stunde. Bei weniger als drei Tagen Restlaufzeit erstellt es mit Xcode ein neues Profil und installiert die App erneut. Der Mac muss dafür angemeldet und wach sein. Das iPhone muss per USB oder im selben WLAN für Xcode erreichbar sein. Bei abgelaufenem Profil kannst du die App mit demselben Team und derselben Bundle-ID erneut installieren und wieder öffnen. [Apples Regeln für Personal Teams](https://developer.apple.com/help/account/basics/about-your-developer-account/)

1. Teste zuerst mit angeschlossenem iPhone. Der erste Befehl zeigt die Erreichbarkeit an. Der zweite baut und installiert Tagwerk mit der lokalen Konfiguration.

   ```zsh
   cd "$HOME/Library/Developer/Tagwerk/src"
   scripts/refresh-install.sh --dry-run
   scripts/refresh-install.sh --force
   tail "$HOME/Library/Logs/Tagwerk/refresh.log"
   ```

   Im Protokoll sollte `install: ok` mit einem Ablaufdatum stehen. Öffne Tagwerk und prüfe, ob deine lokale Testaufgabe noch da ist. Falls der Schlüsselbund nach Zugriff durch `codesign` auf deinen Signierschlüssel fragt, wähle **Immer erlauben**, damit auch der Hintergrundprozess signieren kann.

2. Für den Betrieb ohne Kabel verbinde Mac und iPhone mit demselben WLAN. Ziehe das USB-Kabel ab und wiederhole `scripts/refresh-install.sh --dry-run`. Erwartet wird `device: reachable`. Falls nötig, öffne den **Device Hub** und kopple das iPhone über **+ → Pair Nearby Device** im WLAN oder nutze die Kabelverbindung weiter. [Drahtlose Kopplung in Xcode](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)

3. Installiere den mitgelieferten LaunchAgent. Er startet das Skript in deinem macOS-Benutzerkonto. Führe diesen Block aus dem Git-Klon aus.

   ```zsh
   mkdir -p "$HOME/Library/LaunchAgents"
   cp scripts/de.tagwerk.refresh.plist "$HOME/Library/LaunchAgents/"
   launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/de.tagwerk.refresh.plist"
   launchctl print "gui/$(id -u)/de.tagwerk.refresh"
   ```

   `launchctl print` sollte den Dienst anzeigen. Zwischen den Prüfungen kann er inaktiv sein. Vor einem fälligen Build holt das Skript die neuesten Änderungen von `origin/main` aus deinem Klon. Zum manuellen Erneuern, zur Fehlersuche und zum Abschalten siehe [Installationsskripte](scripts/README.md).

## GitHub-Aufgaben verbinden (optional)

Für Aufgaben aus GitHub verwendest du eine **eigene OAuth App**. Die lokale App und Apple Erinnerungen kannst du bereits nach Schritt 3 verwenden.

1. Öffne auf GitHub **Settings → Developer settings → OAuth Apps → New OAuth App**. Gib einen Namen und als **Homepage URL** die URL des Tagwerk-Repositories oder deines Forks an. Das Formular verlangt eine **Authorization callback URL**. Dafür kannst du beispielsweise `http://localhost` eintragen, da der verwendete Device Flow keine Rückleitung benötigt. Aktiviere **Enable Device Flow** und registriere die App. Falls GitHub **Expire user access tokens** anbietet, lasse die Option aktiv. [OAuth App erstellen](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app) · [GitHub Device Flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow)
2. Kopiere die **Client ID** und ergänze in deiner lokalen Datei `~/Library/Application Support/Tagwerk/config` eine Zeile `GITHUB_CLIENT_ID=DEINE_CLIENT_ID`. Die öffentlich sichtbare Client ID genügt für diesen Anmeldeweg. Ein Client Secret brauchst du dafür nicht.
3. Installiere die App mit der neuen Einstellung erneut.

   ```zsh
   "$HOME/Library/Developer/Tagwerk/src/scripts/refresh-install.sh" --force
   ```

4. Öffne in Tagwerk **Einstellungen → GitHub → Mit GitHub anmelden**. Gib den angezeigten Code im Browser bei GitHub ein. Prüfe, dass dort dein eigenes Konto und deine eigene OAuth App angezeigt werden, bevor du den Zugriff bestätigst. Anschließend kannst du deine Projects in Tagwerk auswählen.

Tagwerk fordert Zugriff auf Repositories und Projects an (`repo` und `project`). `offline_access` dient der Erneuerung zeitlich begrenzter Tokens. Die Zugangstokens liegen im Schlüsselbund des iPhones. Du kannst dich in Tagwerk abmelden und die Berechtigung in GitHub unter **Settings → Applications → Authorized OAuth Apps** widerrufen.

Tagwerk lädt dir zugewiesene offene Issues aus offenen Projects, soweit sie im Project keiner **Done**-Spalte zugeordnet sind. Unterstützte Project-Felder sind **Status**, **Priority** (P1–P5), **Due date**, **Estimate (h)** und **Estimate (MDs)** mit 8 Stunden je MD. Vor dem Schreiben lädt Tagwerk das Issue erneut und zeigt bei zwischenzeitlichen Änderungen einen Konflikt an. Offline zeigt die App den zuletzt geladenen Stand an.

Du kannst Titel, Beschreibung, Labels und Project-Felder bearbeiten, Kommentare schreiben und Issues schließen oder wieder öffnen. Neue Issues weist dir Tagwerk selbst zu und legt sie im gewählten Project mit Status **Ready** an. Beim Abhaken schließt Tagwerk zuerst das Issue und setzt anschließend den Status in den zugehörigen Projects.

## Planen

Der Tab **Planen** zeigt Tag, Woche oder Monat. Der **Arbeitstag** einer Aufgabe liegt nur in Tagwerk; die Fälligkeit in Erinnerungen oder GitHub ändert sich dabei nicht. Fälligkeiten verschiebst du gesondert über **Fälligkeit verschieben**.

- **Tag:** Stundenraster (oder Liste) mit Terminen, Zeitblöcken und Mittagspause. Halten wählt einen Eintrag aus und zeigt Griffe für Beginn und Ende; halten und ziehen verschiebt ihn. Das Panel **Ohne Uhrzeit** unten enthält die für den Tag festgelegten Aufgaben sowie **Heute offen** und **Überfällig**; am Griff ≡ ziehst du eine Aufgabe auf eine Uhrzeit.
- **Freie Zeit:** Arbeitszeit des Wochentags (oder abweichend für einen Tag) minus Termine mit Puffer, Mittagspause und wiederkehrendem Aufwand. Heute zählt nur die Zeit ab jetzt.
- **Zeitblöcke** sind Termine im Plan-Kalender „Tagwerk“ mit `tagwerk://task/…` im URL-Feld. Termine mit `#<Nummer>` eines Issues oder mit dem genauen Titel einer Erinnerung werden automatisch verknüpft.
- **Termine** aller beschreibbaren Kalender lassen sich in Tagwerk anlegen, ändern und löschen. **Frei** markiert Termine nur in Tagwerk, sie belegen dann keine Zeit.
- **Gleiche Termine** in mehreren Kalendern fasst Tagwerk nur nach deiner Zustimmung zusammen. **Einstellungen → Planen → Kalender-Diagnose** zeigt je Kalender, welche Termine gelesen und gezeigt werden.
- **Wichtige Deadlines:** P1-Aufgaben, GitHub-Epics (Label `epic`) und Termine aus Deadline-Kalendern.

## Aus anderen Apps teilen

- **Teilen → Tagwerk** legt Links, Text, Bilder und Dateien aus Safari, Mail, Dateien, Fotos und anderen Apps als Aufgabe, Notiz, Einkauf oder Rezept an. Die Erweiterung sichert den Eintrag nur auf dem iPhone, ohne Netzaufruf und ohne Zugriff auf deine Anmeldungen oder Daten in Tagwerk. Die App öffnet das passende Blatt beim nächsten Öffnen; gespeichert wird erst, wenn du dort bestätigst.
- **Eingang:** höchstens 20 offene Einträge, Dateien bis 25 MB, Einträge nach 14 Tagen verworfen. Ein weggewischtes Blatt kommt höchstens dreimal wieder, danach steht der Eintrag unter „Geteilt (n)“ in „Aufgaben“.
- **Datensicherung:** Der Eingang ist ein Zwischenspeicher, von der Sicherung ausgenommen und nicht durchsuchbar.
- **Mail zu Aufgabe:** Aus einer geteilten Mail (oder Text aus der Zwischenablage über das Menü am „+“ in „Aufgaben“) wird eine Aufgabe mit dem Betreff als Titel und, wenn die Mail eine Nachrichten-ID hat, einem Link zurück zur Mail. Auf Wunsch schlägt ChatGPT Titel, Zusammenfassung und Fälligkeit vor, nur nach Zustimmung unter Einstellungen › KI und nur auf dein Tippen auf „Mit ChatGPT zusammenfassen“. Gesendet werden Betreff, Absendername und Text (höchstens 12 000 Zeichen), nie Anhänge, Adressen, Empfänger oder die Nachrichten-ID.

## Entwicklung

- [`app/`](app/) enthält die SwiftUI-App und ihre lokalen Swift-Pakete. XcodeGen erzeugt das Xcode-Projekt aus [`app/project.yml`](app/project.yml).
- [`scripts/`](scripts/) enthält die Geräteinstallation und den LaunchAgent.
- [`docs/superpowers/`](docs/superpowers/) enthält Entwürfe und Implementierungspläne.
- [`spike/`](spike/) ist der Machbarkeitsprototyp aus Phase 1.

Die Tests verwenden Xcode 27.2, XcodeGen 2.46 und einen iOS-Simulator vom Typ **iPhone 18 Pro**. Für die Simulator-Tests genügt die heruntergeladene iOS-Simulatorlaufzeit in Xcode.

**Gate-Regel:** GitHub Actions ist das Gate vor dem Merge, nicht der lokale Rechner.

1. Je Commit lokal: die schnellen Stufen (`TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`) müssen grün sein.
2. Bei Arbeit an einem Screen lokal zusätzlich nur die berührten UI-Klassen, z. B. `TAGWERK_UI_ONLY="TaskFlowUITests SearchUITests/testFoo" app/test-all.sh`.
3. Vor dem Merge: die CI-Jobs `Tests (fast)` und `Tests (ui)` sind grün. Ein UI-Test, der erst im zweiten Versuch besteht, zählt als grün und steht in der Zusammenfassung des Jobs.
4. Ein roter nächtlicher Lauf blockiert keinen PR, ist aber ein Auftrag: ein Issue von Hand anlegen (keine automatische Anlage). Wackelt derselbe Test zweimal in einer Woche, kommt er mit Issue in Quarantäne und wird vor dem nächsten Release-Stand behoben.
5. Nur wenn CI ausfällt (GitHub-Störung, Warteschlange über 30 Minuten), gilt ersatzweise der volle lokale Lauf `app/test-all.sh` mit allen UI-Tests.

Jeder Checkout (Hauptordner oder Worktree) testet mit eigenem Simulator, eigenem DerivedData-Ordner und eigenen Logs, damit mehrere Checkouts gleichzeitig testen können. Die Einstellungen stehen in [`scripts/test-env.sh`](scripts/test-env.sh):

- Beim ersten Lauf legt `test-all.sh` den Simulator „Tagwerk Tests &lt;Checkout&gt;“ an.
- `TAGWERK_TEST_SIMULATOR` wählt stattdessen einen vorhandenen Simulator (Name oder UDID).
- `TAGWERK_TEST_DERIVED_DATA` setzt einen anderen DerivedData-Ordner.
- Die Stufe „app UI tests“ startet die App mit dem Startargument `-TagwerkUITest` (nur Debug-Build im Simulator): Speicher-Store, Demo-Daten, Demo-Einkaufsliste, offline. Vorher erteilt `test-all.sh` per `simctl privacy` Zugriff auf Kalender und Erinnerungen. Die Stufe dauert lokal gut eine halbe Stunde; deshalb läuft sie im Regelfall auf GitHub Actions (siehe Gate-Regel). Lokal lässt sie sich mit `TAGWERK_SKIP_UI_TESTS=1` überspringen oder mit `TAGWERK_UI_ONLY=<Klasse>[/<Test>] …` auf einzelne Klassen oder Tests beschränken.
- Der Barrierefreiheits-Audit listet mit `TEST_RUNNER_AUDIT_COLLECT_FILE=<Datei>` die Befunde, die weder behoben noch auf der Ausnahmenliste (`app/TagwerkUITests/AuditAllowlist.swift`) stehen, in eine Datei, statt zu scheitern.
- Nach dem Entfernen eines Worktrees bleiben Simulator und `~/Library/Developer/Tagwerk/DerivedData-tests-<Checkout>` liegen; sie lassen sich mit `xcrun simctl delete "Tagwerk Tests <Checkout>"` bzw. durch Löschen des Ordners entfernen.

### Tests auf GitHub Actions

Der Workflow [`.github/workflows/tests.yml`](.github/workflows/tests.yml) führt `app/test-all.sh` auf einem GitHub-gehosteten macOS-Runner aus, und zwar:

- **für jeden Pull Request** (geöffnet, neuer Push, wieder geöffnet) mit dem PR-Satz der UI-Tests und einem Wiederholungsversuch je fehlgeschlagenem UI-Test;
- **nächtlich** (02:17 UTC) auf `main` mit allen UI-Tests ohne Wiederholung, aber nur, wenn `main` seit dem letzten erfolgreichen nächtlichen Lauf neue Commits hat; sonst endet der Lauf sofort grün;
- **auf Abruf** (`workflow_dispatch`, für jeden Branch) ebenfalls mit allen UI-Tests ohne Wiederholung.

Ein neuer Push auf denselben PR bricht den laufenden Lauf ab. Nächtliche und manuelle Läufe derselben Art brechen einen laufenden Lauf nicht ab, sondern laufen nacheinander; ein neuer wartender Lauf ersetzt einen älteren wartenden (GitHub hält je Gruppe höchstens einen wartenden Lauf). Der Workflow braucht keine Secrets und hat nur Lesezugriff auf den Code (`contents: read`, im Job `changes` zusätzlich `actions: read` für die Abfrage des letzten nächtlichen Laufs); getestet wird im Simulator ohne Signierung, die UI-Tests nutzen ausschließlich Demo-Daten.

- **Runner:** Label `xcode-27` (Apple-Silicon-Image mit macOS 27 und Xcode 27.x; 3 Kerne, 7 GB RAM, für öffentliche Repositories kostenlos). Das Image enthält Xcode 27.2 (Build 27B52) unter `/Applications/Xcode_27.2.app` und die iOS-27.2-Simulatorlaufzeit samt iPhone 18 Pro vorinstalliert, es muss nichts heruntergeladen werden. `/Applications/Xcode.app` zeigt dort auf 27.1; deshalb wählt der Workflow 27.2 über `TAGWERK_DEVELOPER_DIR` und bricht ab, wenn Build, Laufzeit oder Gerätetyp fehlen (das Image kann sich ändern).
- **Zwei parallele Jobs:** `Tests (fast)` führt Pakettests, App-Tests und die String-Catalog-Prüfung aus (`TAGWERK_SKIP_UI_TESTS=1`), `Tests (ui)` nur die UI-Tests mit den Barrierefreiheits-Audits (`TAGWERK_ONLY_UI_TESTS=1`). So liegt das Ergebnis der schnellen Stufen früh vor, und die lange UI-Stufe läuft nebenher. Das UI-Testen ist bewusst nicht auf mehrere Runner verteilt (kein Sharding): Das Limit liegt bei 5 gleichzeitigen macOS-Jobs, und jeder Shard baut selbst. Zeitlimits: `fast` 40 Minuten (Testschritt 35), `ui` 60 Minuten (Testschritt 55). Das sind Richtwerte aus dem Plan, weil beim Setzen noch keine gemessene CI-Dauer vorlag; sie sind auf das Doppelte der gemessenen Dauer anzupassen.
- **PR-Satz und nächtlicher Satz:** `TAGWERK_UI_TEST_SET=pr` lässt die Tests aus [`app/TagwerkUITests/nightly-only.txt`](app/TagwerkUITests/nightly-only.txt) aus (eine Testklasse oder `Klasse/Test` je Zeile, `#` beginnt einen Kommentar). Aktuell sind das die AX5/Dunkel-Audits der Rezept- und Einstellungsscreens; die Audit-Varianten in Standardgröße und der AX5/Dunkel-Audit der vier Kernscreens bleiben im PR-Satz. Nächtliche und manuelle Läufe verwenden `TAGWERK_UI_TEST_SET=full`. Lokal und auf CI gilt dieselbe Liste.
- **Wiederholung (Flakiness):** Im PR-Lauf wiederholt `TAGWERK_UI_TEST_RETRIES=1` jeden fehlgeschlagenen UI-Test einmal (`-retry-tests-on-failure -test-iterations 2`). Die Tests, die erst im zweiten Versuch bestanden haben, stehen unter `RETRIED UI TESTS` im Log und in der Zusammenfassung des Jobs. Die Pakettests und die App-Tests wiederholen nie. Nächtliche Läufe wiederholen nicht, damit Wackler sichtbar bleiben.
- **Reine Doku-Änderungen:** Der Job `changes` (Linux-Runner) vergleicht die geänderten Dateien des PR mit der Positivliste `docs/**` und `**/*.md` (einschließlich `TODO.md`). Trifft jede geänderte Datei die Liste, überspringen `Tests (fast)` und `Tests (ui)` alle Schritte und enden grün. Der Filter sitzt im Job und nicht in `on.paths`, damit die beiden Checks immer ein Ergebnis melden und als Pflicht-Checks nicht hängen bleiben.
- **XcodeGen** wird in der festgelegten Version 2.46.0 aus dem GitHub-Release geladen und per SHA-256 geprüft.
- **Fehlerfall:** Bei einem fehlgeschlagenen Job lädt der Workflow die Logs und die `.xcresult`-Bundles als Artefakt `test-failure-fast` bzw. `test-failure-ui` hoch (7 Tage Aufbewahrung). Das Artefakt ist bei einem öffentlichen Repository für angemeldete GitHub-Nutzer abrufbar; die Logs enthalten nur Build- und Testausgaben, keine privaten Daten. Ein `.xcresult` lässt sich in Xcode öffnen.
- **Kein Cache für DerivedData:** Beim Checkout erhalten alle Quelldateien einen neuen Änderungszeitpunkt, sodass Xcode ohnehin vollständig neu baut. Die einzigen externen Abhängigkeiten (swift-markdown, swift-cmark) sind klein.

Zusätzliche Umgebungsvariablen von `app/test-all.sh` und `scripts/test-env.sh` (ohne Angabe bleibt das lokale Verhalten unverändert):

- `TAGWERK_DEVELOPER_DIR` wählt ein anderes Xcode statt `/Applications/Xcode.app` (auch für `scripts/sync-strings.sh`).
- `TAGWERK_ONLY_UI_TESTS=1` führt nur die Stufe „app UI tests“ aus (keine Pakettests, keine App-Tests, keine Katalogprüfung).
- `TAGWERK_TEST_LOG_DIR` setzt den Ordner für die Logs, `TAGWERK_TEST_RESULTS_DIR` legt pro Stufe ein `.xcresult`-Bundle dort ab.
- `TAGWERK_UI_TEST_SET` wählt den UI-Testsatz: `full` (Standard) führt alle UI-Tests aus, `pr` lässt die Tests aus `nightly-only.txt` aus. Fehlt die Datei, bricht die Stufe mit einer Meldung ab.
- `TAGWERK_UI_ONLY` führt nur die genannten UI-Testklassen oder `Klasse/Test`-Einträge aus (durch Leerzeichen getrennt, übersetzt in `-only-testing:`). Die Variable setzt implizit `TAGWERK_ONLY_UI_TESTS=1`, gilt vor `TAGWERK_UI_TEST_SET` und lässt sich nicht mit `TAGWERK_SKIP_UI_TESTS=1` kombinieren.
- `TAGWERK_UI_TEST_RETRIES=1` wiederholt fehlgeschlagene UI-Tests einmal und listet die wiederholten Tests (`RETRIED UI TESTS`, zusätzlich in `<Log-Ordner>/retried-ui-tests.md`). Nur die UI-Stufe wiederholt.

Einen CI-Lauf lokal nachstellen (jeweils eine Stufengruppe wie im Workflow):

```zsh
TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh   # entspricht „Tests (fast)“
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_UI_TEST_SET=pr TAGWERK_UI_TEST_RETRIES=1 app/test-all.sh   # entspricht „Tests (ui)“ im PR-Lauf
TAGWERK_ONLY_UI_TESTS=1 app/test-all.sh   # entspricht „Tests (ui)“ im nächtlichen Lauf (alle UI-Tests)
TAGWERK_UI_ONLY="TaskFlowUITests SearchUITests/testFoo" app/test-all.sh   # nur einzelne UI-Klassen oder -Tests
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_TEST_RESULTS_DIR=/tmp/tagwerk-results app/test-all.sh   # zusätzlich mit .xcresult-Bundle
```

Die Auswahl der UI-Tests und die Auswertung der Wiederholungen prüft `zsh scripts/tests/test-all-ui-selection.zsh` ohne Simulator.

Den Workflow selbst prüft `actionlint` (Homebrew: `brew install actionlint`, Aufruf im Repository-Root); `.github/actionlint.yaml` ergänzt das Label `xcode-27`, das die mitgelieferte Labelliste noch nicht kennt.

```zsh
app/test-all.sh          # Swift package and app tests in the simulator
scripts/install-dev.sh   # Install the current checkout using the local device configuration
```
