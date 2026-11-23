# CI-Audits: verbleibende UI-Test-Fehler nach PR #299

Stand: 2026-11-23. Analyse und Plan, keine Codeänderung. Zeilenangaben beziehen sich auf `origin/main` (`23dbb545`).

## 1. Ergebnis in Kürze

| Punkt | Einordnung | Belegt durch | Empfehlung |
|---|---|---|---|
| Dynamic-Type-Befunde der Rezept-Screens | Nichtdeterminismus des Audits, kein Code-Fehler in den Views | 13 Läufe ohne, 2 Läufe mit Bestätigungsdurchlauf | Bestätigung für `.dynamicType` auf drei Durchläufe erhöhen; Feature-Branches auf `main` bringen |
| Timeout in `testAuditSettings` | Die App hängt auf der Seite „Spracheingabe und Vorlesen“, nicht das Audit | 6 von 6 Timeouts in `AccessibilityAuditRecipesUITests.swift:117` | Systemaufrufe der Seite vom Main-Thread nehmen und im UI-Test-Modus ersetzen; Test je Seite teilen |
| Timeout in `testAuditDefaultSize` (einmal) | App antwortet direkt nach dem Start nicht | 1 Lauf, `UITestCase.swift:230` | `AVSpeechSynthesizer` erst bei Bedarf anlegen (Annahme), Diagnose-Sample einbauen |
| Wiederholung fehlgeschlagener UI-Tests | wirkt praktisch nicht (Nebenbefund) | 0 zweite Iterationen in 15 von 16 Logs | Wiederholung im Skript statt über `-retry-tests-on-failure` |

Der wichtigste Punkt vorweg: Von den 15 ausgewerteten Fehlläufen enthalten nur zwei den Stand von #299. Alle
Rezept-Befunde, die einen Test rot gemacht haben, stammen aus Branches **ohne** den Bestätigungsdurchlauf
(`0cd2c29d`). „Bleiben nach #299“ ist für die Rezept-Befunde damit bisher nicht belegt, für die Timeouts schon
(einer der beiden #299-Läufe).

## 2. Datenbasis

- 15 fehlgeschlagene Läufe von `tests.yml` vom 2026-11-23 (01:26 bis 10:53 UTC), 16 Logs (ein Lauf hat zwei Versuche):
  `45094557132`, `45094689864`, `45101825929`, `45101968856`, `45109270040` (zwei Versuche), `45109273839`, `45117374897`,
  `45117738397`, `45129914169`, `45129942623`, `45130152684`, `45157276905`, `45157447007`, `45157481969`, `45160185976`.
- Ausgewertet wurde je Artefakt nur `tagwerk-test-logs/app-UI-tests.log` (per HTTP-Range aus dem Zip gelesen). Die
  `xcresult`-Bündel (Screenshots, Anhänge) wurden nicht gelesen.
- Stand der Läufe: Nur `45130152684` (`73d04254`) und `45157447007` (`5fc465cd`) enthalten `0cd2c29d`
  (Bestätigungsdurchlauf) und `1805a8a3` (View-Korrekturen); geprüft mit `git merge-base --is-ancestor`. Alle
  anderen 13 Läufe (Feature-Branches und der nächtliche Lauf auf `03bd5441`) enthalten beides nicht.
- Offen bei Abschluss der Analyse: `45172470212` (`feat/nutrition-goals`, `11c2d95e`) ist der erste Lauf eines
  Feature-Branches mit #299 und lief noch.

Grenzen: zwei Läufe mit dem Stand von #299 sind zu wenig für Häufigkeiten. Ein Test bricht beim ersten Fehler ab
(`continueAfterFailure = false`), die Zählung je Befund in den alten Läufen ist daher eine Untergrenze.

## 3. Rezept-Screens: Dynamic-Type-Befunde

### 3.1 Befunde je Lauf (alle ohne Bestätigungsdurchlauf)

Alle Befunde lauten „Dynamic Type font sizes are partially unsupported“.

| Lauf | Screen | Element | Label | Frame (x, y, b, h) |
|---|---|---|---|---|
| `45094557132` | Rezept anlegen (Bestätigung) | `AccessibilityNode` | Rezept speichern | 16, 774, 370, 50 |
| `45094557132` | Einkaufsliste › Übersetzung | `AccessibilityNode` | Milk | 73, 535, 30, 20 |
| `45094689864` | Einkauf › Rezept hinzufügen | `AccessibilityNode` | Rezepttext | 16, 237, 370, 40 |
| `45101825929` | Zutaten (Rezept) | `AccessibilityNode` | 5 Artikel hinzufügen | 16, 774, 370, 50 |
| `45109273839` | Rezept anlegen (Eingabe) | `AccessibilityNode` | Rezepttext | 16, 202, 370, 40 |
| `45109273839` | Rezepte | `AccessibilityNode` | Demo Linsensuppe | 36, 347, 152, 20 |
| `45109273839` | Einkauf › Rezept hinzufügen (Notiz) | `AccessibilityNode` | Andere Notiz wählen … | 37, 363, 214, 20 |
| `45109273839` | Einkaufsliste › Übersetzung | `UIKitTextField` | (leer) | 43, 779, 234, 21 |
| `45117374897` | Rezept anlegen (Eingabe) | `AccessibilityNode` | Füge die Zutatenliste … | 16, 492, 370, 46 |
| `45117374897` | Einkauf › Rezept hinzufügen (Notiz) | `AccessibilityNode` | strukturiert | 68, 314, 77, 18 |
| `45129914169` | Zutaten (Rezept) | `AccessibilityNode` | 5 Artikel hinzufügen | 16, 774, 370, 50 |
| `45129914169` | Einkauf › Rezept hinzufügen (Notiz) | `AccessibilityNode` | Eine Notiz mit den Abschnitten … | 16, 399, 370, 78 |
| `45157276905` | Rezept anlegen (Eingabe) | `AccessibilityNode` | Füge die Zutatenliste … | 16, 492, 370, 46 |
| `45157276905` | Einkauf › Rezept hinzufügen | `AccessibilityNode` | Füge die Zutatenliste … | 16, 527, 370, 46 |
| `45157481969` | Rezept anlegen (Eingabe) | `AccessibilityNode` | Füge die Zutatenliste … | 16, 492, 370, 46 |

„Ich koche für“ kommt in den 16 Logs nicht als Befund vor (nur im Elementbaum); der genannte Befund stammt aus einem
älteren Lauf und ist hier nicht belegt.

### 3.2 Die zwei Läufe mit Bestätigungsdurchlauf

Kein Rezept-Test ist rot. Dieselbe Art Befund erscheint im ersten Durchlauf und fehlt im zweiten
(„Unconfirmed audit finding“):

| Lauf | Screen | unbestätigte Befunde |
|---|---|---|
| `45130152684` | Einkaufsliste | 6 (Brot & Backwaren, Brot, Milch, Kühlregal, `UIKitTextField`, Kopfzeile) |
| `45130152684` | Tagesabschluss | 2 |
| `45157447007` | Rezept anlegen (Eingabe) | 2 (Rezepttext, Füge die Zutatenliste …) |
| `45157447007` | Rezept anlegen (Bestätigung) | 5 (Rezept speichern, Portionen, „2“, zwei `UIKitTextField`) |
| `45157447007` | Einkaufsliste › Übersetzung | 3 (Milch, Milk, `UIKitTextField`) |
| `45157447007` | Datensicherung › Sicherheitskopien | 1 |

19 Befunde im ersten Durchlauf, 0 bestätigt. Alle sind vom Typ Dynamic Type.

### 3.3 Bewertung

**Belegt**

- Die Views enthalten keine Ursache: Die gemeldeten Texte sind Abschnittskopf und -fuß einer `Form`
  (`RecipeSheets.swift:424–427`), ein `Label` in einem `Button` (`RecipeNotePicker.swift:62`), eine Zeile mit
  `.subheadline` (`RecipeNotePicker.swift:91`), SwiftUI-Textfelder und der Abschlussknopf. Kein fester Font, kein
  `lineLimit`, kein fester Rahmen.
- Derselbe Code liefert den Befund in einem Durchlauf und im nächsten nicht (Abschnitt 3.2).
- Ein Durchlauf meldet meist mehrere Texte desselben Screens zugleich (bis zu 6). Das spricht gegen einen Fehler
  einzelner Elemente.
- Die gemeldeten Texte wechseln: 11 verschiedene Labels auf 8 Screens in 13 Läufen.

**Annahme (nicht gemessen)**

- Mechanismus: Der Dynamic-Type-Check stellt die Schriftgröße des Systems um und liest das Layout. Kommt die
  Umstellung auf dem ausgelasteten Runner (3 Kerne) nicht rechtzeitig in der App an, sieht der Check unveränderte
  Texte und meldet den ganzen sichtbaren Teil. Das passt zu den Mehrfachbefunden je Screen, ist aber nicht direkt
  gezeigt.

**Einordnung**: Nichtdeterminismus des Audits. Kein System-Control-Sonderfall, keine View-Korrektur nötig. Das
`UIKitTextField` der Übersetzung gehört in dieselbe Gruppe und braucht keinen eigenen Allowlist-Eintrag.

### 3.4 Restrisiko des Bestätigungsdurchlaufs

In den zwei Läufen traf es 6 von etwa 54 Dynamic-Type-Durchläufen (rund 11 %, zwei Läufe, grobe Schätzung). Ein
Test wird rot, wenn auch der zweite Durchlauf denselben Text meldet. Bei Unabhängigkeit der Durchläufe wäre das je
betroffenem Screen in der Größenordnung von 5 bis 10 %, bei etwa drei betroffenen Screens je Lauf also spürbar.
Ob die Durchläufe unabhängig sind, ist offen: Last hält an, was die Quote erhöhen würde. Beobachtet: 0 von 6. Die
Daten reichen nicht, um das Risiko als erledigt zu werten.

## 4. Timeout „Failed to get matching snapshots: Timed out while evaluating UI query“

### 4.1 Fundstellen

| Lauf | Test | Stelle | Was dort wartet |
|---|---|---|---|
| `45101968856`, `45109273839`, `45129942623`, `45157276905`, `45157481969`, `45109270040` (2. Versuch) | `testAuditSettings` | `AccessibilityAuditRecipesUITests.swift:117` | Navigationsleiste „Spracheingabe und Vorlesen“ nach dem Start mit `settings.ai.voice` |
| `45157447007` (Stand #299) | `testAuditDefaultSize` | `UITestCase.swift:230` | `waitFor("Sprechstunde")` direkt nach dem Start auf „Planen“ |
| `45109270040` (2. Versuch) | sieben Audit-Tests | verschiedene | ganzer Lauf langsam, auch „Audit failed to complete in time“ (Code -56) |

Dazu in `45157276905` drei Startfehler ohne Bezug zum Audit („does not have a process ID“, „Failed to get
background assertion“).

### 4.2 Ablauf (Lauf `45157481969`, die anderen fünf gleich)

- 0 bis 37 s: Start, Seite „Sprachen“, Audit läuft durch.
- 37,8 s: zweiter Start mit `settings.ai.voice`; 60,6 s: Warten auf die Navigationsleiste.
- 61,6 bis 70,9 s: erste Abfrage antwortet nach 9 s.
- danach drei Abfragen mit je 30 s Timeout, Fehler; auch der Snapshot im Teardown bei 265 s kommt nicht zurück.
  Der Test endet nach 326 s.
- Ein Lauf ohne Hänger braucht für dieselbe Seite samt Audit rund 17 s; der ganze Test dauert 193 s, davon etwa
  100 s für die fünf App-Starts (je rund 20 s bis `demoReady`).

### 4.3 Bewertung

**Belegt**

- Das Audit ist nicht die Ursache: Der Timeout tritt vor dem ersten Audit-Aufruf der Seite auf.
- Es ist immer dieselbe Seite. Die anderen vier Einstellungsseiten hängen in keinem Lauf.
- Die App antwortet über mehr als 190 s nicht auf Accessibility-Abfragen. Das Muster entspricht einem blockierten
  Main-Thread, nicht einem großen Elementbaum (die Seite hat drei Abschnitte).
- Die Seite antwortet einmal und hängt dann. Das passt zum `.task` der Seite, der nach dem Erscheinen startet
  (`VoiceSettingsView.swift:113`).

**Annahme (Stack nicht gesehen)**

Kandidaten in `VoiceSettingsView.refresh()` (`:142–149`), nach Plausibilität:

1. `SystemSpeaker()` und `speaker.voices(for:)` auf dem Main-Actor (`:144`, `:147`): legt einen
   `AVSpeechSynthesizer` an und ruft `AVSpeechSynthesisVoice.speechVoices()` synchron auf
   (`SpeechSpeaking.swift:51`, `:82`), zweimal je Aufruf der Seite.
2. `AVAudioApplication.shared.recordPermission` (`:48` als Startwert eines `@State`, `:143`).
3. `AssetInventory.status(forModules:)` und `supportedLocale(equivalentTo:)` (`:22–23`): asynchron, blockieren den
   Main-Thread der Erwartung nach nicht.

Für den Hänger direkt nach dem Start (`testAuditDefaultSize`): `AppEnvironment.swift:269` legt bei jedem Start
einen `SystemSpeaker` und damit einen `AVSpeechSynthesizer` an. Ob das der Auslöser war, ist offen; es ist ein
Einzelfall auf einem langsamen Lauf (Automation-Session 7,5 s, erste Abfrage 11 s).

**Nebeneffekt, belegt**: Der Wert der Zeilen „Sprachpaket …“ hängt vom Zustand des Runners ab
(`LanguagePackState`), der Inhalt des auditierten Screens ist also nicht festgelegt.

### 4.4 Was nicht hilft

- Längere Timeouts: Die App hängt über 190 s; der Timeout der Abfrage ist nicht einstellbar.
- Eingrenzen der Abfrage oder weniger Snapshot-Tiefe: Die Abfrage ist bereits auf die Navigationsleiste begrenzt.
- Höhere Job-Limits (#298): verlängern nur den roten Lauf.

## 5. Nebenbefund: Die Wiederholung im Pull-Request-Lauf greift nicht

- 15 von 16 Logs: jede Testmethode startet als „Iteration 1 of 2“, keine einzige „Iteration 2 of 2“, obwohl 2 bis
  10 Tests je Lauf fehlschlagen. `retried-ui-tests.md` meldet immer „none“.
- Nach jedem fehlgeschlagenen Test beendet sich der Runner („Flushing outgoing messages to the IDE“, neuer Prozess,
  „Restarting after unexpected exit, crash, or test timeout“); die Testklasse läuft danach mit 0 Tests weiter.
- Die einzige zweite Iteration (`45109270040`, 2. Versuch) folgt auf einen geworfenen Fehler (Audit-Timeout -56),
  nicht auf eine Assertion.

Annahme zum Mechanismus: Mit `continueAfterFailure = false` (`UITestCase.swift:18`, in `async setUp`) beendet eine
fehlgeschlagene Assertion den Runner-Prozess; `xcodebuild` wertet den Test als erledigt und wiederholt ihn nicht.
Belegt ist nur das Verhalten, nicht der Grund. Folge: Jeder einzelne Flake macht den Pull-Request-Lauf rot. Das
erklärt einen großen Teil der Fehlläufe unabhängig von den Audits.

## 6. Plan für die Umsetzung

Reihenfolge nach Wirkung. Jede Aufgabe ist ein eigener Commit. Lokal je Commit mit `TAGWERK_SKIP_UI_TESTS=1`, die
betroffenen UI-Testklassen einzeln, der volle UI-Lauf am Ende des Strangs.

### Aufgabe 1: Seite „Spracheingabe und Vorlesen“ ohne Systemaufrufe auf dem Main-Thread

Dateien: `app/Tagwerk/Voice/VoiceSettingsView.swift`, `app/Tagwerk/Voice/SpeechSpeaking.swift`,
`app/Tagwerk/App/AppEnvironment.swift`, `app/TagwerkTests/` (neuer Test), `app/TagwerkTests/Fakes/FakeVoice.swift`.

- Stimmenliste aus `SystemSpeaker` lösen: eine `nonisolated static func installedVoices(for:)` (Inhalt von
  `voices(for:)`, `SpeechSpeaking.swift:80–93`), die keinen `AVSpeechSynthesizer` braucht. `voices(for:)` ruft sie auf.
- `refresh()` lädt die Stimmen außerhalb des Main-Actors (z. B. `await Task.detached { … }.value`) und legt keinen
  `SystemSpeaker` mehr an. `recordPermission` wird nur noch in `refresh()` gelesen; der Startwert des `@State` wird
  `.undetermined`.
- `SystemSpeaker.synthesizer` wird `lazy`, der Delegate wird beim ersten Zugriff gesetzt. Der App-Start legt damit
  keinen Synthesizer mehr an.
- Im UI-Test-Modus (`UITestMode.isActive`) liefert die Seite feste Werte ohne Systemaufruf: beide Sprachpakete
  `.available`, keine zusätzlichen Stimmen, Mikrofon `.undetermined`. Am besten über eine kleine Quelle
  (`VoiceSettingsSource` mit `live` und `uiTest`), damit die View keine Verzweigung enthält.
- Tests: Unit-Test für die feste Quelle und für `installedVoices(for:)` (Sortierung, Filter über eine injizierte
  Stimmenliste). `AccessibilityAuditRecipesUITests/testAuditSettings` und die AX5-Variante lokal je einmal; die
  Allowlist-Einträge für „Automatisch“ und die Fußzeilen bleiben.

Erwartete Wirkung: Der Timeout in Zeile 117 entfällt, wenn einer der drei Kandidaten die Ursache ist (Annahme). Der
Screen-Inhalt ist auf jedem Runner gleich. Risiko: Auf dem Gerät erscheint die Stimmenliste einen Moment später.

### Aufgabe 2: Diagnose für einen hängenden App-Prozess

Datei: `app/test-all.sh` (UI-Stufe), `.github/workflows/tests.yml` nur falls der Upload-Pfad fehlt.

- Während der UI-Stufe liest ein Hintergrundprozess das Log mit. Bei einer Zeile
  `Checking existence of … (retry 2)` schreibt er einmal je Test ein `sample <pid> 3` des App-Prozesses
  (`pgrep -f 'Tagwerk.app/Tagwerk'`; Simulator-Prozesse sind Prozesse des Hosts) nach
  `$TAGWERK_TEST_LOG_DIR/hang-<Zeit>.txt`. Der Ordner wird bereits als Artefakt hochgeladen.
- Kein Einfluss auf das Testergebnis; der Prozess endet mit der Stufe.

Erwartete Wirkung: Der nächste Hänger zeigt den Stack des Main-Threads und bestätigt oder widerlegt die Annahmen
aus 4.3. Diese Aufgabe gehört in denselben Pull Request wie Aufgabe 1, damit ein verbleibender Hänger belegt ist.

### Aufgabe 3: `testAuditSettings` je Seite teilen

Datei: `app/TagwerkUITests/AccessibilityAuditRecipesUITests.swift`, `app/TagwerkUITests/nightly-only.txt` (unverändert,
die Klasse bleibt gleich).

- `auditSettings` wird zu `auditSettingsPage(_ page:)`; fünf Testmethoden je Klasse (`testAuditSettingsLanguages`,
  `…Voice`, `…Capture`, `…Shopping`, `…Siri`). Der Start erfolgt in `setUp` über `extraLaunchArguments` mit
  `-TagwerkUITestScreen`, `launchesInSetUp` und die Namensprüfung (`:15`) entfallen.
- Laufzeit bleibt gleich (fünf Starts wie bisher). Ein Fehler betrifft nur eine Seite, eine Wiederholung kostet
  rund 40 s statt 190 s, und der Bericht nennt die Seite im Testnamen.

### Aufgabe 4: Wiederholung im Skript

Datei: `app/test-all.sh`, Kommentar in `.github/workflows/tests.yml`.

- Vorab eine Messung (ein manueller Lauf mit einem absichtlich fehlschlagenden Test), ob `continueAfterFailure`
  der Grund ist. Unabhängig vom Ergebnis ist die robuste Lösung: `-retry-tests-on-failure -test-iterations 2`
  entfernen, nach dem ersten `xcodebuild test-without-building` die fehlgeschlagenen Tests aus dem Log lesen
  (`Test Case '-[…]' failed`) und genau diese einmal mit `-only-testing:` erneut ausführen (eigenes Ergebnisbündel,
  eigenes Log). Die Stufe ist grün, wenn der zweite Aufruf grün ist; „RETRIED UI TESTS“ listet sie wie bisher.
- Obergrenze: mehr als fünf fehlgeschlagene Tests werden nicht wiederholt (dann ist es kein Flake).
- Der nächtliche Lauf bleibt ohne Wiederholung.

Erwartete Wirkung: Einzelne Flakes (Startfehler, ein Hänger, ein Rundungsfehler wie in `PlanUITests`) machen den
Pull-Request-Lauf nicht mehr rot. Das ist die Aufgabe mit der größten Wirkung auf die Quote grüner Läufe.

### Aufgabe 5: Dynamic-Type-Befund erst nach drei Durchläufen

Datei: `app/TagwerkUITests/AuditAllowlist.swift` (`audit(_:screen:for:)`, `:342–370`).

- Enthält der Durchlauf `.dynamicType` und bleibt nach der ersten Bestätigung ein Befund, folgt ein dritter
  Durchlauf; rot wird nur, was alle drei melden. Für die anderen Audit-Typen bleibt es bei zwei.
- Die Schleife ersetzt die doppelte Abfrage: `requiredPasses = pass.contains(.dynamicType) ? 3 : 2`, Schnittmenge der
  Schlüssel über die Durchläufe, Abbruch sobald die Menge leer ist. Ein sauberer Screen kostet weiterhin nichts.
- `print` für unbestätigte Befunde bleibt und nennt die Zahl der Durchläufe, damit die nächtlichen Logs die Quote
  messbar machen.

Erwartete Wirkung: Das Restrisiko aus 3.4 sinkt um etwa eine Größenordnung (Annahme: Durchläufe annähernd
unabhängig). Ein echter Fehler (fester Font) wird in jedem Durchlauf gemeldet und bleibt rot.

### Aufgabe 6: Feature-Branches auf `main` bringen

Kein Code. Alle offenen Branches (`feat/g2-bible-study-2`, `fix/first-tap-keyboard-controls`, weitere) enthalten
#299 nicht und zeigen deshalb weiter die Rezept-Befunde und „Zeit mit Gott“. `main` einmischen, bevor ihre Läufe
bewertet werden.

## 7. Prüfung auf CI

1. Pull Request mit den Aufgaben 1 bis 5. Erwartung im Log: keine Zeile `AccessibilityAuditRecipesUITests.swift:117`,
   fünf Einstellungs-Tests einzeln, bei einem Flake ein zweiter `xcodebuild`-Aufruf mit Eintrag unter „RETRIED UI TESTS“.
2. Drei manuelle Läufe (`workflow_dispatch`, voller Satz, ohne Wiederholung) auf dem Branch. Auswertung je Lauf:
   Zahl der Zeilen „Unconfirmed audit finding“, Zahl der bestätigten Befunde, Vorkommen von
   „Timed out while evaluating UI query“, vorhandene `hang-*.txt`.
3. Kriterium: in drei vollen Läufen kein Timeout auf der Sprachseite und kein bestätigter Dynamic-Type-Befund auf
   den Rezept-Screens. Tritt ein Hänger auf, entscheidet das Sample über den nächsten Schritt.
4. Danach eine Woche die nächtlichen Läufe mitlesen; die Quote unbestätigter Befunde ersetzt die Schätzung aus 3.4.

Drei Läufe zeigen nur grobe Fehler. Ein Flake mit 10 % Quote bleibt in drei Läufen mit rund 73 % Wahrscheinlichkeit
unsichtbar; deshalb Schritt 4.

## 8. Offene Fragen

1. Soll der Dynamic-Type-Check der Standardgröße im Pull-Request-Satz bleiben? Alternative zu Aufgabe 5: nur im
   nächtlichen Lauf, der AX5-Lauf prüft das Wachsen der Texte ohnehin.
2. Ist ein fester Zustand der Sprachseite im UI-Test-Modus gewollt? Der echte Zustand der Sprachpakete wird dann von
   keinem UI-Test mehr angezeigt.
3. Soll die Wiederholung im Skript (Aufgabe 4) auch lokal gelten oder nur mit `TAGWERK_UI_TEST_RETRIES=1` wie bisher?
4. Die `xcresult`-Bündel wurden nicht gelesen. Falls für die Rezept-Befunde Screenshots gebraucht werden, wären
   bis zu vier Artefakte (je rund 300 MB) zu laden.
