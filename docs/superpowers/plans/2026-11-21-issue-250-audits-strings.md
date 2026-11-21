# UI-Audits stabilisieren und `sync-strings.sh` ohne Umformatierung (#250) – Implementation Plan

> **For agentic workers:** Implement task by task with TDD where a task names a test first. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 21.11.2026. Grundlage `origin/fix/ui-test-stability` auf `e34c1fd` (PR #240). Nur aus Code, Skripten und Git-Historie abgeleitet: kein Build, kein Simulator, kein Testlauf. Einzige Ausnahme: das Verhalten von `xcstringstool sync` wurde an einer temporären Katalogkopie nachgemessen (Teil B). Alle Aussagen zu den Audit-Ursachen sind **Hypothesen mit Code-Belegen**, keine gemessenen Ergebnisse; Task A0 prüft sie, bevor etwas geändert wird.

**Goal:** (1) Die Barrierefreiheits-Audits der UI-Tests liefern auf unverändertem Code an jedem Wochentag und unter Last dasselbe Ergebnis, ohne dass Wiederholungen oder breitere Ausnahmen die Schwankung verdecken. (2) `scripts/sync-strings.sh` schreibt die String-Kataloge im vorhandenen Format und ändert nur die Zeilen, die sich inhaltlich ändern.

**Architecture:** Teil A beseitigt drei Quellen von Nichtdeterminismus: den Wochentag (Arbeitstag wird im UI-Testmodus festgelegt), den zu frühen Bereit-Marker (er wird erst gesetzt, wenn Start und EventKit-Echo abgearbeitet sind) und fehlendes Warten auf einen ruhigen Bildschirm (ein Helfer vergleicht zwei aufeinanderfolgende Snapshots, bevor ein Audit startet). Teil B legt die Serialisierung der Kataloge in ein kleines Python-Modul, das den Stil je Datei erkennt und beibehält; `sync-strings.sh` und `apply-translations.py` schreiben nur noch darüber.

**Branch:** `fix/ui-audits-and-strings`, abgezweigt von `origin/main` (#240 ist seit 21.11.2026 gemergt, `95f28be`).

**Festlegung der Hauptsitzung (21.11.2026):** Alle offenen Fragen 1–8 nach Empfehlung des Plans. **Issue:** #250.

## Global Constraints

- **Ein Testlauf je Arbeitskopie.** `scripts/test-env.sh` gibt jeder Arbeitskopie einen eigenen Simulator und eigenes DerivedData (`scripts/test-env.sh:16-21`), aber nichts verhindert zwei Läufe in derselben Kopie. Nie `app/test-all.sh` und einen Audit-Lauf gleichzeitig in derselben Kopie starten.
- **Keine fremden Prozesse beenden.** Last für den Stabilitätsnachweis kommt von den Läufen der anderen Arbeitskopien oder von selbst endenden Lastprozessen (Task A8).
- **Wiederholungen und Ausnahmen sind letztes Mittel.** Jeder neue oder bleibende Allowlist-Eintrag und jede Wiederholung braucht eine Begründung im Code, die sagt, welche Ursache geprüft und ausgeschlossen wurde.
- **Kataloge nicht umformatieren.** Bis Teil B fertig ist, Schlüssel weiter von Hand im vorhandenen Format ergänzen.
- **Code:** Kommentare, Logausgaben und Meldungen englisch. **Commits:** Conventional Commits, englisch, ohne Hinweis auf KI-Werkzeuge.
- **Zeilenangaben** beziehen sich auf `e34c1fd`.

---

## Ausgangslage

### Teil A: Audit-Infrastruktur

| Baustein | Fundstelle | Befund |
|---|---|---|
| Basisklasse | `app/TagwerkUITests/UITestCase.swift:41-48` | Startet die App mit `-TagwerkUITest` und wartet nur auf den Marker `app.demoReady`. |
| Bereit-Marker | `app/Tagwerk/App/DemoData.swift:52`, `app/Tagwerk/App/RootView.swift:79-87` | `isDemoDataReady = true` wird am Ende des Seedings gesetzt, also **mitten** im Start-Task. |
| Rest des Starts | `app/Tagwerk/App/TagwerkApp.swift:58-77` | Nach dem Seeding (`:58`) folgen `ai.refreshAccount()`, `startObservingChanges()` (`:64`), ein zweites `taskList.reload()`, `planning.reload()`, `shopping.reload()` (`:67-69`) und sechs weitere `start…`-Aufrufe. |
| EventKit-Echo | `app/Tagwerk/App/DemoData.swift:20`, `app/Packages/RemindersKit/Sources/RemindersKit/EventKitGateway.swift:10-25`, `app/Tagwerk/App/AppEnvironment.swift:651-668` | Das Seeding schreibt über einen **eigenen** `EKEventStore`. Der Store des Gateways erfährt davon über `.EKEventStoreChanged`, zeitlich entkoppelt. Jede Meldung löst `taskList.reload`, `planning.reload`, `shopping.reload` aus. |
| Uhr | `app/Tagwerk/App/UITestMode.swift:24-30`, `app/TagwerkUITests/UITestCase.swift:16` | `-TagwerkUITestNow 09:30` fixiert nur die Uhrzeit; das Datum bleibt das echte. |
| „Heute ist vorbei“ | `app/Tagwerk/Planning/PlanningModel.swift:1479-1483` | `isTodayOver = true`, sobald heute **kein Arbeitstag** ist, unabhängig von der Uhr. |
| Standard-Arbeitszeit | `app/Packages/TagwerkCore/Sources/TagwerkCore/WorkSchedule.swift:24-27` | Montag bis Freitag 09:00–18:00, Wochenende frei. |
| Zeile „Unerledigtes verschieben“ | `app/Tagwerk/Planning/LeftoverLine.swift:9-21`, `app/Tagwerk/Planning/DayView.swift:278-281`, `app/Tagwerk/Routines/EveningSheet.swift:167` | Erscheint in der Kapazitätskarte von „Planen“ und im Tagesabschluss nur, wenn `leftFromToday` nicht leer ist, also nur wenn `isTodayOver`. |
| Scrollen auf „jetzt“ | `app/Tagwerk/Planning/DayGridScreen.swift:100-102`, `:139-156` | Das Raster scrollt beim Öffnen auf die aktuelle Zeit und wiederholt das in einem Fenster von 3 Sekunden **Echtzeit** (`Date.now`, `:146-149`), sobald der Inhalt über dem Raster wächst. |
| Animationen | `app/Tagwerk/App/TagwerkApp.swift:23` | Nur `UIView.setAnimationsEnabled(false)`; SwiftUI-Animationen (`withAnimation`, `.transition`) laufen weiter. |
| Audit-Helfer | `app/TagwerkUITests/AuditAllowlist.swift:179-194` | Kontrast läuft als eigener Durchgang; Befunde werden gesammelt und **nach** dem Audit über `element.label` beurteilt. |
| Befund ohne Element | `app/TagwerkUITests/AuditAllowlist.swift:237-247` | Ein Befund, dessen Element sich nicht auflösen lässt, ist nur auf drei benannten Bildschirmen akzeptiert; überall sonst schlägt er fehl und hat keinen Namen. |
| Wiederholung | `app/TagwerkUITests/AuditAllowlist.swift:207-223` | Bis zu drei Versuche bei Fehler `-56` („Audit failed to complete in time“), aus #240. |
| Sprache-Seite | `app/Tagwerk/Voice/VoiceSettingsView.swift:58`, `:134` | `packs[language]?.label ?? "…"`: die Zeilen „Sprachpaket …“ zeigen „…“, bis `AssetInventory.status` in `.task { await refresh() }` antwortet. |
| Einwilligung | `app/Tagwerk/Shopping/RecipeSheets.swift:90-118` | `Button("Nicht jetzt", action: onDecline)` (`:107`) ist ein schlichter Systemknopf unter dem prominenten Knopf. |
| Test der Einwilligung | `app/TagwerkUITests/AccessibilityAuditRecipesUITests.swift:52-59` | Tippt Text, schließt die Tastatur nur „wenn vorhanden“, tippt „Rezept holen“, wartet auf „Einverstanden“ und auditiert sofort. |
| Test der Sprache-Seite | `app/TagwerkUITests/AccessibilityAuditRecipesUITests.swift:80-83` | Wartet nur auf die Navigationsleiste „Sprache“ und auditiert sofort. |

**Was #240 geändert hat** (`git log origin/main..origin/fix/ui-test-stability`, vier Commits vom Samstag, 21.11.2026, 00:32–01:07):

- `1228ab5`: Datumszeile des Tageskopfs bricht bei Bedienungshilfen-Größen um (`app/Tagwerk/App/PageControls.swift`). Echte Korrektur im Produktcode.
- `af51561`: `PlanUITests` mit fester Uhr.
- `d66504a`: Wochentagsmuster `[A-Z]{2}\.,? .* · KW \d+` statt `FR\. …`, Eintrag „Unerledigt von heute“ (Kontrast, Tagesabschluss), Wiederholung bei Audit-Timeout.
- `e34c1fd`: zwei Einträge für „Unerledigtes verschieben · N Aufgaben“ (Dynamic Type und Text clipped, Tagesabschluss).

Die drei Einträge zum Rest von heute sind an einem Samstag entstanden. Nach `PlanningModel.swift:1479-1483` existiert dieser Abschnitt um 09:30 nur an freien Tagen. Die Einträge decken also Befunde ab, die montags bis freitags nie auftreten, und für „Planen (Tag)“ fehlt der passende Kontrast-Eintrag: das ist der erste gemeldete Fall aus #250.

### Teil B: String-Kataloge

| Baustein | Fundstelle | Befund |
|---|---|---|
| Sync | `scripts/sync-strings.sh:47-78` | `xcrun xcstringstool sync "$target"` (`:71`) schreibt im Schreibmodus direkt in den Katalog. |
| Prüfmodus | `scripts/sync-strings.sh:51-57`, `:75-77`, `scripts/check-strings.py:150-160` | `--check` synchronisiert in eine Kopie und vergleicht **inhaltlich** (`a == b` nach `json.load`); das Format spielt dort keine Rolle. |
| Übersetzungen | `scripts/apply-translations.py:102-105` | Schreibt immer `indent=2, separators=(",", " : ")` plus Zeilenende, unabhängig vom Stil der Datei. Der Docstring (`:12-13`) verweist zum „Normalisieren“ auf `sync-strings.sh`. |
| Tests der Skripte | `scripts/tests/` | Nur `refresh-decisions.zsh`; kein Test für die Katalog-Skripte. |

**Gemessenes Format im Repository** (Python-Auswertung aller elf Kataloge, nur lesend): Jede Datei ist Byte für Byte gleich `json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)`. Die Schlüssel von `strings` sind nach Codepunkt sortiert, alle verschachtelten Objekte ebenfalls, leere Einträge stehen als `{}`, `/` ist nicht maskiert. Zwei Merkmale unterscheiden sich je Datei:

| Katalog | Trenner | Zeilenende am Dateiende |
|---|---|---|
| `app/Tagwerk/Localizable.xcstrings` (20.003 Zeilen) | `": "` | ja |
| `app/Packages/TagwerkCore/…/Localizable.xcstrings` | `": "` | ja |
| `app/Tagwerk/AppShortcuts.xcstrings`, `app/Tagwerk/InfoPlist.xcstrings`, `app/TagwerkWidget/InfoPlist.xcstrings` | `": "` | nein |
| `app/TagwerkWidget/Localizable.xcstrings`, `app/TagwerkShare/Localizable.xcstrings`, AIKit, HealthBridge, RemindersKit | `" : "` | ja |
| `app/Packages/GitHubKit/…/Localizable.xcstrings` | `" : "` | nein |

**Gemessenes Verhalten von `xcstringstool sync`** (Kopie des TagwerkCore-Katalogs, 1.998 Zeilen, mit einer aus den Katalogschlüsseln erzeugten `.stringsdata`):

- Ohne inhaltliche Änderung lässt das Werkzeug die Datei unberührt (Diff 0 Zeilen).
- Mit **einem** neuen Schlüssel schreibt es die ganze Datei neu: Trenner `" : "`, leere Objekte als `{` Leerzeile `}`, kein Zeilenende am Dateiende. Ergebnis: 2.415 geänderte Diff-Zeilen. Reihenfolge und Inhalt der alten Einträge blieben gleich.
- Dieselben Daten mit `json.dumps(…, indent=2, sort_keys=True)` und dem Stil der Datei serialisiert ergeben einen Diff von **einer** Zeile (`"…": {},`).

Die in #250 genannten 13.000–24.000 Zeilen passen dazu: Der App-Katalog hat 20.003 Zeilen im Stil `": "`, jede Zeile mit einem Schlüssel ändert sich.

---

## Ursachen-Hypothesen, nach Belegstärke

Belegt ist jeweils der Mechanismus im Code. Nicht belegt ist, dass er die beobachteten Fehlschläge tatsächlich auslöst; das zeigt erst A0.

| # | Hypothese | Beleg | Erklärt | Stärke |
|---|---|---|---|---|
| H1 | **Der Wochentag bestimmt den Bildschirminhalt.** An freien Tagen ist `isTodayOver` trotz fester Uhr wahr; die Zeile „Unerledigtes verschieben“ und der Abschnitt „Unerledigt von heute“ erscheinen nur dann. | `PlanningModel.swift:1479-1483`, `WorkSchedule.swift:24-27`, `DayView.swift:278-281`; #240 entstand an einem Samstag. | „Unerledigtes verschieben“, Kontrast, Planen › Tag: der Befund hat keinen Eintrag für diesen Bildschirm. | hoch |
| H2 | **Der Bereit-Marker kommt vor dem Ende des Starts.** Nach dem Marker laufen ein zweiter vollständiger Reload und das EventKit-Echo des Seedings; unter Last fallen sie in das erste Audit. | `DemoData.swift:52` vor `TagwerkApp.swift:61-77`; getrennte Stores `DemoData.swift:20` / `EventKitGateway.swift:10-25`; `AppEnvironment.swift:651-668`. | Warum H1 **flackert** statt jeden Samstag gleich zu scheitern: `leftFromToday` wird in `planning.reload()` berechnet (`PlanningModel.swift:1486`); ob die Zeile beim Audit schon da ist, hängt vom Timing ab. | hoch |
| H3 | **Das Raster scrollt nach.** Wächst die Karte über dem Raster (Zeile kommt dazu), feuert der Scroll-Task erneut, aber nur 3 Sekunden Echtzeit lang. Danach bleibt die Position, wie sie gerade ist. | `DayGridScreen.swift:100`, `:139-156`. | Welche Elemente sichtbar sind oder unter der durchscheinenden Leiste liegen, hängt von der Geschwindigkeit ab; Kontrastbefunde folgen dem. | mittel bis hoch |
| H4 | **Tests warten auf ein Element, nicht auf einen ruhigen Bildschirm.** „Navigationsleiste existiert“ heißt nicht „Inhalt geladen“. | `VoiceSettingsView.swift:58`, `:134`: „…“ wird durch einen langen Text ersetzt, bei AX5 mit Umbruch und neuer Zeilenhöhe; Test `AccessibilityAuditRecipesUITests.swift:80-83`. | Unbenannter „Text clipped“-Befund auf Einstellungen › KI › Sprache: das Element existiert beim Beurteilen nicht mehr und kommt als `nil` (`AuditAllowlist.swift:237`). | mittel bis hoch |
| H5 | **Tastatur und Seitenwechsel laufen noch.** Die Tastatur ist ein eigener Prozess; `UIView.setAnimationsEnabled(false)` wirkt dort nicht. Der Test schließt sie nur, wenn der Knopf schon existiert, und auditiert, sobald „Einverstanden“ existiert. | `AccessibilityAuditRecipesUITests.swift:54-59`; „Nicht jetzt“ ist das unterste Bedienelement (`RecipeSheets.swift:107`) und damit am stärksten vom Tastaturrand betroffen. | „Nicht jetzt“, Dynamic Type, Rezept-Einwilligung. | mittel |
| H6 | **Der Dynamic-Type-Durchgang des Audits ist selbst zeitkritisch.** Er stellt die Systemschrift um und misst danach; unter Last hinkt das Layout nach. Dieselbe Umstellung läuft beim Zurücksetzen in den nächsten Schritt hinein. | Kommentar `AuditAllowlist.swift:174-178` (im kombinierten Lauf kommen Kontrast-Elemente als `nil`); viele Einträge mit „reports a partial lack of support“ ohne sichtbaren Mangel. | Rest von „Nicht jetzt“, falls H5 nicht reicht; nicht im Produktcode behebbar. | mittel |
| H7 | **SwiftUI-Animationen laufen im Testmodus weiter.** | `TagwerkApp.swift:23` schaltet nur UIKit ab. | Übergänge, während ein Audit startet. | niedrig bis mittel |
| H8 | **Zustand des Simulators zwischen Tests.** | Dagegen spricht: In-Memory-Store (`TagwerkApp.swift:15`), EventKit wird je Start geleert und neu befüllt (`DemoData.swift:26-27`). Offen: ob `AppSettings` (Einwilligungen, „Nicht jetzt“-Merker) im Testmodus persistiert. | Wäre ein harter Fehlschlag (Einwilligung erscheint nicht), kein flackernder Befund. | niedrig |

**Abgrenzung:** Audit-Timeouts (Fehler `-56`) sind eine eigene Fehlerklasse aus CPU-Mangel; #240 fängt sie mit Wiederholung ab. Sie sind nicht Ursache der drei gemeldeten Befunde.

---

## Teil A: Tasks

### Task A0: Hypothesen messen, bevor etwas geändert wird

**Files:** `app/TagwerkUITests/AuditAllowlist.swift` (nur temporäre Diagnose, nicht committen), neues Skript aus A8 vorziehen.

- [ ] Skript `scripts/stress-audits.sh` aus Task A8 zuerst anlegen (es ändert kein Testverhalten) und committen.
- [ ] Ausgangswert auf unverändertem `e34c1fd`: 10 Wiederholungen der vier Audit-Klassen im Sammelmodus (`TEST_RUNNER_AUDIT_COLLECT_FILE`, siehe `AuditAllowlist.swift:262-265`), einmal ohne und einmal mit Last (A8). Ergebnisdatei je Lauf aufheben.
- [ ] Auswerten: Welche Befunde stehen nicht in jeder Wiederholung? Das ist die Liste der flackernden Befunde; sie ist das Abnahmekriterium für A1–A6.
- [ ] H1 prüfen: denselben Lauf mit einer Arbeitszeit-Ausnahme für heute wiederholen (nach A2 möglich) und vergleichen, ob „Unerledigtes verschieben“ verschwindet.
- [ ] H2 prüfen: temporär in `AppEnvironment.startObservingChanges()` und am Ende des Start-Tasks eine Zeile mit Zeitstempel loggen (`print`), im Testlog gegen die Startzeit des ersten Audits halten. Diagnose wieder entfernen.
- [ ] H8 prüfen: nachlesen, ob `AppSettings` im UI-Testmodus persistiert (`app/Tagwerk/Persistence/AppSettings.swift`, `AppEnvironment.init`). Ergebnis im PR-Text festhalten.
- [ ] Ergebnis als kurze Tabelle in die PR-Beschreibung: Hypothese, bestätigt / widerlegt / offen, Beleg (Logzeile, Zähler).

**Abbruchregel:** Bestätigt A0 eine Hypothese nicht, wird der zugehörige Task nicht „auf Verdacht“ umgesetzt, sondern mit dem Befund an die Hauptsitzung zurückgegeben. A1, A2 und A3 sind davon ausgenommen: sie beseitigen belegte Nichtdeterminismen im Aufbau, unabhängig davon, welcher Befund daraus folgt.

### Task A1: Bereit-Marker erst nach dem vollständigen Start und dem EventKit-Echo

**Files:** `app/Tagwerk/App/TagwerkApp.swift`, `app/Tagwerk/App/DemoData.swift`, `app/Tagwerk/App/AppEnvironment.swift`, `app/TagwerkTests/` (neuer Test).

Ziel: Wenn `app.demoReady` existiert, läuft in der App nichts mehr, das den Bildschirm ohne Zutun des Tests ändert.

- [ ] **Test zuerst** (`app/TagwerkTests/StoreChangeSettleTests.swift`, Swift Testing): eine reine Hilfsfunktion `StoreChangeSettle.isSettled(handled:handledAtSeed:isHandling:quietFor:)` bzw. gleichwertig; Fälle: noch kein Echo → nicht ruhig; Echo in Arbeit → nicht ruhig; Echo abgearbeitet und Ruhezeit erreicht → ruhig; Zeitlimit überschritten → ruhig mit Warnung.
- [ ] `AppEnvironment`: zwei beobachtbare Zähler in der Schleife von `startObservingChanges()` (`:654-667`): `storeChangesHandled` (nach jedem abgearbeiteten Durchlauf erhöht) und `isHandlingStoreChange`. Keine Änderung am Verhalten außerhalb des Testmodus.
- [ ] `TagwerkApp.swift`: im UI-Testmodus `startObservingChanges()` **vor** dem Seeding starten, damit das Echo abgearbeitet wird und nicht verloren geht oder verspätet eintrifft. Außerhalb des Testmodus bleibt die Reihenfolge unverändert.
- [ ] `DemoData.seedIfRequested`: `isDemoDataReady` nicht mehr selbst setzen, sondern den Erfolg zurückgeben. Nach dem Seeding im Testmodus warten, bis das Echo abgearbeitet ist und 500 ms kein weiteres kam (höchstens 10 s; danach mit `print("DemoData: no store change echo within 10 s")` weiter, damit ein ausbleibendes Echo den Lauf nicht blockiert).
- [ ] `TagwerkApp.swift`: `environment.isDemoDataReady = true` als **letzte** Anweisung des Start-Tasks (nach `startSnapshotUpdates()`, `:77`), nur wenn das Seeding gelang.
- [ ] Der Timeout in `UITestCase.launchApp()` (`:47`, 60 s) bleibt; prüfen, ob die zusätzliche Wartezeit ihn im Lastlauf erreicht, und nur dann mit Begründung anheben.
- [ ] Verifikation: `app/test-all.sh` (ein Lauf), danach A8-Schleife.

**Commit:** `fix: set the UI test ready marker after the app start and the EventKit echo have finished`

### Task A2: Im UI-Testmodus ist heute immer ein Arbeitstag

**Files:** `app/Tagwerk/App/DemoData.swift`, `app/TagwerkTests/` (neuer Test), ggf. `app/Tagwerk/Planning/PlanStore.swift` (nur lesen: `setOverride`, `:70`).

- [ ] **Test zuerst** (`app/TagwerkTests/DemoDataWorkdayTests.swift`): reine Funktion `DemoData.uiTestWorkdayOverrides(today:calendar:)` liefert für heute und morgen `.hours(WorkHours(startMinutes: 540, endMinutes: 1080))`; Fälle Samstag, Sonntag, Freitag (morgen = Samstag), Mittwoch. Zusätzlich: mit diesen Ausnahmen liefert `TagwerkCore.workHours(on:schedule:overrides:calendar:)` für heute nie `nil`.
- [ ] `DemoData.seedIfRequested`: nur wenn `UITestMode.isActive`, die Ausnahmen vor `planning.reload()` (`:45`) in den Plan-Store schreiben. Die normalen Demodaten (`-TagwerkDemo` ohne Testmodus) bleiben unverändert.
- [ ] Morgen ebenfalls festlegen, damit der „nächste Planungstag“ (`PlanningModel.swift:1484-1485`) an jedem Wochentag morgen ist. Danach prüfen, ob das Muster `"Mo\\. planen"` (`AuditAllowlist.swift:87`) noch je passt; wenn der Knopf dann immer gleich heißt, das Muster auf den tatsächlichen Text einengen.
- [ ] Verifikation: A8-Schleife; der Befund „Unerledigtes verschieben“ auf „Planen (Tag)“ darf in keiner Wiederholung mehr vorkommen. Solange der Lauf an einem Werktag stattfindet, zusätzlich einmal mit Systemdatum-unabhängigem Gegenbeweis: den Unit-Test aus Schritt 1 für Samstag als Beleg nennen (ein Lauf mit verstelltem Simulator-Datum ist nicht nötig).

**Commit:** `test: make today a working day in the UI test mode so the audits do not depend on the weekday`

### Task A3: Vor jedem Audit auf einen ruhigen Bildschirm warten

**Files:** `app/TagwerkUITests/UITestCase.swift`, `app/TagwerkUITests/AuditAllowlist.swift`.

- [ ] `UITestCase`: Helfer `waitUntilScreenIsStable(timeout: TimeInterval = 8)`. Er nimmt mit `try app.snapshot()` einen Snapshot, bildet daraus eine Signatur (rekursiv Elementtyp, Label, Wert, gerundeter Rahmen; Aktivitätsanzeigen ausgenommen) und wiederholt das alle 0,3 s, bis zwei aufeinanderfolgende Signaturen gleich sind. Nach dem Zeitlimit schlägt der Test mit einer Meldung fehl, die die ersten abweichenden Elemente nennt. Das ist kein `sleep`: gewartet wird auf eine Bedingung, und ein unruhiger Bildschirm wird als eigener, benannter Fehler sichtbar statt als zufälliger Audit-Befund.
- [ ] `AuditAllowlist.audit` (`:179-194`): den Helfer vor **jedem** Durchgang aufrufen (also auch zwischen Kontrast- und Restdurchgang) und einmal nach dem letzten Durchgang, damit das Zurückstellen der Schriftgröße nicht in den nächsten Testschritt läuft (H6).
- [ ] Den Kommentar der Basisklasse (`UITestCase.swift:3-5`, „never with `sleep`“) um den Helfer ergänzen.
- [ ] Laufzeit messen: Zahl der Audits (17 Bildschirme, bis zu zwei Durchgänge) mal Kosten eines Snapshots. Steigt die Laufzeit der Audit-Klassen um mehr als etwa 20 %, die Signatur verschlanken (nur `staticTexts`, `buttons`, `cells`).
- [ ] Verifikation: A8-Schleife.

**Commit:** `test: wait for a stable screen before each accessibility audit pass`

### Task A4: Sprache-Seite erst auditieren, wenn die Sprachpakete geladen sind

**Files:** `app/TagwerkUITests/AccessibilityAuditRecipesUITests.swift`.

- [ ] In `auditSettings` (`:80-83`) nach der Navigationsleiste warten, bis kein Platzhalter „…“ mehr existiert: `waitUntilGone(app.staticTexts["…"])` bzw. auf den Wert der Zeile „Sprachpaket Deutsch“ warten, je nachdem, wie `LabeledContent` im Baum erscheint (im Baum-Dump eines Laufs nachsehen, nicht raten).
- [ ] Wenn A0 zeigt, dass der Befund auch bei geladenem Paket auftritt: Element und Rahmen aus dem Sammelmodus bestimmen und als echten Layoutfehler der Seite bei AX5 beheben (Kandidaten: `LabeledContent` mit langem Wert, `VoiceSettingsView.swift:58`; „Tempo“-Zeile mit `Slider`, `:96-105`). Kein Eintrag „ohne Element“ für diesen Bildschirm.
- [ ] Verifikation: A8-Schleife mit `AccessibilityAuditRecipesLargeTextUITests/testAuditSettings`.

**Commit:** `test: audit the voice settings only after the language pack states have loaded`

### Task A5: Einwilligung erst auditieren, wenn Tastatur und Seitenwechsel fertig sind

**Files:** `app/TagwerkUITests/AccessibilityAuditRecipesUITests.swift`, ggf. `app/TagwerkUITests/AuditAllowlist.swift`.

- [ ] In `auditCreateRecipe` (`:52-59`): nach der Eingabe die Tastatur verlässlich schließen (auf den Knopf „Fertig“ **warten** statt `if exists`) und vor „Rezept holen“ `XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:))`.
- [ ] Vor dem Audit der Einwilligung zusätzlich auf „Nicht jetzt“ als treffbares Element warten (`onScreen(label: "Nicht jetzt")`).
- [ ] A8-Schleife mit `AccessibilityAuditRecipesUITests/testAuditCreateRecipe`, 20 Wiederholungen unter Last.
- [ ] **Nur falls der Befund danach noch in einzelnen Wiederholungen auftritt** (H6): „Nicht jetzt“ in den bestehenden Dynamic-Type-Eintrag der Rezeptbildschirme aufnehmen (`AuditAllowlist.swift:150-156`), eingeschränkt auf „Rezept anlegen (Einwilligung)“, mit der Begründung: schlichter Systemknopf ohne eigene Schrift, wächst im AX5-Lauf desselben Bildschirms, Befund tritt nur sporadisch im Durchgang auf, der die Systemschrift umstellt. Zahl der betroffenen Wiederholungen aus dem Lastlauf in die Begründung schreiben.

**Commit:** `test: close the keyboard and wait for the consent buttons before auditing the recipe consent` (und bei Bedarf getrennt: `test: accept the sporadic Dynamic Type finding for the plain decline button of the recipe consent`)

### Task A6: Rest von heute deterministisch auditieren, Einträge aus #240 neu bewerten

**Files:** `app/TagwerkUITests/AccessibilityAuditUITests.swift` (neue Testmethode oder neue Klasse `AccessibilityAuditEveningUITests`), `app/TagwerkUITests/AuditAllowlist.swift`, `app/TagwerkUITests/UITestCase.swift`.

Nach A2 zeigt der Standardlauf (09:30, Arbeitstag) an keinem Wochentag mehr den Abschnitt „Unerledigt von heute“ und die Zeile „Unerledigtes verschieben“. Die drei Einträge aus #240 treffen dort nie mehr zu. Ohne Ersatz wäre diese Oberfläche gar nicht mehr auditiert.

- [ ] `UITestCase`: `static let eveningClockArguments = ["-TagwerkUITestNow", "19:30"]` (nach Arbeitsende 18:00).
- [ ] Neuer Test `testAuditLeftoversInTheEvening`: „Planen“ öffnen, auf die Zeile „Unerledigtes verschieben · …“ warten, Audit „Planen (Abend)“; Tagesabschluss öffnen, Audit „Tagesabschluss (Abend)“. Bedingung prüfen: Die Demodaten liefern um 19:30 mindestens eine übrige Aufgabe (`PlanningModel.swift:1486-1492`); sonst die Demodaten im Testmodus um eine für heute geplante Aufgabe ohne Block ergänzen.
- [ ] Befunde dieses Tests im Sammelmodus erfassen und **einzeln** entscheiden:

| Eintrag aus #240 | Fundstelle | Bewertung | Aktion |
|---|---|---|---|
| „Unerledigt von heute“, Kontrast, Tagesabschluss | `AuditAllowlist.swift:67-71` | Gehört zur Gruppe der grauen Abschnittsüberschriften, die mit K5 (#160) gemeinsam fällt. Sachlich begründet, aber am falschen Bildschirm. | `screens` auf „Tagesabschluss (Abend)“ umstellen; Begründung behalten. |
| „Unerledigtes verschieben · N“, Dynamic Type, Tagesabschluss | `AuditAllowlist.swift:90-94` | Die Begründung beschreibt selbst ein Umschlagen zwischen zwei Befunden („as soon as the height is fixed … it switches“). Das ist ein Hinweis auf einen echten Layoutmangel der Zeile, nicht auf einen Fehlalarm. | Zuerst beheben: `LeftoverLine` (`LeftoverLine.swift:11-16`) bei Bedienungshilfen-Größen umbrechen lassen (`fixedSize(horizontal: false, vertical: true)` am Text, Chevron mit skalierender Schrift) und im Abendtest mit AX5 prüfen. Eintrag nur behalten, wenn der Befund danach noch kommt. |
| „Unerledigtes verschieben · N“, Text clipped, Tagesabschluss | `AuditAllowlist.swift:112-115` | Wie oben; „Not part of the AX5 run“ heißt, die Behauptung „wraps instead of being cut“ ist nicht geprüft. | Wie oben; entfällt, wenn der Abendtest in AX5 ohne Befund läuft. |
| Wochentagsmuster `[A-Z]{2}\.,? .* · KW \d+` | `AuditAllowlist.swift:41` | Das Datum ändert sich legitim täglich; unabhängig von A2 nötig. | Bleibt. |
| Wiederholung bei Audit-Timeout | `AuditAllowlist.swift:196-223` | Ursache ist CPU-Mangel im Audit von XCTest, ohne einstellbares Zeitlimit; kein Befund geht verloren, weil der abgebrochene Versuch verworfen wird. | Bleibt als begründetes letztes Mittel. Zusätzlich jede Wiederholung am Testende zählen und ausgeben; im Lastlauf (A8) die Häufigkeit festhalten. Kommt nach A1–A3 in 20 Wiederholungen unter Last keine mehr vor, auf zwei Versuche senken. |

- [ ] Für den neuen Kontrastbefund der Zeile auf „Planen (Abend)“ (falls er dort stabil auftritt): Ursache am Element bestimmen (Text in Primärfarbe auf `.thinMaterial`, `DayView.swift:288`, oder das graue Chevron im selben Knopf, `LeftoverLine.swift:15`). Ist es das Chevron, `accessibilityHidden(true)` am Chevron prüfen (rein dekorativ); ist es der Text auf Material, gehört es zur Designfrage „Sekundärtexte auf getönten Karten“ (#188) und bekommt einen Eintrag in der bestehenden Gruppe (`AuditAllowlist.swift:56-61`), eingeschränkt auf „Planen (Abend)“.
- [ ] Tote Einträge finden: im Sammelmodus zusätzlich ausgeben, welche Einträge in einem vollständigen Lauf **nie** getroffen haben, und diese Liste im PR nennen. Einträge, die an keinem Bildschirm mehr treffen, entfernen.

**Commits:** `test: audit the leftover row and section in a pinned evening run`, `fix: let the leftover row wrap at accessibility text sizes`, `test: drop the audit allowlist entries that no longer match`

### Task A7: SwiftUI-Animationen im UI-Testmodus abschalten (nur wenn A0 H7 stützt)

**Files:** `app/Tagwerk/App/UITestMode.swift`.

- [ ] `UITestAppearance` (`:53-61`) um `.transaction { if UITestMode.isActive { $0.animation = nil; $0.disablesAnimations = true } }` ergänzen. Der Modifier hängt schon an der Wurzel (`TagwerkApp.swift:53`) und an den Rezept-Sheets (`RecipeSheets.swift:83`, `:117`).
- [ ] Prüfen, welche Sheets den Modifier nicht tragen (Sheets sind eigene Hierarchien) und ob die Audit-Bildschirme darunter sind; nur dort ergänzen.
- [ ] `app/test-all.sh`: Tests, die auf das Ende einer Animation warten (z. B. Hinweis „hinzugefügt“, `AccessibilityAuditUITests.swift:36-38`), müssen weiter grün sein.

**Commit:** `test: turn SwiftUI animations off in the UI test mode`

### Task A8: Stabilitätsnachweis

**Files:** `scripts/stress-audits.sh` (neu), `scripts/README.md` (ein Absatz).

`scripts/stress-audits.sh [iterations] [only-testing …]`:

- [ ] `source scripts/test-env.sh`, `DESTINATION=$(tagwerk_test_destination)`, `xcodegen --quiet` in `app/`, Simulator starten und Kalender/Erinnerungen freigeben wie `app/test-all.sh:97-116` (den Block in eine gemeinsame Funktion in `scripts/test-env.sh` ziehen, statt ihn zu kopieren).
- [ ] Sperre je Arbeitskopie: `mkdir "$TAGWERK_TEST_LOG_DIR/run.lock"` zu Beginn, per `trap` wieder entfernen; existiert sie, mit klarer Meldung und Exit 2 abbrechen. Dieselbe Sperre in `app/test-all.sh` setzen (siehe offene Frage 5).
- [ ] Einmal `xcodebuild build-for-testing`, dann `test-without-building` mit Wiederholungen **ohne** Wiederholen bei Fehlschlag und ohne Abbruch beim ersten Fehler:

```zsh
xcodebuild test-without-building \
  -project app/Tagwerk.xcodeproj -scheme TagwerkUITests \
  -destination "$DESTINATION" -derivedDataPath "$TAGWERK_TEST_DERIVED" \
  -testLanguage de -testRegion DE \
  -only-testing:TagwerkUITests/AccessibilityAuditUITests \
  -only-testing:TagwerkUITests/AccessibilityAuditLargeTextUITests \
  -only-testing:TagwerkUITests/AccessibilityAuditRecipesUITests \
  -only-testing:TagwerkUITests/AccessibilityAuditRecipesLargeTextUITests \
  -test-iterations "$ITERATIONS" \
  > "$TAGWERK_TEST_LOG_DIR/stress-audits.log" 2>&1
```

  `-retry-tests-on-failure` und `-run-tests-until-failure` werden bewusst nicht gesetzt: jede Wiederholung zählt, auch nach einem Fehlschlag.
- [ ] Auswertung am Ende: Zahl der Wiederholungen je Test, Zahl der Fehlschläge je Test, die fehlgeschlagenen Meldungen gruppiert nach Text, Zahl der Audit-Timeout-Wiederholungen (Zeile „Accessibility audit timed out“). Exit 1 bei mindestens einem Fehlschlag.

**Nachweis, den der Implementierer liefert** (Zahlen in die PR-Beschreibung):

1. `scripts/stress-audits.sh 10` ohne Zusatzlast: 0 Fehlschläge.
2. Dasselbe unter Last. Bevorzugt, während in den anderen Arbeitskopien Testläufe laufen (jede Kopie hat eigenen Simulator und eigenes DerivedData). Sonst mit selbst endenden Lastprozessen, die nach 40 Minuten von allein aufhören und nicht beendet werden müssen:

```zsh
for i in {1..8}; do perl -e 'alarm 2400; 1 while 1' & done
scripts/stress-audits.sh 20
```

   Erwartung: 0 Fehlschläge; Zahl der Timeout-Wiederholungen notieren.
3. Vergleich mit dem Ausgangswert aus A0 (gleiche Befehle auf `e34c1fd`): Tabelle „Fehlschläge vorher / nachher“ je Test.
4. Abschließend ein vollständiger `app/test-all.sh`.

Aussagekraft: 20 fehlerfreie Wiederholungen schließen eine Fehlerrate von etwa 14 % oder mehr mit 95 % Sicherheit aus (0,86²⁰ ≈ 0,05), nicht aber seltene Fehler. Der Nachweis zeigt, dass die bekannten Fälle nicht mehr auftreten; er beweist keine Fehlerfreiheit. Tritt in A0 ein Fall seltener als in einem von zehn Läufen auf, die Wiederholungszahl für diesen Test entsprechend erhöhen (Faustregel: mindestens das Dreifache des Kehrwerts der beobachteten Rate).

**Commit:** `build: add a script that repeats the accessibility audit tests and reports flaky findings`

---

## Teil B: Tasks

### Task B1: Format der Kataloge als Modul mit Tests

**Files:** `scripts/catalog_format.py` (neu), `scripts/tests/test_catalog_format.py` (neu).

- [ ] **Tests zuerst** (`unittest`, nur Standardbibliothek, lauffähig mit `/usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py'`):
  1. Jeder Katalog im Repository bleibt Byte für Byte gleich: `serialize(json.loads(text), detect_style(text)) == text` für alle `*.xcstrings` unter `app/` (ohne `.build`).
  2. `detect_style` erkennt die vier Kombinationen (Trenner `": "` / `" : "`, mit / ohne Zeilenende am Dateiende) an kleinen Beispielen.
  3. **Unveränderter Baum → kein Diff:** Eingabe ist derselbe Inhalt im Xcode-Stil (Trenner `" : "`, leere Objekte mit Leerzeile, anderes Zeilenende, Schlüssel in anderer Reihenfolge). `adopt(original_text, synced_text)` liefert `None` (nichts zu schreiben).
  4. **Ein neuer Schlüssel → Diff nur dieses Eintrags:** `difflib.unified_diff(…, n=0)` zwischen Original und Ergebnis enthält genau eine hinzugefügte Zeile und keine entfernte; je einmal für einen Katalog im Stil `": "` und im Stil `" : "`.
  5. Geänderter englischer Wert → genau eine entfernte und eine hinzugefügte Zeile.
  6. Als veraltet markierter Schlüssel → nur die Zeile `"extractionState": "stale"` (bzw. im anderen Stil) kommt hinzu, plus das Komma der Nachbarzeile, falls nötig; der Test legt die erwarteten Zeilen ausdrücklich fest.
  7. Entfernter Schlüssel → nur dessen Zeilen fehlen.
  8. Zeichen: Umlaute, typografische Anführungszeichen, `\n`, `"`, `/` und `%1$@` bleiben wie im Original (kein `\/`, kein `\uXXXX`).
- [ ] `scripts/catalog_format.py`:
  - `Style(separator, trailing_newline)`, `detect_style(text)`: Trenner aus der ersten Zeile mit einem Schlüssel, Zeilenende aus dem Dateiende.
  - `serialize(data, style)`: `json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", style.separator))` plus Zeilenende nach Stil.
  - `adopt(original_text, synced_text) -> str | None`: lädt beide; sind sie inhaltlich gleich, `None`; sonst der neue Inhalt im Stil des Originals.
  - `is_canonical(text)`: Round-Trip-Prüfung für B4.
  - Kommandozeile: `catalog_format.py adopt <catalog> <synced-copy>` schreibt den Katalog nur, wenn sich der Inhalt ändert, und meldet `N new, M changed, K removed` auf der Standardausgabe; `catalog_format.py check <catalog>…` für B4.
- [ ] Hinweis im Modul-Docstring: Die Sortierung nach Codepunkt ist der Bestand im Repository; Xcode sortiert beim Speichern in der Oberfläche anders und schreibt die Datei neu.

**Verifikation:** `/usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v` → alle Tests grün.

**Commit:** `build: add a module that writes the String Catalogs in the format of each file`

### Task B2: `sync-strings.sh` schreibt nur noch über das Modul

**Files:** `scripts/sync-strings.sh`, `scripts/tests/sync-strings-format.zsh` (neu).

- [ ] **Test zuerst** (`scripts/tests/sync-strings-format.zsh`, braucht `xcrun xcstringstool`, aber keinen Build und keinen Simulator): temporärer Ordner mit Kopien von zwei echten Katalogen (einer je Stil), einer leeren Quelldatei und einer erzeugten `.stringsdata`, die alle nicht veralteten Schlüssel des Katalogs nennt (Aufbau wie die echten Dateien: `{"source": …, "tables": {"Localizable": [{"comment": "", "key": …, "location": {…}}]}, "version": 1}`).
  1. Lauf ohne Änderung → `cmp` mit dem Original: gleich.
  2. `.stringsdata` um einen Schlüssel ergänzt → `diff` zeigt genau eine hinzugefügte Zeile, keine entfernte.
  3. Zweiter Lauf direkt danach → keine weitere Änderung (idempotent).
  4. `--check` meldet im Fall 2 vor dem Schreiben Exit 1 und danach Exit 0.
- [ ] `scripts/sync-strings.sh`:
  - `sync_catalog` (`:47-78`) synchronisiert **immer** in eine Kopie im Arbeitsordner (heute nur bei `--check`, `:51-57`), nie direkt in den Katalog.
  - Schreibmodus: danach `/usr/bin/python3 scripts/catalog_format.py adopt "$catalog" "$target"`. Der Katalog wird nur angefasst, wenn sich der Inhalt ändert.
  - Prüfmodus: unverändert über `check-strings.py --same`.
  - Neuer interner Einstieg `--sync-one <catalog> <stringsdata>…` für den Test: ruft `sync_catalog` ohne Build und ohne Suche im DerivedData auf. Im Kopfkommentar als Test-Einstieg dokumentieren.
  - Kopfkommentar (`:1-11`) ergänzen: das Skript behält das Format je Datei.
- [ ] Verhalten bei veralteten Schlüsseln bleibt, wie `xcstringstool` es heute liefert (markieren bzw. entfernen); keine neue Löschlogik. `--skip-marking-strings-stale` wird nicht gesetzt.

**Verifikation:**

```zsh
zsh scripts/tests/sync-strings-format.zsh
# Nach einem regulären Testlauf der Arbeitskopie (DerivedData vorhanden), ohne neuen Build:
scripts/sync-strings.sh --no-build
git diff --stat -- '*.xcstrings'        # erwartet: leer
```

Zusätzlich einmal von Hand: einen neuen Text im Code ergänzen, `app/test-all.sh` laufen lassen (scheitert erwartungsgemäß in der Stufe „string catalogs“), `scripts/sync-strings.sh --no-build`, `git diff --stat -- '*.xcstrings'` → eine Datei, eine Zeile. Änderung wieder verwerfen.

**Commit:** `fix: keep the format of the String Catalogs when syncing them with the source`

### Task B3: `apply-translations.py` behält das Format

**Files:** `scripts/apply-translations.py`, `scripts/tests/test_catalog_format.py`.

- [ ] **Test zuerst:** `apply_to_catalog` auf einer Kopie eines Katalogs im Stil `": "` mit einer geänderten Übersetzung → Diff von genau einer entfernten und einer hinzugefügten Zeile; ohne Änderung → Datei bleibt Byte für Byte gleich.
- [ ] Schreiben (`:102-105`) über `catalog_format.serialize` mit dem erkannten Stil; nur schreiben, wenn sich der Inhalt ändert.
- [ ] Docstring (`:12-13`) korrigieren: kein Verweis mehr auf ein „Normalisieren“ durch `sync-strings.sh`.

**Commit:** `fix: keep the format of the String Catalogs when applying translations`

### Task B4: Formatprüfung in der Stufe „string catalogs“

**Files:** `scripts/check-strings.py`, `app/test-all.sh` (nur falls ein eigener Aufruf nötig ist).

- [ ] **Test zuerst:** ein Katalog mit einem von Hand an falscher Stelle eingefügten Schlüssel → Meldung `…: not in the repository format (first difference at line N)`.
- [ ] `check-strings.py`: im Standardlauf für jeden Katalog `catalog_format.is_canonical`; Abweichung als Problem melden, mit der ersten abweichenden Zeile und dem Hinweis `run scripts/sync-strings.sh`.
- [ ] Damit schlägt `app/test-all.sh` (`:120-123`) früh fehl, wenn ein Hand-Eintrag das Format verlässt, statt dass der nächste Sync-Lauf unerwartete Zeilen ändert. Heute erfüllen alle elf Kataloge die Prüfung.
- [ ] `scripts/README.md`: ein Absatz „String-Kataloge“ (Format je Datei, Befehle, Testaufrufe).

**Commit:** `build: check that the String Catalogs are in the repository format`

---

## Reihenfolge und Abhängigkeiten

1. A8 (Skript), dann A0 (Messung auf dem Ausgangsstand).
2. A1, A2, A3 in dieser Reihenfolge, je mit A8-Schleife.
3. A4, A5, A6; A7 nur bei Bedarf.
4. B1 → B2 → B3 → B4. Teil B ist von Teil A unabhängig und braucht bis auf die Hand-Verifikation in B2 keinen Build; er kann zuerst erledigt werden, solange der Simulator belegt ist.
5. Abschluss: ein vollständiger `app/test-all.sh`, Nachweis aus A8 in die PR-Beschreibung.

## Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| Die Hypothesen sind nur aus dem Code abgeleitet. | Ein Task behebt etwas, das nicht die Ursache war. | A0 misst zuerst; Abbruchregel in A0. |
| Das EventKit-Echo bleibt aus oder kommt mehrfach. | Start hängt oder der Marker kommt wieder zu früh. | Zeitlimit 10 s mit Logzeile, Ruhezeit 500 ms; A3 fängt späte Änderungen als benannten Fehler ab. |
| A3 verlängert die Läufe. | Audit-Klassen dauern spürbar länger. | Messen; Signatur verschlanken; Grenze 20 %. |
| Ein Bildschirm kommt nie zur Ruhe (laufende Anzeige). | A3 schlägt dauerhaft fehl. | Das ist ein echter Befund; Aktivitätsanzeigen sind ausgenommen, alles andere wird benannt und behoben. |
| A2 verdeckt echtes Wochenendverhalten. | Fehler, die nur an freien Tagen auftreten, fallen in den UI-Tests nicht mehr auf. | Die Logik freier Tage ist in Unit-Tests von `TagwerkCore`/`PlanningModel` abzudecken; A6 prüft den Rest von heute gezielt. Lücke im PR benennen, falls solche Unit-Tests fehlen. |
| Der Abendtest (A6) bringt neue Befunde. | Mehr Allowlist-Einträge als vorher. | Jeden Befund zuerst beheben; Einträge nur mit Ursache und Bildschirm. Nettozahl der Einträge im PR nennen. |
| Xcode schreibt einen Katalog beim Öffnen in der Oberfläche neu. | Großer Diff trotz Teil B. | B4 meldet es vor dem Commit; `sync-strings.sh` stellt das Format wieder her. |
| Drei Agenten ergänzen Kataloge parallel von Hand. | Merge-Konflikte mit Teil B. | Teil B ändert keinen Kataloginhalt; nur Skripte und Tests. |
| `sort_keys=True` weicht bei künftigen Schlüsseln von Xcodes Reihenfolge ab. | Keine: maßgeblich ist der Bestand, und der ist nach Codepunkt sortiert. | Test 1 in B1 sichert den Bestand ab. |

## Offene Fragen mit Empfehlung

1. **Abendtest in diesem PR oder die drei Einträge aus #240 ersatzlos streichen?** Empfehlung: Abendtest (A6). Ohne ihn ist die Oberfläche „Rest von heute“ in keinem Audit mehr enthalten, und die Aussage der Einträge („wraps instead of being cut“) bleibt ungeprüft.
2. **EventKit-Beobachtung im UI-Testmodus ganz abschalten statt auf das Echo zu warten?** Empfehlung: nein. Das wäre einfacher, entfernt aber einen echten Codepfad aus den UI-Tests. Erst wenn A1 unter Last nicht zuverlässig wird, als zweite Stufe mit Begründung.
3. **Datum im UI-Testmodus fest einfrieren (z. B. immer derselbe Mittwoch)?** Empfehlung: nein. Die Demodaten liegen relativ zum echten Heute in EventKit; ein festes Datum zöge einen Umbau von `DemoData` und des Kalenderzugriffs nach sich. A2 beseitigt die bekannte Wochentagsabhängigkeit mit einer Zeile Zustand.
4. **Platzhalter „…“ auf der Sprache-Seite durch einen lesbaren Text ersetzen („Wird geprüft …“)?** Empfehlung: nicht in diesem PR. Es wäre eine sinnvolle Verbesserung für VoiceOver, braucht aber neue Texte in zwei Sprachen und gehört in die Designrunde (#188).
5. **Sperre gegen zwei Läufe in derselben Arbeitskopie auch in `app/test-all.sh`?** Empfehlung: ja, zusammen mit A8. Die Regel „ein Lauf je Arbeitskopie“ wird sonst nur durch Absprache eingehalten. Risiko: Eine nach einem Absturz liegengebliebene Sperre blockiert; deshalb die Prozess-ID in den Sperrordner schreiben und eine verwaiste Sperre mit Meldung übernehmen.
6. **Alle Kataloge einmalig auf einen Stil vereinheitlichen?** Empfehlung: nicht jetzt. Ein Umformatierungs-Commit über fünf oder sechs Dateien kollidiert mit den laufenden Hand-Einträgen der anderen Agenten. Nach dem Merge der offenen Zweige als eigener, rein mechanischer Commit möglich; das Modul aus B1 erledigt es mit einem Aufruf.
7. **Wiederholung bei Audit-Timeout entfernen?** Empfehlung: behalten, aber zählen und berichten (A6). Der Timeout liegt in XCTest und ist nicht einstellbar; ohne Wiederholung scheitert ein Lauf unter Last ohne Aussage über die App.
8. **Soll `scripts/stress-audits.sh` Teil der Pflichtprüfung vor einem Merge werden?** Empfehlung: nein, nur bei Änderungen an den Audits, an `UITestMode`, an `DemoData` oder am Start-Task. Der Lauf dauert ein Vielfaches von `app/test-all.sh`.
