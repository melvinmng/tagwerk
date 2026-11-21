# Stand der Fable-Runde vom 20.11.2026

Arbeitsstand für die offenen Punkte aus #173, #188, #232 und #233. Wird bei jedem Schritt aktualisiert.
Branch mit Plänen und Mockups: `chore/fable-open-items` (Worktree `t3-638057bd-99a71137283b18c0`).

## Regeln

- Rollen: Fable (Effort medium) plant und macht Mockups; Sonnet (Effort high) setzt um; die Hauptsitzung prüft jeden Branch, bevor ein PR entsteht.
- Recherche und Faktenprüfung innerhalb der Umsetzung (z. B. Verszählung) macht Sonnet, nicht Fable.
- Höchstens 3 Agents mit Xcode gleichzeitig (Umsetzung), dazu höchstens 3 für Planung/Prüfung.
- Kleine Punkte ohne eigenen Planungsschritt: Sonnet setzt direkt nach Mockup und Entscheidung um.
- Nach jeder Umsetzung Simulator und DerivedData des Agents löschen (`scripts/test-env.sh`).
- Tests (ab 21.11.): vor jedem Task-Commit `TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`; voller Lauf mit UI-Tests einmal am Strangende und vor jedem Merge (mit aktuellem `main`).
- Beim Start jedes Jobs (auch Job 2 eines verketteten Auftrags) und vor dem letzten vollen Lauf: `git fetch origin && git merge origin/main` bzw. Branch von `origin/main` (Nutzer 21.11.).
- Keine künstliche Last (Endlosschleifen, zusätzliche Simulatoren) in Agent-Aufträgen.

## Offene Kleinigkeiten

- Wacklige `AIKit`-Tests auf CI: `LoopbackServerTests.stop_failsPendingWait` (Zeitüberschreitung statt Abbruch), `ChatGPTLoginTests.cancel_stopsServerAndFreesPort` (`portInUse`) – feste Wartezeiten/Port; ohne Zeitabhängigkeit und mit freiem Port umbauen (zu „Tests schlanker“).
- Regel: GitHub-Checks vor jedem Merge abwarten (Fehler bei #269: zu früh gemergt).

## Baustein „Vorbereitung“ für jeden Sonnet-Auftrag (in jeden Auftrag übernehmen)

- Start: `git fetch origin`; neuer Branch von `origin/main` bzw. `origin/main` in den vorhandenen Branch mergen (auch Job 2 eines verketteten Auftrags). Existiert der Branchname lokal mit fremden Commits: anderen Namen nehmen und melden, nichts zurücksetzen.
- Tests: vor jedem Commit `TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`; am Strangende `git fetch origin && git merge origin/main`, dann ein voller `app/test-all.sh`. Bekannte wacklige Audits: einmal wiederholen, jeden Fehler mit Laufnummer melden.
- Ab GitHub-Pflicht-Check (nach #261): `main` nur beim Start holen, kein Nachziehen vor dem Abschlusslauf; GitHub testet das Merge-Ergebnis; nachziehen nur bei Konflikt oder rotem CI (Nutzer 21.11.).
- Determinismus: Datums-Tests zeitzonenunabhängig (Formatierung mit `calendar.timeZone`); GitHub-CI läuft in UTC auf iPhone 18 Pro.
- Kataloge: kompaktes Format; `sync-strings.sh` erst nutzen, wenn #261 auf `main` ist (danach formattreu); `check-strings.py`; Englisch in `scripts/translations/en.json`; „Projekt“ statt „Project“.
- Rechner: keine künstliche Last, keine Prozesse beenden, nur ein Testlauf je Arbeitskopie, Simulator nach UI-Lauf herunterfahren; am Ende eigenen Simulator, DerivedData und Xcode-DerivedData mit Pfad in die Arbeitskopie löschen.
- Grenzen: nicht pushen, keine PRs/Issues/TODO.md/`t3gh`; Commits englisch, ohne KI-Hinweis, ohne Co-Authored-By.

## Entscheidungen (verbindlich, auf GitHub)

| Thema | Wo |
|---|---|
| 17 Entscheidungen aus PR #172 und Plan-Entscheidungen D1–D11, Wochenrückblick | Kommentare in #173 |
| #232 Rezept übersetzen (RT1a–RT5a, ganzer Text, Struktur bleibt, Anhänge mitkopieren) | Kommentar in #232 |
| #233 Notizen mit ChatGPT (NC1c–NC6a, Sitzungsregel, Sprachmodus einzeln) | Kommentar in #233 |
| Designgruppen 1–3, Notiz-Erweiterungen, Bible Study, SP5c, FO13a | Kommentare in #188 |
| Ein gemeinsamer Schalter „Notizen mit ChatGPT“ für Suche, Lesen, Ändern | #173 und #188 |
| Bible-Study-Leseplan zurückgestellt | #239 (Backlog) |
| DS7c: Sicherheitskopien verborgen in `.Sicherheitskopien` im Sicherungsordner, DS0 entfällt (21.11.) | G2-Plan Teil 2, DS4 |
| Zahlenprüfung beim Rezept-Übersetzen darf gelockert werden (21.11.) | Nachtrag auf `feat/recipe-translate` (#241) |
| Wacklige Audits und `sync-strings.sh` | #250 |

## Mockups (`docs/superpowers/mockups/`)

- `2026-11-20-notes-chatgpt-mockups.html` (#232, #233)
- `2026-11-20-decisions-173-mockups.html` (#173)
- `2026-11-20-g1-planen-fokus-erinnerungen-mockups.html` (Gruppe 1)
- `2026-11-20-g2-notizen-routinen-mockups.html`, `2026-11-20-g2-routinen-gewohnheiten-sicherung-mockups.html`, `2026-11-20-g2-notizen-erweiterungen-mockups.html` (Gruppe 2)
- `2026-11-20-g3-system-anbindungen-mockups.html` (Gruppe 3)
- `2026-11-20-g3-sp5c-shopping-translate-mockups.html` (SP5c)

## Pläne (`docs/superpowers/plans/`)

| Plan | Stand |
|---|---|
| `2026-11-20-decisions-173.md` | fertig, mit #233 abgeglichen (gemeinsame Bausteine in #173) |
| `2026-11-20-notes-chatgpt.md` | fertig; Block A = #232, Block B = #233 (baut auf #173 A/B auf) |
| `2026-11-20-g3-system-anbindungen.md` | fertig, Strang L mit SP5c (L6–L9); SPC-Entscheidungen in #188; Zusatz: nach Textänderung der Sortier-Einwilligung einmal neu fragen |
| `2026-11-20-g1-planen-fokus-erinnerungen.md` | fertig; offene Fragen 1–11 nach Empfehlung; Welle 1: P, F (F1–F7), E; Welle 2: V, F8, R |
| `2026-11-21-issue-250-audits-strings.md` | fertig; #250 Audits und `sync-strings.sh`; Fragen nach Empfehlung |
| `2026-11-20-g2-notizen-routinen.md` + `2026-11-20-g2-routinen-persoenliches.md` | fertig; 10 Stränge, 49 Tasks; Budget neu 44/17/1/2; DS4 nur bei „Ja“ aus DS0 |

Festlegungen der Hauptsitzung zum G3-Plan: offene Fragen nach Empfehlung; Zeilenwert „10 Kurzbefehle“; Blau in dunklen Blättern erst messen.

## Umsetzung (Branches)

| Branch | Inhalt | Stand |
|---|---|---|
| `feat/recipe-translate` | #232 Block A | PR #241; Head `d8856a7`; Nachtrag offen: Dezimaltrennzeichen-Prüfung lockern, `test-all` grün; bereit für PR. Hinweis für #233: `NoteEditorSync` lässt Änderungen von außen über ungespeichertes Tippen gewinnen |
| `feat/closed-issues-in-reviews` | #173 Strang C (Tasks 6, 7, 7a) | PR #243; fertig und geprüft, Head `e428cf4` (Review-Korrekturen drin); UI-Stufe rot nur durch vorbestehende Fehler; Folge-Idee: Projekte beim Kaltstart aus dem Cache laden |
| `feat/note-issue-suggestions` | #173 Strang D (Tasks 8, 9), abgezweigt von `33dfc26` | PR #244 (Basis #242); fertig und geprüft, Head `afc05d6`; nach Merge von A/B rebasen |
| `feat/g3-share-mail` | G3 Strang S | PR #247; fertig und geprüft, Head `3908715`; UI-Stufe rot nur durch vorbestehende Fehler (Basis ohne `fix/ui-test-stability`) |
| `feat/g3-languages` | G3 Strang L (L1–L5) | PR #251; geprüft, Head `37a2f8a`, `test-all` grün; L5-Assistentenzeile nach #242 offen |
| `feat/g3-shopping-translate` | SP5c (L6–L9), Basis `feat/g3-languages` | PR #252 (Basis #251); geprüft, Head `805d645`, `test-all` grün; Grenze: sind die ersten 100 Namen schon in Zielsprache, werden spätere nie angeboten |
| `feat/evening-reminders-per-day` | #173 Strang E (Tasks 10, 11) | PR #245; fertig und geprüft, Head `c4c281a`, `test-all` grün; bereit für PR |
| `feat/assistant-assign-and-search` | #173 Stränge A, B und Task 5 | PR #242; fertig und geprüft, Head `e032f71` (Review-Korrekturen drin: Einwilligung wird beobachtet, kein Chatwechsel während laufender Runde) |
| `feat/g3-search-menu` | G3 Strang U | PR #246; fertig und geprüft, Head `9694508` |
| `feat/g3-keyboard-siri` | G3 Strang T | PR #248 (Basis #240); fertig und geprüft, Head `43b277c`, `test-all` grün; T4 (Siri am Gerät) offen; Allowlist-Einträge für K vorgemerkt; ein unbenannter AX5-Befund „Text clipped“ auf Einstellungen › KI › Sprache flackert |
| `feat/g1-plan-grid` | G1 Strang P (P1–P8) | **gemergt (#256, `main` = `811bcda`)**; `PlanHeaderLayoutUITests` 265 s → 85 s; geprüft, Head `69cbd2b`, `test-all` grün; vor Merge `main` einarbeiten (nur Katalog-Konflikt) und `PlanHeaderLayoutUITests` kürzen (265 s je UI-Stufe; AX5 und Sonntag streichen); offene Designfrage: kurze Blöcke bei AX5 abgeschnitten |
| `feat/notes-assistant` | #233 Block B (B3–B9) | PR #258; geprüft, Head `3c00fa1` (main `85c982b` + VoiceOver-Fix), wird mit #262 auf `811bcda` verkettet; 10 Gerätetests offen. Hinweis für G2 NL1a (Notizen sperren): gesperrte Notizen müssen über `NoteToolAccess` ausgeschlossen werden |
| `feat/g1-reminders` | G1 Strang E (E1–E6) | PR #262; geprüft, Head `1456d14`, `test-all` je Task grün |
| `feat/ai-proposal-editing-strand-a` | #255 Strang A (A1–A4), auf #262 | PR #265 (Basis #262); geprüft, Head `067cf17`, voll grün; #258 `2c95998` und #262 `1046293` auf `811bcda` voll grün. Läuft: Kette auf `099f2e8` bringen, ein voller Lauf, dann Merge #258 → #262 → #265 |
| `feat/ai-proposal-editing-cards` | #255 Strang B (B1–B5) | läuft (Sonnet, nach Job 1) |
| `fix/ui-test-stability` | vorbestehende UI-Testfehler | PR #240; fertig und geprüft, Head `e34c1fd`, `test-all` zweimal grün; zuerst mergen. Allowlist-Einträge „Unerledigt von heute“ und Leftover-Zeile bei Strang K (K5) neu bewerten |
| `feat/g3-github-status` | G3 Strang G (G1–G4) | PR #249 (Basis #240); fertig und geprüft, Head `f7eae41`, `test-all` grün; G5 offen (nach #173 A/B), dort auch GH9-Fußtext „erste Stufe“ vs. Startstufe „Ready“ und VoiceOver-Anführungszeichen im Englischen klären |
| `feat/g1-focus` | G1 Strang F (F1–F7) | **gemergt (#253)**; geprüft, Head `683677d`, `test-all` grün; F8 nach P. Achtung: Menütitel jetzt „Fokus starten · 25 min“ – beim Zusammenführen mit #246 (Strang U) UI-Tests auf den Titel prüfen |
| `fix/ui-audits-and-strings` | #250 nach Plan 2026-11-21 | PR #261; geprüft, Head `4f73e1f`, `test-all` grün; `sync-strings.sh` formattreu (1 Zeile je Schlüssel); Allowlist −2/+4/~4; läuft: `main` einarbeiten (Konflikte Allowlist, Rezept-Audit) |
| `feat/g3-contrast` | G3 Strang K (K1–K5), auf #261 | läuft (Sonnet, nach Job 1) |
| `feat/g1-travel-time`, `feat/g1-focus-in-plan` | G1 Strang V (V1–V5) und F8 | **gemergt (#263, #264, `main` = `099f2e8`)**; PL10b gebaut (Kapsel 9,6/10,2:1) |
| `fix/day-capacity` | #260 Kapazität | **gemergt (#268, `main` = `bafd1c3`)**, voll grün; Beispieltag „8 h frei von 8 h“; offen: `TimeGrid.freeGaps` (Raster) kennt Fahrzeit/KA1c nicht; `RecurringEffortStore.reservedMinutes` tot |
| `feat/week-all-events` | #259 Wochenansicht mit allen Terminen | läuft (Sonnet) |

## Neues Thema (21.11.): Ernährung, Gewicht, Ziele mit ChatGPT

Nutzerwunsch: Gewicht, Kalorien, Makros, Ballaststoffe vollständig tracken, Fortschritt verfolgen; Ernährungs- und Aktivitätsziele mit ChatGPT planen; verbrannte Kalorien (Health und eigene Trainings, die nach Health gehen) erhöhen das Tagesziel. Mockups `2026-11-21-ernaehrung-gewicht-ziele-mockups.html` und Planentwurf `2026-11-21-ernaehrung-gewicht-ziele.md` fertig (`2864e05`): 32 Entscheidungen (BU, NU, LM, KG, ZI, PV, OR), 7 Stränge/33 Tasks. Entscheidungen des Nutzers (21.11., wörtlich): BU1b, BU2a, BU3c, BU4b, NU1b, NU2b, NU3b, NU4b, NU5b (falls umsetzbar, sonst NU5a), LM1b & LM1d, LM2b, LM3b, LM4b, KG1c, KG2a, KG3a, KG4b, KG5a, ZI1b, ZI2b, ZI3b, ZI4b, ZI5b, ZI6b, PV1b, PV2a, PV3b, PV4b, OR1a, OR2b, OR3a, OR4b. Zu BU2a: Von der Uhr erfasste Trainings trägt der Nutzer nicht zusätzlich in Tagwerk ein. Warnschwellen ZI2b von Sonnet gegen Quellen prüfen lassen (läuft, mit Open Food Facts und HealthKit-Fakten).
Neuer Wunsch: „Anpassen“ bei ALLEN KI-Vorschlägen – manuell ändern und mit ChatGPT über einzelne oder alle Vorschläge weiterschreiben; Plan und Mockups `2026-11-21-ki-vorschlaege-anpassen-*` fertig (`aafeea3`): 14 Orte, AN1–AN14, 18 Tasks; AN1a–AN14a nach Empfehlung entschieden (Kommentar #255). G6 des Ernährungsplans hängt an A1/A2 dieses Plans.
Faktenprüfung: `docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md` mit Festlegungen (u. a. BU1b Voreinstellung 50 %, OFF-Kontaktadresse in der App abfragen); in den Plan übernommen (`e0c3da5`). Ernährungsplan final (35 Tasks, NU5b umsetzbar, im Standard aus).
Issues: #254 Ernährung, Gewicht und Ziele (Entscheidungen als Kommentar), #255 Anpassen bei allen KI-Vorschlägen. Umsetzung hier in dieser Runde (Sonnet), nachdem die bisherigen Punkte gemergt sind. Nutzerauflage: Die bisherigen Punkte trotzdem vollständig abschließen und mergen.

## Warteschlange Umsetzung (je freier Xcode-Platz, nach Prüfung des fertigen Branches)

**Gemergt am 21.11.:** #240–#249 und #251, #252 in der bestätigten Reihenfolge (`main` = `8326a3c`, identisch mit dem getesteten Gesamtstand, `test-all` grün). Zahlenprüfung in #241 gelockert (`c72b6dd`).

1. **Gemergt:** #257 (G5, GH9-Fußtext, VoiceOver-Anführungszeichen, L5-Zeile, „Projekt“ auch in Swift-Texten geprüft), `main` = `85c982b`. **Läuft (Sonnet):** #253 stabilisieren (Fokus-Leisten-Test ohne Zeitannahme, Hänger „Wait for app to idle“ prüfen) bis grün, dann #256 mit #253 zusammenführen und `PlanHeaderLayoutUITests` kürzen. Merge-Reihenfolge: #253, dann #256. Neuer Audit-Befund für #250: Kontrast „Vorgelesen wird mit den Stimmen …“ (KI › Sprache). Veraltete Katalogschlüssel mit „Project“ (10 + 2, stale) bei Gelegenheit entfernen.
1a. #250: läuft; Plan fertig (`docs/superpowers/plans/2026-11-21-issue-250-audits-strings.md`, offene Fragen nach Empfehlung); Umsetzung durch Sonnet auf `fix/ui-audits-and-strings` ab `origin/main`, nächster freier Platz nach dem Integrationsauftrag
2. G1 Strang E (Basis `fix/ui-test-stability`)

2d. **CI bei GitHub** (Nutzer 21.11.): volle Läufe inkl. UI-Tests auf GitHub-Runnern bei jedem PR/Push; lokal nur schnelle Tests. Sonnet prüft Xcode 27.2 auf den Runnern und schreibt `.github/workflows/tests.yml` Workflow fertig (Runner `xcode-27`, Xcode 27.2 vorinstalliert); PR #267 ist der Probelauf (Aufteilen der UI-Tests durch Sonnet abgebrochen: Nutzer will, dass Fable zuerst alle Möglichkeiten für schlankere Tests prüft → `2026-11-21-tests-schlanker.md` fertig (`1225192`), alle TS-Empfehlungen entschieden (vollständig umsetzen; Rückfall auf den Mac, falls GitHub zu langsam); Task 1+2 (Workflow, ohne Xcode) läuft bei Sonnet, Tasks 3–8 nach Merge von #261; erster CI-Lauf von #267 gemessen: UI-Job 54 min (34 min Kaltbau, Tests 20,5 min – schneller als lokal), schneller Job 37 min (fast nur Bauen); Fehler: 3 Datums-Tests wegen TZ=UTC, 4 bekannte Audit-Flakes (#261 fehlt). Zweiter Lauf: schneller Job grün in 17 min (TZ-Fix wirkt, noch kalt gebaut), UI-Job 44 min mit 3 bekannten Flakes (Planen halb gescrollt, „Vorgelesen wird …“, App-Start) – #261/K. **#267 gemergt (`88e33fe`)**; voller Lauf auf `main` (44950862592) füllt den Build-Cache. **#269 gemergt (`b6f66a9`)**: nach jedem Merge auf `main` ein Build-only-Lauf, der den Cache auffrischt (erster Lauf 44951855605). Gate erst nach Merge von #261; ohne spürbaren Cache-Effekt zurück auf den Mac.); erst dann Strangende-Vollläufe der Agents streichen.
2c. **Automatische Installation** (Nutzer 21.11.): `refresh-install.sh` installierte nur bei bald ablaufendem Profil; jetzt stündlich bei neuem `main` (Lastschutz, fehlerhaften Commit nicht stündlich wiederholen). **Gemergt (#266, `main` = `1d6364a`)**, Klon `~/Library/Developer/Tagwerk/src` aktualisiert; Lastbremse 3 × Kerne. Letzte Installation auf dem iPhone: 20.11. 18:29 (install-dev).
2b. **#260 Kapazität falsch** (Überschneidungen doppelt, freie Termine; Beispiel 24.11. „3 h 10 frei von 3 h 10“): Plan + Mockup fertig (`a091125`): Kernrechnung vereinigt korrekt; 3 h 10 vermutlich durch reservierten Aufwand wiederkehrender Aufgaben oder kürzere Arbeitszeit am Dienstag (Task 0 klärt); Fehler F1–F4 (Karte erklärt Abzug nicht, Puffer in der Pause, Zeitblöcke summiert, „Frei gibt frei“ summiert). KA6a; Ursache bestätigt (wiederkehrende „Karteikarten“ 4 h reserviert); KA3: Abzug nur durch gebuchte Zeitblöcke; KA1c, KA2a, KA4a, KA5a – vollständig entschieden, bereit für Sonnet (nächster freier Platz, `main` hat #256); Start nach Merge von #256
2a. **#259 Wochenansicht (läuft) mit allen Terminen** (Nutzerwunsch 21.11., in dieser Runde): kleiner Punkt ohne Fable – Gestaltung vom Nutzer vorgegeben (wie bisher bzw. wie die Listenansicht eines Tages). Nutzer: erst nach der von Fable geplanten Neugestaltung von Planen, damit es sich am finalen Design orientiert → Start nach Merge von G1 P (#256) **und** G1 V (Fahrzeit am Termin, Zeile „Losfahren“); Termine in der Woche zeigen dann dieselbe Zeilenform inkl. Fahrzeit-Hinweis wie die Tagesliste
3. #233 Block B (PR #258)
4. Strang K (läuft auf Basis #261); G2 Welle 1; G1 E, danach V/F8 nach P, R nach E
5. Gruppen 1 und 2 nach ihren Plänen
6. Danach: Geräteprüfungen – Nutzerwunsch: sobald die neue Version auf seinem iPhone ist, ALLE Gerätetests gesammelt als eine Liste ausgeben; (Task 12 in #173, Z1 in G3, Gerätetests der übrigen Pläne)

## Bekannte Probleme

- UI-Barrierefreiheits-Audits flackern unter Last, auch auf unverändertem Stand (Strang C und E beobachtet). Nach `fix/ui-test-stability` noch beobachtet: „Unerledigtes verschieben“ (Kontrast, Planen Tag), „Nicht jetzt“ (Rezept-Einwilligung, Dynamic Type), unbenannter AX5-Befund auf Einstellungen › KI › Sprache.
- `scripts/sync-strings.sh` formatiert die Kataloge um (~24.000 Zeilen); Agents fügen Einträge im vorhandenen Format ein.
