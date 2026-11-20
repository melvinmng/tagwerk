# Designgruppe 3 „System und Anbindungen“ (#188, #173 Punkt 9) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Stand 20.11.2026, nach den Entscheidungen des Nutzers (Kommentar „Entscheidungen zur Designgruppe 3“ in #188). Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Code-Stand der Befunde: `90a07d1`. Die Kontrastwerte der Mockups sind gerechnet, nicht gemessen; Strang K misst zuerst.

**Goal:** Die entschiedenen Varianten der Gruppe 3 umsetzen: Tastaturknopf als Symbol und „Abschließen“ (TA), eigene Seite „Siri & Kurzbefehle“ mit Tipp-Karten am Ort der Handlung (SI), Status in der Aufgabenzeile, Wortlaut „Projekt“, Kapseln für Issues ohne Projekt und für „in einem Projekt erledigt“ (GH), Teilen-Erweiterung mit Kacheln und Mail-Karte (TE), eigene Seite „Sprachen“ mit getrennter Diktat-, Antwort-, Rezept- und Einkaufssprache samt Wechsel am Feld (SP), benannte Schrifttöne und Akzentfarbe statt Kontrast-Ausnahmen (KO), mittleres Kontextmenü auf Suchtreffern (SU).

**Architecture:** Sechs Stränge auf eigenen Branches. Jeder Strang legt seine Regeln als reine Funktionen in `TagwerkCore` oder `GitHubKit` ab und hält die Views dünn. Neue gespeicherte Werte sind zusätzliche Attribute von `AppSettings` mit Standardwert (leichte SwiftData-Migration, Schema-Regel der Datei). Der bisherige Wert `voiceRecognitionLanguage` bleibt die Diktat-Sprache; die Antwortsprache des Sprachchats wird einmalig aus ihm abgeleitet. Der Rezeptimport liefert bei abweichender Einkaufssprache je Zutat einen zweiten Namen und eine zweite Einheit. Kontrast wird über Farb-Assets und `ShapeStyle`-Erweiterungen gelöst; der Audit im Sammelmodus entscheidet, welche Ausnahmen entfallen.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, XCUITest (`performAccessibilityAudit`), App Intents, String Catalogs (Deutsch als Quellsprache, Englisch).

**Grundlagen:** Issue #188 samt Kommentaren; Mockups `docs/superpowers/mockups/2026-11-20-g3-system-anbindungen-mockups.html` (gewählte Varianten und Abschnitt „Technische Randbedingungen aus dem Quelltext“); Pläne `2026-11-19-keyboard-dismissal.md`, `-siri-shortcuts-fix.md`, `-github-status-and-no-project.md`, `-p6-share-mail.md`, `-g3-uitests-a11y.md`, `-search.md`; `2026-11-20-decisions-173.md`, `2026-11-20-notes-chatgpt.md`.

**Nicht in diesem Plan:**
- SP5c (vorhandene Einkaufsartikel mit ChatGPT übersetzen): eigenes Folge-Issue, legt die Hauptsitzung an.
- TE2c (Knopf „Tagwerk öffnen“), TE4 (Rezept-Wahl in der Erweiterung): abgelehnt.
- Weitere Sprachen als Deutsch und Englisch.
- Schrift auf Liquid Glass, vom System abgeblendete Knöpfe: bleiben Ausnahmen (Mockup „Was voraussichtlich in der Liste bleibt“).
- Alles aus `2026-11-20-decisions-173.md` und `2026-11-20-notes-chatgpt.md` (Abschnitt „Abgrenzung“).

## Entscheidungen (aus #188, 20.11.2026)

| Bereich | Entschieden | Folge für die Umsetzung |
|---|---|---|
| Tastatur | TA1a, TA2a, TA3 ja | Knopf über der Tastatur wird Symbol; einzeilige Felder schließen mit Return-Taste „Fertig“; Blattknopf in Tagesstart und Tagesabschluss heißt „Abschließen“. Keine Leiste in allen Formularen. |
| Siri | SI1b, SI2b, SI3 ja, SI4a | Eigene Seite auf oberster Ebene, `ShortcutsLink` oben, Sätze in vier Gruppen, keine `SiriTipView` auf der Seite; Tipp-Karte an zwei Orten; Satzliste wie heute mit drei Korrekturen, zwei davon erst nach Gerätetest. Alle zehn Plätze bleiben belegt. |
| GitHub | GH1a, GH2a, GH3a, GH4c, GH5c, GH6b, GH7b, GH8, GH9 | GH1a/GH2a/GH3a sind der Ist-Zustand (nur Wortlaut). Neu: Status in der Unterzeile, Kapseltexte, Kapsel beim Verschwinden, Fußtext ohne gemeinsame Stufe, „Projekt/Projekte“ in allen deutschen UI-Texten. |
| Teilen, Mail | TE1b, TE2b, TE3b, TE4 nein | Kacheln statt Menü, Knopf unten, Bestätigung nennt Ziel; Mail als Karte, Vorschläge getönt. |
| Sprachen | SP1b, SP2b, SP3b, SP4b, SP5b | Seite „Sprachen“; Einkaufsliste mit eigener Einstellung, Vorgabe „Wie Rezepte“; große Marke beim Diktieren; Wechsel je Ort gemerkt; Marke im Eingabefeld der Einkaufsliste. |
| Kontrast | KO1a, KO2a, KO3a, KO4a | Sekundärtext 78 % im Hellen, Schrifttöne je Farbe, Uhrzeit im Raster 85 %, `AccentColor` #005FCC im Hellen. Eigener Block: messen, ersetzen, Ausnahmen streichen. |
| Suche | SU1b, SU2 ja, SU3 ja | Aufgaben-Treffer: Öffnen, Zeigen, Einplanen (Heute, Morgen, Anderer Tag), Fokus starten, Auf GitHub öffnen, Erledigt. Termin-Treffer unverändert. Notiz-Treffer: „Im Ordner zeigen“. |

## Global Constraints

- **Texte:** Deutsch im Quelltext, Englisch im Katalog. **Jeder Task trägt seine neuen und geänderten Zeichenketten selbst ein** (`scripts/sync-strings.sh`, dann Englisch in `scripts/translations/en.json` und `scripts/apply-translations.py`), sonst wird `app/test-all.sh` in der Stufe „string catalogs“ rot. Ändert ein Task einen deutschen Text, entfällt der alte Schlüssel in `en.json`.
- **GH6b:** In deutschen UI-Texten steht „Projekt/Projekte“, englisch „Project/Projects“. Wo der Zusammenhang fehlt (Suche): „GitHub-Projekt“. Code-Bezeichner und die englischen Werkzeugbeschreibungen des Assistenten bleiben unverändert. Das gilt auch für neue Texte der anderen Stränge.
- **App Shortcuts:** höchstens zehn (`AppShortcutsTests.providerStaysWithinTheSystemLimitOfTenShortcuts`). Kein neuer Kurzbefehl. `TagwerkIntents.swift`, `AppShortcuts.xcstrings` und die Satzliste der Einstellungen stimmen überein (`scripts/check-strings.py`).
- **Teilen-Erweiterung:** kein Netz, kein Schlüsselbund, kein Zugriff auf den Datenbestand; Bilder nur als Vorschaubild (`ShareModel.swift:7–8, 113–119`). Prüfbare Logik liegt in `TagwerkCore`, weil die Erweiterung kein Test-Target hat.
- **Datenschutz:** An ChatGPT geht durch diesen Plan nichts Neues außer dem Feld „Sprache der Einkaufsliste“ im Rezeptimport (ein Sprachname). Mail-Adressen und der Link zur Mail gehen weiterhin nie hinaus (`MailTaskModel.swift:179–186`).
- **SwiftData:** Neue Attribute von `AppSettings` haben einen Standardwert oder sind optional. Neue Felder in `BackupDTOs.swift` sind optional, damit ältere Sicherungen lesbar bleiben.
- **Farben:** Nach Strang K steht im App-Target keine neue `.foregroundStyle(.secondary)` und keine Systemfarbe als Schriftfarbe mehr; die anderen Stränge nutzen bis dahin die heutigen Farben und werden von Strang K mit ersetzt.
- Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch. Commits im Stil `feat: …`/`fix: …`, ohne Hinweis auf KI, ohne Co-Authored-By. Branches ohne Präfix `claude/`.
- Neue Parameter haben Standardwerte; bestehende Aufrufer und Tests bleiben gültig.
- Höchstens fünf Umsetzer gleichzeitig; Simulatoren nach dem Lauf löschen.

**Testbefehle** (wie in `2026-11-20-decisions-173.md`):

- `PKG <Paket> <Suite>` = `cd app/Packages/<Paket> && xcodebuild test -testLanguage de -testRegion DE -scheme <Paket> -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:<Paket>Tests/<Suite>`
- `APP <Suite>` = `cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>`
- `UI <Klasse>` = wie `APP`, mit `-scheme TagwerkUITests -only-testing:TagwerkUITests/<Klasse>`
- `ALL` = `app/test-all.sh`, erwartet `ALL TESTS PASSED`.

## Abgrenzung zu laufenden Arbeiten

| Laufende Arbeit | Dateien dort | Berührung hier | Regel |
|---|---|---|---|
| `2026-11-20-decisions-173.md`, Stränge A und B | `AppTools*.swift`, `ActionCardDescriber.swift`, `AssistantModel.swift`, `ChatView.swift`, `AppEnvironment.swift` (`makeSearchModel`), `AppSettings.swift`, `BackupDTOs.swift`, `AISettingsView.swift` | G5 (Wortlaut in drei KI-Dateien), L5 (eine Zeile der Systemanweisung), L1 (neue Einstellungsfelder) | G5 und der Anweisungsteil von L5 beginnen erst, wenn die Stränge A und B von #173 auf `main` sind. Neue Felder in `AppSettings`/`BackupDTOs` werden am Ende des jeweiligen Blocks angefügt; Konflikte sind reine Nachbarzeilen. |
| `2026-11-20-decisions-173.md`, Suchwerkzeug | `AppTools+Search.swift`, `SearchResults.swift` | Strang U ändert nur `Search/SearchSheet.swift`, `Tasks/TaskContextMenu.swift`, `App/RootView.swift` | Kein Werkzeugcode in Strang U. |
| `2026-11-20-notes-chatgpt.md`, Block A (#232) | `RecipeTranslationPlan` (TagwerkCore), `RecipeTranslator`, `RecipeConsentView`, `AIPrivacyView`, `NoteEditorView` | L4 ändert `RecipeImporter.swift`, `RecipeSheets.swift`; beide lesen `RecipeLanguage` | Block A nutzt `RecipeLanguage.resolve(setting:)` und `promptName`; L1 lässt beide Signaturen unverändert und ergänzt nur. L4 fasst `RecipeConsentView` und `AIPrivacyView` nicht an (der Einwilligungstext nennt die Sprache nicht). Eine übersetzte Rezept-Notiz wird weiter lokal gelesen; L4 ändert daran nichts (Test `translatedNote_stillOffersIngredientsForShopping` aus Block A muss grün bleiben). |
| Notiz-Sperre (NO10c, NO12) | Notizordner mit Face ID | U2 springt in einen Notizordner | Der Sprung geht über `tasksPath` in die normale Ordneransicht; eine Sperre greift dort wie bei jedem anderen Öffnen. |

## Review Focus

1. **Übernahme der Sprache:** Nach dem Update verhält sich die App ohne Zutun wie vorher: Diktat in der bisherigen Sprache, Antwort im Sprechmodus wie bisher (fest oder „wie gesprochen“), Einkaufsliste folgt den Rezepten. Die Ableitung läuft genau einmal; ein späteres Ändern von „Diktat“ verstellt die Antwortsprache nicht. → L1 (`migration_fixedLanguage_keepsAnswerLanguage`, `migration_runsOnce`).
2. **Zweiter Name je Zutat:** Die Rezept-Notiz enthält immer die Namen in der Rezeptsprache, die Einkaufsliste die Namen in der Einkaufssprache; Dubletten-Erkennung (`alreadyOnList`) und Kategorie-Zuordnung laufen über den Namen, der auf die Liste geht. Bei gleichen Sprachen ändert sich an Anfrage und Ergebnis nichts. → L4.
3. **Kein Netz ohne Einwilligung:** Der lokale Leseweg einer strukturierten Rezept-Notiz sendet auch bei abweichender Einkaufssprache nichts. → L4 (`noteInput_differentShoppingLanguage_neverCallsTheResponder`).
4. **Kapsel beim Verschwinden (GH7b):** Ein Issue, das im gewählten Projekt „Done“ wird und in einem nicht gewählten offen bleibt, verlässt die Liste sofort (nicht erst beim nächsten Laden) und zeigt die Kapsel; ein Issue, das überall „Done“ ist, wird wie bisher geschlossen und zeigt „Rückgängig“. → G3.
5. **Status in der Zeile (GH4c):** kein Status bei Startstufe, davor liegenden Stufen und „Done“; „2 Status“ bei verschiedenen Ständen; VoiceOver nennt ihn. → G2.
6. **Wortlaut:** Kein deutscher Quelltext-String enthält „Project“ oder „Projects“ als Wort. → G1 (Prüfung in `check-strings.py`).
7. **Satzlisten stimmen überein:** Jeder auf der Seite „Siri & Kurzbefehle“ gezeigte Satz, auch die Zeile „auch: …“, ist ein registrierter Satz. → T2.
8. **Suchmenü ohne Unwiderrufliches:** kein Löschen, kein Status, keine Fälligkeit; „Erledigt“ fehlt offline. → U1 (`searchTaskMenu_neverOffersDeleteOrStatus`).
9. **Kontrast:** Jede gestrichene Ausnahme ist durch einen Audit-Lauf belegt, jede verbleibende hat einen aktuellen Grund; keine Pauschalausnahme. Flächen, Balken und Symbole behalten ihre Farbe. → K1, K5.
10. **Mail zu Aufgabe:** Absender und Link stehen weiter in der Notiz der angelegten Aufgabe, auch wenn sie im Blatt eine eigene Zeile sind; ein Vorschlag überschreibt nie ein geändertes Feld. → S3.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Tagwerk/Common/KeyboardDismissal.swift:171–186` | `KeyboardDoneButton`: `Button("Fertig")` in `ToolbarItemGroup(placement: .keyboard)`; 20 Aufrufer von `.keyboardDoneButton()`. |
| `Routines/EveningSheet.swift:148`, `MorningSheet.swift:45` | Blattknopf „Fertig“ markiert die Routine als erledigt. UI-Tests tippen `"Fertig"` (`AccessibilityAuditUITests.swift:27`, `RoutineUITests.swift:15`); `AuditAllowlist.swift:81` nennt „Fertig“ für den Tagesabschluss. |
| `.submitLabel` | Nur an fünf Feldern gesetzt (`TravelSettingsView:27`, `ShoppingInputBar:113`, `ValueStepper:120`, Suche, Senden). Alle anderen einzeiligen Felder zeigen „return“. |
| `Settings/CaptureSettingsView.swift:8, 70–91, 120–124` | Abschnitt „Siri & Kurzbefehle“ mit `SiriTipView` (`@State showsWaterTip = true`), zehn `phrase(…)`-Zeilen, `ShortcutsLink` am Ende. |
| `scripts/check-strings.py:99, 128–135` | Liest die gezeigten Sätze per Regex `phrase("…",` aus `CaptureSettingsView.swift`. |
| `Intents/TagwerkIntents.swift:281–320` | Zehn `AppShortcut`; „Fokus“ hat einen Satz mit Parameter (`\(\.$action) in …`). |
| `Settings/SettingsView.swift:62–98` | Zeilen KI, Erfassen, Routinen, Notizen, Datensicherung, Fokus-Timer. |
| `Tasks/TaskRow.swift:29–44`, `TaskRowText` | Unterzeile: Wiederholung, Fälligkeit, Farbpunkt, Containername. Kein Status. `SearchTaskRow` nutzt `TaskRow` (`SearchRows.swift:87`). |
| `GitHubKit/GitHubMapping.swift:60–75` | `reopenOption(in:)`: „Ready“, sonst erste Stufe, die nicht „Done“ ist. |
| `GitHubKit/GitHubTaskProvider.swift:127–137, 296–300, 413–425` | `apply` gibt `taskItem(fresh)` mit **allen** Platzierungen zurück; `isListed` prüft nur „in einem Projekt“ und „mir zugewiesen“; die Projektauswahl greift erst in `displayed()` beim Laden. Folge: Nach „Done“ im gewählten Projekt bleibt das Issue bis zum nächsten Laden in der Liste und verschwindet dann ohne Hinweis. |
| `Tasks/TaskListModel.swift:234–246, 404–413, 490–505` | `setStatus` ruft `settle(…, announce: false)`; `handOver` baut `HandedOverNotice(item:)`. |
| `Tasks/HandedOverNotice.swift:24–30`, `AssigneeSelection.swift:73–95` | Grund nur aus `item.statuses.isEmpty`; Titel „#151 angelegt · ohne Project“, Überzeile „Angelegt“. |
| `Tasks/NewTaskSheet.swift:119–123, 280–285` | Zeile „Status“ nur bei gemeinsamen Stufen; Fußtext „Ohne Project erscheint das Issue nicht in deinen Aufgaben.“ |
| „Project“ in deutschen Texten | `GitHubSettingsSection.swift:16, 20`, `AssigneeSelection.swift:85`, `TaskListView.swift:79`, `NewTaskSheet.swift:284`, `ProjectSelection.swift:9, 53`, `SetupModel.swift:25`, `SearchSheet.swift:361`, `SearchTexts.swift:132, 155`, `TaskEditorView.swift:102, 514`, `GitHubTaskProvider.swift:228, 398`; in KI-Dateien `ActionCardDescriber.swift:129, 135`, `AppTools+GitHub.swift:20–21`, `AppTools.swift:353`. `TaskChat.swift:151` („Projects:“) ist Kontext für das Modell und bleibt. |
| `TagwerkShare/ShareView.swift:23, 34, 46–66`, `ShareModel.swift:12–18, 96–99` | `Form` mit `Picker("Ablegen als")`, Titel- und Textfeld; Knopf „In Tagwerk sichern“ in der Leiste; `.saved` ohne Ziel, schließt nach 1,2 s. |
| `TagwerkCore/Share/SharePayload.swift:105–132` | `suggestedTarget`, `availableTargets` (bis zu fünf Ziele bei Text). |
| `Share/MailTaskSheet.swift:56–66, 99–104, 133–145`, `MailTaskModel.swift:88, 160–186` | Vorschau ohne Mailtext; Knopf „Vorschlag“ je Zeile; `composeNotes()` schreibt Zusammenfassung, „Von: …“ und den Link in ein Feld; `prefill.notes = notes`. |
| `Persistence/AppSettings.swift:160–163` | `voiceRecognitionLanguage` ("auto", "de-DE", "en-US") und `recipeLanguage`. Kein Wert für Antwortsprache oder Einkaufssprache. |
| Leser von `voiceRecognitionLanguage` | Erkennung: `MealSheet:125`, `ShoppingInputBar:117`, `SuggestionViews:553`, `NoteField:190`, `NotesListView:365`, `VoiceComposer:9`, `ChatView:70`, `AppEnvironment:234`; Antwort: `AppEnvironment:223` (`VoiceChatLanguage.fixed`); Vorlese-Rückfall: `VoiceComposer:222`; Stimmenwahl: `VoiceSettingsView:107`. |
| `Voice/VoiceSettingsView.swift:66–87` | Abschnitte „Sprachchat“ und „Rezepte“ unter KI › Sprache. |
| `Voice/VoiceComposer.swift:112–128`, `TagwerkCore/Voice/DictationMachine.swift:222–238` | Marke `shortName` (≈ 28 × 18 pt), nur während der Aufnahme; `switchLanguage` startet neu und behält den Text; `setLanguage` nur im Ruhezustand. |
| `Shopping/RecipeImporter.swift:50–77, 109–153, 254–294, 311–326, 374–433` | Ein Ergebnis in einer Sprache; `Candidate.name`, `quantity`, `line`; `apply` legt `ParsedItem(name:quantity:)` an und merkt die Kategorie unter `candidate.id`. Strukturierte Notizen werden lokal gelesen. |
| `Shopping/RecipeSheets.swift:458, 534, 557–570, 664–676` | Liest mit `resolvedRecipeLanguage`; skaliert Mengen mit `result.language.locale`; legt Artikel und optional die Rezept-Notiz an. |
| `AI/AssistantModel.swift:397–398`, `AppTools+Definitions.swift:67` | Anweisung und Werkzeug `update_shopping` nennen keine Sprache für neue Artikel. |
| `TagwerkUITests/AuditAllowlist.swift:40–74, 114–142, 197–236` | Vier Gruppen Kontrast-Ausnahmen plus drei für die Rezept-Seiten; der Sammelmodus (`AUDIT_COLLECT_FILE`) schreibt nur Befunde, die **nicht** auf der Liste stehen. Welche Listeneinträge noch treffen, lässt sich heute nicht ablesen. |
| `AccessibilityAuditRecipesUITests.swift:77–95` | `auditSettings` öffnet „KI“ › „Sprache“ und „Erfassen“; die Allowlist nennt deren Texte („Sprachchat“, „Sprache für Rezepte“, Fußtexte). |
| Farben | 291 Stellen `.foregroundStyle(.secondary)` (App, Widget, Erweiterung), 76 Stellen mit Rot, Orange, Grün, Lila oder Blau als Vordergrund, 86 Stellen mit `tint`/`accentColor`; `Assets.xcassets` enthält nur das App-Symbol; `project.yml` setzt keine Akzentfarbe. Tönung im Raster: `TimelineCanvas.swift:208` (24 %). |
| `Search/SearchSheet.swift:392–402, 425–430, 447–457` | Aufgaben-Treffer: Öffnen, Zeigen, Erledigt. Notiz-Treffer: nur Öffnen. |
| `Tasks/TaskContextMenu.swift:49–59, 164–171`, `TaskListView.swift:199–203, 425–441` | Abschnitt „Einplanen · nur in Tagwerk“ und `planButton`; „Anderer Tag …“ öffnet `RescheduleDateSheet` und ruft `planning.assign`. |
| `App/AppEnvironment.swift:481–485`, `RootView.swift:168–174` | Notizordner öffnen über `tasksPath = [.notes, .notesFolder(.folder(id))]`; `showTask` wechselt den Tab und markiert. Eine Markierung einzelner Notizen gibt es nicht. |

## Stränge, Branches und Dateien

| Strang | Branch | Tasks | Dateien (ändern; **neu** fett) |
|---|---|---|---|
| **T** Tastatur und Siri | `feat/g3-keyboard-siri` | T1–T4 | `Common/KeyboardDismissal.swift`, `App/RootView.swift` (eine Zeile), `TagwerkShare/ShareView.swift` (eine Zeile, siehe S2), `Routines/EveningSheet.swift`, `MorningSheet.swift`, `Planning/DayView.swift` (Kommentar), **`Settings/SiriShortcutsSettingsView.swift`**, **`Intents/SiriPhraseCatalog.swift`**, `Settings/CaptureSettingsView.swift`, `Settings/SettingsView.swift`, `Shopping/ShoppingListView.swift`, `Capture/CaptureView.swift`, `Intents/TagwerkIntents.swift`, `Intents/IntentServices.swift`, `AppShortcuts.xcstrings`, `Persistence/AppSettings.swift`, `scripts/check-strings.py`, UI-Tests (`AccessibilityAuditUITests`, `AccessibilityAuditRecipesUITests`, `RoutineUITests`, `AuditAllowlist`) |
| **G** GitHub | `feat/g3-github-status` | G1–G5 | `GitHubKit/GitHubMapping.swift`, `GitHubTaskProvider.swift`, `TagwerkCore/TaskProvider`-Protokoll, `Tasks/TaskRow.swift`, `HandedOverNotice.swift`, `AssigneeSelection.swift`, `TaskListModel.swift`, `UndoCapsule.swift`, `NewTaskSheet.swift`, `ProjectSelection.swift`, `TaskListView.swift`, `Editor/TaskEditorView.swift`, `Settings/GitHubSettingsSection.swift`, `Setup/SetupModel.swift`, `Search/SearchTexts.swift`, `Search/SearchSheet.swift:361`, `scripts/check-strings.py`; G5: `AI/ActionCardDescriber.swift`, `AppTools+GitHub.swift`, `AppTools.swift` |
| **S** Teilen und Mail | `feat/g3-share-mail` | S1–S3 | **`TagwerkCore/Share/ShareSheetText.swift`**, `TagwerkShare/ShareModel.swift`, `ShareView.swift`, `ShareViewController.swift`, `TagwerkShare/Localizable.xcstrings`, `Share/MailTaskModel.swift`, `MailTaskSheet.swift` |
| **L** Sprachen | `feat/g3-languages` | L1–L5 | **`TagwerkCore/Voice/ContentLanguages.swift`**, `TagwerkCore/Voice/VoiceChatLanguage.swift`, `VoiceLanguage.swift`, `RecipeLanguage.swift` (nur Ergänzung), `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, `App/AppEnvironment.swift`, **`Settings/LanguageSettingsView.swift`**, `Voice/VoiceSettingsView.swift`, `Settings/AISettingsView.swift`, `Settings/SettingsView.swift`, `Voice/VoiceComposer.swift`, `VoiceInputModel.swift`, die acht Aufrufer der Erkennungssprache, `Shopping/RecipeImporter.swift`, `RecipeSheets.swift`, `RecipeNoteWriter.swift`, `ShoppingInputBar.swift`, `AI/AssistantModel.swift:397` (L5), UI-Tests (`AccessibilityAuditRecipesUITests`, `AuditAllowlist`) |
| **U** Suche | `feat/g3-search-menu` | U1–U2 | `Search/SearchSheet.swift`, **`Search/SearchTaskMenu.swift`**, `Tasks/TaskContextMenu.swift`, `App/RootView.swift`, `App/AppEnvironment.swift` (eine Funktion) |
| **K** Kontrast | `feat/g3-contrast` | K1–K5 | `TagwerkUITests/AuditAllowlist.swift`, **`Design/Colors.xcassets`**, `project.yml`, **`Common/TextTones.swift`**, breit: alle Views mit Schriftfarben, `Planning/TimelineCanvas.swift`, **`scripts/check-colors.py`**, `test-all.sh` |

**Gemeinsam berührte Dateien:**

| Datei | Stränge | Art |
|---|---|---|
| `Settings/SettingsView.swift` | T (Zeile „Siri & Kurzbefehle“), L (Zeile „Sprachen“) | je eine neue Zeile im selben Abschnitt; zweiter Merge löst von Hand |
| `Persistence/AppSettings.swift` | T (zwei Schalter), L (drei Felder), #173 | Anfügen am Blockende |
| `TagwerkUITests/AuditAllowlist.swift`, `AccessibilityAuditRecipesUITests.swift` | T, L (Seiten ziehen um), K (Einträge streichen) | **K beginnt erst, wenn T und L auf `main` sind** |
| `App/RootView.swift` | T (eine Zeile `.submitLabel`), U (Rückruf für den Notizordner) | verschiedene Stellen |
| `Search/SearchSheet.swift` | G (eine Textzeile, 361), U (Menüs) | verschiedene Stellen |
| `scripts/check-strings.py` | T (Pfad der Satzliste), G (Wortprüfung) | verschiedene Funktionen |
| `TagwerkShare/ShareView.swift` | S (Umbau), T (`.submitLabel` an der Wurzel) | T überlässt die Zeile S; S2 setzt sie |
| `App/AppEnvironment.swift` | L (Übernahme, Sprachleser), U (Sprung in den Notizordner), #173 | verschiedene Stellen |
| Alle Views mit Farben | K gegen alle anderen | K rebased zuletzt und ersetzt neue Stellen der anderen Stränge mit |

## Reihenfolge und Abhängigkeiten

```
T Tastatur+Siri:  T1 ─► T2 ─► T3 ─► T4 (Gerätetest, bedingte Satzänderung)
G GitHub:         G1 ─► G2 ─► G3 ─► G4 ───────────────► G5 (nach #173 A und B)
S Teilen+Mail:    S1 ─► S2        S3 (unabhängig von S1/S2)
L Sprachen:       L1 ─► L2 ─► L3 ─► L4 ─► L5 (Anweisungszeile nach #173 A und B)
U Suche:          U1 ─► U2
K Kontrast:       K1 (misst auf main nach T, L, S) ─► K2 ─► K3 ─► K4 ─► K5
Abschluss:        Z1 (Geräteprüfung aller Stränge)
```

- **Parallel:** T, G, S, L und U laufen gleichzeitig (fünf Umsetzer). K ist der sechste Strang und startet danach; K1 kann als reine Messung schon vorher auf `main` laufen, die verbindliche Ausgangsmessung entsteht aber erst nach dem Merge von T, L und S.
- **Merge-Reihenfolge:** U und S zuerst (kleinste Überschneidung), dann G, T, L; K zuletzt. Jeder Strang ist ein Pull Request; G5 und die Anweisungszeile aus L5 sind Nachzügler-Commits auf eigenen kleinen Branches.
- Innerhalb eines Strangs bauen die Tasks aufeinander auf, außer S3 (eigenständig).

---

## Strang T: Tastatur und Siri

### Task T1: Tastaturknopf als Symbol, Return-Taste „Fertig“, Blattknopf „Abschließen“ (TA1a, TA2a, TA3)

**Files:**
- Modify: `app/Tagwerk/Common/KeyboardDismissal.swift:9–10, 137–143, 171–196`, `app/Tagwerk/Common/AccessibilityID.swift`, `app/Tagwerk/App/RootView.swift` (Wurzel), `app/Tagwerk/Routines/EveningSheet.swift:5, 148`, `MorningSheet.swift:5, 45`, `app/Tagwerk/Planning/DayView.swift:291` (Kommentar), `Localizable.xcstrings`, `scripts/translations/en.json`
- Test: `app/TagwerkUITests/TaskFlowUITests.swift`, `RoutineUITests.swift:15`, `AccessibilityAuditUITests.swift:27`, `AuditAllowlist.swift:81`

**Interfaces:**

```swift
// KeyboardDismissal.swift
private struct KeyboardDoneButton: ViewModifier {
    // Button { focus.wrappedValue = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
    //     .accessibilityLabel("Tastatur ausblenden")          // EN: "Hide Keyboard"
    //     .accessibilityIdentifier(AccessibilityID.Common.hideKeyboard)   // new enum `Common` in AccessibilityID.swift
}
// Multi-line fields keep "return": the key inserts a line there and must not read "Fertig".
private struct OwnFocusDoneButton: ViewModifier { /* adds .submitLabel(.return) */ }
```

Regel für TA1a: Die Wurzel der App (`RootView`) setzt `.submitLabel(.done)`; der Wert vererbt sich über die Umgebung an alle Felder, auch in Blättern. Felder mit eigener Angabe (`.search`, `.send`) behalten sie. `.keyboardDoneButton()` setzt für sein Feld `.submitLabel(.return)`, weil die Return-Taste dort eine Zeile einfügt. `ValueStepper` und `EstimateField` (`keyboardDoneButton(focus:)`) bleiben unverändert.

- [ ] **Step 1: Tests.**
  - `TaskFlowUITests.testKeyboardButtonHidesKeyboard`: „Neue Aufgabe“ öffnen, ins Feld „Notiz“ tippen, Knopf „Tastatur ausblenden“ tippen, die Tastatur ist weg, das Blatt bleibt offen; es gibt keinen zweiten Knopf „Fertig“ über der Tastatur.
  - `RoutineUITests`: `tapButton("Abschließen")` statt `"Fertig"`; ebenso `AccessibilityAuditUITests.swift:27`.
- [ ] **Step 2:** `UI TaskFlowUITests`, `UI RoutineUITests` → rot.
- [ ] **Step 3: Umsetzen.** Symbol und Label wie oben; Kommentare in Zeile 10 und 137 anpassen. `EveningSheet`/`MorningSheet`: `Button("Abschließen")`, Doc-Kommentare in Zeile 5 nachziehen. `AuditAllowlist.swift:81`: „Fertig“ durch „Abschließen“ ersetzen (der Eintrag gilt dem Dynamic-Type-Befund desselben Knopfs). Englisch: „Complete“, „Hide Keyboard“.
- [ ] **Step 4: Prüfung der Vererbung im Simulator** (Software-Tastatur einblenden): In „Neue Aufgabe“ (Titel), im Blatt „Gewohnheit“ und in den Einstellungen (Heimatadresse) heißt die Return-Taste „Fertig“; im Feld „Notiz“ heißt sie „return“. **Rückfall, falls der Wert ein Blatt nicht erreicht:** `.submitLabel(.done)` zusätzlich an der Wurzel jedes betroffenen Blatts setzen (`NewTaskSheet`, `TaskEditorView`, `HabitSheet`, `EventEditSheet`, `ShoppingItemSheet`, `RecipeSheets`, `MailTaskSheet`, `ShareNoteSheet`, `ShareShoppingSheet`), nicht je Feld.
- [ ] **Step 5:** `ALL`. Commit `feat: show the keyboard button as a symbol and name the routine sheets' button "Abschließen"`.

### Task T2: Seite „Siri & Kurzbefehle“ (SI1b, SI2b)

**Files:**
- Create: `app/Tagwerk/Intents/SiriPhraseCatalog.swift`, `app/Tagwerk/Settings/SiriShortcutsSettingsView.swift`
- Modify: `app/Tagwerk/Settings/CaptureSettingsView.swift:1, 8, 70–91, 120–124` (Abschnitt, `showsWaterTip`, `phrase`, `import AppIntents` entfernen), `Settings/SettingsView.swift:~98` (Zeile nach „Fokus-Timer“), `scripts/check-strings.py:8, 99, 128–135`
- Test: neu `app/TagwerkTests/SiriPhraseCatalogTests.swift`, `AccessibilityAuditRecipesUITests.swift:77–95`, `AuditAllowlist.swift:32–36, 114–127`

**Interfaces (Produces):**

```swift
/// The phrases shown under Einstellungen › Siri & Kurzbefehle, grouped by area. One entry per App Shortcut.
struct SiriPhrase: Identifiable {
    let id: String                              // short title of the shortcut, unique
    let phrase: LocalizedStringResource         // first phrase, with "Tagwerk" written out
    let alternative: LocalizedStringResource?   // "Fokus beenden in Tagwerk"
    let effect: LocalizedStringResource         // "250 ml, im Hintergrund"
    let opensApp: Bool                          // mark "öffnet Tagwerk"
}
enum SiriPhraseCatalog {
    struct Group: Identifiable { let id: String; let title: LocalizedStringResource; let phrases: [SiriPhrase] }
    static let groups: [Group]                  // Erfassen · Einkauf · Tag und Fokus · Notizen und Gewohnheiten
    static var shortcutCount: Int { groups.reduce(0) { $0 + $1.phrases.count } }
}
```

Inhalt (Mockup SI2b; „öffnet Tagwerk“ folgt `supportedModes == .foreground` des Intents):

| Gruppe | Satz | Wirkung | öffnet Tagwerk |
|---|---|---|---|
| Erfassen | „Wasser in Tagwerk erfassen“ | 250 ml, im Hintergrund | nein |
| | „Mahlzeit in Tagwerk erfassen“ | Blatt „Essen“ | ja |
| | „Training in Tagwerk erfassen“ | Blatt „Training“ | ja |
| Einkauf | „Füge Milch zur Einkaufsliste in Tagwerk hinzu“ | Artikel im Satz, im Hintergrund | nein |
| | „Auf die Einkaufsliste in Tagwerk“ | Siri fragt nach den Artikeln | nein |
| | „Einkaufsliste in Tagwerk zeigen“ | Einkaufsliste | ja |
| Tag und Fokus | „Was steht heute in Tagwerk an?“ | Termine, Blöcke, Deadlines; nur entsperrt | nein |
| | „Fokus starten in Tagwerk“ · auch: „Fokus beenden in Tagwerk“ | Freier Fokus-Timer, im Hintergrund | nein |
| Notizen und Gewohnheiten | „Notiz in Tagwerk diktieren“ | Brain Dump mit laufendem Diktat | ja |
| | „Gewohnheit in Tagwerk abhaken“ | Hakt eine Gewohnheit für heute ab | nein |

Seite: erste Zeile `ShortcutsLink()` mit Fußtext „Alle Sätze stehen dort bereit, auch für Aktionstaste und Home-Bildschirm.“; darunter die vier Gruppen; am Ende der bisherige Hilfetext („Erkennt Siri einen Satz nicht, …“). Keine `SiriTipView`. Zeile in den Einstellungen: `LabeledContent("Siri & Kurzbefehle", value: "\(SiriPhraseCatalog.shortcutCount) Sätze")`.

- [ ] **Step 1: Tests.**
  - `SiriPhraseCatalogTests`: `catalog_listsEveryShortcutOnce` (zehn Einträge, IDs gleich den `shortTitle` aus `TagwerkShortcuts.appShortcuts`), `catalog_marksForegroundIntents` (genau vier Einträge mit `opensApp`), `catalog_focusNamesBothActions`.
  - `check-strings.py`: Quelle der gezeigten Sätze ist `SiriPhraseCatalog.swift`; die Regex liest `phrase:` **und** `alternative:`. Für die Skripte gibt es kein Test-Target; Gegenprobe von Hand: einen Satz in `alternative` vorübergehend verfälschen, `python3 scripts/check-strings.py` muss ihn melden, dann zurücknehmen.
  - `AccessibilityAuditRecipesUITests.auditSettings`: zusätzlich `openSettingsRow("Siri & Kurzbefehle")`, Audit unter dem Namen „Einstellungen › Siri & Kurzbefehle“; der Name kommt in `AuditAllowlist.recipeScreens`.
- [ ] **Step 2:** `APP SiriPhraseCatalogTests` → rot.
- [ ] **Step 3: Umsetzen** wie oben. In `CaptureSettingsView` entfällt der Abschnitt vollständig.
- [ ] **Step 4:** `ALL` (Stufe „string catalogs“ prüft die Satzliste). Neue Audit-Befunde der Seite zuerst beheben; Ausnahmen nur mit Grund und nur, wenn sie zur bestehenden Gruppe „Sekundärtext“ gehören (Strang K räumt sie ab).
- [ ] **Step 5:** Commit `feat: move the Siri phrases to their own settings page, grouped by area`.

### Task T3: Tipp-Karte am Ort der Handlung (SI3)

**Files:**
- Modify: `app/Tagwerk/Persistence/AppSettings.swift` (zwei Felder), `app/Tagwerk/Shopping/ShoppingListView.swift`, `app/Tagwerk/Capture/CaptureView.swift:~171` (über den Trinkportionen), `app/Tagwerk/Intents/IntentServices.swift` (Nutzung merken)
- Create: `app/Tagwerk/Intents/SiriTipPolicy.swift`
- Test: neu `app/TagwerkTests/SiriTipPolicyTests.swift`, `IntentServicesTests.swift`

**Interfaces (Produces):**

```swift
// AppSettings
/// The Siri tip above the shopping list / the drink buttons was closed or its shortcut was used once (SI3).
var siriTipShoppingDone: Bool = false
var siriTipWaterDone: Bool = false

enum SiriTipPolicy {
    /// Shown until the user closes the card or runs the shortcut once; never in UI test mode.
    static func isVisible(done: Bool, isUITest: Bool) -> Bool
}
```

Die Karte ist `SiriTipView(intent: AddShoppingArticleIntent(), isVisible:)` bzw. `LogWaterIntent()`; das Binding schreibt beim Schließen `…Done = true`. `IntentServices` setzt das jeweilige Feld, wenn der Kurzbefehl einmal lief. Die Felder werden nicht gesichert (Hinweiszustand des Geräts); kein Eintrag in `BackupDTOs`.

- [ ] **Step 1: Tests:** `policy_hidesAfterDismissal`, `policy_hidesInUITests`; `IntentServicesTests.logWater_marksTheTipAsDone`, `addArticle_marksTheTipAsDone`.
- [ ] **Step 2:** `APP SiriTipPolicyTests`, `APP IntentServicesTests` → rot.
- [ ] **Step 3: Umsetzen.** Einkaufsliste: Karte als erste Zeile der Liste mit `listRowInsets(EdgeInsets())` und klarem Hintergrund (rendert die Karte leer, weil die Kurzbefehle nicht registriert sind, bleibt keine Lücke). Erfassen: Karte direkt über den Schnellknöpfen für Wasser.
- [ ] **Step 4:** `ALL`. Die Audits „Einkaufsliste“ und „Erfassen“ dürfen sich nicht ändern (Karte im UI-Testmodus aus).
- [ ] **Step 5:** Commit `feat: show a one-time Siri tip on the shopping list and at the drink buttons`.

### Task T4: Satzliste SI4a und Gerätetest

**Files:**
- Modify (nur nach Befund): `app/Tagwerk/Intents/TagwerkIntents.swift:292–301`, `app/Tagwerk/AppShortcuts.xcstrings`, `SiriPhraseCatalog.swift`
- Test: `AppShortcutsTests.swift`

Die erste der drei Korrekturen (Liste nennt „Fokus beenden in Tagwerk“) ist mit T2 erledigt. Die beiden anderen hängen am Gerätetest:

| Prüfpunkt | Test am Gerät (Siri, Deutsch) | Wenn zuverlässig | Wenn nicht |
|---|---|---|---|
| P1 Training mit Art | „Laufen in Tagwerk erfassen“, „Gehen in Tagwerk erfassen“, je dreimal | Satz bleibt | Satz `\(\.$activity) in … erfassen` streichen; Training hat dann einen Satz |
| P2 Überschneidung Einkauf | „Milch auf die Einkaufsliste in Tagwerk“ dreimal: landet es beim Artikel-Kurzbefehl (legt „Milch“ an) oder fragt Siri nach Artikeln? | beide Sätze von „Auf die Einkaufsliste“ bleiben | „Auf die Einkaufsliste“ behält nur „Einkaufsliste in Tagwerk ergänzen“ (neuer Satz, ersetzt beide) |
| P3 Unbekannter Artikel | „Füge Drachenfrucht zur Einkaufsliste in Tagwerk hinzu“ (nie benutzt) | nichts | nur dokumentieren; kein Code |

- [ ] **Step 1:** Build auf dem Gerät, Prüfpunkte P1–P3 durchführen, Ergebnis als Kommentar in #188 (Hauptsitzung).
- [ ] **Step 2 (nur bei Befund):** Test in `AppShortcutsTests` anpassen (`phrases_haveNoSuffixOverlap`: kein Satz ohne Parameter ist das Ende eines Satzes mit Parameter), Satz ändern, `AppShortcuts.xcstrings` und `SiriPhraseCatalog` nachziehen, `ALL`.
- [ ] **Step 3 (nur bei Befund):** Commit `fix: drop App Shortcut phrases that Siri confuses on the device`.

---

## Strang G: GitHub

GH1a (Abschnitt „Status“ im Editor), GH2a (Untermenü) und GH3a (Zeile im Blatt „Neue Aufgabe“) sind der Ist-Zustand; dort ändert sich nur der Wortlaut (G1). GH8 ist bestätigt und bleibt unverändert.

### Task G1: Wortlaut „Projekt/Projekte“ (GH6b) außerhalb der KI-Dateien

**Files:**
- Modify: die in der Ausgangslage genannten Stellen außer `AI/*`; `GitHubKit`-Katalog; `Localizable.xcstrings`; `scripts/translations/en.json`; `scripts/check-strings.py`
- Test: `ProjectSelectionTests.swift`, `AssigneeSelectionTests.swift`, `SearchTextsTests.swift`, `SetupModelTests.swift`

Neue deutsche Texte (Englisch bleibt „Project/Projects“):

| Stelle | Neu |
|---|---|
| `ProjectSelection` | „Kein Projekt“ |
| `GitHubSettingsSection` | „Projekte“ |
| `TaskEditorView:102, 514` | „Alle Projekte“; „Der Status gilt je Projekt, unabhängig von „Ändern in“.“ |
| `TaskListView:79` | „Keine zugewiesenen Issues in offenen Projekten“ |
| `SetupModel:25` | „… aus deinen offenen GitHub-Projekten …“ |
| `SearchTexts:132, 155` | „GitHub-Projekt“; „ohne Projekt“ |
| `SearchSheet:361` | „… und in einem Projekt liegen.“ |
| `GitHubTaskProvider:228, 398` | „… im Projekt „…“ nicht.“; „… in diesem Projekt nicht ändern.“ |
| `NewTaskSheet:284`, `AssigneeSelection:85` | folgen in G3/G4 |

- [ ] **Step 1: Tests.** Bestehende Erwartungen in den vier Suiten auf den neuen Wortlaut ändern. Neue Prüfung in `check-strings.py` (`check_project_wording`): Kein Quellschlüssel eines Katalogs enthält `\bProjects?\b`. Gegenprobe von Hand vor dem Ändern der Texte: Das Skript meldet die heutigen Schlüssel (z. B. „Kein Project“).
- [ ] **Step 2:** `APP ProjectSelectionTests` usw. → rot.
- [ ] **Step 3: Umsetzen.** Texte ändern, `sync-strings.sh`, alte Schlüssel aus `en.json` entfernen, neue eintragen. Die Prüfung im Skript bekommt bis G5 eine befristete Ausnahme für die drei KI-Dateien (Schlüssel „Kein Project“, „Project fehlt“, „Project %@“, „Bitte ein Project nennen.“, „Dieses Project steht nicht in der Liste von list_github_targets.“, „Repository, Projects und Zugewiesene gibt es nur bei GitHub-Issues.“), mit Kommentar `# removed in G5`.
- [ ] **Step 4:** `ALL`. Commit `fix: write "Projekt" in all German texts about GitHub projects`.

### Task G2: Status in der Unterzeile der Aufgabenzeile (GH4c)

**Files:**
- Modify: `app/Packages/GitHubKit/Sources/GitHubKit/GitHubMapping.swift`, `app/Tagwerk/Tasks/TaskRow.swift:29–44, 94–108`
- Test: `GitHubKitTests` (neue Suite `GitHubProgressStatusTests`), `app/TagwerkTests/TaskRowTextTests.swift`

**Interfaces (Produces):**

```swift
// GitHubMapping
/// What a task row says about the progress of an issue.
public enum ProgressStatus: Equatable, Sendable {
    case stage(String)      // one stage in work, or the same one in every project: "In Progress"
    case several(Int)       // different stages in work: "2 Status"
}
/// The stage is "in work" when it comes after the start stage (`reopenStatus`, else the first stage that is not Done)
/// in board order and is not Done. Stages before the start stage ("Backlog" before "Ready") do not count.
public static func isInProgress(_ status: SubContainerStatus) -> Bool
public static func progressStatus(of statuses: [SubContainerStatus]) -> ProgressStatus?

// TaskRowText
static func statusText(_ status: GitHubMapping.ProgressStatus) -> String   // "In Progress" / "2 Status"
```

Anzeige: in der Unterzeile nach dem Containernamen `Text("·")`, `Image(systemName: "circle.lefthalf.filled")`, Statustext; nur für `item.id.source == .github`. VoiceOver: `TaskRowText.accessibilityLabel` hängt „Status In Progress“ bzw. „2 Status“ nach dem Listennamen an.

- [ ] **Step 1: Tests.**
  - `progressStatus_startStage_isNil` („Ready“ in „Backlog · Ready · In Progress · Done“), `progressStatus_beforeStartStage_isNil` („Backlog“), `progressStatus_done_isNil`, `progressStatus_inProgress_namesStage`, `progressStatus_withoutReady_usesFirstNonDoneAsStart` („Todo · Doing · Done“: „Doing“ zählt, „Todo“ nicht), `progressStatus_twoProjectsSameStage_namesItOnce`, `progressStatus_twoProjectsDifferentStages_isSeveral`, `progressStatus_oneInWorkOneAtStart_namesTheOneInWork`, `progressStatus_noStatusValue_isNil`.
  - `TaskRowTextTests.accessibilityLabel_namesTheStatus`, `accessibilityLabel_localTask_hasNoStatus`.
- [ ] **Step 2:** `PKG GitHubKit GitHubProgressStatusTests`, `APP TaskRowTextTests` → rot.
- [ ] **Step 3: Umsetzen.** `TaskRow` importiert `GitHubKit`. Die Suche zeigt den Status mit, weil `SearchTaskRow` `TaskRow` nutzt.
- [ ] **Step 4:** `ALL`. Commit `feat: show the project status in the task row while an issue is in work`.

### Task G3: Gründe fürs Verschwinden, Kapseltexte (GH5c) und Kapsel „in einem Projekt erledigt“ (GH7b)

**Files:**
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/TaskProvider.swift:18–48` (Protokoll, Standardimplementierung, neuer Typ), `GitHubKit/GitHubTaskProvider.swift:127–137, 296–300, 413–425`, `app/Tagwerk/Tasks/HandedOverNotice.swift`, `AssigneeSelection.swift:82–95`, `TaskListModel.swift:234–246, 404–413, 490–505`, `UndoCapsule.swift:91–110` (unverändert, liest nur `notice`), `Localizable.xcstrings`, `en.json`
- Test: `GitHubKitTests/GitHubStatusWriteTests.swift`, `GitHubAssigneeTests.swift` (dort liegen die `isListed`-Tests), `TaskListModelTests.swift`, `AssigneeSelectionTests.swift`, neu `HandedOverNoticeTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore, next to TaskProvider
/// Why a task that was just written is not part of the user's lists any more.
public enum UnlistedReason: Equatable, Sendable {
    /// Assigned to other people only.
    case handedOver
    /// In no project; `others` are the assignees besides the user.
    case noProject(others: [String])
    /// Done in every selected project, still open in projects that are not selected (names in board order).
    case doneInSelection(doneIn: [String], openIn: [String])
}
public protocol TaskProvider {
    // existing members …
    /// `nil` while the item belongs to the lists. Default: `isListed(item) ? nil : .handedOver`.
    func unlistedReason(_ item: TaskItem) -> UnlistedReason?
}

// HandedOverNotice
init(item: TaskItem, reason: UnlistedReason)
```

`GitHubTaskProvider`:
- `unlistedReason`: (1) `statuses.isEmpty` → `.noProject(others:)`; (2) eigener Login nicht zugewiesen → `.handedOver`; (3) kein gewähltes Projekt mit einem Status, der nicht „Done“ ist, aber ein nicht gewähltes → `.doneInSelection`; sonst `nil`. `isListed(item)` wird `unlistedReason(item) == nil`.
- `apply` gibt für ein weiter gelistetes Issue den Eintrag zurück, wie `displayed()` ihn baut (Platzierungen auf die Auswahl beschränkt, Version des ganzen Issues); dafür wird der Rumpf von `displayed()` zu `displayedItem(_ record:) -> TaskItem?`. Für ein nicht mehr gelistetes Issue bleibt der vollständige Eintrag, damit die Kapsel die Namen der anderen Projekte kennt.

Kapseltexte:

| Grund | Überzeile | Titel | VoiceOver |
|---|---|---|---|
| `.handedOver` | „Vergeben“ | wie heute | wie heute |
| `.noProject(others: [])` | „Angelegt · nicht in Aufgaben“ | „#151 ohne Projekt“ | „Angelegt, nicht in Aufgaben: #151 ohne Projekt. Auf GitHub öffnen verfügbar.“ |
| `.noProject(others: ["lea-m"])` | „Angelegt · nicht in Aufgaben“ | „#151 an lea-m · ohne Projekt“ (ab drei Personen „an 3 Personen“) | entsprechend |
| `.doneInSelection(["Tagwerk"], ["Roadmap 2027"])` | „In „Tagwerk“ erledigt“ (mehrere: „In 2 Projekten erledigt“) | „#154 noch offen in „Roadmap 2027““ (mehrere: „noch offen in 2 Projekten“) | „In Tagwerk erledigt: #154 noch offen in Roadmap 2027. Auf GitHub öffnen verfügbar.“ |

`TaskListModel`: `handOver(_:reason:announce:)`; `settle` fragt `provider.unlistedReason`. `setStatus` und der Weg aus dem Editor (`adopt`, Zeile 404–413) kündigen die Kapsel an; der Weg des Assistenten (`applyReturning`, `createReturning`) bleibt bei `announce: false`. `onHandedOver` läuft für alle drei Gründe (geplanter Tag und künftige Blöcke entfallen, siehe offene Frage 2).

- [ ] **Step 1: Tests.**
  - Provider: `unlistedReason_noPlacement_isNoProjectWithOthers`, `unlistedReason_notAssigned_isHandedOver`, `unlistedReason_doneInSelectedOpenElsewhere_namesBothProjects`, `unlistedReason_doneEverywhereWritable_isNil` (das Issue wird geschlossen, nicht „unlisted“), `apply_returnsItemRestrictedToSelection`, `apply_defaultSelection_usesProjectsWithVisibleIssues`.
  - `TaskListModelTests`: `setStatus_doneInOnlySelectedProject_removesItemAndShowsNotice`, `setStatus_doneInAllProjects_showsUndoCapsule` (bestehendes Verhalten), `editorSave_doneInSelection_showsNotice`, `assistantWrite_doneInSelection_showsNoCapsule`.
  - `HandedOverNoticeTests`: je Zeile der Tabelle Titel, Überzeile und Ansage; `AssigneeSelectionTests`: `noProjectTitle_withOthers_namesThem`, `noProjectTitle_onlyMe_hasNoPerson`.
- [ ] **Step 2:** die genannten Suiten → rot.
- [ ] **Step 3: Umsetzen** wie beschrieben. Alle Fakes mit `isListed` erhalten die Standardimplementierung über das Protokoll.
- [ ] **Step 4:** `ALL`. Commit `feat: explain why an issue left the task list: no project, or done in the selected project only`.

### Task G4: Fußtexte im Blatt „Neue Aufgabe“ (GH5c, GH9)

**Files:**
- Modify: `app/Tagwerk/Tasks/NewTaskSheet.swift:119–135, 277–285`, `ProjectSelection.swift`
- Test: `ProjectSelectionTests.swift`

**Interfaces (Produces):**

```swift
// ProjectSelection
/// True when several projects are selected, each has stages, and they share none: the row "Status" is not offered.
static func lacksCommonStatus(_ optionLists: [[String]]) -> Bool
```

Texte: „Ohne Projekt erscheint das Issue nicht in deinen Aufgaben, nur auf GitHub.“ (ersetzt den Satz in Zeile 284, die Zuweisungszeile folgt wie heute); bei `lacksCommonStatus`: „Die Projekte haben keine gemeinsame Stufe; jedes Issue startet in der ersten Stufe seines Projekts.“ als erster Satz des Fußtexts.

- [ ] **Step 1: Tests:** `lacksCommonStatus_twoBoardsWithDifferentNames_isTrue`, `lacksCommonStatus_oneProject_isFalse`, `lacksCommonStatus_projectWithoutStatusField_isFalse`, `lacksCommonStatus_sharedStageOnlyDone_isTrue`.
- [ ] **Step 2:** `APP ProjectSelectionTests` → rot. **Step 3:** umsetzen. **Step 4:** `ALL`.
- [ ] **Step 5:** Commit `feat: say in "Neue Aufgabe" when the chosen projects share no start stage`.

### Task G5: Wortlaut in den KI-Dateien (nach #173, Stränge A und B)

**Files:** `app/Tagwerk/AI/ActionCardDescriber.swift:129, 135`, `AppTools+GitHub.swift:20–21`, `AppTools.swift:353`, `scripts/check-strings.py` (befristete Ausnahme streichen), Tests `ActionCardDescriberTests`, `AppToolsTests`

- [ ] „Kein Projekt“, „Projekt fehlt“, „Projekt …“, „Bitte ein Projekt nennen.“, „Dieses Projekt steht nicht in der Liste von list_github_targets.“, „Repository, Projekte und Zugewiesene gibt es nur bei GitHub-Issues.“ Werkzeugbeschreibungen (englisch) und `TaskChat.swift:151` bleiben.
- [ ] Tests anpassen, `ALL`, Commit `fix: write "Projekt" in the assistant's German texts`.

---

## Strang S: Teilen und Mail

### Task S1: Texte der Erweiterung als reine Regeln

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/Share/ShareSheetText.swift`
- Test: `TagwerkCoreTests/ShareSheetTextTests.swift`

**Interfaces (Produces):**

```swift
/// What the share sheet says below the title, and after saving. Cases only; the extension owns the wording.
public enum ShareHint: Equatable, Sendable {
    case recipeChoiceLater      // "Text und Link gehen mit. In Tagwerk wählst du, ob die Zutaten auf die Einkaufsliste kommen."
    case textAndLink            // "Text und Link gehen mit."
    case linesBecomeItems       // "Jede Zeile wird ein Artikel."
    case mailContinuesInApp     // "Tagwerk zeigt dir die Mail und schlägt eine Aufgabe vor."
    case filesDropped           // "Dateien werden nur bei Notizen und Rezepten übernommen."
}
public enum ShareSheetText {
    public static func hints(target: ShareTarget, hasFiles: Bool, hasText: Bool, hasURL: Bool) -> [ShareHint]
    /// SF Symbol of a target tile.
    public static func symbol(for target: ShareTarget) -> String   // checklist, square.and.pencil, cart, fork.knife, envelope
}
```

- [ ] **Step 1: Tests:** `hints_recipe_announcesTheChoiceInTheApp`, `hints_taskWithFiles_saysFilesAreDropped`, `hints_noteWithFiles_hasNoDropNotice`, `hints_shopping_saysLinesBecomeItems`, `hints_mail_saysTheAppContinues`, `symbol_isDistinctPerTarget`.
- [ ] **Step 2:** `PKG TagwerkCore ShareSheetTextTests` → rot. **Step 3:** umsetzen. **Step 4:** `ALL`.
- [ ] **Step 5:** Commit `feat: add the rules for the hints of the share sheet`.

### Task S2: Kacheln, Knopf unten, Bestätigung mit Ziel (TE1b, TE2b)

**Files:**
- Modify: `app/TagwerkShare/ShareModel.swift:12–18, 23–24, 46–49, 96–99`, `ShareView.swift`, `ShareViewController.swift`, `TagwerkShare/Localizable.xcstrings`, `en.json`
- Test: kein Test-Target für die Erweiterung; `SharePayload`-Tests in TagwerkCore bleiben grün; Geräteprüfung Z1

Aufbau (Mockup TE1b):
1. Leiste: „Abbrechen“ links, Titel „In Tagwerk sichern“. Kein Knopf rechts.
2. Vorschau (Vorschaubild, Titel, Host oder Dateinamen) wie heute.
3. Kacheln: eine je Ziel aus `payload.availableTargets` (zwei bis fünf), in einer Zeile; ab Bedienungshilfen-Schriftgrößen (`dynamicTypeSize >= .accessibility1`) zwei Spalten. Jede Kachel: Symbol aus `ShareSheetText.symbol`, Name aus `ShareView.name(of:)`; bei fünf Zielen heißt „Mail zu Aufgabe“ auf der Kachel „Mail“. Gewählt: getönter Hintergrund und `.isSelected`; Kachel mindestens 44 pt hoch.
4. Feld „Titel“ (einzeilig, `.submitLabel(.done)`). **Kein Textfeld mehr**: der Text geht unverändert mit (`ShareModel.text` bleibt, `showsTextField` entfällt).
5. Hinweise aus `ShareSheetText.hints`.
6. Unten: `Button("Sichern")` als `.borderedProminent`, volle Breite, in `safeAreaInset(edge: .bottom)`.

Bestätigung (TE2b): `State.saved` trägt das Ziel (`case saved(ShareTarget)`). Erste Zeile nach Ziel: „Als Aufgabe gesichert“, „Als Notiz gesichert“, „Für die Einkaufsliste gesichert“, „Als Rezept gesichert“, „Mail gesichert“; zweite Zeile: „Tagwerk zeigt es dir beim nächsten Öffnen.“ Das Blatt schließt nach 2 s (statt 1,2 s; zwei Zeilen) oder sofort bei einem Tipp.

Halbhohes Blatt: `ShareViewController` setzt in `viewDidLoad` `sheetPresentationController?.detents = [.medium(), .large()]` und `prefersGrabberVisible = true`. Ob das System das für eine Teilen-Erweiterung beachtet, ist nicht geprüft (Geräteprüfung). **Rückfall:** volle Höhe, Inhalt oben, Knopf unten; kein durchsichtiger Zwischen-Controller.

- [ ] **Step 1:** Umsetzen wie beschrieben; `ShareView.name(of:)` bleibt die eine Quelle der Zielnamen.
- [ ] **Step 2:** `xcodegen` und Build des Schemas `Tagwerk` (baut die Erweiterung mit); `ALL`.
- [ ] **Step 3: Prüfung im Simulator:** Aus Safari eine Rezeptseite teilen: Kachel „Rezept“ vorgewählt, Hinweis nennt die Wahl in Tagwerk; aus Notizen einen mehrzeiligen Text teilen: fünf Kacheln passen bei Standardgröße in die Zeile, bei AX3 zwei Spalten.
- [ ] **Step 4:** Commit `feat: choose the target of a share with tiles and name it in the confirmation`.

### Task S3: Blatt „Mail zu Aufgabe“ als Karte mit getönten Vorschlägen (TE3b)

**Files:**
- Modify: `app/Tagwerk/Share/MailTaskModel.swift:24–31, 66–67, 84–88, 99–103, 160–186`, `MailTaskSheet.swift:56–145`, `Localizable.xcstrings`, `en.json`
- Test: `app/TagwerkTests/MailTaskModelTests.swift`

**Interfaces (Produces):**

```swift
// MailTaskModel
/// The summary or what the user wrote; sender and link are not part of it any more.
private(set) var notes: String
/// "Von: Copyshop am Campus" and whether a link back to the mail exists; shown as a fixed row.
var senderNote: String? { get }
var hasMailLink: Bool { get }
/// The first lines of the mail for the card (at most `previewLength` characters, whole words).
var bodyPreview: String { get }
static let previewLength = 160
/// Notes of the task that is created: `notes`, then the sender line and the link, as before.
var prefill: Prefill { get }
```

Blatt:
- **Mail-Karte** (ein Abschnitt): Betreff, darunter „Absender · Datum“, darunter `bodyPreview` mit „mehr“ (klappt den ganzen Text in der Karte auf, höchstens 12 Zeilen, dann scrollt die Karte nicht, sondern kürzt mit „…“); in derselben Karte der Knopf „Mit ChatGPT zusammenfassen“ mit dem bisherigen Fußtext.
- **Aufgabe:** Titel und Notiz; ein vorgeschlagenes Feld trägt links `Image(systemName: "sparkles")` und einen lila getönten Zeilenhintergrund (`Color.purple.opacity(0.12)`), **keinen** Knopf „Vorschlag“. Tippen ins Feld und Ändern übernimmt wie heute (`editTitle`/`editNotes` nehmen die Marke weg). `confirm(_:)` bleibt für VoiceOver als Aktion „Vorschlag übernehmen“.
- **Feste Zeile** unter der Notiz: „Von: … · Link zur Mail“ in Sekundärfarbe, nicht editierbar; ohne Absender und Link entfällt sie.
- **Fällig:** eine Zeile mit Schalter und Datum; bei Vorschlag getönt wie oben. „Uhrzeit“ bleibt.
- Fußtext, solange `suggestedFields` nicht leer ist: „✦ Vorschlag von ChatGPT. Ändern oder so lassen; gesichert wird erst im nächsten Schritt.“

- [ ] **Step 1: Tests.**
  - `prefill_keepsSenderAndLinkInTheNotes` (wie bisher zusammengesetzt), `notes_withoutSummary_isEmpty`, `editNotes_thenSummary_keepsTheUsersText`, `prefill_afterEditingNotes_stillAppendsSenderAndLink`, `bodyPreview_cutsAtWordBoundary`, `senderNote_neverContainsTheAddress` (nur `senderName`), `plainText_hasNoSenderNoteAndNoLink`.
  - Bestehende Tests, die `notes` mit „Von:“ erwarten, auf `prefill.notes` umstellen.
- [ ] **Step 2:** `APP MailTaskModelTests` → rot. **Step 3:** umsetzen. **Step 4:** `ALL`.
- [ ] **Step 5:** Commit `feat: show the mail as a card and mark ChatGPT's proposals by tint instead of buttons`.

Hinweis zu Strang K: Die lila Tönung und das Symbol sind Fläche und Symbol und bleiben; lila **Text** kommt hier nicht vor.

---

## Strang L: Sprachen

### Modell der Spracheinstellungen (verbindlich)

| Einstellung (Seite „Sprachen“) | Gespeichert in | Werte | Vorgabe | Wirkt auf |
|---|---|---|---|---|
| Diktat | `voiceRecognitionLanguage` (**unverändert**, kein Umbenennen) | "auto" (Wie die App), "de-DE", "en-US" | "auto" | Spracherkennung überall, auch im Sprechmodus; Vorgabe für Orte ohne eigenen Stand |
| Sprachchat-Antwort | **neu** `voiceAnswerLanguage: String?` | "spoken" (Wie gesprochen), "de-DE", "en-US"; `nil` = noch nicht übernommen | aus dem alten Wert abgeleitet | Anweisung im Sprechmodus (`VoiceChatLanguage.answerInstruction`), Rückfallsprache der Vorlesestimme |
| Rezepte | `recipeLanguage` (unverändert) | "auto", "de-DE", "en-US" | "auto" | Rezeptimport, Rezept-Notiz, Vorwahl in #232 |
| Einkaufsliste | **neu** `shoppingLanguage: String` | "recipes" (Wie Rezepte), "auto", "de-DE", "en-US" | "recipes" | Namen neuer Artikel aus Rezepten und vom Assistenten; Diktat-Sprache im Eingabefeld der Einkaufsliste |
| Wechsel je Ort (SP4b) | **neu** `dictationPlaceLanguagesData: Data?` (JSON `[String: String]`) | Ort → "de-DE"/"en-US" | leer | Diktat an diesem Ort |

**Übernahme des bisherigen gemeinsamen Werts** (einmalig beim Start, vor dem ersten Lesen, in `AppEnvironment`):

| `voiceRecognitionLanguage` vorher | Diktat danach | `voiceAnswerLanguage` danach | Verhalten |
|---|---|---|---|
| "auto" | "auto" | "spoken" | unverändert: Erkennung in der App-Sprache, Antwort in der gesprochenen Sprache |
| "de-DE" / "en-US" | unverändert | derselbe Wert | unverändert: Erkennung und Antwort fest |
| unbekannter Wert (neuere Version, beschädigte Sicherung) | unverändert (löst wie bisher zur App-Sprache auf) | "spoken" | wie "auto" |

- Die Übernahme schreibt nur, wenn `voiceAnswerLanguage == nil`. Danach sind beide Werte unabhängig.
- **Sicherungen:** `BackupDTOs` bekommt `voiceAnswerLanguage: String?`, `shoppingLanguage: String?`. Fehlt `voiceAnswerLanguage` in einer älteren Sicherung, setzt das Wiederherstellen das Feld auf `nil`; die Übernahme läuft dann beim nächsten Start aus dem wiederhergestellten `voiceRecognitionLanguage`. Fehlt `shoppingLanguage`, bleibt "recipes". `dictationPlaceLanguagesData` wird nicht gesichert.
- **Rückwärts:** Eine ältere App-Version liest weiter `voiceRecognitionLanguage` und verhält sich wie vor dem Update.

### Task L1: Regeln, Felder, Übernahme

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/Voice/ContentLanguages.swift`
- Modify: `TagwerkCore/Voice/VoiceChatLanguage.swift` (Kommentar, `answerInstruction` bleibt), `app/Tagwerk/Persistence/AppSettings.swift:160–163`, `app/Tagwerk/Backup/BackupDTOs.swift:1204–1213, 1284–1292, 1363–1371`, `app/Tagwerk/App/AppEnvironment.swift:223, 234`, `app/Tagwerk/Voice/VoiceComposer.swift:222`
- Test: `TagwerkCoreTests/ContentLanguagesTests.swift`, `app/TagwerkTests/VoiceSettingsTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
/// A place with a dictation field. The raw value is stored.
public enum DictationPlace: String, CaseIterable, Sendable { case notes, chat, meal, planning, shopping }

/// Resolves the four content languages from their stored settings. Pure; the app passes the stored strings.
public struct ContentLanguages: Equatable, Sendable {
    public static let spoken = "spoken"          // voiceAnswerLanguage: answer in the language spoken
    public static let likeRecipes = "recipes"    // shoppingLanguage: follow the recipe language

    public var dictation: String                 // voiceRecognitionLanguage
    public var answer: String?                   // voiceAnswerLanguage
    public var recipe: String                    // recipeLanguage
    public var shopping: String                  // shoppingLanguage
    public var places: [String: String]          // DictationPlace.rawValue -> VoiceLanguage.rawValue

    public func dictationLanguage(at place: DictationPlace?, locale: Locale = .current) -> VoiceLanguage
    /// `nil` for "Wie gesprochen".
    public var fixedAnswerLanguage: VoiceLanguage? { get }
    /// Voice for read-aloud when the text gives no hint: the fixed answer language, else the dictation language.
    public func readAloudFallback(locale: Locale = .current) -> VoiceLanguage
    public func recipeLanguage(locale: Locale = .current) -> VoiceLanguage
    public func shoppingLanguage(locale: Locale = .current) -> VoiceLanguage
    /// The second language of a recipe import; `nil` while list and recipe share one.
    public func shoppingLanguageIfDifferent(locale: Locale = .current) -> VoiceLanguage?

    /// The value to store for the answer language of a settings object that has none yet.
    public static func migratedAnswer(fromDictation setting: String) -> String
    /// The places after switching at `place` to `language`: the entry goes when it equals the default again.
    public func places(switching place: DictationPlace, to language: VoiceLanguage, locale: Locale = .current) -> [String: String]
}

// AppSettings (app target)
var voiceAnswerLanguage: String? = nil
var shoppingLanguage: String = "recipes"
var dictationPlaceLanguagesData: Data? = nil
extension AppSettings {
    var contentLanguages: ContentLanguages { get }
    func migrateVoiceAnswerLanguageIfNeeded()        // called once from AppEnvironment.init, and after a restore
}
```

`.shopping` hat nie einen Eintrag in `places`: Seine Diktat-Sprache ist `shoppingLanguage()` (SP5b: eine Marke, ein Wert).

- [ ] **Step 1: Tests.**
  - `migration_auto_becomesSpoken`, `migration_fixedLanguage_keepsAnswerLanguage`, `migration_unknownValue_becomesSpoken`, `migration_runsOnce` (zweiter Aufruf nach geändertem Diktat ändert die Antwort nicht).
  - `dictation_placeWithoutEntry_usesTheSetting`, `dictation_placeWithEntry_winsOverTheSetting`, `dictation_shoppingPlace_isTheShoppingLanguage`, `places_switchingBackToDefault_removesTheEntry`, `places_unknownStoredValue_isIgnored`.
  - `shopping_likeRecipes_followsRecipeSetting`, `shopping_auto_followsAppLocale`, `shopping_fixed_isIndependentOfRecipes`, `shoppingIfDifferent_sameLanguage_isNil`, `readAloudFallback_spoken_usesDictation`.
  - `BackupTests`: `restore_backupWithoutAnswerLanguage_migratesFromRestoredDictation`, `restore_backupWithoutShoppingLanguage_keepsLikeRecipes`, `backup_roundTripsBothFields`.
- [ ] **Step 2:** `PKG TagwerkCore ContentLanguagesTests`, `APP BackupTests` → rot.
- [ ] **Step 3: Umsetzen.** `AppEnvironment:223`: `assistant.fixedVoiceLanguage = { settings.contentLanguages.fixedAnswerLanguage }`. `AppEnvironment:234` (Sprechmodus): `dictationLanguage(at: .chat)`. `VoiceComposer:222`: `readAloudFallback()`. `resolvedRecipeLanguage` (`RecipeNoteWriter.swift:6`) bleibt und ruft weiter `RecipeLanguage.resolve`. Die übrigen Leser der Erkennungssprache folgen in L3.
- [ ] **Step 4:** `ALL`. Commit `feat: separate the dictation, answer and shopping languages and carry the old shared value over`.

### Task L2: Seite „Sprachen“ (SP1b)

**Files:**
- Create: `app/Tagwerk/Settings/LanguageSettingsView.swift`
- Modify: `app/Tagwerk/Voice/VoiceSettingsView.swift:66–87, 107` (Abschnitte „Sprachchat“ und „Rezepte“ entfallen; Titel „Spracheingabe und Vorlesen“), `Settings/AISettingsView.swift` (Zeilenname), `Settings/SettingsView.swift` (Zeile „Sprachen“ nach „Siri & Kurzbefehle“ bzw. nach „Fokus-Timer“), `Localizable.xcstrings`, `en.json`
- Test: `VoiceSettingsTests.swift`, neu `LanguageSettingsTextTests.swift`, `AccessibilityAuditRecipesUITests.swift:77–86`, `AuditAllowlist.swift:32–36, 114–127`

Seite (Mockup SP1b):
1. „App-Sprache“ mit dem Namen der aktuellen App-Sprache und Pfeil nach außen; öffnet `UIApplication.openSettingsURLString`. Fußtext: „Die Sprache der Oberfläche stellst du in den iOS-Einstellungen ein.“
2. Abschnitt „Inhalte“: Picker „Diktat“ (Wie die App, Deutsch, English), „Rezepte“ (Wie die App, Deutsch, English), „Einkaufsliste“ (Wie Rezepte, Wie die App, Deutsch, English), „Sprachchat-Antwort“ (Wie gesprochen, Deutsch, English). Fußtext: „Beim Diktieren und in der Einkaufsliste wechselst du die Sprache auch direkt am Feld. Rezepte übersetzt ChatGPT in die gewählte Sprache; die Artikel der Einkaufsliste entstehen in der Sprache der Einkaufsliste.“
3. Abschnitt „Stimme“: Zeile „Spracheingabe und Vorlesen“ → `VoiceSettingsView`; Fußtext „Mikrofon, Sprachpakete, Stimmen, Tempo und Sprechmodus.“

Zeile in den Einstellungen: `LabeledContent("Sprachen", value: …)`, Wert ist der Name der Diktat-Sprache („Wie die App“ zeigt den Namen der App-Sprache).

**Interfaces (Produces):**

```swift
enum LanguageSettingsText {
    static func summary(_ languages: ContentLanguages, locale: Locale) -> String   // "Deutsch"
    static func name(_ language: VoiceLanguage) -> String                          // moved from VoiceSettingsView.name
}
```

- [ ] **Step 1: Tests:** `summary_auto_namesTheAppLanguage`, `summary_fixed_namesIt`; `VoiceSettingsTests` an die entfallenen Abschnitte anpassen. UI: `auditSettings` öffnet „Sprachen“ (Audit „Einstellungen › Sprachen“) und danach „KI“ › „Spracheingabe und Vorlesen“ (Audit-Name bleibt „Einstellungen › KI › Sprache“, damit die Allowlist-Zuordnung stabil bleibt; `navigationBars["Spracheingabe und Vorlesen"]`). `recipeScreens` um „Einstellungen › Sprachen“ ergänzen; Muster für die neuen Fußtexte nur, wenn der Audit sie meldet.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. `VoiceSettingsView:107` (Stimmenwahl) nutzt `dictationLanguage(at: nil)`.
- [ ] **Step 4:** `ALL`. Commit `feat: add the settings page "Sprachen" with one row per content language`.

### Task L3: Große Marke beim Diktieren, Wechsel je Ort gemerkt (SP3b, SP4b)

**Files:**
- Modify: `app/Tagwerk/Voice/VoiceComposer.swift:5–17, 20–30, 112–128`, `VoiceInputModel.swift`, Aufrufer `Capture/MealSheet.swift:125`, `Planning/SuggestionViews.swift:553`, `Routines/NoteField.swift:190`, `Notes/NotesListView.swift:365`, `AI/ChatView.swift:70`, `Shopping/ShoppingInputBar.swift:117` (nur Ort, Marke folgt in L5)
- Test: `VoiceInputModelTests.swift`, `TagwerkCoreTests/DictationMachineTests` (bestehend), neu `DictationPlaceStoreTests.swift`

**Interfaces (Produces):**

```swift
// VoiceInputFactory
static func make(_ environment: AppEnvironment, place: DictationPlace) -> VoiceInputModel
// VoiceInputModel
let place: DictationPlace
/// Called after `switchLanguage()` with the new language; the factory stores it for the place.
var onLanguageSwitched: ((VoiceLanguage) -> Void)?
// AppEnvironment or AppSettings extension
func dictationLanguage(at place: DictationPlace) -> VoiceLanguage
func rememberDictationLanguage(_ language: VoiceLanguage, at place: DictationPlace)
```

Zuordnung der Orte: `NoteField` und `NotesListView` → `.notes`; `ChatView` und Sprechmodus → `.chat`; `MealSheet` → `.meal`; `SuggestionViews` → `.planning`; `ShoppingInputBar` → `.shopping`.

Marke (Mockup SP3b): `Text(name)` mit `Image(systemName: "arrow.left.arrow.right")`, Name ausgeschrieben („Deutsch“, „English“), Schrift `.footnote.weight(.semibold)`, Kapsel, Trefferfläche mindestens 44 pt (`.frame(minHeight: 44)` mit `contentShape`). In der kompakten Form (`compact == true`, Vorschlagsblatt) bleibt das Kürzel „DE“/„EN“ mit Wechselzeichen, weil die Zeile zu schmal ist. VoiceOver-Texte bleiben.

- [ ] **Step 1: Tests:** `switchLanguage_notifiesWithTheNewLanguage`, `switchLanguage_whileIdle_doesNotNotify`; `rememberedLanguage_appliesToTheNextRecordingAtThisPlace`, `rememberedLanguage_doesNotChangeOtherPlaces`, `switchingBack_removesTheEntry`, `shoppingPlace_isNeverStoredInPlaces`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen; alle `VoiceMicrophoneButton(…, language:)`-Aufrufer übergeben `environment.dictationLanguage(at:)`.
- [ ] **Step 4:** `ALL`. Commit `feat: name the dictation language on its switch and remember it per place`.

### Task L4: Zweiter Name je Zutat für die Einkaufsliste (SP2b)

**Files:**
- Modify: `app/Tagwerk/Shopping/RecipeImporter.swift:50–77, 104–153, 157–187, 236–294, 311–326, 372–433`, `RecipeSheets.swift:455–472, 531–570, 640–676`, `RecipeNoteWriter.swift:15–30`, `RecipeNoteSaveSheet.swift:85`
- Test: `RecipeImporterTests.swift`, `RecipeNoteFlowTests.swift`, `RecipeServingsTests.swift`, `RecipeSaveOnlyTests.swift`

**Regeln:**
1. `RecipeImporter.read` bekommt `shoppingLanguage: VoiceLanguage? = nil` (`nil` = gleiche Sprache oder Rezept wird nur gespeichert). Der Aufrufer übergibt `settings.contentLanguages.shoppingLanguageIfDifferent()` nur bei `purpose == .shopping`.
2. **Anfrage an ChatGPT:** Die JSON-Eingabe erhält zusätzlich `"shopping_language"` (Sprachname oder `null`). Das Schema erhält je Zutat `"shopping_name"` und `"shopping_unit"` (beide `["string","null"]`, beide in `required`). Anweisung: „Ist "shopping_language" gesetzt und eine andere Sprache als "language", schreibe in shopping_name den kurzen Namen der Zutat und in shopping_unit die Einheit in dieser Sprache; übersetze keine Eigennamen. Sonst sind beide null.“
3. **Ergebnis:** `Candidate` bekommt `shoppingName: String?` und `shoppingUnit: String?`. `Candidate.id` und `alreadyOnList` beziehen sich auf den Namen, der auf die Liste geht (`listName = shoppingName ?? name`), damit Dubletten gegen die Liste erkannt werden. Zwei Zutaten mit gleichem `listName` werden zusammengeführt wie heute.
4. **Rezept-Notiz** (`RecipeNoteWriter.recipeNote`, `ingredientLine(for:locale:)`): immer `name`, `line` und die Rezeptsprache. Nichts aus `shopping…` gelangt in die Notiz.
5. **Einkaufsliste** (`RecipeImporter.apply`): `ParsedItem(name: listName, quantity: listQuantity)`; `listQuantity` wird aus `line` mit `shoppingUnit ?? line.unit` und dem Gebietsschema der Einkaufssprache gebildet (`quantityText(of:locale:)`). Freie Mengentexte ohne Zahl („nach Geschmack“) gehen unverändert mit (offene Frage 6). Die Kategorie wird unter `ShoppingName.key(listName)` gemerkt.
6. **Skalieren** (`RecipeResultSheet.scaled`): rechnet weiter auf `line`; die Anzeige im Blatt zeigt je Zeile `listName` und die Menge in der Einkaufssprache, weil das Blatt zeigt, was auf die Liste geht. Bei abweichender Sprache steht der Rezeptname klein darunter („Rezept: red lentils“).
7. **Lokaler Leseweg** (strukturierte Rezept-Notiz, `result(for:…)`): Es gibt keine Übersetzung auf dem Gerät. Die Namen bleiben in der Sprache der Notiz; `shoppingName` ist `nil`; es wird nichts gesendet. Weicht die Einkaufssprache von der Sprache der Notiz ab, zeigt das Ergebnisblatt eine Hinweiszeile: „Die Zutaten stehen in der Sprache der Notiz (English). Neue Artikel aus dieser Notiz kommen so auf die Liste.“ `Result` bekommt dafür `var keepsNoteLanguage = false`. Die Sprache der Notiz liefert `RecipeNote.headingLanguage` (Überschriften „Zutaten“/„Ingredients“); die Funktion entsteht in Block A von `2026-11-20-notes-chatgpt.md` und ist auf `90a07d1` noch nicht vorhanden. Ist Block A beim Start von L4 nicht auf `main`, legt L4 sie mit genau diesem Namen in `TagwerkCore` an (`static func headingLanguage(of text: String) -> VoiceLanguage?`), und Block A nutzt sie; ist die Sprache nicht erkennbar, gilt die Rezeptsprache.
8. **Nur speichern** (`purpose != .shopping`): keine zweite Sprache, keine Änderung an Anfrage und Ergebnis.

**Interfaces (Produces):**

```swift
// RecipeImporter
func read(_ input: Input, language: VoiceLanguage, shoppingLanguage: VoiceLanguage? = nil, categoryNames: [String],
          openItemKeys: Set<String>, localClassifier: (String) -> String? = { _ in nil }) async throws -> Result
struct Result { /* existing */ var shoppingLanguage: VoiceLanguage? = nil; var keepsNoteLanguage = false }
struct Candidate {
    /* existing */
    var shoppingName: String? = nil
    var shoppingUnit: String? = nil
    var listName: String { shoppingName ?? name }
    var id: String { ShoppingName.key(listName) }
}
static func inputText(recipe: String?, categories: [String], language: VoiceLanguage, shoppingLanguage: VoiceLanguage? = nil,
                      photoCount: Int = 1) -> String
static func listItem(for candidate: Candidate, locale: Locale) -> ParsedItem
```

- [ ] **Step 1: Tests.**
  - `inputText_sameLanguage_sendsNullShoppingLanguage` (Anfrage bis auf das neue Feld unverändert), `inputText_differentLanguage_namesBoth`.
  - `validate_shoppingName_becomesTheListName`, `validate_missingShoppingName_fallsBackToName`, `validate_shoppingNameOnOpenList_isMarkedAlreadyOnList` (Rezept „milk“, Liste „Milch“), `validate_twoIngredientsSameShoppingName_areMerged`, `validate_emptyShoppingName_isIgnored`, `validate_shoppingNameLongerThanLimit_isCut`.
  - `apply_putsShoppingNamesOnTheList_andRemembersTheirCategory`, `listItem_usesShoppingUnitAndLocale` („2 cans“ → „2 Dosen“; „1.5 l“ → „1,5 l“).
  - `recipeNote_alwaysUsesRecipeLanguageNames`, `scaled_keepsShoppingNames`.
  - `noteInput_differentShoppingLanguage_neverCallsTheResponder`, `noteInput_differentShoppingLanguage_marksKeepsNoteLanguage`, `saveOnly_neverSendsAShoppingLanguage`.
- [ ] **Step 2:** `APP RecipeImporterTests` usw. → rot.
- [ ] **Step 3: Umsetzen** nach den Regeln 1–8. Bestehende Tests mit `candidate.id` bleiben gültig, solange `shoppingName == nil`.
- [ ] **Step 4:** `ALL`. Commit `feat: put recipe ingredients on the shopping list in the list's own language`.

### Task L5: Marke im Eingabefeld der Einkaufsliste (SP5b), Sprache für den Assistenten

**Files:**
- Modify: `app/Tagwerk/Shopping/ShoppingInputBar.swift:108–131`, `app/Tagwerk/Voice/VoiceComposer.swift` (Marke als wiederverwendbare View `LanguageChip`), nach #173 A und B: `app/Tagwerk/AI/AssistantModel.swift:397–398`
- Test: `ShoppingInputTests.swift`, `AssistantModelTests.swift`

Marke: `LanguageChip(shortName:)` („DE“/„EN“) dauerhaft links vom Mikrofon, 44 pt Trefferfläche, auch ohne Mikrofon sichtbar (`voiceInputEnabled == false`), weil sie auch die Sprache der Artikel aus Rezepten und vom Assistenten zeigt. Ein Tipp setzt `settings.shoppingLanguage` auf den festen Wert der anderen Sprache ("de-DE"/"en-US"); läuft gerade eine Aufnahme, ruft er zusätzlich `voice.switchLanguage()`. Die Marke im Aufnahmebalken zeigt an diesem Ort dieselbe Sprache und schreibt denselben Wert (`onLanguageSwitched` für `.shopping`). VoiceOver: „Sprache der Einkaufsliste Deutsch, auf Englisch wechseln“.

Assistent (eigener kleiner Commit nach #173): In der Systemanweisung zur Einkaufsliste ein Satz aus der Einstellung: „Schreibe neue Einkaufsartikel auf Deutsch.“ bzw. „… auf Englisch.“ (`RecipeLanguage.promptName`). Die Werkzeugbeschreibung bleibt.

- [ ] **Step 1: Tests:** `chip_togglesBetweenTheTwoLanguages_andStoresAFixedValue`, `chip_fromLikeRecipes_switchesToTheOtherLanguage`, `dictationAtShopping_usesTheShoppingLanguage`; `instructions_nameTheShoppingLanguage` (nach #173).
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`.
- [ ] **Step 5:** Commits `feat: show and switch the language of the shopping list at its input field`, später `feat: tell the assistant the language of new shopping items`.

---

## Strang U: Suche

### Task U1: Mittleres Menü auf Aufgaben-Treffern (SU1b), „Auf GitHub öffnen“ (SU3)

**Files:**
- Create: `app/Tagwerk/Search/SearchTaskMenu.swift`
- Modify: `app/Tagwerk/Search/SearchSheet.swift:14–24, 392–402, 447–457`, `app/Tagwerk/Tasks/TaskContextMenu.swift:49–59, 164–171` (Knöpfe „Heute“/„Morgen“ als wiederverwendbare `TaskPlanButtons`)
- Test: neu `app/TagwerkTests/SearchTaskMenuTests.swift`, `TagwerkUITests/SearchUITests.swift`

**Interfaces (Produces):**

```swift
/// The entries of the context menu on a task hit, in order (mockup SU1b). Pure, so the order and the rules are tested.
enum SearchTaskMenu {
    enum Entry: Equatable { case open, showInTasks, showInPlan, planToday, planTomorrow, planOnDate, startFocus, openOnGitHub, complete }
    static func entries(for item: TaskItem, isPlanned: Bool, isOffline: Bool) -> [Entry]
}
```

Regeln: `open` immer; `showInPlan` wenn eingeplant, sonst `showInTasks`; die drei Einplan-Einträge immer (Einplanen lebt nur in Tagwerk und geht auch offline); `startFocus` für offene Aufgaben (`TaskContextMenu.showsFocusStart`); `openOnGitHub` für `source == .github` mit URL; `complete` nur, wenn die Quelle nicht offline ist. Nie: Löschen, Schließen, Status, Fälligkeit, Wochenende, Nächste Woche, Aufwand, KI.

Aufbau im Menü: Öffnen und Zeigen; `Section("Einplanen · nur in Tagwerk")` mit `ControlGroup { Heute; Morgen }` und „Anderer Tag …“; `Section { FocusStartButton(task:) }`; „Auf GitHub öffnen“; „Erledigt“. „Anderer Tag …“ öffnet `RescheduleDateSheet` über ein neues `@State private var planningDateFor: TaskItem?` im Suchblatt und ruft `environment.planning.assign(item.id, to: PlanDay(day))` (wie `TaskListView.swift:199–203`). „Heute“/„Morgen“ rufen `environment.planning.plan(item.id, option:)`. Nach dem Einplanen bleibt das Suchblatt offen; `AccessibilityNotification.Announcement` sagt „Für heute eingeplant“ bzw. den Tag. Die `accessibilityAction`-Liste der Zeile erhält dieselben Einträge.

- [ ] **Step 1: Tests:** `entries_localTask_hasNoGitHubEntry`, `entries_plannedTask_offersShowInPlan`, `entries_offline_hasNoComplete_butPlanning`, `entries_issue_offersOpenOnGitHub`, `searchTaskMenu_neverOffersDeleteOrStatus` (für lokale Aufgabe, Erinnerung und Issue), `entries_orderMatchesTheMockup`. UI: `SearchUITests.testPlanFromSearchHit`: suchen, Treffer lange drücken, „Morgen“, Menü erneut öffnen, „Im Plan zeigen“ ist da.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. `FocusStartButton` schließt das Blatt selbst (`isPresented`), `onDismiss` ruft `closeSearch()`.
- [ ] **Step 4:** `ALL`. Commit `feat: plan a task, start its focus and open its issue from a search hit`.

### Task U2: „Im Ordner zeigen“ auf Notiz-Treffern (SU3)

**Files:**
- Modify: `app/Tagwerk/Search/SearchSheet.swift:8–12, 26–30, 425–430`, `app/Tagwerk/App/RootView.swift:94–99, 168–174`, `app/Tagwerk/App/AppEnvironment.swift:~481` (Funktion `showNotesFolder`)
- Test: `SearchEntryTests.swift` oder `AppRouterTests.swift` (wo `tasksPath` bereits geprüft wird)

**Interfaces (Produces):**

```swift
// SearchSheet
init(model: SearchModel, onShowDay: @escaping (PlanDay) -> Void, onShowTask: @escaping (TaskID) -> Void,
     onShowNoteFolder: @escaping (UUID?) -> Void = { _ in })
// AppEnvironment
/// Opens the folder list of a note in the tab "Aufgaben"; `nil` opens "Alle Notizen".
func showNotesFolder(_ folderID: UUID?)       // tasksPath = [.notes, .notesFolder(.folder(id) or .all)]
```

Menü des Notiz-Treffers: „Öffnen“, „Im Ordner zeigen“ (`folder`-Symbol). Der Sprung schließt die Suche, wechselt in den Tab „Aufgaben“ und setzt den Pfad. Eine Markierung der Notiz in der Liste gibt es nicht (im Mockup als ungeprüft vermerkt; die Notizliste kennt keine Markierung) und wird hier nicht gebaut. Erledigte Aufgaben, Online-Treffer, Termine und Einkaufsartikel bleiben unverändert (SU2).

- [ ] **Step 1: Tests:** `showNotesFolder_setsThePathToTheFolder`, `showNotesFolder_withoutFolder_opensAllNotes`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen, `accessibilityAction` „Im Ordner zeigen“ ergänzen. **Step 4:** `ALL`.
- [ ] **Step 5:** Commit `feat: jump from a note hit to its folder`.

---

## Strang K: Kontrast (eigener Block, beginnt nach dem Merge von T, L und S)

Reihenfolge verbindlich: **messen → benannte Stile und Assets → ersetzen → erneut messen → Ausnahmen streichen.** Die Werte der Mockups (78 %, 85 %, #005FCC, Schrifttöne) sind Startwerte aus einer Rechnung mit den klassischen Systemfarben; maßgeblich ist der Audit-Lauf.

### Task K1: Ausgangsmessung im Sammelmodus

**Files:**
- Modify: `app/TagwerkUITests/AuditAllowlist.swift:185–236`
- Test: Lauf der Audit-Klassen

Heute schreibt der Sammelmodus nur Befunde, die nicht auf der Liste stehen. Für diesen Block muss er alle Befunde zeigen und sagen, welcher Listeneintrag sie deckt.

**Interfaces (Produces):**

```swift
// AuditAllowlist
/// `AUDIT_COLLECT_ALL=1` together with `AUDIT_COLLECT_FILE`: every finding is written, accepted ones with the
/// index of the entry and the pattern that matched ("accepted=3:Überfällig"), others with "accepted=-".
private static var collectsAll: Bool { get }
private static func matchingEntry(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) -> (index: Int, pattern: String)?
```

Aufruf (xcodebuild reicht Variablen mit dem Präfix `TEST_RUNNER_` an den Testlauf weiter):

```
cd app && xcodegen --quiet && TEST_RUNNER_AUDIT_COLLECT_FILE=/tmp/tagwerk-audit-before.txt TEST_RUNNER_AUDIT_COLLECT_ALL=1 \
  xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme TagwerkUITests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:TagwerkUITests/AccessibilityAuditUITests -only-testing:TagwerkUITests/AccessibilityAuditLargeTextUITests \
  -only-testing:TagwerkUITests/AccessibilityAuditRecipesUITests -only-testing:TagwerkUITests/AccessibilityAuditRecipesLargeTextUITests
```

- [ ] **Step 1:** `matchesAllowlist` auf `matchingEntry` umbauen (Verhalten ohne die Variablen unverändert), Sammelmodus erweitern.
- [ ] **Step 2:** Lauf wie oben auf `main` (nach T, L, S). Auswertung als Tabelle im Pull Request: je Kontrast-Eintrag der Liste die Zahl der Befunde, je Bildschirm, getrennt nach hell (Standardgröße) und AX5/dunkel; dazu die Muster ohne Treffer (schon heute überflüssig).
- [ ] **Step 3:** `ALL` (ohne Variablen grün). Commit `test: let the audit's collect mode report which allowlist entry covers a finding`.

### Task K2: Farb-Assets und benannte Stile

**Files:**
- Create: `app/Design/Colors.xcassets` (Farbsets), `app/Tagwerk/Common/TextTones.swift`
- Modify: `app/project.yml` (Katalog in die Targets `Tagwerk` und `TagwerkShare`; `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` für beide)
- Test: neu `app/TagwerkTests/TextTonesTests.swift`

Farbsets (Startwerte; dunkel „System“ heißt: der Wert der Systemfarbe im Dunkeln wird eingetragen, damit sich dort nichts ändert):

| Asset | Hell | Dunkel | Verwendung |
|---|---|---|---|
| `AccentColor` | #005FCC | #0A84FF | Akzent der App (KO4a) |
| `TextSecondary` | #3C3C43, 78 % | #EBEBF5, 60 % | Sekundärtext (KO1a) |
| `TextGridTime` | #3C3C43, 85 % | #EBEBF5, 60 % | Uhrzeit im Stundenraster (KO3a) |
| `TextRed` | #B91C1C | #FF6961 | rote Schrift (KO2a) |
| `TextOrange` | #A84400 | #FF9F0A | orange Schrift |
| `TextPurple` | #7D3C9E | #DA8FFF | lila Schrift |
| `TextGreen` | #1F7A35 | #30D158 | grüne Schrift |

**Interfaces (Produces):**

```swift
/// Text colours that keep the audit's contrast on the app's backgrounds, cards and tinted cards.
/// Fills, bars and symbols keep the system colours.
extension ShapeStyle where Self == Color {
    static var secondaryText: Color { get }
    static var gridTimeText: Color { get }
    static var redText: Color { get }
    static var orangeText: Color { get }
    static var purpleText: Color { get }
    static var greenText: Color { get }
}
```

- [ ] **Step 1: Tests** (`TextTonesTests`, mit einer WCAG-Rechnung als Testhelfer, aufgelöst über `UIColor(named:)` und `UITraitCollection`): jedes Paar aus der Mockup-Tabelle liegt hell bei mindestens 4,5 : 1 (`secondaryText` auf Systemhintergrund, auf Karte, auf roter Karte mit 12 % Tönung; `redText`/`orangeText`/`greenText`/`purpleText` auf Karte und auf ihrer Tönung; Weiß auf `AccentColor`; `AccentColor` auf Hintergrund und Karte; `gridTimeText` auf Blau, Rot und Grau mit 24 %); `allAssets_resolveInBothAppearances`.
- [ ] **Step 2:** rot (Assets fehlen). **Step 3:** anlegen. **Step 4:** `ALL`; die Audits dürfen jetzt neue Befunde nur durch die Akzentfarbe zeigen: mit dem Sammelmodus prüfen, nichts auf die Liste setzen.
- [ ] **Step 5:** Commit `feat: add colour assets and named text tones for contrast`.

### Task K3: Ersetzen in der Breite

**Files:**
- Modify: alle Views im App-Target mit Schriftfarben (Stand `90a07d1`: 291 Stellen `.secondary`, 76 Stellen Farbe als Vordergrund, einschließlich Widget und Erweiterung); `app/Tagwerk/Planning/TimelineCanvas.swift` folgt in K4
- Create: `scripts/check-colors.py`; Modify: `app/test-all.sh` (Aufruf in der Stufe der Zeichenketten-Prüfung)

Regeln:
1. `.foregroundStyle(.secondary)` und `Color.secondary` als Vordergrund → `.secondaryText`, für Text **und** für SF Symbols in derselben Zeile (ein `Label` teilt sich den Stil). Flächen (`.background(.secondary…)`, `.fill`, `.quaternary`, Materialien) bleiben.
2. Rot, Orange, Grün, Lila als **Schrift** → `.redText` usw. Reine Symbole, Balken, Punkte, Flächen und `role: .destructive` behalten die Systemfarbe. Trägt ein `Label` Text und Symbol, bekommt nur der Text den Ton (Label auflösen oder `labelStyle` mit getrennten Stilen).
3. Blau als Schrift: `Color.accentColor`/`.tint` (kommt aus dem Asset); `Color.blue` als Schrift → `Color.accentColor`.
4. `.tertiary` als Schrift (29 Stellen mit `.tertiary`/`.quaternary`): je Stelle prüfen; trägt der Text Information, → `.secondaryText`; reine Zierde (Trennpunkte, Chevrons) bleibt.
5. Widget und Teilen-Erweiterung: Die Erweiterung nutzt den gemeinsamen Katalog und dieselben Stile (Datei `TextTones.swift` in beide Targets). Das Widget bleibt bei den Systemstilen (Sperrbildschirm und getönter Home-Bildschirm färben selbst).
6. `scripts/check-colors.py`: schlägt fehl, wenn im App-Target `.foregroundStyle(.secondary)`, `.foregroundStyle(Color.secondary)` oder `.foregroundStyle(.red|.orange|.green|.purple)` auf einem `Text(` derselben Anweisung steht; eine Zeile mit dem Kommentar `// system-colour: <reason>` ist ausgenommen.

Vier Commits nach Bereich, jeweils mit `ALL` dazwischen: (a) `Planning`, `Focus`, `Widget`-nahe Texte; (b) `Tasks`, `Editor`, `Search`; (c) `Notes`, `Shopping`, `Routines`, `Capture`; (d) `Settings`, `AI`, `Voice`, `Share`, Rest.

- [ ] **Step 1:** `check-colors.py` schreiben; es meldet die heutigen Stellen (Gegenprobe) und läuft bis zum letzten Bereichs-Commit mit `--report` (zählt nur).
- [ ] **Step 2–5:** je Bereich ersetzen, `ALL`, Commit `fix: use the contrast text tones in <area>`.
- [ ] **Step 6:** `check-colors.py` in `test-all.sh` scharf schalten. Commit `test: fail on system grey and system colours as text colours`.

### Task K4: Uhrzeit im Stundenraster (KO3a)

**Files:** `app/Tagwerk/Planning/TimelineCanvas.swift:~200–215`; Test: Audit „Planen (Tag)“

- [ ] Die Uhrzeitzeile der Rastereinträge nutzt `.gridTimeText`; die Tönung von 24 % und der Titel bleiben. Freie Blöcke (8 %) ebenso.
- [ ] `UI AccessibilityAuditUITests` (grün mit bestehender Liste), `ALL`. Commit `fix: darken the time line of entries in the hour grid`.

### Task K5: Erneut messen, Ausnahmen streichen

**Files:** `app/TagwerkUITests/AuditAllowlist.swift:40–74, 114–142`

- [ ] **Step 1:** Lauf wie in K1 in `/tmp/tagwerk-audit-after.txt`. Vergleich mit der Ausgangsmessung.
- [ ] **Step 2:** Jedes Muster der Kontrast-Einträge, das keinen Befund mehr deckt, streichen. Einträge, die leer werden, ganz entfernen. Für verbleibende Muster den Grund neu schreiben (was genau bleibt und warum): erwartet sind Schrift auf Liquid Glass, vom System abgeblendete Knöpfe, Weiß auf dem gefüllten Knopf im Dunkeln und, falls weiter gemeldet, die AX5/dunkel-Befunde der Rezept-Seiten.
- [ ] **Step 3:** Meldet der Audit nach dem Ersetzen weiter Sekundärtext oder Schrifttöne, **zuerst den Asset-Wert nachziehen** (z. B. 78 % → 82 %) und neu messen; erst wenn ein Wert das Erscheinungsbild sichtbar verändert, Rückfrage an den Nutzer statt neuer Ausnahme.
- [ ] **Step 4:** Zwei volle Läufe von `ALL` hintereinander grün (die Audits sind laufzeitabhängig).
- [ ] **Step 5:** Commit `test: remove contrast exceptions that pass with the new text tones`. Im Pull Request: Tabelle vorher/nachher je Eintrag und die Liste der verbleibenden Ausnahmen mit Grund; Kommentar in #160 durch die Hauptsitzung.

---

## Task Z1: Geräteprüfung (nach allen Strängen)

| Bereich | Prüfung am Gerät |
|---|---|
| Tastatur | Return-Taste heißt „Fertig“ in einzeiligen Feldern mehrerer Blätter; Symbolknopf in Notiz, Brain Dump, Zahlenfeld; VoiceOver liest „Tastatur ausblenden“; „Abschließen“ in Tagesstart und Tagesabschluss markiert, Wegwischen nicht. |
| Siri | Prüfpunkte P1–P3 aus T4; Seite zeigt zehn Einträge; `ShortcutsLink` öffnet die Kurzbefehle; Tipp-Karten erscheinen einmal, verschwinden nach ✕ und nach dem ersten Lauf des Kurzbefehls; Karte ohne registrierte Kurzbefehle lässt keine Lücke. |
| GitHub | Issue in zwei Projekten, nur eines gewählt, dort „Done“: Kapsel, Issue weg, auf GitHub offen. Issue ohne Projekt an andere: Kapsel nennt Person. Zeile zeigt „◐ In Progress“, nicht bei „Ready“ und „Backlog“. Zwei Projekte ohne gemeinsame Stufe: Fußtext. |
| Teilen | Safari-Seite, Text aus Notizen, Bild aus Fotos, Mail: Kacheln, Vorwahl, Höhe des Blatts (halbhoch oder Rückfall), Bestätigung nennt das Ziel; Tagwerk zeigt das Geteilte beim Öffnen. |
| Mail | Mail teilen, zusammenfassen, Felder getönt; ändern nimmt die Tönung; angelegte Aufgabe enthält „Von: …“ und den Link. |
| Sprachen | Update von einer Version mit „Sprache im Sprachchat: English“: Diktat englisch, Antwort englisch. Rezepte English, Einkaufsliste Deutsch: Import einer englischen Seite legt deutsche Artikel an, Notiz englisch. Marke im Diktat schaltet um, gilt am Ort weiter, andere Orte unverändert. Marke in der Einkaufsliste ändert die Einstellung. |
| Kontrast | Sichtprüfung hell und dunkel: Planen, Aufgaben, Erfassen, Einkaufsliste, Einstellungen; „Kontrast erhöhen“ ein; Blau der Knöpfe; Widget unverändert. |
| Suche | Treffer einplanen, Fokus starten (Blatt schließt, Timer öffnet), Issue auf GitHub öffnen, Notiz im Ordner zeigen (auch privater Ordner mit Sperre). |

## Offene Fragen (mit Empfehlung)

1. **GH4c, Stufen vor der Startstufe.** Wörtlich („weder Startstufe noch Done“) erschiene „◐ Backlog“ in einem Board „Backlog · Ready · …“. **Empfehlung (so geplant):** nur Stufen **nach** der Startstufe zählen als „in Arbeit“.
2. **GH7b, Planung beim Verschwinden.** Das Issue ist aus Tagwerk weg, aber offen. **Empfehlung (so geplant):** wie beim Abgeben geplanten Tag und künftige Zeitblöcke entfernen (`onHandedOver`); vergangene Blöcke bleiben.
3. **Sprachchat-Antwort ohne „Wie die App“.** Das Mockup sagt, jede Zeile biete „Wie die App“; für die Antwort wäre das ein neues Verhalten (fest auf die App-Sprache), das heute niemand hat. **Empfehlung (so geplant):** nur „Wie gesprochen“, Deutsch, English.
4. **Marke in der Einkaufsliste und „Wie Rezepte“.** Ein Tipp speichert eine feste Sprache; „Wie Rezepte“ kommt nur über die Einstellungen zurück. **Empfehlung (so geplant):** fester Wert, weil ein späteres Ändern der Rezeptsprache die Liste sonst still umstellt.
5. **Rezept-Notiz lokal gelesen, Einkaufssprache weicht ab.** Ohne ChatGPT gibt es keine Übersetzung. **Empfehlung (so geplant):** Namen bleiben in der Sprache der Notiz, Hinweiszeile im Blatt; das Übersetzen gehört zu SP5c.
6. **Zweite Einheit und freie Mengentexte.** Geplant sind zweiter Name **und** zweite Einheit („2 cans“ auf einer deutschen Liste wäre sonst falsch); freie Texte wie „nach Geschmack“ bleiben in der Rezeptsprache. **Empfehlung:** so lassen; ein drittes Feld erst, wenn es im Gerätetest stört.
7. **Ändern von „Diktat“ in den Einstellungen und gemerkte Orte.** **Empfehlung:** Die gemerkten Orte bleiben (SP4b sagt „bis man zurückschaltet“); kein Zurücksetzen. Alternative: Ändern der Einstellung leert die Orte.
8. **SI3 „einmal“.** **Empfehlung (so geplant):** sichtbar bis ✕ oder bis der Kurzbefehl einmal lief, nicht nur beim ersten Besuch.
9. **Zeilenwert „10 Sätze“.** Gezählt werden die zehn Kurzbefehle, registriert sind 18 Sätze. **Empfehlung:** „10 Kurzbefehle“ statt „10 Sätze“; im Plan steht vorerst der Wortlaut des Mockups.
10. **Blau in dunklen Blättern.** Die Mockup-Tabelle zeigt für dunkle Blätter einen helleren blauen Schriftton (4,92), KO4a lässt `AccentColor` im Dunkeln bei #0A84FF. **Empfehlung:** erst messen (K1); meldet der Audit Akzenttext in dunklen Blättern, den dunklen Wert des Assets anheben (Kandidat #409CFF, rechnen und messen), statt einen zweiten Blauton einzuführen.
11. **TE1b bei fünf Zielen.** Fünf Kacheln in einer Zeile sind bei Standardgröße knapp. **Empfehlung (so geplant):** Kurzname „Mail“ auf der Kachel, zwei Spalten ab AX1.
12. **Halbhohes Blatt der Erweiterung.** Nicht geprüft, ob das System Detents einer Teilen-Erweiterung beachtet. **Empfehlung:** versuchen, sonst volle Höhe ohne weiteren Umbau.

## Risiken

- **Vererbung von `.submitLabel`:** Der Wert ist ein Umgebungswert; ob er jedes Blatt erreicht, ist nicht geprüft. Der Rückfall (Wurzel je Blatt) steht in T1.
- **`SiriTipView` rendert leer**, wenn die Kurzbefehle nicht registriert sind; die Karte darf dann keinen Platz belegen (T3). Text und Aussehen sind nicht anpassbar.
- **Satzänderungen nach Gerätetest** ändern `AppShortcuts.xcstrings`; ein vergessener Abgleich lässt `check-strings.py` fehlschlagen (gewollt).
- **`apply` gibt künftig den auf die Auswahl beschränkten Eintrag zurück (G3):** Der Editor zeigt nach dem Sichern nur noch die Status der gewählten Projekte (wie vor dem Sichern). Versionen bleiben die des ganzen Issues; Tests für Konflikte müssen grün bleiben.
- **Kapsel nur nach eigener Änderung:** Wird ein Status auf GitHub geändert, verschwindet das Issue beim nächsten Laden weiterhin ohne Hinweis. Bewusst nicht im Umfang.
- **Teilen-Erweiterung ohne Tests:** Aufbau und Bestätigung sind nur über die Geräteprüfung abgesichert; die Regeln liegen deshalb in TagwerkCore (S1).
- **Zweiter Name aus ChatGPT:** Das Modell kann `shopping_name` leer lassen oder unglücklich übersetzen („Sahne“/„cream“ ist mehrdeutig). Leere Werte fallen auf den Rezeptnamen zurück; das Ergebnisblatt zeigt beide Namen vor dem Hinzufügen. Dubletten gegen die Liste werden nur über den Listennamen erkannt; ein englischer Altartikel auf einer nun deutschen Liste wird nicht als derselbe erkannt.
- **Überschneidung mit #232:** Beide Arbeiten lesen `RecipeLanguage`; L4 ändert `RecipeImporter`, Block A nicht. Konflikte sind nur in `RecipeSheets.swift` denkbar, falls Block A dort Einstiege ergänzt.
- **Kontrast in der Breite:** Rund 370 Stellen; das Ersetzen ist mechanisch, aber die Unterscheidung Text/Symbol/Fläche verlangt je Stelle einen Blick. Dunklere Texte verändern den Eindruck der App; die Sichtprüfung in Z1 ist Teil der Abnahme. Der Audit arbeitet am gerenderten Bild nach einem nicht dokumentierten Verfahren: Rechnerisch bestandene Paare können weiter gemeldet werden (K5, Schritt 3).
- **Akzentfarbe als Asset** wirkt auf alle Systemsteuerelemente (Schalter, Picker, Links); Weiß auf dem gefüllten Knopf im Dunkeln bleibt rechnerisch unter 4,5 und voraussichtlich Ausnahme.
- **Merge-Reihenfolge:** K gegen alle; wird K vor T oder L gemessen, ist die Ausgangsmessung für die umgezogenen Einstellungsseiten wertlos.
- **Laufzeit der UI-Tests:** Zwei neue Audit-Bildschirme (Siri, Sprachen) und ein Suchtest verlängern die Stufe; die Audits sind zeitabhängig (Regel: zwei volle Läufe vor dem Merge von K).
