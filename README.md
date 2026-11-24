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

**Pakettests auf dem Mac:** Die Tests von `TagwerkCore`, `GitHubKit`, `RemindersKit` und `HealthBridge` laufen mit dem Ziel `platform=macOS` und brauchen keinen Simulator. Dafür deklarieren diese Pakete in `Package.swift` neben iOS auch `.macOS("27.0")`. `AIKit` kann nicht auf dem Mac laufen, weil `ChatGPTLogin.swift` `UIKit` importiert; für Tests wird kein bedingter Code (`#if os(...)`) eingeführt. Seine Tests sind deshalb Teil des Schemas `Tagwerk` (`package: AIKit/AIKitTests` in [`app/project.yml`](app/project.yml)) und laufen im Simulator zusammen mit den App-Tests, in einem Build mit der App. Welches Paket wo läuft, steht in der Tabelle `PACKAGE_TEST_PLATFORM` in [`app/test-all.sh`](app/test-all.sh) (`macos`, `app-scheme`, sonst Simulator mit eigenem `xcodebuild test`); das Skript bricht ab, wenn Tabelle und `Package.swift` bzw. `project.yml` nicht zusammenpassen. Die App-Stufe baut alle Pakete weiter für iOS, die iOS-Übersetzbarkeit bleibt also geprüft. Ein neues Paket ohne iOS-spezifische Importe bekommt `.macOS("27.0")` und einen Eintrag `macos` in der Tabelle.

**Ein Build für App- und UI-Stufe:** Die Stufen „app scheme Tagwerk“ und „app UI tests“ bauen mit `xcodebuild build-for-testing` und führen die Tests danach mit `xcodebuild test-without-building` aus (gleiche Argumente, gleicher DerivedData-Ordner); `-testLanguage de -testRegion DE`, Testauswahl und Wiederholung gelten nur für den Testaufruf. Der Build der UI-Stufe läuft vor der UI-Sperre, die Sperre deckt also nur die Testausführung ab. Die Pakettests bleiben bei `xcodebuild test`, weil jedes Paket seinen eigenen Build hat. Das Log einer Stufe enthält erst die Build-, dann die Testausgabe.

**Gate-Regel:** GitHub Actions ist das Gate vor dem Merge, nicht der lokale Rechner.

1. Je Commit lokal: die schnellen Stufen (`TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`) müssen grün sein.
2. Bei Arbeit an einem Screen lokal zusätzlich nur die berührten UI-Klassen, z. B. `TAGWERK_UI_ONLY="TaskFlowUITests SearchUITests/testFoo" app/test-all.sh`.
3. Vor dem Merge: die CI-Checks `Tests (fast)` und `Tests (ui)` (Gates über `Fast tests`, `Script tests` bzw. die `UI shard`-Jobs) sind grün. Ein UI-Test, der erst im zweiten Versuch besteht, zählt als grün und steht in der Zusammenfassung des Jobs.
4. Ein roter nächtlicher Lauf blockiert keinen PR, ist aber ein Auftrag: ein Issue von Hand anlegen (keine automatische Anlage). Wackelt derselbe Test zweimal in einer Woche, kommt er mit Issue in Quarantäne und wird vor dem nächsten Release-Stand behoben.
5. Nur wenn CI ausfällt (GitHub-Störung, Warteschlange über 30 Minuten), gilt ersatzweise der volle lokale Lauf `app/test-all.sh` mit allen UI-Tests.

Jeder Checkout (Hauptordner oder Worktree) testet mit eigenem DerivedData-Ordner und eigenen Logs; die Simulatoren kommen aus einem Pool, damit mehrere Checkouts gleichzeitig testen können, ohne dass Speicher und Festplatte mit der Zahl der Worktrees wachsen. Die Einstellungen stehen in [`scripts/test-env.sh`](scripts/test-env.sh):

- **Simulator-Pool:** Es gibt drei feste Simulatoren „Tagwerk Tests Slot 1“ bis „Tagwerk Tests Slot 3“, die beim ersten Gebrauch angelegt werden. Ein Lauf (`app/test-all.sh`, `scripts/stress-audits.sh`, `scripts/sync-strings.sh` mit Build) belegt einen freien Platz für seine gesamte Dauer. Die Plätze sind Sperrordner unter `~/Library/Developer/Tagwerk/locks` (`TAGWERK_LOCK_DIR`), gelten also für die ganze Maschine; ein Platz, dessen Prozess nicht mehr existiert (abgestürzter Lauf), wird mit einer Meldung übernommen. Sind alle drei belegt, wartet der Lauf mit einer Meldung, welche Prozesse die Plätze halten, höchstens 30 Minuten (`TAGWERK_SLOT_WAIT_SECONDS`) und endet dann mit Exit-Code 2. `TAGWERK_SIMULATOR_SLOTS` ändert die Zahl der Plätze.
- **Einzelne UI-Stufe:** Auf der Maschine läuft höchstens eine UI-Stufe gleichzeitig (zweite Sperre `ui-stage.lock`). Ein Lauf, der die UI-Stufe erreicht, während eine andere läuft, wartet bis zu 60 Minuten (`TAGWERK_UI_LOCK_WAIT_SECONDS`) und endet dann mit Exit-Code 2. Die Sperre gilt nur für die Ausführung der UI-Tests, nicht für den Build davor.
- **Herunterfahren:** Am Ende eines Laufs (auch nach Fehler, Strg-C oder Beenden des Skripts) fährt das Skript den Pool-Simulator herunter und gibt Platz und Sperren frei. `TAGWERK_KEEP_SIMULATOR=1` lässt den Simulator laufen. Einen mit `TAGWERK_TEST_SIMULATOR` gewählten Simulator fährt das Skript nie herunter.
- `TAGWERK_TEST_SIMULATOR` wählt stattdessen einen vorhandenen Simulator (Name oder UDID) und hat Vorrang vor dem Pool; es wird dann kein Platz belegt.
- `TAGWERK_TEST_DERIVED_DATA` setzt einen anderen DerivedData-Ordner.
- Die Stufe „app UI tests“ startet die App mit dem Startargument `-TagwerkUITest` (nur Debug-Build im Simulator): Speicher-Store, Demo-Daten, Demo-Einkaufsliste, offline. Vorher erteilt `test-all.sh` per `simctl privacy` Zugriff auf Kalender und Erinnerungen. Die Stufe dauert lokal gut eine halbe Stunde; deshalb läuft sie im Regelfall auf GitHub Actions (siehe Gate-Regel). Lokal lässt sie sich mit `TAGWERK_SKIP_UI_TESTS=1` überspringen oder mit `TAGWERK_UI_ONLY=<Klasse>[/<Test>] …` auf einzelne Klassen oder Tests beschränken.
- Der Barrierefreiheits-Audit listet mit `TEST_RUNNER_AUDIT_COLLECT_FILE=<Datei>` die Befunde, die weder behoben noch auf der Ausnahmenliste (`app/TagwerkUITests/AuditAllowlist.swift`) stehen, in eine Datei, statt zu scheitern.
- **Aufräumen:** Nach dem Entfernen eines Worktrees bleibt `~/Library/Developer/Tagwerk/DerivedData-tests-<Checkout>` liegen, und Simulatoren „Tagwerk Tests <Checkout>“ aus der Zeit vor dem Pool sind überflüssig. [`scripts/clean-test-env.sh`](scripts/clean-test-env.sh) listet beides (Probelauf, löscht nichts); `scripts/clean-test-env.sh --apply` löscht die Simulatoren und DerivedData-Ordner, zu denen kein Worktree mehr gehört. Dazu kommen die Paket-Ordner im Standard-DerivedData von Xcode (`~/Library/Developer/Xcode/DerivedData/<Paket>-<Hash>`, je Paket und Checkout einer): Das Skript erkennt sie am `WorkspacePath` in ihrer `info.plist` und listet sie, sobald der Checkout, aus dem sie gebaut wurden, nicht mehr auf der Festplatte existiert. `--legacy-simulators` nimmt zusätzlich die Einzel-Simulatoren bestehender Worktrees auf, die der Pool ersetzt. Das Skript fasst die Pool-Simulatoren, gestartete Simulatoren und Checkouts mit aktivem Testlauf nie an und beendet keine Prozesse. Andere Klone des Repositorys gelten nicht als Worktrees dieses Repositorys, ihre Ordner würden also mit gelistet (sie werden beim nächsten Lauf neu gebaut).

### Merge-Treiber für String Catalogs und `en.json`

Parallele Branches, die verschiedene Schlüssel in `Localizable.xcstrings` (oder am Ende von `scripts/translations/en.json`) ergänzen, erzeugen bei einem Text-Merge fast immer Konflikte, obwohl sich nichts widerspricht. Der Merge-Treiber [`scripts/merge-xcstrings.py`](scripts/merge-xcstrings.py) führt stattdessen den JSON-Inhalt schlüsselweise zusammen: ein Schlüssel, den nur eine Seite ergänzt, ändert oder entfernt, wird übernommen; ändern beide Seiten denselben Schlüssel, wird eine Ebene tiefer (Lokalisierung, `stringUnit`) weiterverglichen, und nur derselbe Wert mit verschiedenem Inhalt bleibt ein Konflikt. Dann meldet der Treiber den Pfad auf stderr und setzt die üblichen Konfliktmarker nur um diese Werte; alles andere ist schon zusammengeführt. Das Ergebnis steht im Format der Datei ([`scripts/catalog_format.py`](scripts/catalog_format.py)); ein Merge ohne Änderung auf der eigenen Seite lässt die Datei byteweise unverändert.

Einrichtung, einmal je Klon (die Treiber stehen in der lokalen Git-Konfiguration, `.gitattributes` weist sie nur zu):

```zsh
scripts/setup-git-merge-drivers.sh          # registriert die Treiber, wiederholbar
scripts/setup-git-merge-drivers.sh --unset  # entfernt sie wieder
```

Worktrees teilen die Konfiguration ihres Repositorys: ein Lauf deckt Hauptordner und alle Worktrees ab. Ohne die Einrichtung werden die Dateien wie bisher als Text zusammengeführt; `app/test-all.sh`, `scripts/test-env.sh` und die CI hängen nicht davon ab. **Die Merge-Schaltfläche von GitHub verwendet keine eigenen Treiber** (GitHub führt immer den Text-Merge aus); der Nutzen gilt für lokale Merges, etwa `git merge origin/main` in einen Feature-Branch. Konflikte, die GitHub in einem PR meldet, löst man deshalb lokal mit einem Merge von `origin/main`. Git liest `.gitattributes` aus dem ausgecheckten Stand: Ein Branch, der vor dieser Änderung von `main` abgezweigt wurde, hat die Datei noch nicht, sein erster `git merge origin/main` ist deshalb noch ein Text-Merge (mit den bekannten Konflikten); danach, oder bei `git rebase origin/main`, greift der Treiber.

### Tests auf GitHub Actions

Der Workflow [`.github/workflows/tests.yml`](.github/workflows/tests.yml) führt `app/test-all.sh` auf einem GitHub-gehosteten macOS-Runner aus, und zwar:

- **für jeden Pull Request** (geöffnet, neuer Push, wieder geöffnet; Umfang je nach geänderten Dateien, siehe „Welche Jobs laufen“) mit dem PR-Satz der UI-Tests und einem Wiederholungsversuch je fehlgeschlagenem UI-Test (die fehlgeschlagenen Tests laufen gezielt erneut);
- **nächtlich** (02:17 UTC) auf `main` mit allen UI-Tests ohne Wiederholung, aber nur, wenn `main` seit dem letzten erfolgreichen nächtlichen Lauf neue Commits hat; sonst endet der Lauf sofort grün;
- **auf Abruf** (`workflow_dispatch`, für jeden Branch) ebenfalls mit allen UI-Tests ohne Wiederholung;
- **nach jedem Merge auf `main`** (Trigger `push`) nur als Build ohne Tests, der den Build-Cache auffrischt (siehe „Build-Cache“ unten).

Ein neuer Push auf denselben PR bricht den laufenden Lauf ab, ebenso bricht ein neuer Merge auf `main` den noch laufenden Cache-Build des vorherigen Merges ab (nur der neueste Stand zählt). Nächtliche und manuelle Läufe derselben Art brechen einen laufenden Lauf nicht ab, sondern laufen nacheinander; ein neuer wartender Lauf ersetzt einen älteren wartenden (GitHub hält je Gruppe höchstens einen wartenden Lauf). Der Workflow braucht keine Secrets und hat nur Lesezugriff auf den Code (`contents: read`, im Job `changes` zusätzlich `actions: read` für die Abfrage des letzten nächtlichen Laufs); getestet wird im Simulator ohne Signierung, die UI-Tests nutzen ausschließlich Demo-Daten.

- **Runner:** Label `xcode-27` (Apple-Silicon-Image mit macOS 27 und Xcode 27.x; 3 Kerne, 7 GB RAM, für öffentliche Repositories kostenlos). Das Image enthält Xcode 27.2 (Build 27B52) unter `/Applications/Xcode_27.2.app` und die iOS-27.2-Simulatorlaufzeit samt iPhone 18 Pro vorinstalliert, es muss nichts heruntergeladen werden. `/Applications/Xcode.app` zeigt dort auf 27.1; deshalb wählt der Workflow 27.2 über `TAGWERK_DEVELOPER_DIR` und bricht ab, wenn Build, Laufzeit oder Gerätetyp fehlen (das Image kann sich ändern).
- **Simulator-Pool auf CI:** Jeder Job läuft auf einem eigenen Runner und ist der einzige Testlauf dort, der Pool ist also immer leer: Der Lauf belegt „Tagwerk Tests Slot 1“ (wird auf dem Runner neu angelegt), die UI-Sperre ist frei, und das Herunterfahren am Ende schadet nicht. Die Sperren liegen unter `~/Library/Developer/Tagwerk/locks` und gehören nicht zum Build-Cache.
- **Jobs und Pflicht-Checks:** `Tests (fast)` und `Tests (ui)` sind die Pflicht-Checks von `main` (Branch-Schutz, `enforce_admins`) und unverändert benannt, aber nur noch billige Linux-Jobs („Gates“, `if: always()`). Die Arbeit machen eigene Jobs: `Fast tests` (Pakettests, App-Tests und String-Catalog-Prüfung, `TAGWERK_SKIP_UI_TESTS=1`), `UI shard (1/2)` und `UI shard (2/2)` (nur die UI-Tests mit den Barrierefreiheits-Audits, `TAGWERK_ONLY_UI_TESTS=1`, je eine Hälfte der Testklassen) und `Script tests` (`scripts/run-script-tests.sh`, rund eine Minute). Ein Gate ist grün, wenn der Job `Changes` erfolgreich war und jeder benötigte Job `success` meldet oder übersprungen wurde, weil er laut `Changes` nicht laufen sollte; ein Job, der laufen sollte, aber `skipped` oder `cancelled` ist, macht das Gate rot (GitHub meldet einen per Bedingung übersprungenen Job an einen Pflicht-Check als Erfolg, ebenso einen Job, der wegen eines fehlgeschlagenen Vorgängers übersprungen wurde; deshalb prüft das Gate die Ergebnisse selbst, Quellen im Kopf von `tests.yml`). Das Aufteilen in zwei Shards: `scripts/ui-test-shards.py` liest die Testklassen aus den Quellen von `app/TagwerkUITests`, gewichtet sie mit den gemessenen Dauern aus `app/TagwerkUITests/ui-test-durations.txt` und verteilt sie deterministisch (längste Klasse zuerst auf den bisher leichtesten Shard); `TAGWERK_UI_SHARD=I/N` wählt in `app/test-all.sh` den Anteil I. Eine neue Testklasse landet ohne Eintrag in der Dauerliste mit dem mittleren Gewicht in einem Shard (das Skript meldet es); die Liste ist aus den Zeilen `Executed … in … seconds` eines Laufs nachzuführen, wenn die Shards auseinanderlaufen (die Zusammenfassung jedes Shards nennt seine Testdauer). Gemessen vor der Aufteilung (Lauf 45193805665, PR-Satz): 88 UI-Tests, 4619 s Testzeit in einem Job; zwei Shards haben je rund 2350 s (39 Minuten) plus eigenen Build (76 s mit warmem Cache, rund 34 Minuten kalt). Drei Shards wären rechnerisch rund 26 Minuten je Shard; das lohnt erst, wenn der Pool an macOS-Läufern es hergibt (Limit 5 gleichzeitige macOS-Jobs, ein PR belegt jetzt `Fast tests` plus zwei Shards, bei einem zweiten PR oder einem Cache-Build warten Jobs). Zeitlimits (Job, davon Testschritt): `Fast tests` 55 (45) Minuten, `UI shard` im PR-Lauf 95 (85) Minuten, im nächtlichen und manuellen Lauf mit dem vollen UI-Satz 105 (95) Minuten, `Script tests` 15 Minuten. Die Limits tragen auch einen kalten Lauf (leerer Cache); der Job hat 10 Minuten mehr als der Testschritt, damit Artefakt-Upload und Cache-Speichern nach einem Zeitlimit noch laufen. Gemessene Dauer des ersten Laufs (kalt, ohne Cache, Runner `xcode-27`): `fast` 37 Minuten (Pakete AIKit 4,5, GitHubKit 5,4, HealthBridge 5,0, RemindersKit 3,7, TagwerkCore 6,5 Minuten, fast nur Kompilieren; App-Schema rund 10 Minuten; diese Paketzeiten stammen aus dem Lauf, in dem alle Pakete im Simulator getestet wurden – seit vier Pakete auf macOS laufen und AIKit im App-Schema, sind sie auf dem Runner noch nicht gemessen und nachzutragen).
- **Zeitzone:** Die Jobs laufen in `Europe/Berlin` (`TZ` und `TEST_RUNNER_TZ`, zusätzlich best effort `systemsetup -settimezone`), weil die Tests deutsche Daten erwarten und die Runner UTC verwenden. Drei App-Tests (`SearchTaskMenuTests.plannedAnnouncement_namesTodayTomorrowAndOtherDays`, `SuggestionFactsTests.due_overdueTodayTomorrowLater` und `move_targetIsLateWhenAfterDue`) scheiterten im ersten Lauf daran, dass zwei Formatierer (`SearchTaskMenu.plannedAnnouncement`, `SuggestionFacts.weekday`) die Systemzeitzone statt der Zeitzone des übergebenen Kalenders benutzten; sie nutzen jetzt die Kalenderzeitzone. In der App ändert sich nichts, weil der Kalender der App (`Calendar.tagwerk`) der Systemzeitzone folgt.
- **PR-Satz und nächtlicher Satz:** `TAGWERK_UI_TEST_SET=pr` lässt die Tests aus [`app/TagwerkUITests/nightly-only.txt`](app/TagwerkUITests/nightly-only.txt) aus (eine Testklasse oder `Klasse/Test` je Zeile, `#` beginnt einen Kommentar). Aktuell sind das die AX5/Dunkel-Audits der Rezept- und Einstellungsscreens und der Abend-Variante von „Planen“ und „Tagesabschluss“; die Audit-Varianten in Standardgröße und der AX5/Dunkel-Audit der vier Kernscreens bleiben im PR-Satz. Nächtliche und manuelle Läufe verwenden `TAGWERK_UI_TEST_SET=full`. Lokal und auf CI gilt dieselbe Liste.
- **Wiederholung (Flakiness):** Fehlgeschlagene UI-Tests laufen einmal gezielt erneut, im PR-Lauf auf GitHub und lokal. `app/test-all.sh` liest nach dem ersten `xcodebuild test-without-building` die fehlgeschlagenen Tests aus dem Log (`scripts/ui-test-log.py`) und führt genau diese in einem zweiten Aufruf mit `-only-testing:` aus (eigenes Log `app-UI-tests-retry.log`, eigenes Ergebnisbündel). Ein Test ist nur rot, wenn beide Versuche fehlschlagen. Mehr als fünf fehlgeschlagene Tests werden nicht wiederholt (dann ist es kein Wackler). Die Tests, die erst im zweiten Versuch bestanden haben, stehen unter `RETRIED UI TESTS` im Log und in der Zusammenfassung des Jobs. Der früher verwendete Schalter `-retry-tests-on-failure` wiederholte keinen Test, der an einer Assertion scheiterte (in keinem PR-Lauf vom 2026-11-23 gab es eine zweite Iteration), deshalb der eigene Aufruf. Die Pakettests und die App-Tests wiederholen nie. Nächtliche und manuelle Läufe setzen `TAGWERK_UI_TEST_RETRIES=0`, damit Wackler sichtbar bleiben.
- **Hänger (Watchdog):** Jeder `xcodebuild`-Aufruf von `app/test-all.sh` läuft unter `scripts/ui-watchdog.py` (Test: `scripts/tests/test_ui_watchdog.py`, `scripts/tests/test-all-watchdog.zsh`). Der Watchdog liest das Stufen-Log mit und schreibt den Fortschritt (`Test Case … started/passed/failed`) und alle 300 s eine Herzschlag-Zeile (Phase, Laufzeit, Sekunden seit der letzten Log-Ausgabe, Teststand, aktueller Test) auf stdout, sodass das Job-Log zeigt, wo der Lauf steht. Bleibt das Log `TAGWERK_UI_SILENCE_SECONDS` (Testlauf, Standard 600 s) bzw. `TAGWERK_STAGE_SILENCE_SECONDS` (Builds und übrige Aufrufe, 900 s) ohne neue Zeile oder überschreitet ein Aufruf sein Zeitlimit (`TAGWERK_UI_MAX_SECONDS`, `TAGWERK_STAGE_MAX_SECONDS`; lokal standardmäßig aus, weil ein voller Lauf unter Last über eine Stunde dauern kann; CI setzt 3600 s für den UI-Testlauf, 2700 s bzw. 1800 s für Builds und die übrigen Aufrufe), schreibt er Diagnosen nach `watchdog-<Phase>-<Zeit>/` im Log-Ordner (`summary.txt` mit Grund und letzten Log-Zeilen, `ps.txt`, `simctl-booted.txt`, `sample-*.txt` von App, UI-Test-Runner, xcodebuild und testmanagerd, `simulator-log.txt` der letzten 10 Minuten), beendet die Prozessgruppe von `xcodebuild` (TERM, nach 10 s KILL) samt Nachkommen, fährt den eigenen Pool-Simulator herunter und endet mit Status 124; `test-all.sh` meldet `HUNG in stage: …` und wiederholt einen Hänger nicht. Der Start des Simulators (`simctl boot`, `bootstatus -b`), das Auslesen der Bundle-ID und das Erteilen der Berechtigungen haben eigene Limits (`TAGWERK_BOOT_TIMEOUT_SECONDS`, 300 s; 180 s; 120 s) und zeigen ihre Ausgabe. Anlass: Lauf 45362527642 (PR #303), zwei UI-Jobs blieben nach „build succeeded“ 100 Minuten stumm. Zusätzlich liest `scripts/ui-hang-sampler.py` das Log mit: Meldet XCTest, dass die App nicht antwortet (`Checking existence of … (retry 2)` oder `Failed to get matching snapshots: Timed out`), schreibt es einmal je Test ein `sample` des App-Prozesses nach `hang-*.txt` im Log-Ordner (er sieht aber nur diese beiden Zeilen, nicht die stumme Phase davor).
- **Stand des Branches vor der Bewertung:** Der Lauf prüft den Merge des Branches in `main`, aber ein Branch hinter `main` hat Korrekturen von `main` nicht (die Rezept-Befunde der Audits stammten aus Branches ohne den Bestätigungsdurchlauf). Vor der Bewertung eines roten Laufs `main` in den Branch holen (`git fetch origin && git merge origin/main`, dann pushen und den neuen Lauf bewerten). Die Zusammenfassung „Changes“ eines PR-Laufs nennt, wie viele Commits der Branch hinter `main` liegt.
- **Bestätigungsdurchläufe der Audits:** Ein Audit-Befund lässt einen Test nur scheitern, wenn ihn mehrere Durchläufe melden: Dynamic Type bei Standardgröße drei, alle anderen Typen zwei (`app/TagwerkUITests/AuditConfirmation.swift`, Unit-Test `AuditConfirmationTests`). Weitere Durchläufe laufen nur, wenn der vorige etwas gemeldet hat. Befunde, die ein späterer Durchlauf nicht wiederholt, stehen als `Unconfirmed audit finding` im Log.
- **Welche Jobs laufen:** Der Job `Changes` (Linux-Runner) übergibt die geänderten Dateien des PR an `scripts/ci-changes.py` (Test: `scripts/tests/test_ci_changes.py`). Nur `docs/**` und `**/*.md` (einschließlich `TODO.md`): keine Tests, die Gates enden grün. Änderungen unter `app/**`, an `.github/**` und an den Skripten, die der Testlauf selbst nutzt (`scripts/test-env.sh`, `ui-hang-sampler.py`, `ui-test-log.py`, `ui-test-shards.py`, `ui-watchdog.py`, `ci-restore-mtimes.py`, `ci-collect-artifacts.sh`, `ci-changes.py`, `run-script-tests.sh`): Fast, UI und Skript-Tests. Nur Skripte der String-Catalog-Stufe (`check-strings.py`, `check-colors.py`, `sync-strings.sh`, `catalog_format.py`, `translations/**`): Fast und Skript-Tests, keine UI-Tests. Alle anderen Skripte unter `scripts/**`: nur Skript-Tests. Jeder andere Pfad (Wurzeldateien, `spike/`, …) lässt alles laufen (sicherer Standard). Ein Test prüft, dass jedes Skript, das `test-all.sh`, `test-env.sh`, `sync-strings.sh` oder der Workflow aufrufen, nicht als „nur Skript-Tests“ eingestuft ist. Der Filter sitzt im Job und nicht in `on.paths`, damit die Pflicht-Checks immer ein Ergebnis melden und nicht hängen bleiben. Die Zusammenfassung von `Changes` nennt Entscheidung und Grund.
- **XcodeGen** wird in der festgelegten Version 2.46.0 aus dem GitHub-Release geladen und per SHA-256 geprüft.
- **Fehlerfall und Artefakte:** Nach dem Testschritt läuft immer (`if: always()`, also auch nach Zeitlimit und Abbruch) der Schritt „Stop leftover processes and pack the logs“ (`scripts/ci-collect-artifacts.sh`): Er beendet, was der Testlauf zurückgelassen hat (`xcodebuild`, UI-Test-Runner, Sampler, `DTServiceHub`, den Simulator des Jobs; der Runner gehört dem Job allein), und packt Log-Ordner und `.xcresult`-Bundles in ein einziges `tar.gz`. Vorher schrieben die verwaisten Prozesse weiter in den Ordner, während `upload-artifact` ihn zippte (Zip-Fehler im Lauf 45362527642). Das Artefakt `test-failure-fast` bzw. `test-failure-ui-shard-<n>` (7 Tage) wird hochgeladen, wenn der Job fehlschlug oder abgebrochen wurde (ein Zeitlimit zählt als Fehlschlag), und auch dann, wenn der Lauf Hänger-Diagnosen erzeugt hat. Das Artefakt ist bei einem öffentlichen Repository für angemeldete GitHub-Nutzer abrufbar; die Logs enthalten nur Build- und Testausgaben, keine privaten Daten. Ein `.xcresult` lässt sich in Xcode öffnen.
- **Build-Cache:** Der kalte Build dominiert die Laufzeit, deshalb wird DerivedData je Job (`fast`, `ui`) mit `actions/cache` zwischengespeichert: der App-Build (`~/Library/Developer/Tagwerk/DerivedData-ci`, der Workflow setzt `TAGWERK_TEST_DERIVED_DATA` dorthin, sodass der Pfad nicht vom Checkout-Schlüssel abhängt) und der Standardordner `~/Library/Developer/Xcode/DerivedData`, in dem die Paketstufen bauen. Damit Xcode unveränderte Dateien nicht neu kompiliert, setzt `scripts/ci-restore-mtimes.py` nach dem Checkout (`fetch-depth: 0`, rund 8 MB Verlauf, unter einer Sekunde) bei jeder Datei die Änderungszeit auf den Zeitpunkt des letzten Commits, der sie geändert hat; ohne das erhielte jede Datei beim Checkout die aktuelle Zeit.
  - **Schlüssel:** `derived-<Job>-<Xcode-Build>-<Image-Version>-<Hash aus project.yml, Package.swift, Package.resolved>-<Commit>`. Der Commit macht den Schlüssel eindeutig; die Wiederherstellung nutzt `restore-keys` mit abnehmender Genauigkeit (gleiche Manifeste, gleiches Image, gleiches Xcode). Ein anderes Xcode stellt nie einen fremden Cache her.
  - **Wann der Cache aufgefrischt wird:** Nach jedem Merge auf `main` bauen `Build cache (fast)` und `Build cache (ui)` denselben Stand wie die PR-Jobs, ohne Tests, und speichern den Cache. Ein PR startet damit von einem Cache, der höchstens einen Merge alt ist, statt vom letzten nächtlichen Lauf. Zusätzlich speichern die nächtlichen und manuellen Läufe auf `main` ihren Cache (siehe unten).
    - **Gleicher Build wie im PR-Job:** Der Cache-Build ist dieselbe Matrix wie der Testjob (`fast`, `ui`), mit `TAGWERK_BUILD_ONLY=1` statt der Tests. `app/test-all.sh` ruft dann statt `xcodebuild test` `xcodebuild build-for-testing` auf, mit denselben Schemata (Pakete, `Tagwerk`, `TagwerkUITests`), demselben Ziel (macOS bzw. Simulator, je Paket) und denselben DerivedData-Ordnern. Die App- und die UI-Stufe bauen auch im Testlauf mit demselben `build-for-testing`-Aufruf (danach `test-without-building`), die Pakete mit `xcodebuild test`, das aus `build-for-testing` und anschließendem Testlauf besteht; der Build ist also derselbe, nur der Testlauf entfällt. Dieselben Schritte davor (Änderungszeiten, Xcode 27.2, XcodeGen), derselbe Schlüssel (er enthält weder Ereignis noch Modus) und derselbe Pfad stellen sicher, dass ein PR den Cache so wiederherstellt wie jeden anderen von `main`. Der Simulator wird nicht gestartet, es werden keine Berechtigungen erteilt, die String-Catalog-Prüfung entfällt, `TAGWERK_UI_TEST_SET`, `TAGWERK_UI_TEST_RETRIES` und `TAGWERK_UI_ONLY` haben keine Wirkung.
    - **Reine Doku-Merges:** Ein Push, der nur `docs/**` oder `*.md` ändert, startet den Workflow nicht (`paths-ignore` am `push`-Trigger), weil der Cache dann weiterhin zum Quellstand passt. Anders als bei PRs darf der Filter hier im Trigger stehen: Auf `main` verlangt kein Pflicht-Check ein Ergebnis, und GitHub wertet den Filter über alle Commits des Pushes aus (Merge, Rebase, Squash), während ein Vergleich nur des letzten Commits im Job `changes` frühere Commits desselben Pushes übersehen könnte. Jede andere Änderung (Code, `project.yml`, `Package.swift`, Skripte, der Workflow selbst) löst den Build aus.
    - **Abbruch und Dauer:** Die Gruppe für `push` bricht einen laufenden Cache-Build ab, sobald ein neuer Merge eintrifft (ein abgebrochener Lauf speichert keinen Cache). Folgen mehrere Merges schneller aufeinander als der Build dauert, wird der Cache erst nach dem letzten Merge der Serie aufgefrischt; PRs nutzen bis dahin den vorherigen. Der Lauf hat die Gruppe `Tests-push-refs/heads/main` und blockiert weder den nächtlichen noch einen manuellen Lauf (und umgekehrt); je Lauf belegt er zwei der fünf gleichzeitigen macOS-Jobs. Limit: 55 Minuten (Schritt 45), ausgelegt auf einen kalten Build. Mit warmem Cache ist nur der Unterschied seit dem letzten Cache zu bauen; geschätzt rund 10 bis 20 Minuten je Job inklusive Wiederherstellen und Speichern des Caches (Schätzung, noch nicht gemessen; nach den ersten Läufen mit Cache hier nachtragen).
  - **Speichern nur auf `main`:** Cache-Builds nach einem Merge sowie nächtliche und manuelle Läufe auf `main` speichern den Cache (auch nach fehlgeschlagenen Tests, sonst bliebe der `ui`-Cache bei einem roten Audit leer). Pull Requests stellen nur wieder her, und zwar den neuesten Cache von `main`, und bauen nur den Unterschied. Ein Cache, den ein PR schreibt, wäre nur für diesen PR sichtbar und würde bei jedem Push einen weiteren Eintrag zum Limit von 10 GB je Repository addieren. Vor dem Speichern werden `Index.noindex` und `Logs` entfernt. Der Job `Prune build caches` (Linux, eigene Berechtigung `actions: write`) behält je Job die neuesten zwei Caches von `main` (gleich ob aus einem Merge-Build, dem nächtlichen oder einem manuellen Lauf); zusätzlich verdrängt GitHub bei Überschreiten des Limits die am längsten nicht benutzten Einträge, und Einträge ohne Zugriff verfallen nach 7 Tagen.
  - **Start:** Bis zum ersten Lauf auf `main` (Merge, nächtlich oder `workflow_dispatch` auf `main`) gibt es keinen Cache, PRs bauen dann kalt. Auch der Merge dieser Änderung löst bereits einen Cache-Build aus.
  - **Nachweis:** Die Zusammenfassung jedes Jobs nennt den wiederhergestellten Cache, die Größe der Ordner und die Zahl der Kompilierschritte je Stufe. Bei warmem Cache sollten es nur wenige sein; liegt die Zahl nahe am kalten Lauf, greift die Änderungszeit-Methode nicht (z. B. weil Xcode mehr als die Änderungszeit auswertet) und der Cache bringt nichts.
  - **Nicht verwendet:** Xcodes Kompilier-Cache (`COMPILATION_CACHE_ENABLE_CACHING`, inhaltsbasiert, ab Xcode 26). Für Xcode 27.2 liegt keine geprüfte Apple-Quelle zu Umfang und Einstellungen vor (die Treffer stammen aus Drittdokumentation und Foren); er wäre die Ausweichlösung, falls der DerivedData-Cache mit Änderungszeiten nicht greift. Die einzigen externen Abhängigkeiten (swift-markdown, swift-cmark) sind klein.

Zusätzliche Umgebungsvariablen von `app/test-all.sh` und `scripts/test-env.sh` (ohne Angabe bleibt das lokale Verhalten unverändert):

- `TAGWERK_DEVELOPER_DIR` wählt ein anderes Xcode statt `/Applications/Xcode.app` (auch für `scripts/sync-strings.sh`).
- `TAGWERK_ONLY_UI_TESTS=1` führt nur die Stufe „app UI tests“ aus (keine Pakettests, keine App-Tests, keine Katalogprüfung).
- `TAGWERK_BUILD_ONLY=1` baut nur und testet nicht: Jede Stufe, die Tests ausführen würde, ruft `xcodebuild build-for-testing` mit denselben Schemata, demselben Ziel und denselben DerivedData-Ordnern auf. Zusammen mit `TAGWERK_SKIP_UI_TESTS=1` (Pakete und App) oder `TAGWERK_ONLY_UI_TESTS=1` (App und UI-Test-Runner) wählt man die Stufen wie in den CI-Jobs. Der Simulator wird nicht gestartet, die String-Catalog-Prüfung entfällt, die Variablen zur Testauswahl haben keine Wirkung. CI nutzt das nach jedem Merge auf `main`, um den Build-Cache aufzufrischen.
- `TAGWERK_KEEP_SIMULATOR=1`, `TAGWERK_SIMULATOR_SLOTS`, `TAGWERK_SLOT_WAIT_SECONDS`, `TAGWERK_UI_LOCK_WAIT_SECONDS` und `TAGWERK_LOCK_DIR` steuern den Simulator-Pool und die Sperren (siehe oben).
- `TAGWERK_TEST_LOG_DIR` setzt den Ordner für die Logs, `TAGWERK_TEST_RESULTS_DIR` legt die `.xcresult`-Bundles dort ab: eines je Stufe für die Tests (`<Stufe>.xcresult`) und eines für den Build einer getrennt gebauten Stufe (`<Stufe>-build.xcresult`).
- `TAGWERK_UI_TEST_SET` wählt den UI-Testsatz: `full` (Standard) führt alle UI-Tests aus, `pr` lässt die Tests aus `nightly-only.txt` aus. Fehlt die Datei, bricht die Stufe mit einer Meldung ab.
- `TAGWERK_UI_ONLY` führt nur die genannten UI-Testklassen oder `Klasse/Test`-Einträge aus (durch Leerzeichen getrennt, übersetzt in `-only-testing:`). Die Variable setzt implizit `TAGWERK_ONLY_UI_TESTS=1`, gilt vor `TAGWERK_UI_TEST_SET` und lässt sich nicht mit `TAGWERK_SKIP_UI_TESTS=1` kombinieren.
- `TAGWERK_UI_TEST_RETRIES` steuert die gezielte Wiederholung fehlgeschlagener UI-Tests (siehe „Wiederholung“ oben): `1` oder nicht gesetzt (Standard, auch lokal) wiederholt, `0` oder leer nicht. Die wiederholten Tests stehen unter `RETRIED UI TESTS` (zusätzlich in `<Log-Ordner>/retried-ui-tests.md`). Nur die UI-Stufe wiederholt.
- `TAGWERK_UI_SHARD=I/N` führt nur Shard I von N der UI-Testklassen aus (Shard 1 bis N-1 mit `-only-testing`, der letzte Shard als Rest mit `-skip-testing` für alle Klassen der anderen, sodass eine vom Skript nicht erkannte Klasse im letzten Shard läuft und nicht in keinem; siehe „Jobs und Pflicht-Checks“ oben; die Shards zusammen sind der Satz von `TAGWERK_UI_TEST_SET`; schließt `TAGWERK_UI_ONLY` aus). `scripts/ui-test-shards.py plan 2 --set pr` zeigt die Aufteilung.
- Watchdog: `TAGWERK_UI_SILENCE_SECONDS`, `TAGWERK_UI_MAX_SECONDS`, `TAGWERK_STAGE_SILENCE_SECONDS`, `TAGWERK_STAGE_MAX_SECONDS`, `TAGWERK_HEARTBEAT_SECONDS` (siehe „Hänger“ oben; `0` schaltet ein Limit ab) und `TAGWERK_BOOT_TIMEOUT_SECONDS` (Start des Simulators vor den UI-Tests).

Einen CI-Lauf lokal nachstellen (jeweils eine Stufengruppe wie im Workflow):

```zsh
TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh   # entspricht „Tests (fast)“
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_UI_TEST_SET=pr app/test-all.sh   # entspricht beiden „UI shard“-Jobs des PR-Laufs zusammen (Wiederholung ist der Standard)
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_UI_TEST_SET=pr TAGWERK_UI_SHARD=1/2 app/test-all.sh   # nur „UI shard (1/2)“
scripts/run-script-tests.sh   # entspricht „Script tests“
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_UI_TEST_RETRIES=0 app/test-all.sh   # entspricht „Tests (ui)“ im nächtlichen Lauf (alle UI-Tests, ohne Wiederholung)
TAGWERK_UI_ONLY="TaskFlowUITests SearchUITests/testFoo" app/test-all.sh   # nur einzelne UI-Klassen oder -Tests
TAGWERK_BUILD_ONLY=1 TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh   # entspricht „Build cache (fast)“ nach einem Merge (nur bauen)
TAGWERK_BUILD_ONLY=1 TAGWERK_ONLY_UI_TESTS=1 app/test-all.sh   # entspricht „Build cache (ui)“ nach einem Merge (nur bauen)
TAGWERK_ONLY_UI_TESTS=1 TAGWERK_TEST_RESULTS_DIR=/tmp/tagwerk-results app/test-all.sh   # zusätzlich mit .xcresult-Bundle
```

Die Sperrlogik des Simulator-Pools und der UI-Stufe (Vergabe, Warten, Übernahme verwaister Sperren, Herunterfahren auch nach SIGTERM) prüft `zsh scripts/tests/test-env-locks.zsh`, das Zusammenspiel in `app/test-all.sh` (Platz, UI-Sperre, Herunterfahren) `zsh scripts/tests/test-all-simulator-pool.zsh`, das Aufräumskript (Probelauf, `--apply`, geschützte Einträge) `zsh scripts/tests/clean-test-env.zsh`; beide arbeiten mit Attrappen für `xcrun` und `git`. Die Auswahl der UI-Tests und die Auswertung der Wiederholungen prüft `zsh scripts/tests/test-all-ui-selection.zsh` ohne Simulator, den Ablauf der gezielten Wiederholung (zweiter Aufruf, Grenze von fünf Tests, Schalter) `zsh scripts/tests/test-all-ui-retry.zsh` mit Attrappen; die Aufrufe des Build-only-Modus prüft `zsh scripts/tests/test-all-build-only.zsh` mit Attrappen für `xcodebuild`, `xcodegen` und `xcrun` (es wird nichts gebaut). Das Entfernen und Prüfen der eingebetteten Ressourcen-Bundles (auch in den App-Erweiterungen) prüft `zsh scripts/tests/test-all-resource-bundles.zsh` an einem nachgebauten Produktordner.

Den Workflow selbst prüft `actionlint` (Homebrew: `brew install actionlint`, Aufruf im Repository-Root); `.github/actionlint.yaml` ergänzt das Label `xcode-27`, das die mitgelieferte Labelliste noch nicht kennt.

```zsh
app/test-all.sh          # Swift package tests (on the Mac where possible), app tests in the simulator
scripts/install-dev.sh   # Install the current checkout using the local device configuration
```
