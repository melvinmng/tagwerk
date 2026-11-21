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
| `2026-11-20-g2-notizen-routinen.md` + `2026-11-20-g2-routinen-persoenliches.md` | fertig; 10 Stränge, 49 Tasks; Budget neu 44/17/1/2; DS4 nur bei „Ja“ aus DS0 |

Festlegungen der Hauptsitzung zum G3-Plan: offene Fragen nach Empfehlung; Zeilenwert „10 Kurzbefehle“; Blau in dunklen Blättern erst messen.

## Umsetzung (Branches)

| Branch | Inhalt | Stand |
|---|---|---|
| `feat/recipe-translate` | #232 Block A | fertig und geprüft, Head `d8856a7`, `test-all` grün; bereit für PR. Hinweis für #233: `NoteEditorSync` lässt Änderungen von außen über ungespeichertes Tippen gewinnen |
| `feat/closed-issues-in-reviews` | #173 Strang C (Tasks 6, 7, 7a) | fertig und geprüft, Head `e428cf4` (Review-Korrekturen drin); UI-Stufe rot nur durch vorbestehende Fehler; Folge-Idee: Projekte beim Kaltstart aus dem Cache laden |
| `feat/note-issue-suggestions` | #173 Strang D (Tasks 8, 9), abgezweigt von `33dfc26` | fertig und geprüft, Head `afc05d6`; nach Merge von A/B rebasen |
| `feat/g3-share-mail` | G3 Strang S | fertig und geprüft, Head `3908715`; UI-Stufe rot nur durch vorbestehende Fehler (Basis ohne `fix/ui-test-stability`) |
| `feat/g3-languages` | G3 Strang L mit SP5c auf Basis `fix/ui-test-stability` (ggf. L6–L9 auf `feat/g3-shopping-translate`) | läuft (Sonnet) |
| `feat/evening-reminders-per-day` | #173 Strang E (Tasks 10, 11) | fertig und geprüft, Head `c4c281a`, `test-all` grün; bereit für PR |
| `feat/assistant-assign-and-search` | #173 Stränge A, B und Task 5 | fertig und geprüft, Head `e032f71` (Review-Korrekturen drin: Einwilligung wird beobachtet, kein Chatwechsel während laufender Runde) |
| `feat/g3-search-menu` | G3 Strang U | fertig und geprüft, Head `9694508` |
| `feat/g3-keyboard-siri` | G3 Strang T | fertig und geprüft, Head `43b277c`, `test-all` grün; T4 (Siri am Gerät) offen; Allowlist-Einträge für K vorgemerkt; ein unbenannter AX5-Befund „Text clipped“ auf Einstellungen › KI › Sprache flackert |
| `feat/g1-plan-grid` | G1 Strang P auf Basis `fix/ui-test-stability` | läuft (Sonnet) |
| `fix/ui-test-stability` | vorbestehende UI-Testfehler | fertig und geprüft, Head `e34c1fd`, `test-all` zweimal grün; zuerst mergen. Allowlist-Einträge „Unerledigt von heute“ und Leftover-Zeile bei Strang K (K5) neu bewerten |
| `feat/g3-github-status` | G3 Strang G (G1–G4) | fertig und geprüft, Head `f7eae41`, `test-all` grün; G5 offen (nach #173 A/B), dort auch GH9-Fußtext „erste Stufe“ vs. Startstufe „Ready“ und VoiceOver-Anführungszeichen im Englischen klären |
| `feat/g1-focus` | G1 Strang F (F1–F7) auf Basis `fix/ui-test-stability` | läuft (Sonnet) |

## Warteschlange Umsetzung (je freier Xcode-Platz, nach Prüfung des fertigen Branches)

3. #233 Block B (nach Merge von #173 A/B)
4. G5 und L5-Anweisungszeile nach Merge von #173 A/B; Strang K nach T, L, S; Strang K zuletzt nach T, L, S
5. Gruppen 1 und 2 nach ihren Plänen
6. Danach: Geräteprüfungen (Task 12 in #173, Z1 in G3, Gerätetests der übrigen Pläne)

## Bekannte Probleme

- UI-Barrierefreiheits-Audits flackern unter Last, auch auf unverändertem Stand (Strang C und E beobachtet). Nach `fix/ui-test-stability` noch beobachtet: „Unerledigtes verschieben“ (Kontrast, Planen Tag), „Nicht jetzt“ (Rezept-Einwilligung, Dynamic Type), unbenannter AX5-Befund auf Einstellungen › KI › Sprache.
- `scripts/sync-strings.sh` formatiert die Kataloge um (~24.000 Zeilen); Agents fügen Einträge im vorhandenen Format ein.
