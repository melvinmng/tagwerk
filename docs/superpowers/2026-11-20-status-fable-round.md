# Stand der Fable-Runde vom 20.11.2026

Arbeitsstand für die offenen Punkte aus #173, #188, #232 und #233. Wird bei jedem Schritt aktualisiert.
Branch mit Plänen und Mockups: `chore/fable-open-items` (Worktree `t3-638057bd-99a71137283b18c0`).

## Regeln

- Rollen: Fable (Effort medium) plant und macht Mockups; Sonnet (Effort high) setzt um; die Hauptsitzung prüft jeden Branch, bevor ein PR entsteht.
- Recherche und Faktenprüfung innerhalb der Umsetzung (z. B. Verszählung) macht Sonnet, nicht Fable.
- Höchstens 3 Agents mit Xcode gleichzeitig (Umsetzung), dazu höchstens 3 für Planung/Prüfung.
- Kleine Punkte ohne eigenen Planungsschritt: Sonnet setzt direkt nach Mockup und Entscheidung um.
- Nach jeder Umsetzung Simulator und DerivedData des Agents löschen (`scripts/test-env.sh`).

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
| `feat/g1-plan-grid` | G1 Strang P auf Basis `fix/ui-test-stability` | läuft (Sonnet) |
| `fix/ui-test-stability` | vorbestehende UI-Testfehler | PR #240; fertig und geprüft, Head `e34c1fd`, `test-all` zweimal grün; zuerst mergen. Allowlist-Einträge „Unerledigt von heute“ und Leftover-Zeile bei Strang K (K5) neu bewerten |
| `feat/g3-github-status` | G3 Strang G (G1–G4) | PR #249 (Basis #240); fertig und geprüft, Head `f7eae41`, `test-all` grün; G5 offen (nach #173 A/B), dort auch GH9-Fußtext „erste Stufe“ vs. Startstufe „Ready“ und VoiceOver-Anführungszeichen im Englischen klären |
| `feat/g1-focus` | G1 Strang F (F1–F7) | PR #253; geprüft, Head `683677d`, `test-all` grün; F8 nach P. Achtung: Menütitel jetzt „Fokus starten · 25 min“ – beim Zusammenführen mit #246 (Strang U) UI-Tests auf den Titel prüfen |
| `fix/ui-audits-and-strings` | #250 nach Plan 2026-11-21 | läuft (Sonnet) |

## Neues Thema (21.11.): Ernährung, Gewicht, Ziele mit ChatGPT

Nutzerwunsch: Gewicht, Kalorien, Makros, Ballaststoffe vollständig tracken, Fortschritt verfolgen; Ernährungs- und Aktivitätsziele mit ChatGPT planen; verbrannte Kalorien (Health und eigene Trainings, die nach Health gehen) erhöhen das Tagesziel. Mockups `2026-11-21-ernaehrung-gewicht-ziele-mockups.html` und Planentwurf `2026-11-21-ernaehrung-gewicht-ziele.md` fertig (`2864e05`): 32 Entscheidungen (BU, NU, LM, KG, ZI, PV, OR), 7 Stränge/33 Tasks. Entscheidungen des Nutzers (21.11., wörtlich): BU1b, BU2a, BU3c, BU4b, NU1b, NU2b, NU3b, NU4b, NU5b (falls umsetzbar, sonst NU5a), LM1b & LM1d, LM2b, LM3b, LM4b, KG1c, KG2a, KG3a, KG4b, KG5a, ZI1b, ZI2b, ZI3b, ZI4b, ZI5b, ZI6b, PV1b, PV2a, PV3b, PV4b, OR1a, OR2b, OR3a, OR4b. Zu BU2a: Von der Uhr erfasste Trainings trägt der Nutzer nicht zusätzlich in Tagwerk ein. Warnschwellen ZI2b von Sonnet gegen Quellen prüfen lassen (läuft, mit Open Food Facts und HealthKit-Fakten).
Neuer Wunsch: „Anpassen“ bei ALLEN KI-Vorschlägen – manuell ändern und mit ChatGPT über einzelne oder alle Vorschläge weiterschreiben; Fable plant mit Mockups (`2026-11-21-ki-vorschlaege-anpassen-*`, läuft, zusammen mit der Finalisierung des Ernährungsplans).
Issues: #254 Ernährung, Gewicht und Ziele (Entscheidungen als Kommentar), #255 Anpassen bei allen KI-Vorschlägen. Umsetzung hier in dieser Runde (Sonnet), nachdem die bisherigen Punkte gemergt sind. Nutzerauflage: Die bisherigen Punkte trotzdem vollständig abschließen und mergen.

## Warteschlange Umsetzung (je freier Xcode-Platz, nach Prüfung des fertigen Branches)

**Gemergt am 21.11.:** #240–#249 und #251, #252 in der bestätigten Reihenfolge (`main` = `8326a3c`, identisch mit dem getesteten Gesamtstand, `test-all` grün). Zahlenprüfung in #241 gelockert (`c72b6dd`).

1. **Läuft (Sonnet):** #253 auf `main` bringen (Konflikte, `SearchUITests` auf neuen Menütitel), danach `feat/g3-github-status-g5`: G5, GH9-Fußtext vs. „Ready“, englische Anführungszeichen, L5-Assistentenzeile, „Project“-Reste aus #242 → „Projekt“
1a. #250: läuft; Plan fertig (`docs/superpowers/plans/2026-11-21-issue-250-audits-strings.md`, offene Fragen nach Empfehlung); Umsetzung durch Sonnet auf `fix/ui-audits-and-strings` ab `origin/main`, nächster freier Platz nach dem Integrationsauftrag
2. G1 Strang E (Basis `fix/ui-test-stability`)

3. #233 Block B (jetzt möglich)
4. Strang K (T, L, S gemergt – jetzt möglich); G2 Welle 1; G1 E, danach V/F8 nach P, R nach E
5. Gruppen 1 und 2 nach ihren Plänen
6. Danach: Geräteprüfungen – Nutzerwunsch: sobald die neue Version auf seinem iPhone ist, ALLE Gerätetests gesammelt als eine Liste ausgeben; (Task 12 in #173, Z1 in G3, Gerätetests der übrigen Pläne)

## Bekannte Probleme

- UI-Barrierefreiheits-Audits flackern unter Last, auch auf unverändertem Stand (Strang C und E beobachtet). Nach `fix/ui-test-stability` noch beobachtet: „Unerledigtes verschieben“ (Kontrast, Planen Tag), „Nicht jetzt“ (Rezept-Einwilligung, Dynamic Type), unbenannter AX5-Befund auf Einstellungen › KI › Sprache.
- `scripts/sync-strings.sh` formatiert die Kataloge um (~24.000 Zeilen); Agents fügen Einträge im vorhandenen Format ein.
