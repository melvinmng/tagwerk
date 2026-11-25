# Designgruppe 2 „Notizen, Routinen und Persönliches“ (#188), Teil 1: Notizen – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Stand 20.11.2026, nach den Entscheidungen des Nutzers (drei Kommentare „Entscheidungen zur Designgruppe 2 …“ und „… Notiz-Erweiterungen und Bible Study“ in #188). Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Code-Stand der Befunde: `547a88b` (Branch `chore/fable-open-items`). Aussagen über das Verhalten von WebKit, `TextEditor`, VisionKit, PencilKit und iCloud sind Annahmen aus der Dokumentation und stehen jeweils als Geräteprüfung mit Rückfallregel im Plan.

**Dieser Plan hat zwei Dateien:**

- **Teil 1 (diese Datei):** Kopf für beide Teile (Entscheidungen, Global Constraints, Abgrenzung, Review Focus, Stränge, Reihenfolge, offene Fragen, Risiken) und die Notiz-Stränge **NF** (Ordner und Liste), **NE** (Editor, Markdown, Anhänge), **NS** (Sperren), **NX** (Scannen, Zeichnen, Tabellen).
- **Teil 2:** `2026-11-20-g2-routinen-persoenliches.md` mit den Strängen **RO** (Routinen), **BS** (Bible Study), **GW** (Gewohnheiten), **DS** (Datensicherung), **EK** (Einkauf und Rezept), **TB** (Tagebuch-Import) und der Geräteprüfung **Z1**.

**Goal:** Die entschiedenen Varianten der Gruppe 2 umsetzen: Ordneransicht mit benannten Abschnitten, eigenen Farben und schnellem Brain Dump (NO1–NO8), Dankbarkeit als Kopfkarte und als eigener Listeneintrag (NO13, NO14), Schreiben durch Tippen in die Ansicht mit Formatierungsleiste (NO15–NO18), eine gemeinsame Sperre für Notizen und private Ordner (NO10c, NL), Scannen, Zeichnen und Tabellen-Editor (SC, ZE, TX), dazu in Teil 2 Routinen (RO), Bible Study mit Versauswahl und Erinnerung (BS, BV, BE), Gewohnheiten (GW), Datensicherung (DS), Einkauf (EK) und Notion-Import (TB).

**Architecture:** Zehn Stränge auf eigenen Branches, höchstens drei gleichzeitig. Regeln liegen als reine Funktionen in `TagwerkCore` (Abschnitte der Ordneransicht, Datumsgruppen, Zeilenzuordnung der Ansicht, Markdown-Formatierung, Tabellen, Schutzregel, Bibelstellen, Erinnerungsplan, Sicherungsstatus); Views bleiben dünn. Neue gespeicherte Werte sind zusätzliche Attribute mit Standardwert (leichte SwiftData-Migration). Die Notiz bleibt reines Markdown: Scan, Zeichnung und Tabelle stehen als Verweis bzw. Markdown-Tabelle im Text. Die gerenderte Ansicht bleibt eine `WKWebView` ohne JavaScript; alles Antippbare ist ein Link mit eigenem Schema, den die App auswertet. Die Sperre ist eine Sichtsperre (LocalAuthentication), keine Verschlüsselung, und erweitert die Privat-Regel aus #173 um eine dritte Bedingung.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, XCUITest, swift-markdown, WebKit, LocalAuthentication, VisionKit, Vision, PDFKit, PencilKit, CryptoKit/CommonCrypto, UserNotifications, String Catalogs (Deutsch als Quellsprache, Englisch).

**Grundlagen:** Issue #188 samt Kommentaren; Mockups `docs/superpowers/mockups/2026-11-20-g2-notizen-routinen-mockups.html`, `…-g2-routinen-gewohnheiten-sicherung-mockups.html`, `…-g2-notizen-erweiterungen-mockups.html` (gewählte Varianten und Abschnitt „Technische Randbedingungen“); Pläne `2026-11-20-decisions-173.md`, `2026-11-20-notes-chatgpt.md`, `2026-11-20-g3-system-anbindungen.md`.

**Nicht in diesem Plan:**

- NO9 Tags, NO11 gemeinsames Bearbeiten, BS3 Leseplan (#239), GW5 Import der Notion-Historie, DS2 Chatverlauf sichern, RO2 Bewertung im Dream Log, RO16 Epics: abgelehnt bzw. zurückgestellt.
- NO5a, NO19a, TB2a, TB3a, DS3, DS5, RO13, RO14a: Ist-Zustand, nichts zu bauen (NO5a: nur der veraltete Kommentar in `NoteRecord.swift:24` wird in NF1 bereinigt).
- Zeichenblock im Text (ZE1b) und Bearbeiten in der Ansicht (TX1c): setzen einen neuen Editor voraus.
- Alles aus `2026-11-20-decisions-173.md`, `2026-11-20-notes-chatgpt.md` und `2026-11-20-g3-system-anbindungen.md` (Abschnitt „Abgrenzung“).

## Entscheidungen (aus #188, 20.11.2026)

| Bereich | Entschieden | Folge für die Umsetzung | Strang |
|---|---|---|---|
| Ordneransicht | NO1b, NO2b, NO3b, NO3c, NO4 ja, NO5a | Abschnitte „Meine Ordner“, „Routinen“, „Persönlich“; Symbole und Farben je Routine-Ordner; Plus-Knopf in der Zeile „Brain Dump“; Halten auf dem Tab „Aufgaben“ (unter Vorbehalt, siehe offene Frage 1); „Namen zurücksetzen“. | NF |
| Notizliste | NO6b, NO7b, NO8b, NO19a | Kopfhinweis und Löschdatum in „Zuletzt gelöscht“; ein Menü „⋯“ mit Richtung und Datumsgruppen; Zähler, „Alle auswählen“, „Anheften“. | NF |
| Dankbarkeit | NO13b, NO14 ja | Kopfkarte statt grauer Zeile; Tage nur mit Dankbarkeit als Listeneintrag ohne `NoteRecord`. | NF |
| Editor | NO15b, NO16b, NO17 ja, NO18b | Tipp in die Ansicht schreibt an dieser Zeile, „Fertig“ zeigt; Leiste mit sechs Knöpfen; Typografie; Bildhöhe höchstens 40 %, Datei-Chips. | NE |
| Sperren | NO10c, NO12 erweitert, NL1a–NL6a | Eine Sperre für gesperrte Notizen und private Ordner; Menü und Kontextmenü; Titel sichtbar; Suche nur im Titel; Face ID, sonst Gerätecode; Sicherung unverändert. **Gesperrte Notizen gehen nie an ChatGPT, auch nicht entsperrt.** | NS |
| Scannen | SC1a, SC2c, SC3b | Gruppiertes Einfügen-Menü; eine PDF mit Vorschau der ersten Seite; Text unsichtbar durchsuchbar, Einfügen auf Wunsch. | NX |
| Zeichnen | ZE1a, ZE2b, ZE3c | Vollbild-Zeichenfläche; Bild und Strichdaten; Großansicht mit „Bearbeiten“. | NX |
| Tabellen | TX1b, TX2c, TX3b, TX4b | Raster-Editor als Blatt; aus Ansicht und beim Schreiben; Leiste über der Tastatur; Umbruch bis 200 pt, dann seitlich scrollen. | NX |
| Einkauf | EK1b, EK2a, EK3b, EK4b | Teil 2. | EK |
| Tagebuch | TB1b, TB2a, TB3a, TB4b, TB5a | Teil 2 (TB1b im Strang RO, Import im Strang TB). | RO, TB |
| Bible Study | BS1b, BS2b (mit Ergänzung), BS4 ja, BS5b, BS6c, BV1b, BV2b, BV3a, BE1c, BE2b, BE3b | Teil 2. | BS, RO |
| Gewohnheiten | GW1c, GW2a, GW3b, GW4b, Fußtext | Teil 2. | GW |
| Datensicherung | DS1b, DS4b, DS6b, DS7c (verborgen im Sicherungsordner) | Teil 2. | DS |
| Routinen | RO1b, RO3b, RO4 ja, RO5b, RO6b, RO7b, RO8b, RO9c, RO10a, RO11b, RO12b, RO15b | Teil 2. | RO |

## Global Constraints

- **Texte:** Deutsch im Quelltext, Englisch im Katalog. **Jeder Task trägt seine neuen und geänderten Zeichenketten selbst ein** (`scripts/sync-strings.sh`, dann Englisch in `scripts/translations/en.json` und `scripts/apply-translations.py`), sonst wird `app/test-all.sh` in der Stufe „string catalogs“ rot. Ändert ein Task einen deutschen Text, entfällt der alte Schlüssel in `en.json`. Deutsche UI-Texte folgen GH6b („Projekt/Projekte“).
- **Privates verlässt das Gerät nie:** `NoteKind.isPrivate` und private Ordner samt Unterordnern, auch wenn der Ordner gesperrt oder entsperrt ist. **Gesperrte Notizen** (`NoteRecord.isLocked`) gehen nicht an ChatGPT, solange sie gesperrt sind; entsperrt (Sitzung offen, Schalter „Mit Face ID schützen“ an) kann der Assistent sie lesen und ändern, bis der Nutzer Tagwerk verlässt oder die Sperre schließt (Entscheidung vom 22.11. in #188). Die Prüfung bleibt die eine reine Funktion `NoteFolderRules.mayLeaveDevice`; die Sitzung fließt als `isLocked: NoteProtection.holdsBack(…)` hinein (`NoteStore.lockHoldsBack`). In der App wählt weiterhin nur `NoteToolAccess` Notizen für ChatGPT aus. Kein Strang baut eine zweite Prüfung.
- **Kein Notiztext in Logs, Fehlermeldungen, Diagnosen.** Erkannter Text aus Scans (SC3b) gehört zum Anhang und geht nie an ChatGPT, solange er nicht in den Notiztext eingefügt wurde. Dankbarkeit ohne Notiz (NO14) geht nie an ChatGPT.
- **Ansicht ohne JavaScript:** `allowsContentJavaScript` bleibt `false`, die Content Security Policy und die Blockregeln bleiben. Kein Task ruft `evaluateJavaScript` auf oder fügt ein `WKUserScript` hinzu. Antippbares ist ein Link mit einem Schema, das nur `NoteMarkdownView.Coordinator` auswertet.
- **Notiz bleibt Markdown:** Jede Formatierung, Tabelle und jeder Anhang ist Text. `MarkdownText.attachmentIDs` bleibt die einzige Quelle für „welcher Anhang gehört zur Notiz“.
- **SwiftData:** Neue Attribute haben einen Standardwert oder sind optional (Schemaregel in `NoteRecord.swift:6–7`). Neue Felder in `BackupDTOs.swift` sind optional, damit ältere Sicherungen lesbar bleiben; `BackupRules.schemaVersion` steigt nur in DS3 (verschlüsselter Umschlag), nicht für neue optionale Felder.
- **Mitteilungen:** iOS hält 64 ausstehende Mitteilungen je App. Neue Aufteilung nach diesem Plan (gegenüber Strang E von #173 mit 46/14/1/3): **Aufgaben und Deadlines 44, Routinen 17 (Abend 12, Tagesstart 1, Wochenplanung 1, Bible Study 3), Fokus 1, Reserve 2**; Summe 64 (`NotificationBudgetTests`). Begründung in Teil 2, Task BS7.
- **Farben:** Neue Farben sind benannte Farbsets in `app/Tagwerk/Assets.xcassets` mit hellem und dunklem Wert und werden nur über `Color("…")`-Konstanten in einer Datei je Bereich angesprochen (`NoteFolderTint`, `HabitMarkerTint`). Keine neue `.foregroundStyle(.secondary)`-Stelle mit eigener Deckkraft, keine Systemfarbe als Schriftfarbe auf getöntem Grund. Strang K von G3 läuft zuletzt und misst diese Stellen mit; liegt `Design/Colors.xcassets` dann schon auf `main`, kommen die Farbsets dorthin.
- **Trefferflächen:** Jeder neue Knopf hat mindestens 44 × 44 pt (`frame(minWidth: 44, minHeight: 44)` plus `contentShape`), auch in Zeilen und Leisten.
- Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch. Commits im Stil `feat: …`/`fix: …`, ohne Hinweis auf KI, ohne Co-Authored-By. Branches ohne Präfix `claude/`.
- Neue Parameter haben Standardwerte; bestehende Aufrufer und Tests bleiben gültig.
- **Höchstens drei Umsetzer gleichzeitig**; Simulatoren nach dem Lauf löschen. Kein Umsetzer ändert GitHub-Issues oder `TODO.md`.

**Testbefehle** (wie in `2026-11-20-g3-system-anbindungen.md`):

- `PKG <Paket> <Suite>` = `cd app/Packages/<Paket> && xcodebuild test -testLanguage de -testRegion DE -scheme <Paket> -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:<Paket>Tests/<Suite>`
- `APP <Suite>` = `cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>`
- `UI <Klasse>` = wie `APP`, mit `-scheme TagwerkUITests -only-testing:TagwerkUITests/<Klasse>`
- `ALL` = `app/test-all.sh`, erwartet `ALL TESTS PASSED`.

## Abgrenzung zu laufenden Arbeiten

| Laufende Arbeit | Dateien dort | Berührung hier | Regel |
|---|---|---|---|
| `2026-11-20-notes-chatgpt.md`, Block A (#232, umgesetzt auf `feat/recipe-translate`) | `NoteEditorView.swift` (A5: `lastSavedText`, `saveText()`, `adoptStoredText()`, `.onChange(of: store.revision)`), `NoteEditorSync.swift`, `NoteAttachmentStore.swift`, `NoteStore.swift` | NE3 baut den Editor um; NS, NX und BS4 hängen sich an | **Strang NE beginnt erst, wenn Block A auf `main` ist.** Jede Schreibstelle des Editors geht weiter über `saveText()`; `adoptStoredText()` bleibt die einzige Stelle, die Text von außen übernimmt. NE3 verschiebt Code nur in Erweiterungsdateien, ohne A5 umzuschreiben (Test `NoteEditorSyncTests` bleibt unverändert grün). |
| `2026-11-20-notes-chatgpt.md`, Block B (#233, später) | `NoteEditorView` (B9: Einstieg „Mit ChatGPT bearbeiten“), `NoteChatTools`, `NoteToolAccess` | NE3 (Menü), NS (Regel) | B9 setzt auf den Menüaufbau aus NE3 auf (`NoteEditorView+Menu.swift`) und nutzt für die Sichtbarkeit `NoteStore.isPrivate`; die Sperre ist dort dann schon enthalten. `update_note` verlangt gleiche Anhang-IDs: Scans, Zeichnungen und ihre Begleitdateien (NX2) erben das ohne Zusatz, weil nur die Verweise im Text zählen. |
| `2026-11-20-decisions-173.md`, Strang B (Tasks 3, 4, 4a, 4b; in Umsetzung auf `feat/assistant-assign-and-search`) | `NoteFolderRules.privateFolderIDs`, `mayLeaveDevice`, `NoteStore.isPrivate`, `NoteToolAccess`, `RecipeNotePicker.swift:34`, `AssistantModel.endNoteSession()` | NS1 erweitert `mayLeaveDevice` und `NoteStore.isPrivate` | **Strang NS beginnt erst, wenn Strang B von #173 auf `main` ist.** NS1 ergänzt einen Parameter mit Standardwert und baut nichts neu. Ist Strang B zum Start von NS wider Erwarten nicht gemergt, wartet NS; eine eigene Privat-Regel ist ausgeschlossen. |
| `2026-11-20-decisions-173.md`, Strang E (Tasks 10, 11; in Umsetzung auf `feat/evening-reminders-per-day`) | `RoutineSchedule` (`DatedRoutineNotification`, `eveningNotifications`), `NotificationBudget`, `RoutineNotificationScheduler` (`addDated`, `itemChecked`), `RoutineSettingsView` | BS7 (Bible-Study-Erinnerung), RO4 (vierter erinnernder Punkt) | **BS7 und RO4 beginnen erst, wenn Strang E auf `main` ist**, und nutzen `DatedRoutineNotification` und `addDated`. Budgetzahlen ändert nur BS7. |
| `2026-11-20-g3-system-anbindungen.md`, Strang T | `EveningSheet`, `MorningSheet` (Blattknopf „Abschließen“), `KeyboardDismissal.swift`, `SettingsView` | RO1, RO3 (beide Blätter), NE4 (Leiste über der Tastatur) | RO beginnt nach dem Merge von T oder rebased darauf; der Knopf „Abschließen“ bleibt. NE4 ersetzt im Notizeditor `.keyboardDoneButton()` durch die eigene Leiste; der Knopf ⌄ nutzt `AccessibilityID.Common.hideKeyboard`, falls T1 schon auf `main` ist. |
| G3, Strang L (L4: `RecipeImporter.swift`, `RecipeSheets.swift`) | zweiter Name je Zutat | EK2, EK3 (dieselbe Datei `RecipeSheets.swift`) | Strang EK beginnt nach dem Merge von L. |
| G3, Strang U (U2: „Im Ordner zeigen“) | `SearchSheet.swift`, `RootView.swift` | NS4, NF5 (Suchzeilen) | Verschiedene Stellen; der Sprung in einen gesperrten Ordner landet auf dem Sperrbildschirm (NS3). |
| G3, Strang K (Kontrast, zuletzt) | alle Views mit Farben | NF1, GW2 und alle neuen Views | Benannte Farben (Global Constraints); K rebased zuletzt. |
| Designgruppe 1 (Planen; Plan folgt) | `Planning/DayView.swift` (`CapacityCard`, Karten oben) | RO7, RO8 (Zeile in der Kapazitätskarte, Karte „Wochenplanung“) | RO7 und RO8 sind die letzten Tasks von RO und werden mit dem G1-Plan abgestimmt, sobald er vorliegt (offene Frage 9). |

## Review Focus

1. **Gesperrt heißt privat, solange gesperrt (geändert am 22.11.):** Eine Notiz mit `isLocked` erreicht ChatGPT auf keinem Weg, solange sie nicht entsperrt ist: nicht über `NoteToolAccess` (`search`, `read_note`, später `list_notes`/`update_note`), nicht über „Vorschläge holen“, nicht über die Rezeptauswahl, nicht über „Rezept übersetzen“. Entsperrt (Sitzung offen) stehen diese Wege offen, bis die Sperre schließt (App im Hintergrund, „Jetzt sperren“, Schutz aus); dann endet die Notiz-Sitzung des Assistenten (`NoteLock.onSessionClosed`). Bei ausgeschaltetem Schalter oder ohne Code lässt sich nichts entsperren, die Notiz bleibt zurückgehalten; das gilt auch nach einer Wiederherstellung. Private Arten und Ordner bleiben immer ausgeschlossen. → NS1 (`lockedNote_whileLocked_reachesNoOutboundPath`, `lockedNote_whileUnlocked_isOpenToTheAssistant_untilTheSessionEnds`, `lockedNote_isPrivateOnlyWhileTheSessionIsClosed`, `lockSwitchOff_stillPrivate`, `unlockedNote_isOpenToTheAssistant_untilTheLockCloses`).
2. **Sperre sperrt wirklich:** Verborgen sind Vorschautext, Vorschaubild, Anhang-Zähler, Volltexttreffer (App-Suche und Suchfeld der Liste), erkannter Scan-Text und der Inhalt im App-Umschalter. Nach dem Wechsel in den Hintergrund ist alles wieder zu. Ohne Gerätecode ist nichts gesperrt und die Einstellungen sagen das. → NS2–NS4.
3. **Zeilenzuordnung (NO15b):** Ein Tipp auf Text der Ansicht setzt die Schreibmarke ans Ende genau der Quellzeile; Checkbox, Link, Anhang und Tabelle schalten nicht ins Schreiben; Scrollen löst nichts aus. Die Rückfallregel ist gebaut und die Geräteprüfung dokumentiert, welche Stufe gilt. → NE2, NE3, Z1.
4. **A5 bleibt heil:** Text, der von außen geändert wird, während der Editor offen ist, wird übernommen; eigene Änderungen (Formatierungsleiste, Tabelle, Scan, Zeichnung, Checkbox, Sitzungsüberschrift) laufen über `saveText()` und lösen kein „Übernehmen“ aus. → NE3 (`formattingAction_isOwnSave`).
5. **Tage nur mit Dankbarkeit (NO14):** Der Eintrag entsteht aus `RoutineDayRecord`, es wird nie ein `NoteRecord` dafür angelegt; er lässt sich nicht anheften, bewegen, auswählen oder löschen; er ist in der App-Suche auffindbar, nie beim Assistenten; nach einer Wiederherstellung ist er da. → NF4, NF5.
6. **Anhänge gehen nicht verloren:** `removeUnreferenced` und `purgeOrphans` löschen die Strichdaten einer Zeichnung nur zusammen mit ihrem Bild; eine Sicherung mit Scan und Zeichnung stellt beide vollständig wieder her; das Ersetzen einer Zeichnung behält die ID. → NX2, NX5.
7. **Tabellen verlustfrei:** Lesen und Zurückschreiben einer Tabelle ändert außerhalb des Tabellenblocks kein Zeichen; senkrechte Striche in Zellen sind maskiert; Tabellen über 8 Spalten öffnet das Blatt nicht. → NX6.
8. **Verszahlen belegt (BV3a):** Die Tabelle nennt ihre Quelle und das Abrufdatum, ist gegen eine zweite Quelle geprüft, und die Tests für die Abweichungen zur englischen Zählung stammen aus der Quelle, nicht aus dem Gedächtnis. → Teil 2, BS1.
9. **Budget:** Summe 64; Bible Study plant höchstens drei Mitteilungen; an einem Tag mit abgeschlossener Sitzung oder „Heute nicht“ steht keine aus. → Teil 2, BS7.
10. **Passwort (DS6b):** Ohne das richtige Passwort wird nichts entschlüsselt und nichts ersetzt; die Seite warnt vor dem Einschalten; der Schlüssel liegt nur im Schlüsselbund dieses Geräts; eine unverschlüsselte Sicherung bleibt lesbar. → Teil 2, DS3.
11. **DS7c im Sicherungsordner:** Sicherheitskopien liegen verborgen in `.Sicherheitskopien` im gewählten Sicherungsordner (z. B. iCloud Drive), ohne neue Berechtigung; ohne Sicherungsordner wie heute. DS0 entfällt. → Teil 2, DS4.
12. **Farben benannt, Trefferflächen 44 pt.** → NF1, NF2, GW2.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `Notes/NotesFoldersView.swift:28–63, 115–132, 172–192` | Vier Abschnitte, nur „Ordner“ hat eine Überschrift; „Brain Dump“ und „Rezepte“ im ersten Abschnitt; neue Brain-Dump-Notiz nur über Wischen und Kontextmenü; Symbole alle in `.tint`; „Dream Log“ `moon.zzz`. |
| `Notes/NotesListView.swift:96–119, 223–243, 247–292` | `EditButton` und Sortiermenü (drei Werte, eine Einstellung `noteSortOrder`); Auswahl mit „Bewegen“ und „Löschen“; Karte mit Titel, Vorschau, Fußzeile, 48-pt-Bild, Büroklammer. Routine-Ordner zeigen nur `NoteRecord`. |
| `Notes/NoteEditorView.swift:16, 43–57, 86–90, 115–144` | Modi `.view`/`.edit`, Umschalter Auge/Stift, Anhängen-Menü oben und über der Tastatur; `gratitudeHeader` als graue Zeile; Schreiben in `TextEditor(text:selection:)`. Auf `feat/recipe-translate` zusätzlich A5 (`saveText`, `lastSavedText`, `adoptStoredText`). |
| `Notes/NoteMarkdownView.swift:29–35, 136–153, 161–181` | `WKWebView` ohne JavaScript; die Navigation lässt nur `tagwerk-toggle:`, `attachment:`, Web-, Mail- und Telefon-Links durch; `AttachmentSchemeHandler` liefert nur Bilder. |
| `TagwerkCore/NoteHTMLRenderer.swift:13–16, 92–231` | `BodyVisitor` über swift-markdown; `toggleScheme`; Tabellen mit Ausrichtung; kein Bezug zur Quellzeile. |
| `TagwerkCore/MarkdownText.swift:50–105` | Anhang-Verweise, `togglingCheckbox(at:in:)`; keine Formatierungs- und keine Tabellenfunktionen. |
| `Notes/NoteAttachmentStore.swift:14–17, 45–81, 111–136, 190–208` | `addImage` speichert JPEG (2048 px), `addFile(at:)` nur von einer URL, `store(…)` privat; eine Datei je Eintrag; `removeUnreferenced`, `purgeOrphans`; `cardInfo` zählt PDF als Datei ohne Vorschaubild. Ordner `Application Support/NoteAttachments`. |
| `Notes/NoteAttachmentRecord.swift` | Felder `id`, `noteID`, `fileName`, `typeIdentifier`, `byteCount`, `createdAt`. |
| `Notes/NoteRecord.swift` | Kein Feld für eine Sperre; Kommentar in Zeile 24 nennt noch den virtuellen Ordner „Gedanken“. |
| `TagwerkCore/NoteFolderRules.swift:23–29`, `NoteText.swift:14–18` | `NoteFolderRole.isPrivate` (Tagebuch, Bible Study, Dream Log), `NoteKind.isPrivate`. `privateFolderIDs`, `mayLeaveDevice`, `NoteStore.isPrivate`, `NoteToolAccess` gibt es auf diesem Stand noch nicht (#173 Task 3). |
| Sperre | Kein `LocalAuthentication` im Code; `project.yml` hat keinen Eintrag `NSFaceIDUsageDescription`. |
| `App/AppEnvironment.swift:515–520` | `searchItem(for:folderNames:)` baut `NoteSearchItem` aus dem ganzen Text; `NoteSearchItem` hat `id`, `text`, `kindLabel`, `updatedAt`, `dayKey`. |
| `Routines/RoutineRecords.swift:14, 175–189` | Dankbarkeit liegt in `RoutineDayRecord.gratitudeData`; `RoutineStore.day(_:)` liest einen Tag, eine Abfrage „alle Tage mit Dankbarkeit“ fehlt. `RoutineDayBackup` (`BackupDTOs.swift:868`) sichert den Tageseintrag. |
| `App/RootView.swift:49–74` | `TabView` mit `Tab("Aufgaben", …, value: 1)`; SwiftUI bietet für Tab-Einträge kein Kontextmenü. |
| `Settings/NotesSettingsView.swift` | 37 Zeilen: Sortierung und Notion-Import. |

## Stränge, Branches und Dateien

Pfade relativ zu `app/Tagwerk/`, Paketdateien mit `TagwerkCore/…` = `app/Packages/TagwerkCore/Sources/TagwerkCore/…`. **Neu** fett.

| Strang | Branch | Tasks | Dateien |
|---|---|---|---|
| **NF** Ordner und Liste | `feat/g2-notes-folders-list` | NF1–NF5 | **`TagwerkCore/NoteFolderSections.swift`**, **`TagwerkCore/NoteDateGroups.swift`**, **`TagwerkCore/RoutineFolderEntries.swift`**, `TagwerkCore/Search/SearchResults.swift` (ein Feld), `Notes/NotesFoldersView.swift`, **`Notes/NoteFolderTint.swift`**, `Notes/NotesListView.swift`, **`Notes/NotesListView+Selection.swift`**, **`Notes/GratitudeCard.swift`**, **`Notes/MorningDayView.swift`**, `Notes/NoteStore+DefaultFolders.swift`, `Notes/NoteRecord.swift` (Kommentar), `Routines/RoutineRecords.swift`, `App/RootView.swift`, `App/AppEnvironment.swift`, `Search/SearchSheet.swift`, `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, `Assets.xcassets` |
| **NE** Editor | `feat/g2-note-editor` | NE1–NE4 | `TagwerkCore/NoteHTMLRenderer.swift`, `TagwerkCore/HTMLSanitizer.swift`, **`TagwerkCore/NoteEditTarget.swift`**, **`TagwerkCore/MarkdownFormatting.swift`**, `Notes/NoteMarkdownView.swift`, `Notes/NoteEditorView.swift`, **`Notes/NoteEditorView+Attachments.swift`**, **`Notes/NoteEditorView+Menu.swift`**, **`Notes/NoteFormattingBar.swift`**, `Notes/NoteAttachmentStore.swift` (eine Lesefunktion) |
| **NS** Sperren | `feat/g2-note-lock` | NS1–NS4 | `TagwerkCore/NoteFolderRules.swift`, **`TagwerkCore/NoteProtection.swift`**, `Notes/NoteRecord.swift`, `Notes/NoteStore.swift`, **`Notes/NoteLock.swift`**, **`Notes/LockedContentView.swift`**, **`Notes/NoteLockIntroSheet.swift`**, `Notes/NotesListView.swift`, `Notes/NotesListView+Selection.swift`, `Notes/NoteEditorView+Menu.swift`, `Notes/NoteEditorView.swift` (Sperrbildschirm, Abdeckung), `Settings/NotesSettingsView.swift`, `Routines/NoteField.swift`/`NoteSuggestionModel.swift` (eine Bedingung), `Shopping/RecipeNotePicker.swift`, `App/AppEnvironment.swift`, `App/TagwerkApp.swift`, `Search/SearchRows.swift`, `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, `Backup/BackupSettingsView.swift` (eine Zeile), `project.yml`, `InfoPlist.xcstrings` |
| **NX** Scannen, Zeichnen, Tabellen | `feat/g2-note-inserts` | NX1–NX7 | `Notes/NoteAttachmentMenu.swift` (wird **`NoteInsertMenu.swift`**), `Notes/NoteAttachmentRecord.swift`, `Notes/NoteAttachmentStore.swift`, **`Notes/DocumentScanner.swift`**, **`Notes/ScanPDFBuilder.swift`**, **`Notes/ScanTextRecognizer.swift`**, **`Notes/DrawingCanvasView.swift`**, **`Notes/DrawingViewer.swift`**, **`Notes/TableEditorSheet.swift`**, **`TagwerkCore/MarkdownTable.swift`**, `TagwerkCore/NoteHTMLRenderer.swift`, `TagwerkCore/Search/…` (Feld „Im Scan“), `Notes/NoteMarkdownView.swift`, `Notes/NoteEditorView+Attachments.swift`, `Notes/NoteFormattingBar.swift`, `Notes/NotesListView.swift` (Vorschaubild), `App/AppEnvironment.swift`, `Backup/BackupDTOs.swift` |
| **RO, BS, GW, DS, EK, TB** | siehe Teil 2 | | |

**Gemeinsam berührte Dateien (beide Teile):**

| Datei | Stränge | Art |
|---|---|---|
| `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift` | NF, NS, NX (nur DTO), BS, DS, RO, GW | Anfügen am Blockende; Konflikte sind Nachbarzeilen. Zweiter Merge löst von Hand. |
| `Localizable.xcstrings`, `scripts/translations/en.json` | alle | Beim Rebase `scripts/sync-strings.sh` und `apply-translations.py` neu laufen lassen statt Konflikte von Hand zu lösen. |
| `Notes/NoteEditorView.swift` und Erweiterungsdateien | NE (Umbau), danach NS (Sperrbildschirm, Menü), NX (Einfügen), BS4 (Sitzungsleiste) | **NS, NX und BS4 beginnen erst nach dem Merge von NE.** Nach NE3 fügt jeder Strang höchstens einen Modifier in `NoteEditorView.swift` selbst hinzu, der Rest steht in der eigenen Datei. NS und NX laufen parallel; der zweite Merge löst das Menü von Hand. |
| `Notes/NoteMarkdownView.swift`, `TagwerkCore/NoteHTMLRenderer.swift` | NE (Zeilenlinks, Typografie, Chips, Kontextmenü-Haken), NX (Scan-Karte, Tabellen-Link, Zeichnung), BS5 (Marke „→ Aufgabe“) | NX und BS5 nach NE; verschiedene Funktionen. |
| `Notes/NotesListView.swift` | NF (Umbau), NS (Karte, Sperrbildschirm), NX (Vorschaubild für PDF), BS4 (Zeile offener Sitzungen), TB (Zeile im leeren Ordner) | **NF zuerst.** Die anderen ändern je eine Stelle. |
| `Notes/NoteAttachmentStore.swift` | NE (liest), NX (erweitert), NS (liest) | NX ist der einzige schreibende Strang. |
| `App/AppEnvironment.swift` | NF (Suche: Dankbarkeit), NS (Suche: Titel), NX (Suche: Scan), BS (Planer), DS | Verschiedene Funktionen; `searchItem(for:)` ändern NF, NS und NX nacheinander. |
| `Routines/RoutineSettingsView.swift` | RO3, RO4, BS6 | RO vor BS6. |
| `Routines/EveningSheet.swift`, `MorningSheet.swift` | nur RO | TB1b und BS6c (Platz der Zeilen) werden in RO3 gebaut, damit nur ein Strang die Blätter anfasst. |
| `Backup/BackupSettingsView.swift` | DS (Umbau), NS (Zeile „Gesperrte Notizen“) | NS fügt die Zeile in die Form ein, die zum Zeitpunkt seines Rebase gilt. |
| `project.yml` | NS (`NSFaceIDUsageDescription`), DS3 (Dateityp `.tagwerk`) | Verschiedene Schlüssel. |
| `Assets.xcassets` | NF1, GW2 | Je eigene Farbsets. |

## Reihenfolge und Abhängigkeiten

```
Voraussetzungen auf main:  #232 Block A (für NE) · #173 Strang B (für NS) · #173 Strang E (für BS7, RO4)
                           G3 Strang T (für RO) · G3 Strang L (für EK)

NF Ordner, Liste:   NF1 ─► NF2 ─► NF3 ─► NF4 ─► NF5
NE Editor:          NE1 ─► NE2 ─► NE3 ─► NE4
NS Sperren:                       (nach NF, NE, #173 B)   NS1 ─► NS2 ─► NS3 ─► NS4
NX Einfügen:                      (nach NE)               NX1 ─► NX2 ─► NX3 ─► NX4 ─► NX5      NX6 ─► NX7
RO Routinen:        RO1 ─► RO2 ─► RO3 ─► RO4 (nach #173 E) ─► RO5 ─► RO6 ─► RO7 ─► RO8
BS Bible Study:     BS1 ─► BS2 ─► BS3 ─► BS4 (nach NE) ─► BS5 (nach NE) ─► BS6 (nach RO3) ─► BS7 (nach #173 E) ─► BS8
GW Gewohnheiten:    GW1 ─► GW2 ─► GW3
DS Datensicherung:  DS1 ─► DS2 ─► DS3 ─► DS4
EK Einkauf:         EK1      EK2 ─► EK3 (nach G3 L)
TB Import:          TB1 ─► TB2
Abschluss:          Z1 (Geräteprüfung, Hauptsitzung mit Nutzer)
```

**Wellen mit höchstens drei Umsetzern:**

| Welle | Parallel | Bedingung |
|---|---|---|
| 1 | **NE**, **NF**, **BS (nur BS1 und BS2)** | Block A auf `main`. BS1 ist eine Rechercheaufgabe ohne Überschneidung, BS2 reine Regeln in `TagwerkCore`. |
| 2 | **NS**, **NX**, **RO** | NE und NF gemergt; #173 Strang B (für NS) und Strang E (für RO4) auf `main`; G3 T gemergt. NX6 kann innerhalb von NX vorgezogen werden (reine Regeln). |
| 3 | **BS (BS3–BS8)**, **DS**, **GW** | NE und RO3 gemergt, #173 E auf `main`. |
| 4 | **EK**, **TB** | G3 L gemergt (EK2, EK3). |
| 5 | **Z1** | alles gemergt; danach G3 Strang K. |

- **Merge-Reihenfolge:** NF, NE; dann NX, NS (der zweite löst `NoteEditorView+Menu.swift` und `NotesListView.swift` von Hand); RO; BS; GW; DS; EK; TB. Jeder Strang ist ein Pull Request; ein Strang darf in mehrere aufeinanderfolgende Pull Requests geteilt werden (NE1–NE2 vor NE3–NE4, BS1–BS2 vor dem Rest).
- Ist eine Voraussetzung nicht auf `main`, wird der abhängige Task zurückgestellt, nicht umgangen.
- Die Hauptsitzung prüft jeden Pull Request gegen den Review Focus.

---

## Strang NF: Notizen-Ordner und Liste

### Task NF1: Abschnitte der Ordneransicht, Symbole und Farben, „Namen zurücksetzen“ (NO1b, NO2b, NO4, NO5a)

**Files:**
- Create: `TagwerkCore/NoteFolderSections.swift`, `app/Tagwerk/Notes/NoteFolderTint.swift`, Farbsets `FolderBrainDump` (Violett), `FolderMorning` (Orange), `FolderEvening` (Indigo) in `Assets.xcassets`
- Modify: `Notes/NotesFoldersView.swift:23–63, 105–192`, `Notes/NoteStore+DefaultFolders.swift`, `Notes/NoteRecord.swift:24` (Kommentar ohne „Gedanken“), Kataloge
- Test: neu `TagwerkCoreTests/NoteFolderSectionsTests.swift`, `app/TagwerkTests/NotesListTextTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/NoteFolderSections.swift
/// The sections of the notes entry page in display order (mockup NO1b).
public enum NoteFolderSections {
    public enum Kind: Sendable, Equatable { case own, routines, personal }
    public struct Section: Sendable, Equatable { public let kind: Kind; public let folders: [NoteFolderNode] }
    /// The system folders shown in the first, unnamed section next to "Alle Notizen" and "Notizen".
    public static let pinnedRoles: [NoteFolderRole] = [.recipes]
    public static let routineRoles: [NoteFolderRole] = [.brainDump, .morningRoutine, .eveningRoutine, .dreamLog]
    public static let personalRoles: [NoteFolderRole] = [.journal, .bibleStudy]
    /// "Meine Ordner" (flattened tree of the user's folders, may be empty), "Routinen" and "Persönlich" in the fixed
    /// order of their roles. A missing system folder is simply left out; the view adds the placeholders.
    public static func sections(_ tree: [NoteFolderNode]) -> [Section]
}

// Notes/NoteFolderTint.swift
enum NoteFolderTint {
    /// Named colours of the routine folders; every other folder keeps the accent colour.
    static func color(for role: NoteFolderRole?) -> Color   // brainDump: FolderBrainDump, morningRoutine: FolderMorning,
                                                            // eveningRoutine, dreamLog: FolderEvening, else .accentColor
}
// NotesFoldersView.symbol(for:): dreamLog becomes "cloud.moon"; the others stay.
// NoteStore+DefaultFolders
/// Puts the fixed name back; only offered while the name differs from `defaultFolderName(for:)`.
func resetFolderName(_ id: UUID) throws
```

Aufbau der Seite: erster Abschnitt „Alle Notizen“, „Notizen“, „Rezepte“; „Meine Ordner“ mit Plus-Knopf in der Überschrift (`startCreating(under: nil)`, 44 pt), auch wenn noch kein eigener Ordner existiert; „Routinen“; „Persönlich“ (mit den Platzhalterzeilen für Tagebuch und Bible Study wie heute); zuletzt „Zuletzt gelöscht“. Der Knopf „Neuer Ordner“ in der Leiste bleibt. Die Routinen-Blätter zeigen weiterhin die festen Bezeichnungen (`NoteField` liest keinen Ordnernamen; so lassen).

- [ ] **Step 1: Tests.** `NoteFolderSectionsTests`: `sections_orderIsOwnRoutinesPersonal`, `sections_routinesFollowFixedRoleOrder`, `sections_ownFoldersAreFlattenedWithDepth`, `sections_missingSystemFolderIsLeftOut`, `sections_recipesAndBrainDumpNotInOwn`. `NotesListTextTests`: `resetFolderName_restoresDefault`, `resetFolderName_onOwnFolder_throwsSystemFolderError` (nur für Systemordner erlaubt), `symbol_dreamLogDiffersFromEvening`.
- [ ] **Step 2:** `PKG TagwerkCore NoteFolderSectionsTests` → rot.
- [ ] **Step 3: Umsetzen.** `NotesFoldersView.systemFolders(_:)` entfällt zugunsten von `NoteFolderSections.sections`. `rowLabel` bekommt die Farbe über `NoteFolderTint`. Kontextmenü eines umbenannten Systemordners: „Namen zurücksetzen“ (`arrow.uturn.backward`). Farbsets mit hellem und dunklem Wert; Symbol gegen Listenhintergrund mindestens 3:1 (rechnerisch prüfen und im Pull Request nennen; gemessen wird in Strang K).
- [ ] **Step 4:** `ALL`. Commit `feat: group the notes folders into named sections with their own colours`.

### Task NF2: Brain Dump schnell anlegen (NO3b, NO3c)

**Files:**
- Modify: `Notes/NotesFoldersView.swift:115–132`, `App/RootView.swift:64` (nur bei bestandener Prüfung), `App/AppEnvironment.swift` (eine Funktion), Kataloge
- Test: `app/TagwerkUITests/` (bestehende Notiz-UI-Tests um einen Fall ergänzen), `app/TagwerkTests/AppRouterTests.swift`

**Interfaces:**

```swift
// AppEnvironment
/// Creates an empty note in "Brain Dump" and opens it for writing from anywhere in the app.
func openNewBrainDumpNote()
```

NO3b: Die Zeile „Brain Dump“ zeigt statt des Pfeils einen Knopf `plus` (44 × 44 pt, `accessibilityLabel("Neue Notiz in Brain Dump")`); Tipp auf die Zeile öffnet den Ordner. Wischen und Kontextmenü bleiben.

NO3c: Halten auf dem Tab „Aufgaben“ soll ein Menü zeigen: „Brain Dump schreiben“, „Brain Dump diktieren“ (`openDictatedNote()`), „Neue Notiz“. **SwiftUI kennt für `Tab` kein Kontextmenü.** Deshalb zuerst eine Prüfung mit fester Regel:

- [ ] **Step 1: Machbarkeit NO3c (höchstens 45 Minuten, Simulator iOS 27).** Versuch: ein `UILongPressGestureRecognizer` auf der `UITabBar` der `UITabBarController`-Instanz hinter der `TabView` (über einen kleinen `UIViewControllerRepresentable`, der `tabBarController` liest), Treffer über den Rahmen des zweiten Eintrags; Menü als `UIMenu` über ein `UIContextMenuInteraction`. **Entscheidungsregel:** Gebaut wird NO3c nur, wenn (a) kein privater Schlüssel und keine Klassensuche per Namen nötig ist, (b) der normale Tipp und der Wechsel der Tabs unverändert bleiben, (c) es mit der Glas-Tableiste von iOS 27 im Hoch- und Querformat und mit großer Schrift funktioniert. Ist eine Bedingung nicht erfüllt, wird NO3c **nicht** gebaut; der Befund kommt in den Pull Request und offene Frage 1 gilt.
- [ ] **Step 2: Tests.** UI-Test `testBrainDumpPlusOpensEmptyNoteForWriting` (Tipp auf Plus: Editor offen, Tastatur da; Zurück ohne Text: keine Notiz angelegt). `AppRouterTests.openNewBrainDumpNote_pushesNotesAndNote`.
- [ ] **Step 3:** rot, dann umsetzen. `openNewBrainDumpNote()` setzt `tasksPath = [.notes, .notesFolder(.folder(id)), .note(new.id)]` und wechselt in den Tab.
- [ ] **Step 4:** `ALL`. Commit `feat: add a plus button to the Brain Dump row` (und bei bestandener Prüfung ein zweiter Commit `feat: offer Brain Dump from a long press on the tasks tab`).

### Task NF3: Sortiermenü, Datumsgruppen, Mehrfachauswahl, „Zuletzt gelöscht“ (NO7b, NO8b, NO6b)

**Files:**
- Create: `TagwerkCore/NoteDateGroups.swift`, `Notes/NotesListView+Selection.swift`
- Modify: `Notes/NotesListView.swift:52–154, 223–243, 247–345, 434–518`, `Notes/NoteStore.swift:41–62` (Richtung), `Persistence/AppSettings.swift` (nach `noteSortOrderRaw`), `Backup/BackupDTOs.swift` (`AppSettingsBackup`), `Settings/NotesSettingsView.swift`, Kataloge
- Test: neu `TagwerkCoreTests/NoteDateGroupsTests.swift`, `app/TagwerkTests/NoteStoreTests.swift`, `NotesListTextTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/NoteDateGroups.swift
public enum NoteDateGroups {
    public enum Group: Sendable, Hashable { case pinned, today, lastSevenDays, month(year: Int, month: Int) }
    /// The group of a note by the date the list is sorted by. Pinned notes form the first group.
    public static func group(of date: Date, isPinned: Bool, now: Date, calendar: Calendar) -> Group
    /// Groups in list order for the given direction; `ids` keep the order they came in.
    public static func grouped<ID>(_ items: [(id: ID, date: Date, isPinned: Bool)], now: Date, calendar: Calendar) -> [(group: Group, ids: [ID])]
}
// AppSettings
var noteSortAscending: Bool = false          // "Älteste zuerst"; for "Titel": Z to A
var noteGroupsByDate: Bool = true
// NoteStore
func notes(_ filter: Filter = .all, sortedBy order: NoteSortOrder = .modified, ascending: Bool = false) -> [NoteRecord]
// NotesListView texts
static func trashFooter(for note: NoteRecord, folderName: String, now: Date, calendar: Calendar) -> String  // "Gelöscht am 23.10. · aus „Notizen“"
static func daysLeftText(_ days: Int) -> String                                                             // "noch 3 Tage"
static func selectionTitle(_ count: Int) -> String                                                          // "2 ausgewählt"
```

Regeln:
- Ein Menü „⋯“ (`ellipsis.circle`) ersetzt `EditButton` und den Sortierknopf: „Notizen auswählen“, „Sortieren nach“ (Bearbeitet, Erstellt, Titel), Richtung („Neueste zuerst“/„Älteste zuerst“; bei Titel „A bis Z“/„Z bis A“), Schalter „Nach Datum gruppieren“ (bei „Titel“ ausgegraut). Die Wahl gilt für alle Ordner. Routine-Ordner bleiben nach Tag absteigend und ungruppiert (ihr Titel ist schon das Datum); das Menü zeigt dort nur „Notizen auswählen“.
- Gruppenüberschriften: „Angeheftet“, „Heute“, „Letzte 7 Tage“ (gestern bis vor sieben Tagen), danach Monat und Jahr („Oktober 2026“).
- Auswahl: Titelzeile „N ausgewählt“, links „Alle auswählen“ (wechselt zu „Keine auswählen“), rechts „Fertig“; unten „Bewegen“, „Anheften“ (heftet an, wenn mindestens eine gewählte Notiz nicht angeheftet ist, sonst „Lösen“), „Löschen“. In Routine-Ordnern (`folderRole?.noteKind != nil`) entfällt „Bewegen“. Im Papierkorb bleiben „Wiederherstellen“ und „Löschen“.
- „Zuletzt gelöscht“: Kopftext „Notizen bleiben 30 Tage hier und werden dann endgültig gelöscht, mit ihren Anhängen.“ (ersetzt `trashFootnote` am Listenende); Karte mit Marke „noch N Tage“ (unter 7 Tagen in Orange als Text plus Symbol `clock`, nicht nur Farbe) und Fußzeile „Gelöscht am … · aus „Ordner““ (Ordner gelöscht: „Notizen“).

- [ ] **Step 1: Tests.** `NoteDateGroupsTests`: `group_today`, `group_yesterdayIsLastSevenDays`, `group_eightDaysAgoIsMonth`, `group_pinnedWins`, `grouped_keepsInputOrderInsideGroup`, `grouped_yearChange`, `group_summerTimeDay` (29.03.2026, Europe/Berlin). `NoteStoreTests`: `notes_ascendingReversesWithinPinnedAndUnpinned`. `NotesListTextTests`: `trashFooter_namesDateAndFolder`, `trashFooter_deletedFolderFallsBackToNotizen`, `daysLeft_singularAndPlural`, `selectionTitle_counts`. `BackupTests.settings_roundTripSortDirectionAndGrouping`, `settings_olderFileKeepsDefaults`.
- [ ] **Step 2:** Suiten rot.
- [ ] **Step 3: Umsetzen.** Die Auswahl-Leiste und ihre Aktionen wandern nach `NotesListView+Selection.swift` (die Datei hat 518 Zeilen und wächst sonst weiter). `NotesSettingsView` zeigt zusätzlich Richtung und Gruppierung.
- [ ] **Step 4:** `ALL`. Commit `feat: sort notes with a direction and date groups and select them with a counter`.

### Task NF4: Dankbarkeit als Kopfkarte und als Listeneintrag ohne Notiz (NO13b, NO14)

**Files:**
- Create: `TagwerkCore/RoutineFolderEntries.swift`, `Notes/GratitudeCard.swift`, `Notes/MorningDayView.swift`
- Modify: `Routines/RoutineRecords.swift` (neue Abfrage nach `closedDays`), `Notes/NotesListView.swift` (`visibleNotes`, `card`), `Notes/NotesFoldersView.swift` (Zähler „Tagesstart“), `Notes/NoteEditorView.swift:119, 126, 135–144` (nur der Aufruf; NE3 baut den Rest um, siehe Hinweis), `App/RootView.swift` (neuer Pfad), der Pfad-Typ von `tasksPath` (dort, wo `.note` und `.notesFolder` stehen), Kataloge
- Test: neu `TagwerkCoreTests/RoutineFolderEntriesTests.swift`, `app/TagwerkTests/RoutinesModelTests.swift` bzw. neu `RoutineStoreGratitudeTests.swift`, `NotesListTextTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/RoutineFolderEntries.swift
/// The entries of the folder "Tagesstart": a note per day and, for days that only have gratitude, an entry without a note.
public enum RoutineFolderEntry<NoteID: Hashable & Sendable>: Sendable, Hashable {
    case note(id: NoteID, day: PlanDay?)
    case gratitudeOnly(day: PlanDay)
}
public enum RoutineFolderEntries {
    /// Days descending. A day that has a live note is never listed twice; a day whose note is in the trash and that has
    /// gratitude is listed as `gratitudeOnly`.
    public static func merge<NoteID>(notes: [(id: NoteID, day: PlanDay?)], gratitudeDays: Set<PlanDay>) -> [RoutineFolderEntry<NoteID>]
    /// Notes plus days with gratitude only, for the count in the folder overview.
    public static func count(noteDays: [PlanDay?], gratitudeDays: Set<PlanDay>) -> Int
}
// Routines/RoutineRecords.swift
/// Every day with at least one gratitude entry.
func gratitudeDays() -> [PlanDay: [String]]
// tasksPath
case morningDay(PlanDay)        // the page of a day that has gratitude but no note
```

Regeln (verbindlich):
- **Kein `NoteRecord`:** Der Eintrag ist reine Anzeige aus `RoutineDayRecord`. `MorningDayView` zeigt die Kopfkarte und darunter „Kein Brain Dump an diesem Tag.“; sie hat kein Textfeld und legt nichts an.
- **Kopfkarte (NO13b):** `GratitudeCard(entries:onOpen:)` zeigt „Dankbar für“ mit nummerierten Zeilen. Tipp öffnet den Tagesstart dieses Tages (`RoutinesModel.openStart(day)`) zum Ändern. Sie ersetzt `gratitudeHeader` in Ansicht und Schreibmodus der Tagesstart-Notiz. Die Dankbarkeit wird nicht in den Notiztext kopiert.
- **Anheften, Bewegen, Auswählen, Löschen:** für den Eintrag nicht angeboten (kein Wischen, kein Kontextmenü, im Auswahlmodus nicht wählbar, „Alle auswählen“ zählt ihn nicht). Entfernt wird er, indem die Dankbarkeit im Tagesstart geleert wird. Wird die Notiz eines Tages gelöscht, bleibt der Tag als Eintrag „nur Dankbarkeit“ stehen, solange Dankbarkeit eingetragen ist; die Notiz liegt wie jede andere 30 Tage im Papierkorb. Dieser Zusammenhang steht als Kommentar an `merge`.
- **Sortierung und Suche in der Liste:** Der Eintrag steht nach Tag absteigend zwischen den Notizen. Das Suchfeld der Liste (`searchable`) durchsucht bei Tagesstart-Einträgen auch die Dankbarkeit.
- **Zähler:** Die Zeile „Tagesstart“ der Ordneransicht zählt Notizen plus Tage nur mit Dankbarkeit. „Alle Notizen“ zählt weiter nur Notizen.
- **Sicherung:** `RoutineDayBackup` enthält die Dankbarkeit bereits; es kommt kein Feld hinzu. Der Test hält fest, dass der Eintrag nach einer Wiederherstellung wieder erscheint.
- **Assistent:** `NoteToolAccess` wählt nur `NoteRecord`; Einträge ohne Notiz erreichen ChatGPT nie. Die Dankbarkeit wird auch nicht an den Text einer Notiz angehängt, der an ChatGPT geht.

- [ ] **Step 1: Tests.** `RoutineFolderEntriesTests`: `merge_dayWithNoteAndGratitude_isOneNoteEntry`, `merge_gratitudeOnlyDay_isListed`, `merge_sortsDaysDescending`, `merge_noteWithoutDayGoesLast`, `merge_trashedNoteDay_isGratitudeOnly` (der Aufrufer übergibt nur lebende Notizen), `count_addsGratitudeOnlyDays`. Store: `gratitudeDays_skipsEmptyAndWhitespace`, `gratitudeDays_afterClearing_isGone`. `BackupTests.gratitudeOnlyDay_survivesRestore`. `NotesListTextTests.listSearch_matchesGratitude`.
- [ ] **Step 2:** Suiten rot.
- [ ] **Step 3: Umsetzen.** In `NotesListView` nur für `folderRole == .morningRoutine`. **Hinweis zur Überschneidung mit NE3:** NF4 ersetzt in `NoteEditorView` ausschließlich den Aufruf `gratitudeHeader` durch `GratitudeCard`; die private Funktion `gratitude(of:)` bleibt. Liegt NE3 schon auf `main`, gilt dasselbe in der umgebauten Datei.
- [ ] **Step 4:** `ALL`. Commit `feat: show gratitude as a card and list days that only have gratitude`.

### Task NF5: Dankbarkeit in der App-Suche

**Files:**
- Modify: `TagwerkCore/Search/SearchResults.swift:40–55` (`NoteSearchItem`), `App/AppEnvironment.swift:515–520` und `makeSearchModel`, `Search/SearchSheet.swift:413` (Öffnen), `Search/SearchRows.swift:206`, Kataloge
- Test: `app/TagwerkTests/` (Suite der Suche, dort wo `searchItem(for:)` geprüft wird), `TagwerkCoreTests` (Suchtests)

**Interfaces:**

```swift
public struct NoteSearchItem {
    …
    /// The routine day this hit opens instead of a note: a day of "Tagesstart" that only has gratitude.
    public let routineDay: PlanDay?          // new, default nil in the initialiser
}
// AppEnvironment
/// Search items of the morning days: the gratitude of a day with a note is appended to that note's text (app search
/// only); a day without a note becomes an item of its own with a stable id derived from the day.
static func gratitudeSearchItems(gratitudeDays: [PlanDay: [String]], morningNoteDays: Set<PlanDay>) -> [NoteSearchItem]
```

Regel: Nur `makeSearchModel` (App-Suche) bekommt diese Einträge. `SearchToolSources.notes` (#173 Task 3) bleibt bei `NoteToolAccess.visibleNotes()`; ein Test hält fest, dass dort keine Dankbarkeit ankommt. Ein Treffer ohne Notiz öffnet `.morningDay(day)`; die Zeile zeigt „Tagesstart“ und das Datum.

- [ ] **Step 1: Tests.** `gratitudeSearchItems_dayWithoutNote_hasRoutineDay`, `gratitudeSearchItems_idIsStable`, `appSearch_findsGratitudeOfDayWithNote`, `assistantSearchSource_neverContainsGratitude` (nur wenn #173 Task 3 auf `main` ist; sonst als Kommentar-TODO im Pull Request vermerken und mit NS1 nachziehen).
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`. Commit `feat: find gratitude entries in the app search`.

---

## Strang NE: Editor, Markdown, Anhänge

**Voraussetzung:** Block A von `2026-11-20-notes-chatgpt.md` auf `main` (Task A5).

### Task NE1: Typografie, Bildhöhe, Datei-Chips (NO17, NO18b)

**Files:**
- Modify: `TagwerkCore/NoteHTMLRenderer.swift:16–75, 143–160, 208–225`, `Notes/NoteMarkdownView.swift:14–20, 50–55`, `Notes/NoteEditorView.swift:127–129`, `Notes/NoteAttachmentStore.swift` (eine Lesefunktion)
- Test: `TagwerkCoreTests/NoteHTMLRendererTests.swift`, `app/TagwerkTests/NoteMarkdownViewTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/NoteHTMLRenderer.swift
/// What the page needs to know about an attachment of the note.
public struct NoteAttachmentDisplay: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case image, file }     // NX adds .scan(pages: Int) and .drawing
    public var name: String
    /// "1,2 MB", already formatted by the app.
    public var detail: String
    public var kind: Kind
    public init(name: String, detail: String = "", kind: Kind = .file)
}
public struct RenderOptions: Sendable, Equatable {
    public var attachments: [UUID: NoteAttachmentDisplay] = [:]
    /// Wraps the text of the page in links that open the editor at that source line (NE2).
    public var editLinks = false
    public init()
}
public static func html(markdown: String, options: RenderOptions) -> String
/// Kept for existing callers; forwards to `html(markdown:options:)`.
public static func html(markdown: String, attachmentNames: [UUID: String] = [:]) -> String

// Notes/NoteAttachmentStore.swift
/// Name, formatted size and kind of every attachment of a note, for the rendered page.
func displays(of noteID: UUID) -> [UUID: NoteAttachmentDisplay]
```

CSS und HTML:
- `h1` 24 pt fett, `h2` 17 pt halbfett, Text in `1rem` (folgt `textScale`), Zeilenabstand 1,45.
- Checkboxen als abgerundete Quadrate: der Link `tagwerk-toggle:N` bekommt `display:inline-flex; min-width:44px; min-height:44px; align-items:center; justify-content:center` (negativer Rand, damit die Zeile nicht springt). Erledigte Zeilen in `--muted`, nicht durchgestrichen (`li.done`).
- Bilder: `max-width:100%; max-height:40vh; object-fit:contain`.
- Datei-Verweise (`[Name](attachment:ID)` mit `kind == .file`) als Chip: `<a class="chip" href="attachment:ID"><span class="name">…</span><span class="detail">…</span></a>` mit getöntem Grund aus den vorhandenen Variablen `--code`/`--line`; Text in `--text` (kein Akzentblau auf getöntem Grund).

- [ ] **Step 1: Tests.** `renderer_checkedItemGetsDoneClass`, `renderer_fileReferenceBecomesChipWithNameAndSize`, `renderer_unknownAttachmentKeepsPlainLink`, `renderer_imageKeepsImgTag`, `page_limitsImageHeight` (CSS enthält `max-height:40vh`), `page_headingSizes`, `legacyHtmlSignature_matchesOptionsVariant`. App: `displays_namesSizeAndKind`.
- [ ] **Step 2:** `PKG TagwerkCore NoteHTMLRendererTests` → rot.
- [ ] **Step 3:** umsetzen; `NoteMarkdownView` bekommt `attachments: [UUID: NoteAttachmentDisplay]` statt `attachmentNames`.
- [ ] **Step 4:** Sichtprüfung im Simulator, hell und dunkel, Schriftgrößen „Large“ und „AX3“: Checkbox trifft mit 44 pt, Hochformat-Bild lässt Text darunter sichtbar. `ALL`.
- [ ] **Step 5:** Commit `feat: restyle the rendered note with square checkboxes, limited images and file chips`.

### Task NE2: Zeilenzuordnung der Ansicht (NO15b, reiner Teil)

Das ist der riskanteste Punkt des Plans. Die Zuordnung hat drei Stufen; A und B werden gebaut, C ist die Rückfallebene nach der Geräteprüfung.

**Stufe A (führend): Links mit Quellzeile.** Der Renderer kennt über swift-markdown die Quellposition jedes Knotens (`markup.range?.lowerBound.line`, 1-basiert). Mit `options.editLinks` umschließt er jeden Textlauf mit `<a class="e" href="tagwerk-edit:<Zeile>">…</a>`. Ein Tipp darauf ist eine Link-Navigation, die `NoteMarkdownView.Coordinator` wie `tagwerk-toggle:` abfängt. Kein JavaScript.

**Stufe B (für Tipps, die kein Link beantwortet): nächster Absatz nach Höhe.** Ein `UITapGestureRecognizer` auf der Web-Ansicht (erkennt gleichzeitig, bricht Berührungen nicht ab) merkt sich den Punkt. Meldet die Seite innerhalb von 150 ms keine Link-Navigation, rechnet die App den Anteil `(contentOffset.y + y) / contentSize.height` in eine Quellzeile um und setzt die Schreibmarke ans Ende der nächsten nicht leeren Zeile. Das trifft Zwischenräume, rohe HTML-Blöcke und Trennlinien; es ist bewusst ungenau („nächster Absatz“).

**Stufe C (Rückfall nach Geräteprüfung): Stiftknopf.** Besteht Stufe A die Prüfung in Z1 nicht, wird `NoteEditorView.usesTapToEdit` auf `false` gesetzt: Die Ansicht rendert ohne `editLinks`, in der Leiste steht wieder der Stift (wie NO15a), und der Editor öffnet mit der Schreibmarke am Ende. Das ist eine Konstante, kein Schalter in den Einstellungen.

**Files:**
- Create: `TagwerkCore/NoteEditTarget.swift`
- Modify: `TagwerkCore/NoteHTMLRenderer.swift` (`BodyVisitor`: `visitText`, `visitInlineCode`, `visitCodeBlock`, `visitLink`, `page`), `TagwerkCore/HTMLSanitizer.swift` (Schema aus rohem HTML entfernen)
- Test: `TagwerkCoreTests/NoteHTMLRendererTests.swift`, neu `TagwerkCoreTests/NoteEditTargetTests.swift`, `HTMLSanitizerTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/NoteEditTarget.swift
public enum NoteEditTarget {
    public static let scheme = "tagwerk-edit"
    public static let endToken = "end"
    /// "tagwerk-edit:12" → 12, "tagwerk-edit:end" → nil with `isEnd`; anything else is no edit link.
    public static func parse(_ url: String) -> (line: Int?, isEnd: Bool)?
    /// The character offset right behind the last character of the 1-based source line (before its line break).
    /// Lines beyond the text clamp to the end; "\r\n" counts as one break.
    public static func offset(endOfLine line: Int, in text: String) -> Int
    /// Stage B: the source line for a tap at `fraction` (0…1) of the page height: the nearest non-empty line to
    /// `fraction × lineCount`, searching downwards first. Empty text gives line 1.
    public static func approximateLine(fraction: Double, in text: String) -> Int
}
```

Regeln des Renderers mit `editLinks`:
- `visitText` und `visitInlineCode`: Textlauf in `<a class="e" href="tagwerk-edit:L">`, mit `L` = Zeile des Knotens. Ein Absatz mit weichen Umbrüchen hat je Zeile einen eigenen Textknoten, die Zuordnung ist also zeilengenau.
- Innerhalb eines echten Links (`visitLink`, auch Anhang-Verweise) und innerhalb der Checkbox gibt es keinen Bearbeiten-Link (kein Anker im Anker). Der Besucher führt dafür einen Zähler `anchorDepth`.
- Codeblock: der ganze Block in einem Link auf die erste Inhaltszeile.
- Tabellen: kein Bearbeiten-Link; NX6 setzt dort `tagwerk-table:`.
- Roher HTML-Block und Inline-HTML: unverändert durch den Sanitizer, ohne Link (Stufe B greift).
- Seitenende: `<a class="e tail" href="tagwerk-edit:end"></a>` als Block mit `min-height:50vh`, damit ein Tipp unter den Text ans Ende schreibt.
- CSS: `a.e { color: inherit; text-decoration: none; -webkit-touch-callout: none; }`.
- `HTMLSanitizer` entfernt `href` mit den Schemata `tagwerk-edit`, `tagwerk-toggle` und (ab NX6) `tagwerk-table` aus rohem HTML der Notiz, damit nur der Renderer solche Links setzt.

- [ ] **Step 1: Tests.**
  - Renderer: `editLinks_wrapEveryTextRunWithItsLine` (Überschrift Zeile 1, Absatz Zeilen 3 und 4 mit weichem Umbruch, Listenpunkt Zeile 6), `editLinks_nestedListItemKeepsOwnLine`, `editLinks_notInsideRealLink`, `editLinks_notInsideCheckboxLink`, `editLinks_emphasisWrapsAnchorNotViceVersa`, `editLinks_codeBlockPointsToFirstLine`, `editLinks_tableHasNone`, `editLinks_tailLinkPresent`, `editLinks_off_htmlIsUnchanged` (Vergleich mit dem bisherigen Ergebnis), `editLinks_crlfText_linesMatch`.
  - `NoteEditTargetTests`: `parse_lineAndEnd`, `parse_rejectsOtherSchemes`, `offset_endOfMiddleLine`, `offset_lastLineWithoutBreak`, `offset_beyondTextClampsToEnd`, `offset_crlf`, `offset_emoji` (Zeichen, nicht UTF-16), `approximateLine_skipsEmptyLines`, `approximateLine_zeroAndOne`.
  - `HTMLSanitizerTests.rawHTML_dropsAppSchemes`.
- [ ] **Step 2:** `PKG TagwerkCore NoteEditTargetTests`, `NoteHTMLRendererTests` → rot.
- [ ] **Step 3:** umsetzen.
- [ ] **Step 4:** `PKG TagwerkCore` vollständig, `ALL`. Commit `feat: give the rendered note links that name their source line`.

### Task NE3: Tippen schreibt, „Fertig“ zeigt; Editor in Erweiterungsdateien (NO15b)

**Files:**
- Create: `Notes/NoteEditorView+Attachments.swift` (alles unter `// MARK: Actions` zu Fotos, Dateien, `run`, `insertReference`, `refreshShareURLs`, `message(for:)`), `Notes/NoteEditorView+Menu.swift` (`moreMenu`, `isRecipeNote`)
- Modify: `Notes/NoteEditorView.swift`, `Notes/NoteMarkdownView.swift:19–24, 37–55, 92–153`, Kataloge
- Test: `app/TagwerkTests/NoteMarkdownViewTests.swift`, `NoteEditorSyncTests.swift` (unverändert grün), neu `app/TagwerkUITests/NoteEditorUITests.swift`

**Interfaces (Produces):**

```swift
// NoteMarkdownView
/// A tap on text: the source line, or `nil` for "end of the note".
var onEdit: ((_ line: Int?) -> Void)? = nil
/// A tap the page did not answer: the fraction of the page height (stage B).
var onUnansweredTap: ((_ fraction: Double) -> Void)? = nil
/// Native context menu for a long press on a link of the page (attachments, checkboxes); `nil` shows none.
/// NX (scan, drawing) and BS5 ("Als Aufgabe anlegen") fill it.
var contextMenu: ((_ url: URL) -> UIMenu?)? = nil

// NoteEditorView
/// Stage C switch: `false` renders without edit links and shows the pencil button again.
static let usesTapToEdit = true
/// Opens the editor with the cursor at the end of the source line (`nil`: end of the text) and focuses it.
func beginEditing(atLine line: Int?)
```

Verhalten:
- Startmodus wie heute (`NoteEditorView.swift:84–90`): Notiz mit Text öffnet als Ansicht, leere Notiz, unberührte Vorlage und laufende Sitzung zum Schreiben.
- Ansicht: kein Knopf Auge/Stift. In der Leiste steht nur „⋯“. Im Menü „⋯“ steht als erster Eintrag „Bearbeiten“ (`pencil`), damit es einen Weg ohne Geste gibt; die Ansicht bekommt zusätzlich `accessibilityAction(named: "Bearbeiten")`.
- Schreiben: rechts „Fertig“ (`confirmationAction`); speichert über `saveText()` und wechselt in die Ansicht.
- `beginEditing(atLine:)`: `saveText()` ist nicht nötig (Ansicht ändert nichts), setzt `selection = TextSelection(insertionPoint:)` aus `NoteEditTarget.offset(endOfLine:in:)`, `mode = .edit`, `@FocusState` auf das Textfeld.
- Koordinator: `tagwerk-edit:` ruft `onEdit`. Für Stufe B merkt der Tap-Recognizer Zeit und Anteil; jede `linkActivated`-Navigation innerhalb von 150 ms verwirft ihn, sonst `onUnansweredTap`. Der Recognizer verlangt, dass der Finger sich nicht bewegt hat (Standard) und feuert nicht während des Scrollens (`scrollView.isDragging || isDecelerating`).
- Kontextmenü: `WKUIDelegate.webView(_:contextMenuConfigurationForElement:completionHandler:)` liest `elementInfo.linkURL` und fragt `contextMenu`; ohne Ergebnis `nil` (kein Systemmenü, keine Linkvorschau).
- **A5:** `adoptStoredText()` bleibt wie auf `main`. Übernimmt der Editor Text von außen, während geschrieben wird, bleibt die Schreibmarke am Ende, wenn ihr Versatz nicht mehr passt.

- [ ] **Step 1: Vorprüfung „Schreibmarke sichtbar“ (30 Minuten, Simulator).** Eine Notiz mit 200 Zeilen, `selection` auf Zeile 150 setzen, Fokus geben. **Entscheidungsregel:** Scrollt `TextEditor` die Schreibmarke selbst ins Bild, bleibt `TextEditor`. Tut er es nicht, wird das Textfeld in diesem Task durch eine schmale `UIViewRepresentable`-Hülle um `UITextView` ersetzt (`Notes/NoteTextView.swift`: Bindungen `text` und `selection` als Zeichenversatz, `scrollRangeToVisible`, gleiche Schrift und Ränder, Dynamic Type) und NE4 hängt seine Leiste als `inputAccessoryView`-freie SwiftUI-Leiste über `safeAreaInset` an. Der Befund steht im Pull Request.
- [ ] **Step 2: Tests.**
  - `NoteMarkdownViewTests`: `coordinator_editLink_callsOnEditWithLine`, `coordinator_endLink_callsOnEditWithNil`, `coordinator_toggleLink_doesNotCallOnEdit`, `coordinator_unansweredTap_firesAfterDelay`, `coordinator_linkWithinWindow_cancelsUnansweredTap`, `configuration_stillDisablesJavaScript` (bleibt).
  - `NoteEditorUITests`: `testTapOnLineOpensEditorThere` (Notiz mit drei Absätzen; Tipp auf den zweiten; ein getipptes „X“ steht danach am Ende von Absatz 2), `testTapOnCheckboxTogglesAndStaysInView`, `testDoneReturnsToView`, `testEmptyNoteOpensForWriting`, `testEditFromMenu`.
  - Unit: `formattingAction_isOwnSave` wird mit NE4 ergänzt; hier `beginEditing_doesNotChangeLastSavedText`.
- [ ] **Step 3:** Suiten rot.
- [ ] **Step 4: Umsetzen.** Zuerst das reine Verschieben in die Erweiterungsdateien als eigener Commit ohne Verhaltensänderung (`refactor: split the note editor into focused files`), dann das Verhalten.
- [ ] **Step 5:** `ALL`. Commit `feat: start writing where the rendered note is tapped`.

**Geräteprüfung (Z1, entscheidet über Stufe C):** Testnotiz mit Überschriften, langem Absatz mit weichen Umbrüchen, verschachtelter Liste, Checkboxen, Link, Bild, Datei-Chip, Codeblock, Tabelle und rohem HTML.
1. 20 Tipps auf Text verschiedener Zeilen: Die Schreibmarke steht in mindestens 19 Fällen in der angetippten Quellzeile.
2. Tipps auf Checkbox, Link, Bild, Chip: kein Wechsel ins Schreiben.
3. Scrollen und Wischen zurück lösen nichts aus; Tipp in einen Zwischenraum öffnet am nächsten Absatz.
4. Tastatur erscheint, Schreibmarke ist sichtbar, auch in Zeile 150 einer langen Notiz.
5. Halten auf Text wählt Text aus (Kopieren möglich) oder tut nichts; es erscheint kein Link-Menü.
6. VoiceOver: Der Text wird vorgelesen; die Aktion „Bearbeiten“ ist erreichbar. Wird jede Zeile als „Link“ angesagt, bekommen die Bearbeiten-Links `role="text"` (WebKit) und die Prüfung wird wiederholt; bleibt es störend, gilt Stufe C für VoiceOver-Nutzer über `UIAccessibility.isVoiceOverRunning` (Ansicht ohne `editLinks`, Menüeintrag „Bearbeiten“).
**Regel:** Scheitert Punkt 1, 2 oder 4 und lässt sich nicht in einem Nachbesserungslauf beheben, gilt Stufe C für alle.

### Task NE4: Formatierungsleiste über der Tastatur (NO16b)

**Files:**
- Create: `TagwerkCore/MarkdownFormatting.swift`, `Notes/NoteFormattingBar.swift`
- Modify: `Notes/NoteEditorView.swift` (Leiste statt `.keyboardDoneButton()` und statt des zweiten Anhängen-Menüs), Kataloge
- Test: neu `TagwerkCoreTests/MarkdownFormattingTests.swift`, `NoteEditorUITests`

**Interfaces (Produces):**

```swift
// TagwerkCore/MarkdownFormatting.swift
public enum MarkdownFormatting {
    public struct Edit: Sendable, Equatable {
        public var text: String
        /// Character offsets of the new selection (`lowerBound == upperBound` is a cursor).
        public var selection: Range<Int>
    }
    public enum Action: Sendable, CaseIterable { case heading, bold, italic, list, checkbox }
    /// Applies an action to the selection or, without one, to the line of the cursor.
    /// heading: none → "# " → "## " → none, on every selected line.
    /// bold / italic: wraps the selection in "**" / "*", unwraps when it is already wrapped; without a selection it
    ///   inserts the pair and puts the cursor between.
    /// list / checkbox: toggles "- " / "- [ ] " at the start of every selected line; a list line becomes a checkbox line
    ///   and back without doubling the marker. Indentation is kept.
    public static func apply(_ action: Action, to text: String, selection: Range<Int>) -> Edit
}
```

Leiste (sieben Elemente, je 44 pt, seitlich scrollbar bei großer Schrift): Überschrift (`textformat.size`, Label „Überschrift“), Fett (`bold`), Kursiv (`italic`), Liste (`list.bullet`), Checkbox (`checklist`), Anhängen (das vorhandene `NoteAttachmentMenu`; NX1 macht daraus das Einfügen-Menü), Tastatur ausblenden (`keyboard.chevron.compact.down`, Label „Tastatur ausblenden“). Jede Aktion ändert `text` und `selection` und ruft `saveText()`.

- [ ] **Step 1: Tests.** `heading_cyclesNoneOneTwoNone`, `heading_onSeveralLines`, `bold_wrapsSelection`, `bold_unwrapsWrappedSelection`, `bold_withoutSelection_insertsPairAndPlacesCursor`, `italic_doesNotBreakBold`, `list_togglesMarker`, `checkbox_fromListLine_replacesMarker`, `checkbox_keepsIndentation`, `apply_selectionAtEndOfText`, `apply_emojiOffsets`, `apply_crlf`. App: `formattingAction_isOwnSave` (nach einer Aktion ergibt `NoteEditorSync.resolution` `.keep`). UI: `testCheckboxButtonInsertsCheckbox`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`. Commit `feat: add a formatting bar above the keyboard of the note editor`.

---

## Strang NS: Sperren

**Voraussetzungen:** NF und NE gemergt; Strang B von `2026-11-20-decisions-173.md` (Tasks 3, 4, 4a, 4b) auf `main`.

### Regeln der Sperre (verbindlich)

1. **Eine Sperre (NL1a):** „Geschützt“ ist eine Notiz, wenn der Schalter „Mit Face ID schützen“ an ist und sie entweder selbst gesperrt ist (`isLocked`) oder, bei eingeschaltetem „Private Ordner sperren“, privat ist (Art oder Ordner, über `NoteFolderRules.privateFolderIDs`). „Verborgen“ ist geschützter Inhalt, solange nicht entsperrt ist.
2. **Eine Entsperrung:** Einmal entsperren öffnet alles Geschützte, bis Tagwerk in den Hintergrund geht (`scenePhase == .background`) oder „Jetzt sperren“ getippt wird.
3. **Prüfung:** `LAPolicy.deviceOwnerAuthentication` (Face ID bzw. Touch ID, danach Gerätecode). Ohne eingerichteten Gerätecode ist nichts geschützt; die Zeile „Sperren“ ist dann ausgegraut mit dem Hinweis „Richte zuerst einen Code für dein iPhone ein.“
4. **Nach außen immer privat:** `isLocked` allein entscheidet, ob eine Notiz das Gerät verlassen darf, unabhängig von Schalter und Entsperrung (Global Constraints).
5. **Sichtsperre, keine Verschlüsselung:** Datenbank und Sicherung enthalten gesperrte Notizen im Klartext (mit DS6b verschlüsselt die Sicherung als Ganzes). Das sagen die Erklärung beim ersten Sperren und die Einstellungen.
6. **Welche Notizen:** freie Notizen sowie Notizen aus Tagesstart, Tagesabschluss, Brain Dump und Rezepten. In privaten Ordnern entfällt der Eintrag „Sperren“, solange „Private Ordner sperren“ an ist.
7. **Löschen und Bewegen** einer geschützten Notiz verlangen die Entsperrung; in „Zuletzt gelöscht“ bleibt sie gesperrt.
8. **Schalter aus:** verlangt die Prüfung, hebt keine Markierung auf; die Notizen sind dann ohne Abfrage offen, bleiben aber privat (Regel 4).
9. **Wiederherstellung:** `isLocked` wird mitgesichert. Enthält eine wiederhergestellte Sicherung gesperrte Notizen und kann das Gerät prüfen, wird „Mit Face ID schützen“ eingeschaltet (sicherer Zustand); die Einstellungen der Sperre selbst werden nicht gesichert.

### Task NS1: Feld, Privat-Regel mit dritter Bedingung, Sicherung

**Files:**
- Modify: `Notes/NoteRecord.swift`, `TagwerkCore/NoteFolderRules.swift` (`mayLeaveDevice`), `Notes/NoteStore.swift` (`isPrivate`, `setLocked`), `Shopping/RecipeNotePicker.swift:34`, `Routines/NoteSuggestionModel.swift:65` und `NoteField.swift:245–260` (Angebot „Vorschläge holen“), der Menüeintrag „Übersetzen“ aus Block A (`NoteEditorView+Menu.swift`), `Backup/BackupDTOs.swift:643–695` (`NoteBackup`) und die Wiederherstellung, `AI/AssistantModel` (nur Aufruf von `endNoteSession()`)
- Test: `TagwerkCoreTests/NoteFolderRulesTests.swift`, `app/TagwerkTests/PrivateNotesTests.swift`, `NoteToolAccessTests.swift`, `NoteSuggestionModelTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// Notes/NoteRecord.swift
/// The user locked this note (NL1a). A locked note does not leave the device while it is locked; unlocked in the current lock session it is open to the assistant until the user leaves Tagwerk.
var isLocked: Bool = false

// TagwerkCore/NoteFolderRules.swift (extends #173 Task 3; the new parameter has a default)
/// Whether a note may be shown to the assistant: its kind is not private, it does not lie in a private folder and
/// it is not locked.
public static func mayLeaveDevice(kind: NoteKind, folderID: UUID?, privateFolderIDs: Set<UUID>, isLocked: Bool = false) -> Bool

// Notes/NoteStore.swift
func isPrivate(_ note: NoteRecord) -> Bool          // now passes `note.isLocked`
/// Sets or clears the lock mark. Locking ends the assistant's note session (`onNoteLocked`).
func setLocked(_ ids: [UUID], _ locked: Bool)
var lockedCount: Int { get }
@ObservationIgnored var onNoteLocked: (() -> Void)?  // wired to `AssistantModel.endNoteSession()` in AppEnvironment

// Backup
struct NoteBackup { …; var isLocked: Bool? }         // optional; `nil` reads as false
```

- [ ] **Step 1: Tests.**
  - `NoteFolderRulesTests`: `mayLeaveDevice_lockedFreeNote_isFalse`, `mayLeaveDevice_defaultParameterKeepsOldBehaviour`.
  - `PrivateNotesTests`: `storeIsPrivate_lockedNote`, `unlockedSession_stillPrivate` (Regel 4: es gibt keinen Parameter für den Sitzungszustand; der Test hält die Signatur fest), `lockSwitchOff_stillPrivate`.
  - `NoteToolAccessTests.lockedNote_neverReachesAnyOutboundPath`: eine gesperrte freie Notiz, eine gesperrte Rezept-Notiz, eine gesperrte Tagesstart-Notiz. Erwartet: nicht in `visibleNotes()`, `visibleNote(key:)` ist `nil`, `RecipeNoteSource` bietet die Rezept-Notiz nicht an, `NoteSuggestionModel.fetch` sendet nichts (Responder wird nie aufgerufen), „Vorschläge holen“ und „Übersetzen“ sind nicht angeboten.
  - `setLocked_callsHook`, `setLocked_unlock_doesNotCallHook`.
  - `BackupTests`: `lockedNote_roundTrips`, `olderFileWithoutField_isUnlocked`, `restoreWithLockedNotes_turnsProtectionOn` (mit einem Prüfer, der „verfügbar“ meldet), `restoreWithLockedNotes_withoutPasscode_leavesItOff`.
- [ ] **Step 2:** Suiten rot.
- [ ] **Step 3:** umsetzen. Jede Stelle, die heute `kind.isPrivate` oder `role?.isPrivate` für eine Entscheidung „darf hinaus“ liest, geht über `store.isPrivate(note)`; mit `grep -rn "isPrivate\|allowsSuggestions" app/Tagwerk` gegenprüfen und das Ergebnis im Pull Request auflisten.
- [ ] **Step 4:** `ALL`. Commit `feat: treat locked notes as private for everything that leaves the device`.

### Task NS2: Prüfung, Sitzung, Einstellungen

**Files:**
- Create: `TagwerkCore/NoteProtection.swift`, `Notes/NoteLock.swift`
- Modify: `project.yml` (`NSFaceIDUsageDescription: "Tagwerk entsperrt damit gesperrte Notizen und private Ordner."`), `InfoPlist.xcstrings` (Englisch), `Persistence/AppSettings.swift`, `App/AppEnvironment.swift`, `App/TagwerkApp.swift:79` (Sperren beim Wechsel in den Hintergrund), `Settings/NotesSettingsView.swift`, Kataloge
- Test: neu `TagwerkCoreTests/NoteProtectionTests.swift`, neu `app/TagwerkTests/NoteLockTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/NoteProtection.swift
public enum NoteProtection {
    public struct Settings: Sendable, Equatable {
        public var isEnabled: Bool          // "Mit Face ID schützen"
        public var locksPrivateFolders: Bool
        public var canAuthenticate: Bool    // a passcode is set
    }
    /// Rule 1.
    public static func isProtected(isLocked: Bool, isPrivateContent: Bool, settings: Settings) -> Bool
    /// Whether a folder shows the lock screen instead of its list.
    public static func isProtectedFolder(isPrivateFolder: Bool, settings: Settings) -> Bool
}

// Notes/NoteLock.swift
protocol DeviceOwnerAuthenticating: Sendable {
    func canAuthenticate() -> Bool
    /// Face ID or Touch ID, then the device passcode. `false` when the user cancels or fails.
    func authenticate(reason: String) async -> Bool
}
struct SystemDeviceOwnerAuthenticator: DeviceOwnerAuthenticating   // LAContext, .deviceOwnerAuthentication

@MainActor @Observable final class NoteLock {
    private(set) var isUnlocked = false
    init(settings: AppSettings, authenticator: any DeviceOwnerAuthenticating)
    var protection: NoteProtection.Settings { get }
    /// Asks once; a second call while a prompt is open waits for the first.
    func unlock(reason: String) async -> Bool
    func lockNow()
    /// Turning protection on asks once; turning it off asks too and leaves the marks alone (rule 8).
    func setEnabled(_ enabled: Bool) async -> Bool
}
// AppSettings
var noteLockEnabled: Bool = false
var noteLockPrivateFolders: Bool = false
var noteLockExplained: Bool = false
```

Einstellungen › Notizen, Abschnitt „Sperre“ (Mockup NL1a): Schalter „Mit Face ID schützen“ („Gilt für gesperrte Notizen und private Ordner.“; auf Geräten mit Touch ID „Mit Touch ID schützen“, ohne Biometrie „Mit Gerätecode schützen“), Schalter „Private Ordner sperren“, Zeile „Gesperrte Notizen · N“ (öffnet die Liste aller gesperrten Notizen, nach Entsperren). Fußtext: „Einmal entsperren öffnet alles Gesperrte, bis du Tagwerk verlässt. Private Ordner: Tagebuch mit Gott, Bible Study, Dream Log.“ Abschnitt „Was die Sperre tut“ mit drei Zeilen (verbirgt den Inhalt, bleibt auf dem iPhone, verschlüsselt nicht). Die Einstellungen der Sperre kommen **nicht** in `AppSettingsBackup` (Regel 9).

- [ ] **Step 1: Tests.** `NoteProtectionTests`: `lockedNote_protectedOnlyWhileEnabled`, `privateNote_protectedOnlyWithFolderSwitch`, `withoutPasscode_nothingIsProtected`, `folder_privateWithSwitch`. `NoteLockTests` (mit Fake-Prüfer): `unlock_success_setsUnlocked`, `unlock_failure_staysLocked`, `unlock_twoCalls_promptOnce`, `lockNow_locks`, `background_locks`, `setEnabledOff_requiresAuthentication_keepsMarks`, `setEnabledOn_withoutPasscode_fails`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`. Commit `feat: add one lock session for locked notes and private folders`.

### Task NS3: Sperren und Entsperren in Liste und Notiz (NL2a, NL3a, NL5a, NO10c)

**Files:**
- Create: `Notes/LockedContentView.swift`, `Notes/NoteLockIntroSheet.swift`
- Modify: `Notes/NotesListView.swift` (Karte, Kontextmenü, Sperrbildschirm für geschützte Ordner), `Notes/NotesListView+Selection.swift` („Sperren“ in der Auswahl), `Notes/NoteEditorView+Menu.swift`, `Notes/NoteEditorView.swift` (ein `overlay`/Weiche auf den Sperrbildschirm, Abdeckung im App-Umschalter), `Notes/NotesFoldersView.swift` (Schloss an geschützten Ordnern), `Backup/BackupSettingsView.swift` (Zeile „Gesperrte Notizen“), Kataloge
- Test: `app/TagwerkTests/NotesListTextTests.swift`, neu `app/TagwerkUITests/NoteLockUITests.swift` (mit einem Prüfer, der im UI-Test-Modus sofort Erfolg oder Fehlschlag meldet: Startargument `UITestMode.lockAuthentication=succeed|fail`)

**Interfaces:**

```swift
// LockedContentView: lock symbol, "Diese Notiz ist gesperrt." / "Dieser Ordner ist gesperrt.", button "Mit Face ID öffnen"
struct LockedContentView: View { let kind: Kind; let onUnlock: () async -> Void; enum Kind { case note, folder } }
// NotesListView texts
static func lockedPreview() -> String        // "Gesperrt"
```

Verhalten:
- **Menü „⋯“ der Notiz und Kontextmenü der Karte:** „Sperren“ (`lock`) bzw. bei gesperrter Notiz „Sperre aufheben“ (`lock.open`, verlangt die Prüfung) und, solange entsperrt ist, „Jetzt sperren“. In der Mehrfachauswahl „Sperren“ (sperrt alle gewählten, die sich sperren lassen).
- **Erstes Sperren:** Ist „Mit Face ID schützen“ aus oder `noteLockExplained == false`, erscheint `NoteLockIntroSheet` (Mockup NL2a: vier Zeilen, Knopf „Mit Face ID sperren“); der Knopf schaltet den Schalter ein, fragt einmal ab und sperrt die Notiz.
- **Karte (NL3a):** Titel sichtbar; statt Vorschau „Gesperrt“ mit Schloss; kein Vorschaubild, kein Anhang-Zähler. Entsperrt: normale Karte mit offenem Schloss. VoiceOver: „gesperrt“ bzw. „entsperrt“ im Wert.
- **Öffnen:** Eine verborgene Notiz zeigt `LockedContentView` und fragt sofort ab; schlägt die Prüfung fehl, bleibt der Bildschirm stehen. Der Editor lädt den Text erst nach dem Entsperren (kein Text im View-Baum vorher).
- **Ordner (NO10c):** Ein geschützter privater Ordner zeigt statt der Liste `LockedContentView(kind: .folder)`; auch der Sprung aus der Suche (G3 U2) landet dort.
- **Löschen und Bewegen** (Wischen, Kontextmenü, Auswahl) fragen bei verborgenen Notizen zuerst ab.
- **App-Umschalter:** Ist eine geschützte Notiz oder ein geschützter Ordner offen, deckt eine undurchsichtige Fläche mit Schloss den Inhalt ab, sobald `scenePhase != .active`.
- **Teilen** bleibt nach dem Entsperren möglich. „Mit ChatGPT bearbeiten“ (#233 B9) ist für gesperrte Notizen ausgegraut mit dem Fußtext „Gesperrt: Diese Notiz geht nicht an ChatGPT. Entsperre sie, wenn der Assistent sie lesen soll.“; entsperrt steht dort „Entsperrt: Der Assistent kann diese Notiz lesen und ändern, bis du Tagwerk verlässt.“ (`NoteLock.assistantNotice(isUnlocked:)`).
- **Datensicherung (NL6a):** Zeile „Gesperrte Notizen · N“ mit dem Wert „in der Datei unverschlüsselt enthalten“ (bzw. „enthalten“ bei aktiver Verschlüsselung aus DS3) und dem Fußtext „Die Sperre schützt vor Mitlesen in Tagwerk, nicht die Sicherungsdatei. Bewahre die Datei an einem geschützten Ort auf.“

- [ ] **Step 1: Tests.** UI: `testLockFromMenuShowsIntroOnce`, `testLockedCardHidesPreviewAndThumbnail`, `testOpeningLockedNoteAsksAndShowsTextAfterSuccess`, `testFailedAuthenticationKeepsLockScreen`, `testBackgroundRelocks`, `testPrivateFolderShowsLockScreen`, `testDeleteLockedNoteAsksFirst`, `testUnlockRemovesMark`. Unit: `lockedPreview_text`, `selection_lockSkipsNotesInPrivateFolders`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`. Commit `feat: lock single notes and private folders behind Face ID`.

### Task NS4: Suche und übrige Oberflächen (NL4a)

**Files:**
- Modify: `App/AppEnvironment.swift` (`searchItem(for:folderNames:)`, `makeSearchModel`), `Notes/NotesListView.swift` (Filter des Suchfelds), `Search/SearchRows.swift:206`, `Search/SearchSheet.swift` (Fußzeile), `TagwerkCore/Search/SearchResults.swift` (`NoteSearchItem.isConcealed`, Standard `false`), Kataloge
- Test: Suchtests der App, `NotesListTextTests`

Regel: Für eine verborgene Notiz enthält `NoteSearchItem.text` nur die Titelzeile (`NoteText.title`), `isConcealed` ist `true`; die Zeile zeigt Schloss und „Ordner · Gesperrt“, keinen Ausschnitt. Gibt es mindestens eine verborgene Notiz, steht unter den Notiz-Treffern „Gesperrte Notizen werden nur über den Titel gefunden.“ Solange entsperrt ist, sucht die Suche im ganzen Text. Dasselbe gilt für das Suchfeld der Notizliste und für erkannten Scan-Text (NX4). Das Such-Modell wird beim Sperren neu aufgebaut, damit kein Volltext einer inzwischen verborgenen Notiz im Speicher des Modells bleibt.

- [ ] **Step 1: Tests.** `searchItem_concealedNote_hasOnlyTitle`, `searchItem_unlocked_hasFullText`, `searchItem_privateFolderNote_followsFolderSwitch`, `listSearch_concealedNote_matchesTitleOnly`, `lockNow_rebuildsSearchItems`.
- [ ] **Step 2:** rot. **Step 3:** umsetzen. **Step 4:** `ALL`. Commit `feat: search locked notes by their title only`.

**Geräteprüfung (Z1):** Face ID erfolgreich; Face ID abgelehnt, dann Gerätecode; „Abbrechen“; App in den Hintergrund und zurück; App-Umschalter zeigt die Abdeckung; iPhone ohne Gerätecode (Testgerät oder Simulator ohne Code): „Sperren“ ausgegraut mit Hinweis; gesperrte Notiz taucht im Assistenten bei `search` nicht auf.

---

## Strang NX: Scannen, Zeichnen, Tabellen

**Voraussetzung:** NE gemergt.

### Task NX1: Einfügen-Menü (SC1a)

**Files:**
- Create: `Notes/NoteInsertMenu.swift` (übernimmt `NoteAttachmentMenu`, die Datei `NoteAttachmentMenu.swift` entfällt; `inserting(_:into:replacing:)` zieht unverändert mit)
- Modify: `Notes/NoteFormattingBar.swift`, `Notes/NoteEditorView+Attachments.swift`, `app/TagwerkTests/NoteAttachmentMenuTests.swift` (Typname), Kataloge

Menü mit zwei Gruppen (`Section`): „Aufnehmen“ mit „Foto auswählen“, „Foto aufnehmen“, „Dokument scannen“ (`doc.viewfinder`, nur wenn `VNDocumentCameraViewController.isSupported`), „Datei“, „Einfügen“ (der vorhandene `PasteButton`); „Erstellen“ mit „Zeichnung“ (`pencil.tip.crop.circle`) und „Tabelle“ (`tablecells`). Symbol des Knopfs `plus.circle`, Label „Einfügen“. Die drei neuen Einträge rufen zunächst leere Rückrufe; NX3, NX5 und NX7 füllen sie. Das Menü steht nur noch in der Leiste über der Tastatur (im Schreibmodus), nicht mehr oben.

- [ ] **Step 1:** Tests: `insertMenu_hidesScanWithoutDocumentCamera` (über eine injizierte Verfügbarkeit), bestehende `inserting`-Tests unverändert grün.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: group the insert menu of the note editor`.

### Task NX2: Anhänge aus erzeugten Daten, Begleitdateien, erkannter Text

**Files:**
- Modify: `Notes/NoteAttachmentRecord.swift`, `Notes/NoteAttachmentStore.swift:60–81, 111–136, 150–208`, `Backup/BackupDTOs.swift:729–755, 1503–1530, 1592–1600`
- Test: `app/TagwerkTests/NoteAttachmentStoreTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// NoteAttachmentRecord
/// "" for a plain picture or file, "scan" for a scanned PDF, "drawing" for the picture of a drawing,
/// "strokes" for the stroke data that belongs to a drawing.
var roleRaw: String = ""
/// The attachment this file belongs to (the picture of a drawing); `nil` for every file that stands on its own.
var companionOfID: UUID? = nil
/// Text recognised in a scan (SC3b); `nil` until recognition has run. Never part of the note text.
var recognizedText: String? = nil
var pageCount: Int = 0

// NoteAttachmentStore
enum Role: String { case plain = "", scan, drawing, strokes }
/// Stores generated data (a PDF, a PNG, stroke data). Throws `.tooLarge` above `maximumFileBytes`.
func addData(_ data: Data, fileName: String, type: UTType, role: Role, to noteID: UUID, companionOf: UUID? = nil,
             pageCount: Int = 0) throws -> NoteAttachmentRecord
/// Replaces the bytes of an attachment and keeps its id, so references in the text stay valid.
func replaceData(_ data: Data, for id: UUID) throws
func rename(_ id: UUID, to name: String)
func setRecognizedText(_ text: String, for id: UUID)
func companion(of id: UUID, role: Role) -> NoteAttachmentRecord?
```

Regeln:
- Eine Begleitdatei gilt als referenziert, genau wenn ihr Hauptanhang referenziert ist: `removeUnreferenced` und `delete(ids:)` nehmen sie mit; `purgeOrphans` löscht sie nicht, solange der Eintrag existiert.
- `cardInfo` zählt Begleitdateien nie; ein Scan zählt als Bild mit Vorschaubild, nicht als Datei. `thumbnail(for:)` rendert bei PDF die erste Seite. „Anhänge teilen“ (`exportURL`) lässt Begleitdateien aus.
- Sicherung: `NoteAttachmentBackup` bekommt die vier Felder optional; jede Datei bleibt ein eigener Eintrag mit eigenem Datenblock, das Dateiformat ändert sich nicht.

- [ ] **Step 1: Tests.** `addData_storesRoleAndPageCount`, `addData_tooLargeThrows`, `replaceData_keepsID`, `removeUnreferenced_takesCompanionWithParent`, `removeUnreferenced_keepsCompanionWhileParentReferenced`, `purgeOrphans_keepsCompanionFile`, `cardInfo_ignoresCompanions`, `cardInfo_scanCountsAsImage`, `thumbnail_ofPDFIsFirstPage`, `exportURLs_skipCompanions`; `BackupTests.drawingAndScan_roundTripWithCompanionAndText`, `olderAttachmentWithoutNewFields_restores`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: let note attachments hold generated files and companions`.

### Task NX3: Dokument scannen, PDF mit Vorschau der ersten Seite (SC2c)

**Files:**
- Create: `Notes/DocumentScanner.swift` (`UIViewControllerRepresentable` um `VNDocumentCameraViewController`), `Notes/ScanPDFBuilder.swift`
- Modify: `Notes/NoteEditorView+Attachments.swift`, `Notes/NoteMarkdownView.swift:161–181` (`AttachmentSchemeHandler`: PDF liefert die erste Seite als JPEG), `TagwerkCore/NoteHTMLRenderer.swift` (`NoteAttachmentDisplay.Kind.scan(pages:)`, Karte), `Notes/NoteAttachmentStore.swift` (`displays(of:)`), `Notes/NoteEditorView.swift` (Kontextmenü-Rückruf an `NoteMarkdownView.contextMenu`), Kataloge
- Test: neu `app/TagwerkTests/ScanPDFBuilderTests.swift`, `NoteHTMLRendererTests`, `NoteMarkdownViewTests`

**Interfaces:**

```swift
enum ScanPDFBuilder {
    /// One PDF from the scanned pages; each page is scaled to at most `NoteAttachmentStore.maximumImageEdge` on its
    /// longer side and compressed as JPEG.
    static func pdf(pages: [UIImage]) -> Data
    /// "Scan 20.11.2026.pdf"; a second scan of the same day gets " 2", " 3", …
    static func fileName(for day: PlanDay, existing: [String]) -> String
}
```

Ablauf: „Dokument scannen“ öffnet die Dokumentenkamera; „Sichern“ baut die PDF, legt sie mit `addData(role: .scan, pageCount:)` ab und setzt `[Scan 20.11.2026](attachment:ID)` an der Schreibmarke ein (über `insertReference`, also `saveText()`). Kein Zwischenblatt. Über 25 MB: vorhandene Meldung „Die Datei ist größer als …“. Ansicht: Karte mit dem Bild der ersten Seite (`tagwerk-attachment://ID`), Name, „8 Seiten · 3,1 MB · PDF“ und, sobald Text erkannt ist, „Text erkannt“ (bis dahin „Text wird erkannt …“). Tipp öffnet Quick Look. Halten zeigt das native Menü: „Öffnen“, „Umbenennen“, „Teilen“ (NX4 ergänzt die Text-Einträge).

- [ ] **Step 1: Tests.** `pdf_hasOnePagePerImage`, `pdf_scalesLongEdgeTo2048`, `fileName_countsUpOnSameDay`, `renderer_scanBecomesCardWithPagesAndPreviewImage`, `schemeHandler_servesFirstPageOfPDF`, `schemeHandler_stillRejectsOtherFiles`.
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`. Die Dokumentenkamera gibt es im Simulator nicht: Der Weg ab „Seiten liegen vor“ ist über `ScanPDFBuilder` und einen UI-Test-Haken (Startargument liefert zwei Testbilder statt der Kamera) geprüft; die Kamera selbst in Z1.
- [ ] **Step 5:** Commit `feat: scan documents into a note as one PDF`.

### Task NX4: Texterkennung, durchsuchbar und auf Wunsch einfügbar (SC3b)

**Files:**
- Create: `Notes/ScanTextRecognizer.swift`
- Modify: `Notes/NoteEditorView+Attachments.swift` (Start nach dem Scan, Menüeinträge), `TagwerkCore/Search/SearchResults.swift` (`NoteSearchItem.scanText`, Standard `""`) und die Trefferbildung der Suche (Feld „Im Scan“), `App/AppEnvironment.swift` (`searchItem(for:)`), `Search/SearchRows.swift`, Kataloge
- Test: neu `app/TagwerkTests/ScanTextRecognizerTests.swift`, Suchtests in `TagwerkCoreTests` und App

**Interfaces:**

```swift
protocol ScanTextRecognizing: Sendable {
    /// Recognises the text of all pages on the device (German and English), page by page, joined by blank lines.
    func text(inPDF data: Data) async throws -> String
}
struct VisionScanTextRecognizer: ScanTextRecognizing     // Vision, accurate level, languages ["de-DE", "en-US"], no network
```

Regeln:
- Die Erkennung läuft nach dem Einsetzen im Hintergrund (`Task.detached` mit niedriger Priorität); das Ergebnis steht in `NoteAttachmentRecord.recognizedText`. Schlägt sie fehl, bleibt das Feld leer und die Unterzeile zeigt nichts; ein erneuter Versuch steht im Menü („Text erkennen“).
- Suche: `NoteSearchItem.scanText` enthält die erkannten Texte der referenzierten Scans. Ein Treffer nur dort zeigt in der Zeile „Im Scan: …“ mit Ausschnitt. Für verborgene Notizen (NS4) ist `scanText` leer.
- **Nie an ChatGPT:** Die Quelle des Assistenten (`SearchToolSources.notes`, #173) setzt `scanText` nicht; `read_note` liest nur den Notiztext. Test dazu.
- Menü am Scan: „Erkannten Text einfügen“ (setzt den Text als Absatz unter den Verweis, über `saveText()`), „Erkannten Text kopieren“.
- Sicherung: `recognizedText` ist seit NX2 im DTO.

- [ ] **Step 1: Tests.** Mit einer erzeugten PDF, die gesetzten Text als Bild enthält: `recognizer_findsGermanWord` (toleriert Groß-/Kleinschreibung; wenn Vision im Simulator des Testlaufs nicht verfügbar ist, wird der Test mit einer klaren Meldung übersprungen und in Z1 geprüft), `recognition_storesTextOnRecord` (Fake), `search_findsWordOnlyInScan_marksFieldScan`, `search_concealedNote_ignoresScanText`, `assistantSource_hasNoScanText`, `insertRecognizedText_putsParagraphBelowReference`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: recognise the text of scans for search and optional insertion`.

### Task NX5: Zeichnen (ZE1a, ZE2b, ZE3c)

**Files:**
- Create: `Notes/DrawingCanvasView.swift` (Vollbild mit `PKCanvasView` und `PKToolPicker`), `Notes/DrawingViewer.swift`
- Modify: `Notes/NoteEditorView+Attachments.swift`, `Notes/NoteEditorView.swift` (`fullScreenCover`), `TagwerkCore/NoteHTMLRenderer.swift` (`Kind.drawing`: helle Papierfläche), Kataloge
- Test: neu `app/TagwerkTests/DrawingAttachmentTests.swift`, `NoteHTMLRendererTests`, `NoteEditorUITests`

**Interfaces:**

```swift
enum DrawingAttachment {
    /// The drawing on white paper as PNG (never transparent), with a margin of 16 pt around the strokes.
    static func png(of drawing: PKDrawing, scale: CGFloat) -> Data
    /// Stores picture and stroke data and returns the reference line "![Zeichnung](attachment:<id>)".
    @MainActor static func insert(_ drawing: PKDrawing, into noteID: UUID, store: NoteAttachmentStore) throws -> (id: UUID, reference: String)
    /// Replaces picture and stroke data of an existing drawing; the id and the reference stay.
    @MainActor static func update(_ drawing: PKDrawing, id: UUID, store: NoteAttachmentStore) throws
    /// The strokes of a drawing; `nil` when the companion is missing (the drawing then opens as a picture only).
    @MainActor static func strokes(of id: UUID, store: NoteAttachmentStore) -> PKDrawing?
}
```

Verhalten:
- „Zeichnung“ im Einfügen-Menü öffnet die Zeichenfläche im Vollbild: „Abbrechen“ (fragt nach, wenn schon gezeichnet wurde: „Zeichnung verwerfen?“), Rückgängig, Wiederholen, „Fertig“. Die Fläche ist in beiden Modi hell (`overrideUserInterfaceStyle = .light`), `drawingPolicy = .anyInput`.
- „Fertig“: PNG als Anhang mit `role: .drawing`, Strichdaten (`PKDrawing.dataRepresentation()`) als Begleitdatei `role: .strokes`; Verweis an der Schreibmarke. Eine leere Zeichnung legt nichts an.
- Ansicht: Zeichnung in voller Breite auf weißem Grund mit dünnem Rand, Höhe wie Bilder begrenzt. Tipp öffnet `DrawingViewer` (zoombar, „Bearbeiten“, „Teilen“); „Bearbeiten“ öffnet die Zeichenfläche mit den Strichen. Halten: „Bearbeiten“, „Teilen“, „Löschen“ (entfernt die Verweiszeile aus dem Text; der Anhang geht beim Schließen über `removeUnreferenced`).
- Fehlen die Strichdaten (ältere Sicherung, beschädigt), ist „Bearbeiten“ ausgegraut mit Hinweis.

- [ ] **Step 1: Tests.** `png_isOpaqueWhiteBackground`, `insert_createsPictureAndCompanion`, `update_keepsIDAndReference`, `strokes_roundTrip`, `strokes_missingCompanion_isNil`, `emptyDrawing_insertsNothing`, `renderer_drawingGetsPaperClass`. UI: `testDrawAndSeeDrawingInNote` (im Simulator mit einem Wisch auf der Fläche), `testEditDrawingKeepsSingleReference`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: draw in a note on a full-screen canvas`.

### Task NX6: Tabellen als reine Regeln, Darstellung (TX4b)

**Files:**
- Create: `TagwerkCore/MarkdownTable.swift`
- Modify: `TagwerkCore/NoteHTMLRenderer.swift:163–186` und CSS, `TagwerkCore/HTMLSanitizer.swift` (Schema), `Notes/NoteMarkdownView.swift` (Navigation `tagwerk-table:`)
- Test: neu `TagwerkCoreTests/MarkdownTableTests.swift`, `NoteHTMLRendererTests`

**Interfaces (Produces):**

```swift
public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable { case none, left, center, right }
    public var header: [String]
    public var alignments: [Alignment]
    public var rows: [[String]]
    public static let maximumColumns = 8
    public static let scheme = "tagwerk-table"

    /// A new table: three columns, a header row and two empty rows.
    public static var empty: MarkdownTable { get }
    /// The table blocks of a text in order, each with the range of lines it covers (1-based, inclusive). Tables inside
    /// fenced code are skipped. The count and order match what `NoteHTMLRenderer` numbers.
    public static func blocks(in text: String) -> [(table: MarkdownTable, lines: ClosedRange<Int>)]
    /// The index of the table block that contains the 1-based line, if any.
    public static func blockIndex(containingLine line: Int, in text: String) -> Int?
    /// The Markdown of the table with padded columns; "|" in a cell is written as "\|", line breaks become spaces.
    public func markdown() -> String
    /// The text with the block at `index` replaced; everything outside the block is untouched, the line break style is kept.
    public static func replacing(blockAt index: Int, with table: MarkdownTable, in text: String) -> String
    // Editing
    public mutating func insertRow(at index: Int)
    public mutating func insertColumn(at index: Int)      // no-op at `maximumColumns`
    public mutating func removeRow(at index: Int)
    public mutating func removeColumn(at index: Int)      // no-op when one column is left
    public mutating func moveRow(from: Int, to: Int)
    public mutating func setAlignment(_ alignment: Alignment, column: Int)
}
```

Darstellung: Der Renderer nummeriert Tabellen in Dokumentreihenfolge und umschließt den Text jeder Zelle mit `<a class="t" href="tagwerk-table:N">` (echte Links in Zellen bleiben Links). Die Tabelle steht in `<div class="table">` mit `overflow-x:auto` und weichem Rand rechts (`mask-image`), Zellen `max-width:200pt; white-space:normal`, Kopfzeile halbfett auf getöntem Grund, Ausrichtung aus dem Markdown.

- [ ] **Step 1: Tests.** `blocks_findsTwoTablesWithLineRanges`, `blocks_skipsTableInCodeFence`, `blocks_needsSeparatorLine`, `parse_alignments`, `parse_escapedPipeInCell`, `markdown_padsColumns`, `markdown_escapesPipeAndFlattensLineBreak`, `replacing_touchesOnlyTheBlock` (Text davor und danach byteweise gleich), `replacing_keepsCRLF`, `roundTrip_parseMarkdownParse_isEqual`, `insertColumn_stopsAtEight`, `removeColumn_keepsLast`, `removeRow_neverRemovesHeader` (Kopfzeile ist kein Element von `rows`), `moveRow`, `blockIndex_forCursorLine`; Renderer: `table_cellsLinkToTableIndex`, `table_numberingMatchesBlocks`, `table_realLinkInCellStaysLink`, `page_tableWrapsAt200pt`.
- [ ] **Step 2–4:** rot, umsetzen, `PKG TagwerkCore`, `ALL`. Commit `feat: parse and write Markdown tables and wrap them in the rendered note`.

### Task NX7: Tabellen-Editor als Blatt (TX1b, TX2c, TX3b)

**Files:**
- Create: `Notes/TableEditorSheet.swift`
- Modify: `Notes/NoteEditorView.swift` (ein `sheet`), `Notes/NoteEditorView+Attachments.swift` (Einfügen, Zurückschreiben), `Notes/NoteFormattingBar.swift` (Knopf wechselt zu `tablecells`, wenn die Schreibmarke in einer Tabelle steht), Kataloge
- Test: `NoteEditorUITests`, neu `app/TagwerkTests/TableEditorModelTests.swift`

**Interfaces:**

```swift
@MainActor @Observable final class TableEditorModel {
    var table: MarkdownTable
    var focus: (row: Int, column: Int)        // row 0 is the header
    init(table: MarkdownTable)
    /// "Weiter": the next cell, a new row after the last cell.
    func advance()
    var canDeleteRow: Bool { get }            // false on the header
    var canDeleteColumn: Bool { get }         // false with one column left
    var canAddColumn: Bool { get }            // false at eight columns
}
```

Verhalten:
- Einstiege (TX2c): Tipp auf die Tabelle in der Ansicht (`tagwerk-table:N`); beim Schreiben der Knopf `tablecells` in der Leiste, sobald `MarkdownTable.blockIndex(containingLine:)` für die Zeile der Schreibmarke etwas liefert; „Tabelle“ im Einfügen-Menü legt `MarkdownTable.empty` an der Schreibmarke an und öffnet das Blatt.
- Blatt: Raster aus Textfeldern (einzeilig), Kopfzeile halbfett; „Abbrechen“ verwirft, „Fertig“ schreibt über `MarkdownTable.replacing` und `saveText()`. Fußtext „Die erste Zeile ist die Kopfzeile. In der Notiz steht die Tabelle als Markdown-Text.“
- Leiste über der Tastatur (TX3b): „＋ Zeile“, „＋ Spalte“, „⋯“ (Zeile darüber einfügen, Spalte links einfügen, Zeile nach oben, Zeile nach unten, Ausrichtung, Zeile löschen, Spalte löschen), „Weiter“. Nicht mögliche Aktionen sind ausgegraut.
- Tabellen mit mehr als 8 Spalten öffnet das Blatt nicht: Hinweis „Diese Tabelle hat mehr als 8 Spalten. Bearbeite sie im Text.“ mit dem Knopf „Im Text bearbeiten“ (`beginEditing(atLine:)` an der ersten Tabellenzeile).
- Breite: Spalten teilen sich die Breite bis mindestens 96 pt je Spalte, darüber scrollt das Raster seitlich.

- [ ] **Step 1: Tests.** `advance_movesThroughCellsAndAddsRow`, `canDeleteRow_falseOnHeader`, `canAddColumn_falseAtEight`. UI: `testNewTableFromInsertMenu`, `testEditTableFromView_writesBackAligned`, `testTableButtonAppearsInsideTable`, `testWideTableShowsHint`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: edit tables of a note in a grid sheet`.

**Geräteprüfung (Z1):** Scan mit drei Seiten (automatischer Auslöser, Zuschneiden), Vorschau in Notiz und Karte, Quick Look blättert; Suche findet ein Wort aus dem Scan mit „Im Scan“; Zeichnen mit Finger (und Apple Pencil, falls vorhanden), dunkler Modus zeigt helle Fläche, erneutes Bearbeiten behält Striche; Tabelle anlegen, füllen, Spalte löschen, in der Ansicht mit langer Zelle (Umbruch) und sechs Spalten (seitliches Scrollen mit Rand).

---

## Offene Fragen (mit Empfehlung)

| # | Frage | Empfehlung |
|---|---|---|
| 1 | **NO3c:** SwiftUI bietet für Tab-Einträge kein Kontextmenü. Lässt sich das Halten auf „Aufgaben“ nur über einen Eingriff in die UIKit-Tableiste lösen, der die Bedingungen aus NF2 nicht erfüllt: Was dann? | NO3c entfallen lassen und stattdessen eine Schnellaktion am App-Symbol („Brain Dump schreiben“, „Brain Dump diktieren“) anbieten; NO3b deckt den Weg in der App ab. |
| 2 | **NO14, Zähler und Löschen:** Soll „Tagesstart“ Tage nur mit Dankbarkeit mitzählen, und bleibt ein Tag nach dem Löschen seiner Notiz als Eintrag stehen? | Ja zu beidem (so geplant): Der Ordner ist das Archiv des Morgens; Dankbarkeit wird nur im Tagesstart geleert. |
| 3 | **NO14, Suche:** Dankbarkeit in der App-Suche auffindbar (bisher gar nicht durchsucht)? | Ja, nur in der App-Suche, nie beim Assistenten (NF5). |
| 4 | **NL, Wiederherstellung:** Nach dem Wiederherstellen einer Sicherung mit gesperrten Notizen den Schutz automatisch einschalten? | Ja (Regel 9), sonst wären die Notizen auf dem neuen Gerät offen, bis der Schalter gefunden wird. |
| 5 | **Mitteilungskontingent:** Aufgaben und Deadlines 44, Routinen 17, Fokus 1, Reserve 2? | Ja. Alternative mit zwei Tagen Vorlauf für Bible Study: 45/16/1/2; drei Tage passen zum Vorlauf der Abend-Erinnerungen. Zu prüfen, ob Designgruppe 1 (Erinnerungen ER) eigene Plätze braucht. |
| 6 | **DS7c:** Der iCloud-Container setzt voraus, dass das Entwicklerkonto die iCloud-Berechtigung vergeben kann; mit dem kostenlosen „Personal Team“ ist das voraussichtlich nicht möglich (DS0 prüft es). Bleibt es dann wirklich beim heutigen Stand (sichtbar, unbegrenzt)? | Erledigt (21.11.2026): verborgen in `.Sicherheitskopien` im gewählten Sicherungsordner, ohne iCloud-Berechtigung; DS0 entfällt. |
| 7 | **DS6b, Schlüsselbund:** Abgeleiteten Schlüssel (nicht das Passwort) speichern; Passwort mindestens 8 Zeichen; ältere Dateien behalten ihr altes Passwort nach „Passwort ändern“? | Ja zu allen drei (Teil 2, DS3). |
| 8 | **GW1c:** Vorhandene Gewohnheit „Bewegung“ mit Quelle „Training erfasst“ einmalig auf die kombinierte Quelle umstellen? | Ja, einmalig und nur, wenn Name und Quelle dem alten Vorschlag entsprechen (Teil 2, GW1). |
| 9 | **RO10a, RO15b und Designgruppe 1:** Beide ändern `DayView`. Reihenfolge? | RO7 und RO8 nach dem G1-Strang „Planen“ umsetzen oder dessen Umsetzer mitgeben. |
| 10 | **BV3a, Quelle:** Welche Quelle für die Verszahlen der Schlachter 2000 gilt als maßgeblich, und reicht eine zweite unabhängige Quelle als Gegenprobe? | Ja; BS1 dokumentiert beide. Weichen sie ab, entscheidet der Nutzer mit seiner gedruckten Ausgabe an den genannten Stellen. |
| 11 | **BS5b, Umfang:** „Als Aufgabe anlegen“ nur in Bible-Study-Notizen oder an jeder Checkbox? | Nur Bible Study (wie entschieden); der Mechanismus ist allgemein und lässt sich später öffnen. |
| 12 | **NO15b, VoiceOver:** Falls die Zeilenlinks als „Link“ angesagt werden und `role="text"` nicht hilft: Ansicht für VoiceOver ohne Zeilenlinks, Einstieg über „Bearbeiten“? | Ja (NE3, Punkt 6 der Geräteprüfung). |

## Risiken

- **NO15b:** Die Zuordnung hängt daran, dass WebKit Tipps auf Anker ohne JavaScript zuverlässig als Navigation meldet (für Checkboxen ist das heute so) und dass `TextEditor` die Schreibmarke ins Bild holt. Beides ist nicht am Gerät geprüft. Gegenmittel: Vorprüfung in NE3 Step 1, Stufe B für unbeantwortete Tipps, Stufe C als Konstante. Nebenwirkung der Anker: Textauswahl in der Ansicht kann schwieriger werden; im Schreibmodus bleibt sie normal.
- **Abhängigkeiten von anderen Branches:** NE (A5), NS (#173 Strang B), BS7 und RO4 (#173 Strang E), RO (G3 T), EK (G3 L). Verzögert sich einer, verschiebt sich die Welle; die Namen der Bausteine (`mayLeaveDevice`, `DatedRoutineNotification`, `addDated`, `endNoteSession`) sind aus den Plänen übernommen und vor dem Start gegen `main` zu prüfen.
- **Sperre ist keine Verschlüsselung:** Wer den Gerätecode kennt oder an die Sicherungsdatei kommt, liest alles. Der Titel einer gesperrten Notiz bleibt sichtbar. Beides ist entschieden und wird in der App gesagt, bleibt aber die häufigste Fehlannahme.
- **Suchmodell im Speicher:** Nach dem Sperren darf kein Volltext verborgener Notizen im Such-Modell bleiben (NS4); ein vergessener Neuaufbau wäre ein Leck.
- **Begleitdateien:** Ein Fehler in `removeUnreferenced`/`purgeOrphans` löscht Strichdaten oder lässt Waisen liegen; deshalb eigene Tests in NX2.
- **Texterkennung:** Qualität bei Handschrift und schlechten Scans ist ungeprüft; die Suche findet dann nichts, ohne Fehlermeldung. Vision im Simulator kann von der Hardware abweichen.
- **Dateigröße:** Scans (bis 25 MB je Datei) und Zeichnungen vergrößern die Sicherung, die vollständig im Arbeitsspeicher aufgebaut wird; mit Verschlüsselung (DS3) verdoppelt sich der Spitzenbedarf kurzzeitig.
- **Dateiumfang und Konflikte:** `NoteEditorView`, `NotesListView`, `AppSettings`, `BackupDTOs` und die Kataloge werden von vielen Strängen berührt. Die Wellen und die Regel „ein Modifier je Strang in `NoteEditorView.swift`“ halten das klein; Konflikte in den Katalogen werden durch Neuerzeugen gelöst.
- **Kontrast:** Neue Farben (Ordner, Blitz-Marke) sind gerechnet, nicht gemessen; Strang K misst zuletzt und kann Werte ändern.
- **Umfang:** Rund 50 Tasks in zehn Strängen. Die Stränge sind einzeln auslieferbar; fällt einer weg (zum Beispiel NO3c oder DS4), bleiben die anderen gültig.
