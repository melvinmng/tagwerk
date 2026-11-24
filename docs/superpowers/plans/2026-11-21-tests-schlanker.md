# Tests schlanker und schneller – Analyse, Optionen und Zielbild


> **Entscheidung des Nutzers (21.11.2026):** Alle Empfehlungen, vollständig umsetzen (TS1b, TS2b, TS3b, TS4b, TS5b, TS6b, TS7a, TS8b, TS9b, TS10b, TS11b, TS12b), inklusive Branch-Schutz mit Pflicht-Checks, sobald CI grün läuft. Rückfall: Ist GitHub zu langsam, laufen die (verbesserten) UI-Tests wieder auf dem Mac.

> **For agentic workers:** Implement task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Erst die TS-Entscheidungen der Hauptsitzung abwarten; die Tasks setzen die jeweils empfohlene Variante um.

> **Status:** Entwurf vom 21.11.2026. Grundlage: `origin/main` (`1d6364a`), `origin/fix/ui-audits-and-strings` (`4f73e1f`, PR #261) und `origin/ci/github-full-tests` (`af4116c`, PR #267). **Kein Build, kein Simulator, kein Testlauf für diesen Plan.** Die Zeiten stammen aus den vorhandenen lokalen Logs unter `$TMPDIR/tagwerk-tests/` (nur gelesen) und sind als **gemessen** markiert; alles andere ist als **Schätzung** oder **ungeprüft** markiert. Zeilenangaben beziehen sich auf `origin/main`, sofern nicht anders genannt.

**Goal:** Der Testaufbau soll (1) lokal den Mac nicht mehr mit drei gleichzeitig laufenden UI-Stufen überlasten, (2) vor einem Merge in deutlich unter der heutigen Zeit ein belastbares Ergebnis liefern und (3) Schwankungen (Flakiness) sichtbar machen, ohne den Merge zu blockieren.

**Kurzfassung:** Die UI-Stufe kostet lokal 26 bis 31 Minuten, und der größte Teil davon ist keine Prüfzeit: 24 % sind App-Starts, 19 % Scroll-Gesten, 21 % Elementabfragen. Allein die zwei Tests `testAuditSettings` brauchen zusammen 5,7 Minuten, davon nach dem Log etwa vier Fünftel für eine Scrollschleife. Empfohlen wird: Navigation der Audits per Direktsprung, AX5/Dark-Varianten der Nebenscreens in einen nächtlichen Lauf, vier Layout-/Kontrastklassen als Render-Tests in die Unit-Stufe, die UI-Stufe als Gate auf GitHub Actions statt lokal, Pakettests ohne Simulator.

---

## 1. Befunde

### 1.1 Wohin die Zeit geht (Stufen)

Quelle: Änderungszeitpunkte und Testsummen der Stufenlogs von 14 lokalen Läufen (20./21.11.2026). „Stufendauer“ ist der Abstand zum Log der vorherigen Stufe, enthält also Build und Simulatorstart.

| Stufe | Tests | Testlaufzeit (gemessen) | Stufendauer ohne Last (gemessen) | Stufendauer unter Last (gemessen) |
|---|---|---|---|---|
| 5 Pakete (`app/test-all.sh:68-79`) | 1.818 bis 1.916 | zusammen 1 bis 15 s | 5 × ca. 5 s (inkrementell) | 6 bis 12 min (z. B. `baseline-24de86db`: 2,0 + 1,6 + 3,0 + 4,5 min) |
| App-Scheme `Tagwerk` (`:88`) | 1.784 bis 2.378 | 22 bis 89 s | 0,8 bis 1,6 min | 2,6 bis 10,2 min |
| UI-Tests (`:117`) | 17 bis 19 (20.11.), 36 (Stand #261) | 10,8 bis 17,7 min (17 Tests), 26,4 min (36 Tests) | Testlaufzeit + ca. 0,4 min | bis 29,9 min Stufendauer in einem Lauf mit 4 Fehlschlägen |
| String-Kataloge | – | Sekunden | Sekunden | Sekunden |

Folgerungen:

- **Ohne Last ist nur die UI-Stufe teuer.** Pakete und App-Stufe brauchen warm zusammen 1,5 bis 2,5 Minuten; die UI-Stufe über 90 % der Gesamtzeit.
- **Unter Last werden auch die „schnellen“ Stufen langsam**, obwohl ihre Testlaufzeit bei Sekunden bleibt. Der Grund liegt im Aufbau, nicht in den Tests: Jede Paketstufe ist ein eigener `xcodebuild test`-Aufruf gegen den Simulator (`:78`, Ziel `$DESTINATION`), braucht also einen gestarteten Simulator samt Testrunner-Installation. Die Aufgabenbeschreibung nennt `swift test`; tatsächlich läuft kein Pakettest auf dem Mac selbst.
- **`TagwerkCore` wird bis zu fünfmal gebaut:** je einmal im DerivedData der Paket-Schemes `TagwerkCore`, `GitHubKit`, `RemindersKit`, `HealthBridge` (kein `-derivedDataPath`, also je ein eigener Ordner unter Xcodes Standardpfad) und einmal im DerivedData der App. Lokal fällt das nur beim ersten Lauf eines Worktrees auf, auf CI bei jedem Lauf. Die Höhe der Ersparnis ist **ungeprüft**.
- **Für `main` plus #261 ergibt sich rechnerisch 41 UI-Tests** (39 auf `main`, plus 2 Abend-Audits aus #261). Der gemessene 36-Test-Lauf enthält `TravelContrastUITests` (3 Tests) und 2 Tests von `PlanUITests` noch nicht. **Schätzung:** 29 bis 31 Minuten Testlaufzeit ohne Last.

### 1.2 Wohin die Zeit in der UI-Stufe geht (pro Klasse)

Quelle: voller Lauf im Worktree von PR #261 (`t3-9d48c5a6…/app-UI-tests.log`, 36 Tests, 0 Fehler, 1.586 s) – **eine Messung**, ergänzt um 4 bis 6 Wiederholungen der Audit-Tests aus `scripts/stress-audits.sh` (Median in Klammern).

| Klasse | Tests | Zeit | Anteil |
|---|---|---|---|
| `AccessibilityAuditRecipesLargeTextUITests` (AX5/dunkel) | 5 | 391 s | 24,7 % |
| `AccessibilityAuditRecipesUITests` | 5 | 286 s | 18,1 % |
| `TaskFlowUITests` | 5 | 126 s | 8,0 % |
| `AccessibilityAuditUITests` | 1 | 102 s (116 s) | 6,5 % |
| `PlanHeaderLayoutUITests` | 1 | 88 s | 5,5 % |
| `SearchUITests` | 3 | 64 s | 4,0 % |
| `AccessibilityAuditEveningUITests` + `…EveningLargeText…` | 2 | 126 s | 8,0 % |
| `ShoppingTranslateUITests` | 2 | 61 s | 3,8 % |
| `AccessibilityAuditLargeTextUITests` (AX5/dunkel, 4 Kernscreens) | 1 | 59 s (49 s) | 3,7 % |
| `NotesUITests`, `PlanUITests`, `PlanOverlapUITests`, `NowMarkerUITests`, `RoutineUITests`, `CaptureUITests`, `ShoppingUITests` | 10 | 282 s | 17,8 % |

- **Audits: 14 Tests, 16,1 min (61 %).** Funktionale Tests: 22 Tests, 10,3 min (39 %).
- **AX5/Dunkel-Varianten: 7 Tests, 513 s (32 %).**
- **Zwei Tests kosten 22 % der UI-Stufe:** `testAuditSettings` braucht 126 s (Median 142 s) in der Standardgröße und 217 s (Median 230 s) in AX5/dunkel.

### 1.3 Wohin die Zeit in der UI-Stufe geht (nach Tätigkeit)

Quelle: derselbe Lauf, Zeitstempel der obersten XCTest-Schritte je Test, nach Schrittart summiert (Auswertung per Skript, nur gelesen).

| Tätigkeit | Alle 36 Tests | Audit-Klassen (16,1 min) | Funktionale Klassen (10,3 min) |
|---|---|---|---|
| App-Start bis `demoReady` (`UITestCase.swift:41-47`) | 6,4 min (24 %), Median 9,8 s je Test | 2,6 min (16 %) | 3,8 min (37 %) |
| Warten auf Elemente | 5,6 min (21 %) | 2,5 min (15 %) | 3,1 min (30 %) |
| Elementabfragen (finden, `exists`, `isHittable`, Label lesen) | 5,4 min (21 %), 2.133 Abfragen | 5,1 min (32 %), 1.891 Abfragen | 0,3 min |
| Ziehen/Wischen | 4,9 min (19 %), 138 Gesten | 4,7 min (29 %), 124 Gesten | 0,3 min |
| Tippen | 2,4 min (9 %) | 0,9 min | 1,6 min |

Folgerungen:

- **Der Audit selbst ist nicht der Kostentreiber.** Die stillen Phasen, in denen `performAccessibilityAudit` läuft, sind je Screen 3 bis 6,5 s lang (im Log als Lücken ohne Schritt sichtbar). Bei rund 48 Audit-Durchgängen wären das 3 bis 5 Minuten. Das ist ein **Indiz aus Loglücken**, keine direkte Messung; ein Teil der Auditzeit kann in den Abfragen stecken.
- **Die Scrollschleife von `openSettingsRow`** (`AccessibilityAuditRecipesUITests.swift:147-158`: erst viermal `swipeDown`, dann bis zu 20 Zieh-Schritte, vor jedem Schritt `exists` und `isHittable`) erzeugt in `testAuditSettings` 36 Gesten in der Standardgröße und 68 in AX5. Bei gut 2 s je Geste samt Abfragen erklärt das 75 bis 170 s der 126 bzw. 217 s.
- **Der Abgleich mit der Ausnahmenliste kostet Abfragen:** Für jeden Befund liest `matchesAllowlist` drei Eigenschaften des Elements (`AuditAllowlist.swift:305`), jede ist eine eigene Abfrage an die App. Die größte Gruppe der Liste ist der graue Sekundärtext (Kontrast), der auf fast jedem Screen Dutzende Befunde liefert. Der genaue Anteil an den 1.891 Abfragen ist **nicht getrennt gemessen**.
- **Jeder Test startet die App neu** (`setUp` ruft `launchApp`, `UITestCase.swift:21-39`). Bei den funktionalen Tests ist das mit 37 % der größte Einzelposten; `PlanHeaderLayoutUITests` startet für einen Test sechsmal (`PlanHeaderLayoutUITests.swift:44`).
- Animationen sind im UI-Testmodus bereits aus (`TagwerkApp.swift:23`), dort ist nichts mehr zu holen.

### 1.4 Simulator- und Speicherlage (gemessen am 21.11.2026, 20:33 Uhr)

- 3 Simulatoren „Tagwerk Tests …“ vorhanden, alle 3 gestartet; Auslagerung 4,4 von 5,1 GB belegt bei 16 GB RAM.
- `~/Library/Developer/CoreSimulator/Devices`: 12 GB; `~/Library/Developer/Tagwerk` (DerivedData der Tests): 5,0 GB in 3 Ordnern.
- `$TMPDIR/tagwerk-tests` enthält Logs von 47 Checkouts: Jeder neue Worktree legt Simulator und DerivedData neu an (`scripts/test-env.sh:20`, `:36`, `:50`), der Simulator **bleibt nach der UI-Stufe gestartet** (`app/test-all.sh:96`).
- Fehlschläge häufen sich unter Last: Von den 5 UI-Läufen, die am 20.11. zwischen 21:21 und 22:22 Uhr endeten, enthalten 4 Fehlschläge; im selben Zeitfenster brauchten die Paketstufen ein Vielfaches ihrer üblichen Zeit (bis 4,5 min statt 5 s), was auf Parallelbetrieb hinweist. Von den übrigen 16 UI-Logs enthalten 2 Fehlschläge. Das **stützt die Annahme**, dass Last die Hauptursache der Restflakiness ist; ein Beweis ist es nicht, weil die Läufe verschiedene Codestände testen.

### 1.5 CI (PR #267)

- Workflow `tests.yml`: Matrix mit zwei Jobs `fast` und `ui` auf `xcode-27`, 90 min Job-Limit, 80 min Schritt-Limit, Abbruch bei neuem Push.
- **Jeder Job baut alles selbst**, ein Cache fehlt bewusst (Begründung im README: neue Änderungszeitpunkte nach dem Checkout).
- Der erste Lauf (Run `44940990259`) lief bei Redaktionsschluss seit über 12 Minuten, beide Jobs im Schritt „Run test stages“. **CI-Dauern sind deshalb unbekannt.**
- GitHub-Limits (geprüft am 21.11.2026 in der [Limits-Referenz](https://docs.github.com/en/actions/reference/limits) und der [Runner-Referenz](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)): Free-Plan **20 gleichzeitige Jobs, davon höchstens 5 macOS-Jobs**; das macOS-Limit gilt gemeinsam für Standard- und größere Runner; 6 Stunden je Job; 256 Matrix-Jobs je Lauf. Die Seite unterscheidet **nicht** zwischen öffentlichen und privaten Repositories, die 5 gelten also auch hier. Standard-Runner sind für öffentliche Repositories kostenlos und ohne Minutenlimit. `xcode-27` steht in der Tabelle der arm64-Runner mit 3 Kernen (M1), 7 GB RAM, 14 GB SSD.
- Folge für Sharding: `fast` + 3 UI-Shards sind 4 macOS-Jobs je PR. Zwei gleichzeitig aktualisierte PRs (bei drei Agenten der Normalfall) brauchen 8 und stehen in der Warteschlange.

### 1.6 Wo Logik liegt

| Modul | Quellzeilen | Testzeilen | Fremd-Frameworks | Tests brauchen Simulator? |
|---|---|---|---|---|
| `TagwerkCore` | 13.654 | 12.774 | Foundation, Markdown, NaturalLanguage | heute ja, technisch nein |
| `GitHubKit` | 2.408 | 3.187 | Foundation | heute ja, technisch nein |
| `AIKit` | 1.656 | 1.803 | Foundation, Network, 1 × UIKit, AuthenticationServices | heute ja, ungeprüft |
| `RemindersKit` | 1.302 | 1.119 | EventKit | heute ja, ungeprüft |
| `HealthBridge` | 530 | 93 | HealthKit | heute ja, ungeprüft |
| App-Target `Tagwerk` | 53.136 (313 Dateien) | 30.160 (166 Dateien, `TEST_HOST`, `project.yml:143`) | SwiftUI, SwiftData, … | ja (in der App gehostet) |

Alle Pakete deklarieren nur `platforms: [.iOS("27.0")]`, deshalb ist `swift test` auf dem Mac heute nicht möglich. Rund 1.900 der gut 4.200 Unit-Tests hängen damit ohne technischen Grund am Simulator. Die App-Tests (ca. 2.350) prüfen überwiegend Modelle und Stores (79 von 166 Dateien importieren SwiftData), liegen aber im App-Target und brauchen die gehostete App.

---

## 2. Bewertung der UI-Tests

### 2.1 Kandidaten für Unit- oder Render-Tests

Es gibt ein Vorbild im Projekt: `MarkerRenderContrastTests` misst den Kontrast am gerenderten Bild einer View (`ContrastMath.renderedRatio`), ohne UI-Testlauf.

| UI-Test | Zeit | Was er prüft | Vorschlag |
|---|---|---|---|
| `PlanHeaderLayoutUITests.testTitleNeverTouchesTheBarButtons` | 88 s, 6 Starts | Abstand Titel zu Leistenknöpfen in 2 Sprachen × 3 Textgrößen | Render-/Layout-Test der Kopfzeile in `TagwerkTests` (Größe der gehosteten View messen). Die Textlogik deckt `PlanHeaderTextTests` schon ab. **Risiko:** Die echte Navigationsleiste verhält sich anders als eine gehostete View; ein UI-Fall (Standardgröße, Deutsch) bleibt im nächtlichen Lauf. |
| `TravelContrastUITests.testTightTripInLight/-Dark` | ca. 50 s (Schätzung) | Kontrast der Kapsel „zu früh“ per Audit | Redundant zum Render-Test derselben Kapsel in `MarkerRenderContrastTests` („one of the four proofs“). Entfernen bzw. nur nächtlich. |
| `TravelContrastUITests.testAttachmentSitsAboveItsEventInTheGrid` | ca. 25 s (Schätzung) | Geometrie der Kapsel im Raster | Layout-Test der Rasterberechnung, falls die Position aus einem Modell kommt (**ungeprüft**); sonst nächtlich. |
| `PlanOverlapUITests` (2 Tests) | 49 s | Überlappende Einträge fallen bei großer Schrift zu einem Block zusammen | Die Entscheidung (Spaltenbreite gegen Schriftgröße) als Unit-Test der Layoutfunktion; ein UI-Fall bleibt nächtlich. |
| `NowMarkerUITests` (2 Tests) | 39 s | Restzeit des laufenden Eintrags, Ausrichtung auf „jetzt“ | Text über `NowLineTextTests` abgedeckt; `testHeuteAlignsTheGridToNowAgain` ist echtes Scrollverhalten und bleibt. Ersten Test streichen. |
| `TaskFlowUITests.testKeyboardButtonHidesKeyboard`, `…testReturnKeyReadsFertigInSingleLineFields` | 39 s | Tastaturknopf, Beschriftung der Return-Taste | In einen Test zusammenlegen (ein Start statt zwei). `KeyboardTapPolicyTests` deckt die Regel, nicht die Systemtaste. |

### 2.2 Audit-Varianten

- **Standardgröße, alle Audit-Typen** (`AccessibilityAuditUITests`, `AccessibilityAuditRecipesUITests`, Abend): hoher Wert, weil jeder neue Screen-Fehler (fehlendes Label, Trefferfläche, Kontrast) hier auffällt. Bleibt Gate.
- **AX5/dunkel, 4 Kernscreens** (`AccessibilityAuditLargeTextUITests`, 49 bis 59 s): günstig und deckt die meistgenutzten Screens. Bleibt Gate.
- **AX5/dunkel für 15 Rezept-/Einstellungsscreens und die Abend-Screens** (454 s): prüft nur `textClipped` und `contrast`. Kontrast im Dunkelmodus hängt an Farbwerten, die sich selten ändern; abgeschnittener Text hängt am Layout einzelner Screens, die nach ihrer Fertigstellung selten angefasst werden. **Annahme, nicht gemessen:** Diese Variante findet selten etwas, das nicht auch die Standardgröße oder der Kernscreen-Lauf findet. Belegen lässt sich das mit der Historie von `AuditAllowlist.swift` nicht sauber. Vorschlag: nächtlich statt je PR.
- **Kein Screen wird doppelt in derselben Variante auditiert** bis auf die Einkaufsliste (in `testAuditDefaultSize`, `testAuditShoppingTranslate` und AX5). Das ist vertretbar, weil die Zustände verschieden sind.

### 2.3 Was UI-Test bleiben sollte

Die Abläufe mit echtem Zusammenspiel aus Navigation, EventKit-Demodaten und Systemtastatur: `TaskFlowUITests.testCreateEditCompleteUndo`, `PlanUITests`, `ShoppingUITests`, `ShoppingTranslateUITests`, `NotesUITests`, `SearchUITests`, `RoutineUITests`, `CaptureUITests`, die Fokus-Tests. Sie kosten zusammen etwa 8 Minuten, davon gut ein Drittel App-Starts.

---

## 3. Optionen, nach Nutzen geordnet

Ersparnis bezogen auf den lokalen Lauf ohne Last (Basis: ca. 30 min UI-Stufe für 41 Tests), soweit nicht anders vermerkt. Alle Ersparnisse sind **Schätzungen aus der Logauswertung**.

| # | Option | Aufwand | Erwartete Ersparnis | Risiko |
|---|---|---|---|---|
| 1 | **UI-Stufe als Gate auf CI statt lokal** (lokal nur schnelle Stufen und gezielte UI-Klassen) | klein (PR #267 fertigstellen, Regel ändern) | lokal 15 bis 30+ min je Strangende, dazu entfällt der Parallelbetrieb von drei UI-Stufen (Hauptursache der Lastspitzen) | CI-Dauer und -Stabilität unbekannt; Rückmeldung kommt später als lokal |
| 2 | **AX5/Dunkel-Audits der Nebenscreens und Stress nur nächtlich** | klein | 7,6 min je PR-Lauf (454 s) | Regression in AX5/dunkel fällt bis zu einem Tag später auf, nach dem Merge |
| 3 | **Direktsprung zu Screens in den Audits statt Scrollschleifen** | mittel (Startargument in der App, 2 Testhelfer) | 3,5 bis 4,5 min im vollen Lauf, 1 bis 1,5 min im PR-Lauf | Audit sieht den Screen ohne den Weg dorthin; Navigation selbst bleibt über funktionale Tests abgedeckt |
| 4 | **Layout-/Kontrast-UI-Tests als Render-/Unit-Tests** (2.1) | mittel | 3,5 bis 4,5 min | Gehostete View weicht von der echten Leiste ab; deshalb je ein nächtlicher UI-Fall |
| 5 | **Pakettests ohne Simulator** (macOS-Ziel) | mittel, Spike nötig | ohne Last ca. 0; unter Last 6 bis 12 min; auf CI ein Simulatorstart weniger | Plattformbedingter Code, String-Kataloge und `-testLanguage` unter macOS ungeprüft |
| 6 | **Ein Build, mehrere Testläufe** (`build-for-testing` einmal, danach `test-without-building`; Pakettests im selben Build-Graphen) | mittel | lokal warm gering; kalt und auf CI 4 überflüssige Builds von `TagwerkCore` und `swift-markdown` (Höhe ungeprüft) | XcodeGen-Unterstützung für Paket-Testziele im Scheme ungeprüft |
| 7 | **Simulator-Pool mit festen Plätzen, Herunterfahren nach dem Lauf, höchstens eine UI-Stufe gleichzeitig** | klein bis mittel | keine Laufzeit, aber RAM (drei dauerhaft gestartete Simulatoren entfallen) und Platte (12 GB Geräte, 5 GB DerivedData wachsen nicht mehr je Worktree) | Wartezeit, wenn alle Plätze belegt sind |
| 8 | **Ein Wiederholungsversuch für UI-Tests auf CI mit Bericht, Quarantäneliste** | klein | keine Laufzeit; verhindert, dass ein Lastausreißer den Merge blockiert | Wiederholungen können echte Wackler verdecken; deshalb Bericht und nächtlicher Lauf ohne Wiederholung |
| 9 | **Funktionale Tests zu weniger Starts zusammenlegen** (27 → ca. 15) | klein bis mittel | 1,5 bis 2,5 min | Fehler sind schlechter einzugrenzen; Zustand eines Schritts beeinflusst den nächsten |
| 10 | **Abgleich mit der Ausnahmenliste verbilligen** (Element einmal als Snapshot lesen; graue Sekundärtexte beheben, Task K5/#160) | klein (Technik) bzw. bereits geplant (Farbe) | 1 bis 2 min (unsicher) | gering |
| 11 | **Reine Doku-Änderungen überspringen die Tests auf CI** | klein | ganze Läufe; entlastet das Limit von 5 macOS-Jobs | Filter falsch gesetzt lässt Codeänderungen ungetestet; deshalb Positivliste der Doku-Pfade |
| 12 | **Sharding der UI-Stufe auf CI** | mittel | halbiert bis drittelt die UI-Testlaufzeit, aber jeder Shard baut neu (oder braucht einen Build-Job mit Artefakt) | 4 Jobs je PR gegen das Limit von 5; nach Option 2 bis 4 voraussichtlich unnötig |
| 13 | **DerivedData- oder Kompilat-Cache auf CI** | mittel bis hoch | Buildzeit je Job (Höhe unbekannt) | Verhalten mit Xcode 27 ungeprüft; Cache-Fehler sind schwer zu finden |
| 14 | **`-parallel-testing-enabled` für UI-Tests** | klein | bis ca. 40 % Laufzeit bei 2 Workern | Jeder Worker ist ein geklonter Simulator: lokal bei 16 GB und 3 Agenten und auf CI bei 7 GB nicht tragbar. **Nicht empfohlen.** Die Unit-Tests laufen mit Swift Testing schon parallel (2.300 Tests in 22 bis 89 s). |
| 15 | **Logik aus dem App-Target in Pakete verlagern** | hoch | langfristig: App-Unit-Tests ohne Simulator | großer Umbau mit `@testable`-Abhängigkeiten und SwiftData-Modellen; jetzt nicht |
| 16 | **Build-Einstellungen für Testbuilds** (`COMPILER_INDEX_STORE_ENABLE=NO`, `CODE_SIGNING_ALLOWED=NO` im Simulator) | klein | 5 bis 10 % Buildzeit (Schätzung aus allgemeiner Erfahrung, hier ungeprüft) | gering |

---

## 4. Entscheidungen (TS)

Jede Entscheidung nennt die Varianten und eine Empfehlung mit Begründung.

### TS1 – Wo ist die UI-Stufe Gate vor dem Merge?

- **TS1a** Lokal wie bisher (voller Lauf am Strangende und vor dem Merge), CI zusätzlich.
- **TS1b** CI ist das Gate. Lokal: je Commit die schnellen Stufen, dazu gezielt die UI-Klassen, die der Strang berührt (`TAGWERK_UI_ONLY`). Kein voller lokaler UI-Lauf mehr.
- **TS1c** CI ist Gate, lokal zusätzlich ein Smoke-Satz von 4 UI-Tests (ca. 2 min) vor dem Push.

**Empfehlung: TS1b.** Der volle lokale Lauf ist der Hauptgrund für drei gleichzeitig gestartete Simulatoren und damit für die Last, unter der die Tests überhaupt erst wackeln (1.4). TS1c lohnt erst, wenn sich zeigt, dass CI zu oft an Trivialem scheitert. **Bedingung:** Der erste CI-Lauf muss durchlaufen und in vertretbarer Zeit fertig sein (Task 1).

### TS2 – Welche Audit-Varianten laufen je PR?

- **TS2a** Alle, wie heute.
- **TS2b** Je PR: alle Audits in Standardgröße plus AX5/dunkel der 4 Kernscreens. Nächtlich und auf Abruf: AX5/dunkel der Rezept-, Einstellungs- und Abend-Screens.
- **TS2c** Je PR nur Standardgröße; jedes AX5/dunkel nächtlich.

**Empfehlung: TS2b.** Spart 454 s je PR-Lauf und behält die günstige Kernscreen-Prüfung (ca. 55 s). Die Annahme zum geringen Zusatzwert der Nebenscreens (2.2) ist nicht gemessen; der nächtliche Lauf liefert nach zwei Wochen die Daten, um TS2b zu bestätigen oder zurückzunehmen.

### TS3 – Wie erreichen Audits ihren Screen?

- **TS3a** Über die Oberfläche wie heute (Scrollschleifen).
- **TS3b** Direktsprung per Startargument `-TagwerkUITestScreen <name>` (nur im UI-Testmodus, wie die vorhandenen Argumente in `UITestMode.swift`), für Einstellungsseiten und andere statische Screens.
- **TS3c** Direktsprung über das vorhandene URL-Schema `tagwerk://`.

**Empfehlung: TS3b.** Es folgt dem Muster von `-TagwerkUITestNow` und bleibt vollständig außerhalb des Release-Codes (`#if DEBUG && targetEnvironment(simulator)`). TS3c würde Produktionsrouten für Testzwecke erweitern. Der Weg zu den Einstellungen bleibt durch einen funktionalen Test gedeckt (Task 4).

### TS4 – UI-Tests in Render-/Unit-Tests umwandeln?

- **TS4a** Nichts umwandeln.
- **TS4b** Die Klassen aus 2.1 umwandeln (`PlanHeaderLayoutUITests`, `TravelContrastUITests`, `PlanOverlapUITests`, ein Test von `NowMarkerUITests`, zwei Tastaturtests zusammenlegen); je ein UI-Fall für Kopfzeile und Überlappung bleibt im nächtlichen Lauf.
- **TS4c** Wie TS4b, zusätzlich die funktionalen Tests zu weniger Starts zusammenlegen (Option 9).

**Empfehlung: TS4b.** Die Kandidaten prüfen Geometrie und Farbe, wofür es mit `MarkerRenderContrastTests` ein funktionierendes Muster gibt. TS4c spart nur 1,5 bis 2,5 Minuten und verschlechtert die Fehlersuche; zurückstellen, bis die PR-Laufzeit auf CI bekannt ist.

### TS5 – Pakettests ohne Simulator?

- **TS5a** Wie heute im Simulator.
- **TS5b** Pakete zusätzlich für macOS deklarieren und mit Ziel `platform=macOS` testen; zuerst ein Spike an `TagwerkCore` und `GitHubKit` (reines Foundation), danach `AIKit`, `RemindersKit`, `HealthBridge` einzeln entscheiden.

**Empfehlung: TS5b, gestuft.** `TagwerkCore` und `GitHubKit` stellen 1.600 bis 1.700 der Pakettests und haben keine iOS-Abhängigkeit im Import. Pakete, die unter macOS nicht ohne Bedingungen bauen, bleiben im Simulator. **Ungeprüft:** Ressourcen (`.process("Resources")`, `defaultLocalization: "de"`) und die deutschen Erwartungswerte unter macOS.

### TS6 – Ein Build für alle Stufen?

- **TS6a** Getrennte `xcodebuild test`-Aufrufe wie heute.
- **TS6b** `build-for-testing` einmal je Scheme, danach `test-without-building`; die im Simulator verbleibenden Pakettests in das App-Scheme aufnehmen (ein Build-Graph, ein DerivedData).

**Empfehlung: TS6b, aber nach TS5b** und nur, wenn der Spike zeigt, dass XcodeGen Paket-Testziele im Scheme zulässt. Der Nutzen liegt fast ganz auf CI und bei kalten Worktrees.

### TS7 – Zuschnitt der UI-Stufe auf CI

- **TS7a** Ein UI-Job je PR (nach TS2b, TS3b, TS4b), kein Sharding.
- **TS7b** Drei Shards, jeder baut selbst.
- **TS7c** Ein Build-Job lädt die Testprodukte als Artefakt hoch, zwei Shards laden sie und testen ohne Build.

**Empfehlung: TS7a.** Nach TS2b bis TS4b bleibt eine UI-Testlaufzeit von etwa 13 bis 15 Minuten (lokaler Maßstab, Schätzung). Sharding lohnt nur, wenn die Testlaufzeit die Buildzeit deutlich übersteigt, und kostet Plätze im Limit von 5 macOS-Jobs. **Schwelle für eine Neubewertung:** UI-Job auf CI im Median über 30 Minuten; dann TS7c.

### TS8 – Umgang mit Flakiness

- **TS8a** Keine Wiederholung; jeder Fehlschlag blockiert.
- **TS8b** Auf CI im PR-Lauf ein Wiederholungsversuch je fehlgeschlagenem UI-Test (`-retry-tests-on-failure -test-iterations 2`), Liste der wiederholten Tests in der Job-Zusammenfassung; nächtlicher Lauf ohne Wiederholung; Quarantäneliste (Datei mit Testname und Issue) für Tests, die zweimal in einer Woche wackeln. Unit-Stufen nie mit Wiederholung.

**Empfehlung: TS8b.** Die Wiederholung verhindert, dass ein Ausreißer des geteilten Runners den Merge blockiert; der nächtliche Lauf ohne Wiederholung und die Zusammenfassung halten die Wackler sichtbar. Das widerspricht nicht der Regel aus dem Plan zu #250 („Wiederholungen sind letztes Mittel“), solange jede Wiederholung berichtet wird und Quarantäne ein Issue verlangt.

### TS9 – Simulatoren lokal

- **TS9a** Ein Simulator je Checkout, bleibt gestartet (heute).
- **TS9b** Pool aus 3 festen Simulatoren („Tagwerk Tests Slot 1–3“), Vergabe über eine Sperre, Herunterfahren am Ende des Laufs; UI-Stufen laufen maschinenweit einzeln (zweite Sperre). DerivedData bleibt je Checkout.
- **TS9c** Wie TS9a, aber Herunterfahren nach dem Lauf und ein Aufräumskript für verwaiste Simulatoren und DerivedData.

**Empfehlung: TS9b.** Feste Plätze begrenzen RAM und Platte unabhängig von der Zahl der Worktrees und passen zur bestehenden Regel von höchstens drei Implementierungsagenten. Mit TS1b sind lokale UI-Läufe selten, die Einzelsperre kostet also kaum Wartezeit. TS9c ist die kleinere Lösung, falls TS9b zu viel Umbau ist.

### TS10 – Nächtlicher Lauf

- **TS10a** Keiner.
- **TS10b** Täglich nachts auf `main`, nur wenn es seit dem letzten Lauf neue Commits gibt: alle Stufen, alle UI-Tests ohne Wiederholung; zusätzlich auf Abruf (`workflow_dispatch`) für jeden Branch.

**Empfehlung: TS10b.** Er ist die Voraussetzung für TS2b und TS4b und liefert die Flakiness-Daten für TS8b.

### TS11 – Reine Doku-Änderungen

- **TS11a** Jede Änderung löst alle Jobs aus.
- **TS11b** Ein vorgeschalteter Job prüft die geänderten Pfade; betreffen sie nur `docs/**`, `*.md` und `TODO.md`, melden die Testjobs Erfolg, ohne zu laufen.

**Empfehlung: TS11b.** Auf Arbeitsbranches wie `chore/fable-open-items` bestehen ganze Folgen von Commits nur aus Statusdokumenten und Plänen (dort die letzten fünf); jeder Push auf einen offenen PR würde sonst zwei macOS-Jobs belegen. Der Filter sitzt im Job, nicht in `on.paths`, damit ein später als Pflicht markierter Check nicht hängen bleibt.

### TS12 – Logik aus dem App-Target in Pakete

- **TS12a** Nichts ändern.
- **TS12b** Regel für neuen Code: Reine Logik (Texte, Rechnen, Sortieren, Parser) entsteht in `TagwerkCore`; keine Migration des Bestands.
- **TS12c** Gezielte Migration der größten Logikblöcke (`Planning`, 11.135 Zeilen).

**Empfehlung: TS12b.** Sie kostet nichts und verschiebt neue Tests in die Stufe ohne Simulator (nach TS5b). TS12c ist ein eigenes Projekt und erst sinnvoll, wenn die App-Stufe nach allen anderen Maßnahmen noch stört.

---

## 5. Empfohlenes Zielbild

### 5.1 Was wo läuft

| Anlass | Wo | Inhalt | Erwartete Dauer |
|---|---|---|---|
| Je Commit | lokal | Pakete (macOS), App-Scheme, String-Kataloge: `TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh` | 1,5 bis 3 min warm (heutiger Messwert; mit TS5b unter Last weniger vom Simulator abhängig) |
| Bei Arbeit an einem Screen | lokal | gezielt: `TAGWERK_UI_ONLY=<Klasse>[/<Test>] app/test-all.sh` | 1 bis 3 min |
| Je PR (Gate) | CI, 2 Jobs | `fast`: Pakete, App-Scheme, Kataloge. `ui`: PR-Satz der UI-Tests mit einem Wiederholungsversuch | `ui`: 13 bis 15 min Testlaufzeit im lokalen Maßstab (Schätzung), CI-Faktor unbekannt |
| Nächtlich auf `main` und auf Abruf | CI | alles, UI-Tests vollständig, ohne Wiederholung | ca. 25 min UI-Testlaufzeit im lokalen Maßstab (Schätzung) |
| Bei Änderungen an Audits, `UITestMode`, `DemoData`, App-Start | lokal, einzeln | `scripts/stress-audits.sh` (aus #261) | wie heute |

### 5.2 PR-Satz und nächtlicher Satz der UI-Tests

- **PR-Satz:** alle funktionalen Klassen (nach TS4b), `AccessibilityAuditUITests`, `AccessibilityAuditRecipesUITests`, `AccessibilityAuditEveningUITests`, `AccessibilityAuditLargeTextUITests`.
- **Nur nächtlich:** `AccessibilityAuditRecipesLargeTextUITests`, `AccessibilityAuditEveningLargeTextUITests`, die verbleibenden UI-Fälle für Kopfzeile, Überlappung und Reisekapsel.
- Die Zuordnung steht in einer Datei im Repository (`app/TagwerkUITests/nightly-only.txt`, eine Testkennung je Zeile), die `app/test-all.sh` in `-skip-testing:`-Argumente übersetzt. Lokal und auf CI gilt damit dieselbe Liste.

### 5.3 Rechnung zur Ersparnis (lokaler Maßstab, Schätzung)

| Schritt | UI-Testlaufzeit je PR |
|---|---|
| Heute (`main` + #261, 41 Tests) | ca. 30 min |
| nach TS2b (AX5/dunkel der Nebenscreens nächtlich) | ca. 22,5 min |
| nach TS3b (Direktsprung, betrifft im PR-Satz `testAuditSettings` in Standardgröße) | ca. 21 min |
| nach TS4b (Render-Tests, Tastaturtests zusammengelegt) | ca. 17 min |
| nach Option 10 (Ausnahmenliste), sofern sie trägt | ca. 15 bis 16 min |

Lokal entfällt die UI-Stufe im Regelfall ganz (TS1b). Die Zahlen beruhen auf einem einzigen vollständigen Lauf und den Stress-Wiederholungen; sie sind Größenordnungen, keine Zusagen.

### 5.4 Gate-Regel (ersetzt die bisherige)

1. Je Commit lokal: schnelle Stufen grün.
2. Vor dem Merge: CI-Jobs `fast` und `ui` grün. Ein UI-Test, der erst im zweiten Versuch besteht, zählt als grün und steht in der Zusammenfassung.
3. Ein roter nächtlicher Lauf blockiert keinen PR, erzeugt aber eine Aufgabe (Issue von Hand; keine automatische Anlage). Zwei Wackler desselben Tests in einer Woche: Quarantäne mit Issue, Behebung vor dem nächsten Release-Stand.
4. Fällt CI aus (GitHub-Störung, Warteschlange über 30 min), gilt ersatzweise der volle lokale Lauf.

---

## 6. Tasks für das empfohlene Zielbild

Reihenfolge nach Nutzen und Abhängigkeit. Jede Task ist ein eigener kleiner PR, sofern nicht anders vermerkt. Vor jeder Task prüfen, ob die zugehörige TS-Entscheidung wie empfohlen gefallen ist.

### Task 0: Voraussetzungen

- [ ] PR #261 ist „CONFLICTING“ gegen `main`. Zuerst #261 auf `main` bringen und mergen; alle folgenden Tasks setzen `waitUntilScreenIsStable`, `tagwerk_prepare_ui_simulator`, die Laufsperre und `scripts/stress-audits.sh` voraus.
- [ ] Ergebnis des ersten CI-Laufs von PR #267 (Run `44940990259`) festhalten: Dauer je Job, Dauer von Build und Test je Stufe (aus den Logs), Fehlschläge. Diese Zahlen in Abschnitt 1.5 dieses Plans nachtragen.

### Task 1: PR #267 auf das Zielbild bringen (TS1b, TS7a, TS8b, TS10b, TS11b)

Änderungen in `.github/workflows/tests.yml`, `app/test-all.sh`, `README.md` auf Branch `ci/github-full-tests`:

- [ ] **Kein Sharding.** Die Matrix bleibt bei `fast` und `ui`; der begonnene 3-Shard-Umbau wird nicht fortgesetzt.
- [ ] `app/test-all.sh`: neue Variable `TAGWERK_UI_TEST_SET` mit den Werten `pr` (Standard auf CI im PR-Lauf) und `full` (Standard lokal und nächtlich). Bei `pr` liest das Skript `app/TagwerkUITests/nightly-only.txt` und übergibt je Zeile `-skip-testing:TagwerkUITests/<Kennung>`. Leere Zeilen und Zeilen mit `#` überspringen. Fehlt die Datei, bricht die Stufe mit einer klaren Meldung ab.
- [ ] `app/test-all.sh`: neue Variable `TAGWERK_UI_ONLY` (durch Leerzeichen getrennte Kennungen), übersetzt in `-only-testing:TagwerkUITests/<Kennung>`; setzt implizit `TAGWERK_ONLY_UI_TESTS=1`.
- [ ] `app/test-all.sh`: neue Variable `TAGWERK_UI_TEST_RETRIES` (Standard leer). Ist sie `1`, erhält nur der Aufruf der UI-Stufe `-retry-tests-on-failure -test-iterations 2`. Nach der Stufe listet das Skript die Tests, die erst im zweiten Versuch bestanden haben (aus dem Log), unter der Überschrift `RETRIED UI TESTS`.
- [ ] Workflow: Auslöser `schedule` (täglich, nachts UTC) ergänzen. Der nächtliche Job prüft zuerst, ob `main` seit dem letzten erfolgreichen nächtlichen Lauf neue Commits hat, und endet sonst sofort erfolgreich. Nächtlich und bei `workflow_dispatch`: `TAGWERK_UI_TEST_SET=full`, ohne Wiederholung. PR-Lauf: `TAGWERK_UI_TEST_SET=pr`, `TAGWERK_UI_TEST_RETRIES=1`.
- [ ] Workflow: Job `changes` vor der Matrix. Er vergleicht die geänderten Pfade des PR mit der Positivliste `docs/**`, `**/*.md`, `TODO.md`. Trifft jede geänderte Datei die Liste, überspringen die Testschritte ihre Arbeit und der Job endet erfolgreich (Filter im Job, nicht in `on.paths`).
- [ ] Workflow: die Liste `RETRIED UI TESTS` in `$GITHUB_STEP_SUMMARY` schreiben.
- [ ] Workflow: Zeitlimits nach den Zahlen aus Task 0 setzen (Richtwert: doppelte gemessene Dauer, höchstens 60 min für `ui`).
- [ ] `app/TagwerkUITests/nightly-only.txt` anlegen mit `AccessibilityAuditRecipesLargeTextUITests` und, sobald #261 gemergt ist, `AccessibilityAuditEveningLargeTextUITests`.
- [ ] README-Abschnitt „Tests auf GitHub Actions“ an Satz, Wiederholung, nächtlichen Lauf und Doku-Filter anpassen; neue Variablen dokumentieren.
- [ ] `actionlint` läuft ohne Befund.
- [ ] Nachweis: ein PR-Lauf und ein von Hand ausgelöster voller Lauf sind grün; Dauern im PR-Text.

### Task 2: Gate-Regel und Doku umstellen (TS1b)

- [ ] README-Testabschnitt (`README.md:151-165`) und Kopfkommentar von `app/test-all.sh` auf die Regel aus 5.4 ändern.
- [ ] Die Hauptsitzung passt ihre Arbeitsregel an (Memory-Eintrag „UI tests per strand“): voller lokaler UI-Lauf nur noch als Ersatz bei CI-Ausfall.
- [ ] **Nutzerentscheidung, nicht Teil der Umsetzung:** `Tests (fast)` und `Tests (ui)` in den Branch-Schutz von `main` als Pflicht-Checks eintragen.

### Task 3: Direktsprung für Audit-Screens (TS3b)

- [ ] `app/Tagwerk/App/UITestMode.swift`: Argument `-TagwerkUITestScreen <name>` im vorhandenen `#if DEBUG && targetEnvironment(simulator)`-Block; außerhalb liefert der Zugriff `nil`. Zuerst ein Test in `UITestModeTests`, der die bekannten Namen und den Fall „unbekannter Name“ prüft.
- [ ] Namen für die fünf Einstellungsseiten aus `auditSettings` (`AccessibilityAuditRecipesUITests.swift:100-127`): `settings.languages`, `settings.ai.voice`, `settings.capture`, `settings.shopping`, `settings.siri`. Die App öffnet beim Start den Tab „Einstellungen“ mit dem passenden Navigationspfad. Zuerst lesen, wie `AppRouter` (siehe `AppRouterTests`) Ziele abbildet, und dessen Mechanik nutzen, statt eine zweite zu bauen.
- [ ] `auditSettings` in fünf Schritte umbauen, die je Seite `launchApp()` mit dem Argument aufrufen, oder – falls ein Start je Seite teurer ist als erwartet (ca. 10 s) – den Navigationspfad zur Laufzeit über einen versteckten Testknopf wechseln. Entscheidung nach Messung: Die Variante mit der kleineren Summe gewinnt.
- [ ] `openSettingsRow` bleibt für genau einen funktionalen Test erhalten, der eine Einstellungsseite über die Oberfläche öffnet (Standardgröße), damit der Weg weiter geprüft ist.
- [ ] Nachweis: `scripts/stress-audits.sh 3 AccessibilityAuditRecipesUITests/testAuditSettings AccessibilityAuditRecipesLargeTextUITests/testAuditSettings` grün; Dauer je Test vorher/nachher im PR-Text (Ausgangswerte: Median 142 s und 230 s).
- [ ] Die Befundmenge darf sich nicht ändern: `--collect` vor und nach dem Umbau vergleichen.

### Task 4: Layout- und Kontrastklassen als Render-/Unit-Tests (TS4b)

Je Klasse ein Commit; je Klasse zuerst den neuen Test schreiben und zeigen, dass er eine absichtlich eingebaute Regression findet (z. B. Reserve der Kopfzeile verkleinern), dann den UI-Test verschieben oder entfernen.

- [ ] `PlanHeaderLayoutUITests` → `PlanHeaderLayoutTests` in `app/TagwerkTests`: Kopfzeile in Deutsch und Englisch bei Standard, XXXL und AX1 hosten und den Abstand Titel zu Knöpfen messen. Zeigt sich, dass die gehostete View die Leiste nicht realistisch abbildet, bleibt der UI-Test und wandert nur in `nightly-only.txt`; das im PR-Text begründen.
- [ ] `TravelContrastUITests.testTightTripInLight/-Dark` entfernen, wenn `MarkerRenderContrastTests` die Kapsel „zu früh“ in Hell und Dunkel im Raster- und Listenkontext misst; sonst den Render-Test um den fehlenden Kontext ergänzen. `testAttachmentSitsAboveItsEventInTheGrid` in `nightly-only.txt`.
- [ ] `PlanOverlapUITests`: die Entscheidung „zusammenfassen oder nebeneinander“ als Unit-Test der Layoutfunktion; `testOverlappingEntriesCollapseAtLargeText` in `nightly-only.txt`, `testOverlappingEntriesStaySideBySideAtStandardSize` entfernen.
- [ ] `NowMarkerUITests.testRunningEntryShowsTheTimeLeftAndTheNowCapsule` entfernen, wenn `NowLineTextTests` Restzeit und Kapseltext abdeckt; sonst dort ergänzen.
- [ ] `TaskFlowUITests`: die zwei Tastaturtests zu einem Test zusammenlegen.
- [ ] Nachweis: Zahl und Dauer der UI-Tests vorher/nachher; neue Unit-Tests laufen in der App-Stufe.

### Task 5: Spike und Umstellung der Pakettests auf macOS (TS5b)

- [ ] Spike an `TagwerkCore`: `platforms` um macOS ergänzen (Version passend zu macOS 27), `xcodebuild test -scheme TagwerkCore -destination 'platform=macOS' -testLanguage de -testRegion DE`. Festhalten: baut es, laufen alle Tests, stimmen die deutschen Erwartungswerte, wie lange dauert es kalt und warm.
- [ ] Bei Erfolg dasselbe für `GitHubKit`; danach `AIKit`, `RemindersKit`, `HealthBridge` einzeln versuchen. Ein Paket, das Bedingungen im Quelltext bräuchte, bleibt im Simulator; keine `#if os(...)`-Zweige nur für Tests einführen.
- [ ] `app/test-all.sh`: je Paket das Ziel aus einer kleinen Tabelle im Skript wählen (macOS oder Simulator). Die App-Stufe baut die Pakete weiter für iOS, die iOS-Übersetzbarkeit bleibt also geprüft.
- [ ] Nachweis: Testzahlen je Paket identisch zu vorher; Stufendauer vorher/nachher bei gleichzeitig laufendem zweiten Testlauf.

### Task 6: Simulator-Pool (TS9b)

- [ ] `scripts/test-env.sh`: `tagwerk_test_destination` vergibt einen von drei Simulatoren „Tagwerk Tests Slot 1–3“ über eine Sperre im Stil von `tagwerk_acquire_run_lock` (#261); sind alle belegt, wartet der Aufruf mit Meldung (Obergrenze 30 min, dann Abbruch mit Exit-Code 2). `TAGWERK_TEST_SIMULATOR` hat weiter Vorrang.
- [ ] Zweite Sperre für die UI-Stufe: höchstens eine gleichzeitig auf der Maschine.
- [ ] Am Ende des Laufs (auch bei Fehler, `trap`) den Simulator herunterfahren, außer `TAGWERK_KEEP_SIMULATOR=1`.
- [ ] `scripts/clean-test-env.sh`: listet Simulatoren „Tagwerk Tests <Checkout>“ und DerivedData-Ordner ohne zugehörigen Worktree und löscht sie erst mit `--apply`. Keine Prozesse beenden.
- [ ] `scripts/tests/`: Test der Sperrlogik nach dem Muster der vorhandenen zsh-Tests.
- [ ] README anpassen (Abschnitt zu Simulator und DerivedData je Checkout).

### Task 7: Abgleich mit der Ausnahmenliste verbilligen (Option 10)

- [ ] Messen, wie viele Abfragen auf `matchesAllowlist` entfallen (Zähler im Collect-Modus).
- [ ] Label, Kennung und Typ eines Befunds aus einem einzigen Snapshot des Elements lesen statt aus drei Abfragen (`AuditAllowlist.swift:305`); nur übernehmen, wenn die Befundmenge im `--collect`-Vergleich gleich bleibt und die Laufzeit messbar sinkt.
- [ ] Mit Task K5 (#160, Farbwert `TextSecondary`) abstimmen: Fällt die Gruppe der grauen Sekundärtexte weg, die Messung wiederholen.

### Task 8: Ein Build für alle Stufen (TS6b) – nur nach Task 5

- [ ] Prüfen, ob XcodeGen Paket-Testziele im Scheme zulässt (Dokumentation der eingesetzten Version 2.46.0); wenn ja, die im Simulator verbliebenen Pakettests in das Scheme `Tagwerk` aufnehmen.
- [ ] `app/test-all.sh`: App- und UI-Stufe über `build-for-testing` und `test-without-building` (Muster in `scripts/stress-audits.sh` aus #261).
- [ ] Nachweis auf CI: Dauer des Jobs `fast` vorher/nachher.

### Zurückgestellt (keine Task)

- Sharding (TS7b/TS7c), Cache auf CI (Option 13), Zusammenlegen funktionaler Tests (TS4c), Migration von App-Logik (TS12c): erst nach zwei Wochen CI-Daten neu bewerten.
- `-parallel-testing-enabled` für UI-Tests: nicht vorgesehen (Option 14).

---

## 7. Grenzen dieser Analyse

**Gezeigt (aus Logs gemessen):** Stufendauern von 14 Läufen; Zeit je UI-Test aus einem vollständigen Lauf und 4 bis 6 Wiederholungen der Audit-Tests; Verteilung nach Tätigkeit aus den Schritt-Zeitstempeln; Zahl der Gesten in `testAuditSettings`; Simulator- und Speicherlage zum Zeitpunkt der Analyse; GitHub-Limits laut Dokumentation.

**Angenommen:** dass die Zeit je Geste und Abfrage auf CI im selben Verhältnis steht wie lokal; dass AX5/dunkel auf Nebenscreens selten eigene Befunde liefert; dass Last die Hauptursache der verbliebenen Fehlschläge ist.

**Ungeprüft:**

- Jede CI-Dauer (erster Lauf lief noch) und damit der Faktor zwischen lokalem Mac und Runner mit 3 Kernen und 7 GB.
- Der Lauf mit 36 Tests stammt vom Stand des PR #261, nicht von `main`; die 41-Test-Zahl ist hochgerechnet.
- Anteil der eigentlichen Auditzeit (nur aus Loglücken geschlossen) und Anteil des Ausnahmenlisten-Abgleichs an den Abfragen.
- macOS-Tauglichkeit der Pakete (Ressourcen, Lokalisierung, `AIKit` mit einem UIKit-Import, EventKit, HealthKit).
- XcodeGen-Unterstützung für Paket-Testziele im Scheme; Wirkung von `-retry-tests-on-failure` zusammen mit dem Zählen der Testsummen in `run_tests`.
- Ob gehostete Views die Navigationsleiste für den Kopfzeilentest realistisch genug abbilden.
- Ersparnis durch Build-Einstellungen und Caches unter Xcode 27.

**Praktische Folge:** Task 0 und Task 1 liefern die fehlenden CI-Zahlen. Erst danach steht fest, ob TS7a (kein Sharding) trägt.
