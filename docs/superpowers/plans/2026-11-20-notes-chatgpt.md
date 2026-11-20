# Notizen und Rezepte mit ChatGPT (#232, #233) – Implementation Plan

> **For agentic workers:** Setze den Plan Task für Task um, jeweils mit TDD. Schritte stehen als Checkbox (`- [ ]`). Block A (#232) ist allein lauffähig und wird zuerst gebaut; Block B (#233) baut auf nichts aus Block A auf, außer auf Task A5 (Editor übernimmt fremde Textänderungen).

> **Status:** Entwurf vom 20.11.2026. Grundlage ist `main` auf `e236b5d`. Mockups: `docs/superpowers/mockups/2026-11-20-notes-chatgpt-mockups.html`. Entscheidungen: RT1a, RT2a, RT3c, RT4a, RT5a, NC1c, NC2b, NC3a, NC4a, NC5b, NC6a (Kommentare in #232 und #233). Nichts ist gebaut und nichts am Gerät geprüft.

**Goal:**
- **#232:** Eine strukturierte Rezept-Notiz im Ordner „Rezepte“ lässt sich über „Übersetzen …“ im Mehr-Menü nach Deutsch oder Englisch übersetzen. Übersetzt wird der ganze Notiztext. Ein Vorschau-Blatt zeigt Original und Übersetzung; erst „Original ersetzen“ oder „Als Kopie sichern“ ändert etwas. Die Rezept-Struktur bleibt lesbar (`RecipeNote.parse`), Anhang-Verweise bleiben erhalten, eine Kopie bekommt eigene Anhänge.
- **#233:** Der Assistent kann nicht-private Notizen auflisten, lesen, überarbeiten, anlegen und löschen. Einstieg aus der Notiz-Übersicht, den Ordnerlisten und der geöffneten Notiz, in einem eigenen Chat mit Kontext „Notizen“ oder „Notiz …“. Jede Notiz-Karte wird einzeln bestätigt, Löschen geht nach „Zuletzt gelöscht“. Private Notizen (Tagebuch, Bible Study, Dream Log) verlassen das Gerät nie. Gelesene Notiztexte liegen nur im Arbeitsspeicher der laufenden Sitzung; gespeichert wird nur „Gelesen: Titel“.

**Architecture:**
- **Reine Regeln in `TagwerkCore`:**
  - `RecipeTranslationPlan`: zerlegt den Notiztext in Zeilen-Segmente, baut die Anfrage, setzt die Antwort wieder zusammen und prüft sie (Block A).
  - `RecipeNote.outline` und `RecipeNote.headingLanguage`: Abschnittsfolge und erkannte Sprache einer Rezept-Notiz (Block A).
  - `MarkdownText.replacingAttachmentIDs`: Verweise auf neue Anhang-IDs umschreiben (Block A).
  - `NoteFolderRules.privateFolderIDs` und `mayLeaveDevice`: Privat-Regel über die ganze Ordnerkette (Block B; gleiche Namen wie in `2026-11-20-decisions-173.md`).
  - `NoteDiff`: Zeilenvergleich für Karte und Blatt „Änderungen“ (Block B).
  - `OpenCards.notes` und `VoiceModeMachine`: „alle“ wird bei Notiz-Karten abgelehnt (Block B).
- **`AIKit`:** `ToolHandler` bekommt zwei Hooks mit Standardverhalten (`storedForm`, `showsActivity`), `Conversation` bekommt `storableHistory` und den Nachrichtentyp `.activity`. Das ist der gemeinsame Baustein „nicht gespeichertes Funktionsergebnis“ (siehe Abschnitt „Abstimmung mit `2026-11-20-decisions-173.md`“).
- **App:**
  - Block A: `RecipeTranslator` (eine Anfrage, wie `RecipeImporter`), `RecipeTranslationModel`, `RecipeTranslationSheet`, `NoteStore.duplicate`, `NoteAttachmentStore.duplicate`, Eintrag im Mehr-Menü von `NoteEditorView`.
  - Block B: `NoteToolAccess` (einzige Stelle, die Notizen für ChatGPT filtert), `NoteSession` (Texte der laufenden Sitzung), `NoteChatTools` (`ToolHandler` um `AppTools`, nach dem Muster von `TaskChatTools`), `AssistantModel.Context.notes/.note`, `NoteAssistantConsentSheet`, Notiz-Karten mit `NoteChangeSheet`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, XcodeGen. Kein neues SwiftData-Modell, keine neue Abhängigkeit.

**Issues:** #232, #233. **Branches:** `feat/recipe-translate` (Block A), `feat/notes-assistant` (Block B, zweigt nach dem Merge von Block A ab).

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht deutsch und englisch im Katalog (`Tagwerk/Localizable.xcstrings`, für `TagwerkCore` `Packages/TagwerkCore/Sources/TagwerkCore/Resources/Localizable.xcstrings`) und in `scripts/translations/en.json`. Bestehendes JSON-Format beibehalten, nie den ganzen Katalog neu formatieren. Prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch. Anweisungen an ChatGPT für eine Einzelanfrage englisch (wie `RecipeImporter`), Anweisungen des Assistenten deutsch (wie `AssistantModel.instructions`).
- **Datenschutz:**
  - Private Notizen gehen nie an ChatGPT. Maßgeblich ist ab Block B `NoteStore.isPrivate(_:)`. Block A arbeitet mit einer Positivliste: nur freie Notizen direkt im Ordner mit der Rolle `.recipes`.
  - Notiztext steht in keinem Log, keiner Fehlermeldung und keiner Diagnose (`PlanningDiagnostics`, `VoiceDiagnostics`).
  - Anhänge (Dateien) werden nie gesendet. Die Verweise im Text (`[Name](attachment:UUID)`) gehören zum Notiztext.
- **SwiftData:** kein neues Modell. `AppSettings` bekommt ein Feld mit Standardwert; `BackupDTOs` ein optionales Feld (Muster `mailSummaryConsent`, `BackupDTOs.swift:1184/1267/1346`).
- **SwiftUI-Falle:** Nie `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile in `Form`/`List` hängen.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** Ab dem ersten Task mit App-Code läuft `app/test-all.sh` nach jedem Task (`TAGWERK_SKIP_UI_TESTS=1` für Zwischenstände, der volle Lauf vor dem letzten Commit jedes Blocks).

## Befunde aus dem Quelltext (Stand `e236b5d`)

1. **`RecipeNote.parse` ignoriert Text außerhalb der Abschnitte** (`RecipeNote.swift:47–48`). Eine Übersetzung über `RecipeNote` → `markdown(language:)` würde eigene Anmerkungen und Anhang-Verweise verlieren. Deshalb arbeitet Block A zeilenweise auf dem Originaltext.
2. **Der Editor hält den Text als `@State`** und schreibt ihn nach 500 ms und beim Schließen zurück (`NoteEditorView.swift:95–110`). Jede Änderung von außen (Übersetzung ersetzen, Assistent überarbeitet) würde dadurch überschrieben. Task A5 behebt das für beide Blöcke.
3. **Anhänge hängen an `noteID` und an der eigenen ID im Text.** `removeUnreferenced` (`NoteAttachmentStore.swift:186`) löscht Anhänge einer Notiz, deren ID nicht mehr im Text steht; `NoteStore.delete` löscht alle Anhänge der Notiz. Eine Kopie mit den alten IDs würde ihre Bilder verlieren, sobald das Original endgültig gelöscht wird. Die Kopie braucht eigene Datensätze, eigene Dateien und umgeschriebene Verweise.
4. **Privat-Filter prüft nur den direkten Ordner** (`RecipeNotePicker.swift:34`). `NoteFolderRules.canCreateFolder` verbietet Unterordner unter Systemordnern (`NoteFolderRules.swift:149–154`); ob `validateMove` das Verschieben eines eigenen Ordners unter einen Systemordner verbietet, ist nicht geprüft. Block B prüft deshalb die ganze Ordnerkette und belegt das mit einem Test.
5. **`ChatStore` speichert `conversation.history` vollständig** (`AssistantModel.swift:346–350`), also auch Funktionsergebnisse und die Argumente von Funktionsaufrufen. Für Notizen müssen beide Seiten bereinigt werden: das Ergebnis von `read_note` und die Argumente von `create_note`/`update_note` (sie enthalten den vollen neuen Text).
6. **Lesende Funktionen sind im Chat unsichtbar** (`Conversation.messages`, `Conversation.swift:165–185`). „Gelesen: …“ braucht einen neuen Nachrichtentyp.
7. **`confirmAll` bestätigt alle offenen Karten** (`AssistantModel.swift:308–318`), der Knopf erscheint ab zwei offenen Karten (`ChatView.swift:214–221`). Im Sprachmodus sind Löschungen und fremd zugewiesene Issues gesondert behandelt (`AssistantModel.swift:177–206`, `VoiceModeMachine.swift:390–398`).
8. **Der Chat ist ein Blatt über den Tabs** (`RootView.swift:88–90`). Eine Notiz kann auch in einem eigenen Blatt offen sein (`NoteEditorSheet`, `EntrySheets.swift:52–62`); von dort kann das Chat-Blatt nicht zusätzlich erscheinen.

## Abstimmung mit `2026-11-20-decisions-173.md`

Jener Plan (Stand beim Schreiben dieses Plans gelesen) berührt dieselben Stellen in fünf Punkten. Die Namen in diesem Plan sind bereits an ihn angeglichen, wo das ohne Bedeutungsverlust ging. Die Hauptsitzung entscheidet die Reihenfolge; wer zuerst landet, baut den gemeinsamen Baustein, der andere Branch nutzt ihn.

| Thema | #173 (Task) | Dieser Plan (Task) | Vorschlag zur Zusammenführung |
|---|---|---|---|
| Privat-Regel | `NoteFolderRules.privateFolderIDs(in:)`, `mayLeaveDevice(kind:folderID:privateFolderIDs:)`; stellt `RecipeNotePicker.swift:34` um (Task 3) | B1 | **Identisch übernommen.** B1 baut genau diese zwei Funktionen und darauf `NoteStore.isPrivate`. Landet #173 zuerst, entfällt in B1 alles bis auf `NoteStore.isPrivate` und dessen Tests. |
| Gekürzter Verlauf | `ToolHandler.storedOutput(of:output:)`, `Conversation.storableHistory`; zusätzlich ersetzt `Conversation` nach Zugende alle Ergebnisse im Arbeitsspeicher (D4, Task 4) | B2: `storedForm(of:output:)` kürzt Ergebnis **und Argumente**; `storableHistory` | **Ein Hook, zwei Abweichungen klären.** (a) #233 muss auch Argumente kürzen (`update_note` trägt den vollen neuen Text); `storedForm` ist die Obermenge von `storedOutput`. (b) Das Ersetzen im Arbeitsspeicher nach Zugende widerspricht für `read_note` der Entscheidung „gilt für die laufende Sitzung“: Der Text muss über mehrere Nachrichten hinweg verfügbar bleiben. Vorschlag: zweiter Hook `forgetsAfterTurn(_ name: String) -> Bool` (Standard `false`); `search` liefert `true`, `read_note` `false`. |
| Einwilligung | `assistantNoteSearchConsent`, Schalter „Notizen in der Suche des Assistenten“ (D5); nennt #233 als Nutzer desselben Schalters | B3: `noteAssistantConsent`, Schalter „Notizen mit ChatGPT“, eigenes Blatt (NC5b) | **Offene Entscheidung, siehe Offene Fragen 7.** Die Umfänge unterscheiden sich (Titel und 80 Zeichen Ausschnitt gegen ganzen Text und Änderungen). Empfehlung: zwei Schalter; der weitere (`noteAssistantConsent`) schließt die Suche ein, d. h. `notesAllowed = assistantNoteSearchConsent || noteAssistantConsent`. |
| Einzelbestätigung | `needsSingleConfirmation(_:me:)`, `batchConfirmable`, Kartenfelder `warning` und `confirmTitle` (gesetzt = roter Knopf), `OpenCards.guarded` mit der Ansage „Zuweisungen …“ (Task 2) | B7, B8 | **Namen übernommen:** `batchConfirmable`, `confirmTitle`. `needsSingleConfirmation` wird um die Notiz-Werkzeuge erweitert. Zwei Unterschiede: „Anlegen“ ist ein eigener Knopftext ohne Rot, deshalb zusätzlich `isDestructive` (für #173: bei „Abgeben“ gesetzt). Notiz-Karten zählen im Sprachmodus als `OpenCards.notes`, nicht als `guarded`, weil die Ansage anders lautet. |
| Notizen finden | `search` liefert `note:<uuid>`, Titel, Ausschnitt (Task 3) | B4: `list_notes` mit `query` | Gleiche ID-Form. `search` bleibt im allgemeinen Assistenten, `list_notes`/`read_note` gibt es nur im Notiz-Chat. Beide filtern über dieselbe Privat-Regel. |

## Review Focus

1. **Struktur nach der Übersetzung (#232):** Original und Übersetzung ergeben mit `RecipeNote.parse` dieselbe Abschnittsfolge, dieselbe Zahl an Zutaten und Schritten, dieselben Portionen und dieselbe Quelle. Jede Abweichung führt zu einer Fehlermeldung, nie zu einem übernommenen Text. Tests in Task A1 und A2.
2. **Nichts geht verloren (#232):** Zeilen außerhalb der Rezept-Abschnitte, Leerzeilen, Listenzeichen und Anhang-Verweise stehen nach der Übersetzung an derselben Stelle. Die Menge der Anhang-IDs ist gleich. Tests in Task A1.
3. **Kopie mit eigenen Anhängen (#232):** Nach „Als Kopie sichern“ und endgültigem Löschen des Originals zeigt die Kopie ihre Bilder noch. Test `duplicate_copySurvivesDeletingTheOriginal` in Task A3.
4. **Editor überschreibt nichts (#232, #233):** Nach „Original ersetzen“ und nach einer bestätigten Karte des Assistenten zeigt die offene Notiz den neuen Text; der verzögerte Speicherlauf schreibt den alten nicht zurück. Tests in Task A5.
5. **Privat bleibt privat (#233):** Kein Werkzeug liefert Titel, Text oder Existenz einer privaten oder gelöschten Notiz, auch nicht über eine geratene ID, auch nicht in Unterordnern. Schreibende Werkzeuge lehnen sie ab. Tests in Task B1 und B4.
6. **Gespeicherter Verlauf ohne Notiztext (#233):** Nach `read_note`, `update_note` und `create_note` enthält `ChatStore.history(for:)` weder den gelesenen noch den geschriebenen Text; im Arbeitsspeicher steht er weiter. Tests in Task B2 und B6.
7. **Einzeln bestätigen (#233):** „Alle bestätigen“ erfasst nie eine Notiz-Karte, auch nicht per Stimme. Tests in Task B7 und B8.
8. **Veraltete Vorschläge (#233):** Eine Überarbeitung wird abgelehnt, wenn die Notiz seit dem Lesen geändert wurde (Task B5). Eine zweite offene Karte zur selben Notiz verfällt, sobald die erste bestätigt ist (Task B7).

---

# Block A: Rezept-Notiz übersetzen (#232)

## Ablauf (verbindlich)

1. Mehr-Menü der Notiz: „Übersetzen …“ unter „Zutaten auf die Einkaufsliste“. Sichtbar, wenn die Notiz frei ist, direkt im Ordner `.recipes` liegt und `RecipeNote.parse(text) != nil` ergibt.
2. Blatt Schritt 1: Auswahl „Deutsch“ / „Englisch“. Vorgewählt ist die Sprache, in der das Rezept nicht steht (`RecipeNote.headingLanguage`); ist sie nicht erkennbar, die „Sprache für Rezepte“ (`RecipeLanguage.resolve(setting: settings.recipeLanguage)`). Fußnote: „Tagwerk sendet den Text dieser Notiz an ChatGPT. Du siehst die Übersetzung, bevor sich etwas ändert.“ Knopf „Übersetzen“.
3. Fehlt `shoppingRecipeConsent`, erscheint `RecipeConsentView` (ergänzter Text). Ohne Anmeldung steht „Anmeldung unter Einstellungen › KI“, der Knopf ist aus.
4. Eine Anfrage an ChatGPT. Währenddessen Fortschrittsanzeige mit „Abbrechen“.
5. Blatt Schritt 2 (RT2a): Umschalter „Übersetzung“ / „Original“, darunter der Text als `NoteMarkdownView`. Hinweis: „Vorschlag von ChatGPT. Mengen bleiben unverändert; bitte kurz prüfen. Anmerkungen und Anhänge der Notiz bleiben erhalten.“ Knöpfe „Original ersetzen“ und „Als Kopie sichern“, oben „Verwerfen“.
6. „Original ersetzen“ schreibt den Text in die Notiz. „Als Kopie sichern“ legt eine neue Notiz im selben Ordner an, mit eigenen Anhängen; die Notiz bleibt offen, ein Hinweis nennt die Kopie („Als „Rotes Linsencurry“ gesichert.“).

## Übersetzungsverfahren (verbindlich)

Der Text wird zeilenweise zerlegt. Was Struktur ist, bleibt auf dem Gerät und wird dort in die Zielsprache gesetzt; nur der übersetzbare Teil jeder Zeile geht an ChatGPT.

| Zeile | Behandlung |
|---|---|
| leer | bleibt, wird nicht gesendet |
| nur Anhang-Verweis(e) oder nur eine Adresse | bleibt, wird nicht gesendet |
| Überschrift „Zutaten“/„Ingredients“ | lokal durch die Überschrift der Zielsprache ersetzt (`Localized.string("Zutaten", in:)`) |
| Überschrift „Zubereitung“/„Anleitung“/„Instructions“/„Directions“ | lokal ersetzt („Zubereitung“ bzw. „Instructions“) |
| „Portionen: 4“ / „Servings: 4“ / „Personen: 4“ | Bezeichnung lokal ersetzt, Wert unverändert |
| „Quelle: …“ / „Source: …“ | Bezeichnung lokal ersetzt, Wert unverändert |
| jede andere Zeile | Präfix (Einrückung, `#`-Zeichen, Listenzeichen, Checkbox, Nummer) bleibt; der Rest wird gesendet und übersetzt |

- **Anfrage:** `{"target":"Deutsch","lines":[{"i":3,"text":"250 g red lentils"},…]}`. Antwort mit striktem Schema `{"lines":[{"i":Int,"text":String}]}`.
- **Grenzen:** höchstens 300 gesendete Zeilen und 12 000 Zeichen. Darüber: Fehlermeldung, kein Kürzen (ein gekürzter Text wäre nach „Ersetzen“ verloren).
- **Prüfung der Antwort (alles muss gelten, sonst Fehler „Die Übersetzung passt nicht zur Notiz. Versuch es noch einmal.“):**
  1. Genau dieselben Indizes wie in der Anfrage, jeder einmal.
  2. Kein Text leer, kein Zeilenumbruch im Text.
  3. Je Zeile dieselben Anhang-IDs (`MarkdownText.attachmentReferences`) und dieselben Link-Adressen in derselben Reihenfolge.
  4. In Zeilen des Abschnitts „Zutaten“ dieselben Zahlen in derselben Reihenfolge (Ziffernfolgen, `½ ¼ ¾ ⅓ ⅔` eingeschlossen). Einheiten dürfen übersetzt werden („tbsp“ → „EL“), Zahlen nicht.
  5. Der zusammengesetzte Text ergibt mit `RecipeNote.parse` ein Rezept mit derselben `outline`, derselben Zahl an Zutaten und Schritten, denselben `servings` und derselben `sourceURL` wie das Original.

## Task A1: `RecipeTranslationPlan` in TagwerkCore

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/RecipeTranslationPlan.swift`, `Tests/TagwerkCoreTests/RecipeTranslationPlanTests.swift`. Modify `RecipeNote.swift`.

- [ ] `RecipeNote` (ergänzend, bestehendes Verhalten unverändert):
  - `public enum SectionKind: Sendable, Equatable { case ingredients, steps, other }`
  - `public static func outline(_ markdown: String) -> [SectionKind]`: die Überschriften ab Ebene 2 in Reihenfolge, klassifiziert wie in `parse`. Die bestehende private Klassifizierung dafür in eine gemeinsame Funktion `sectionKind(ofHeading:)` ziehen, damit `parse` und `outline` nicht auseinanderlaufen.
  - `public static func headingLanguage(_ markdown: String) -> VoiceLanguage?`: `.german` bei „Zutaten“, `.english` bei „Ingredients“, sonst `nil`.
  - Die Zeilenhilfen `heading`, `labelled`, `listItem` und die Wortlisten bleiben privat; `RecipeTranslationPlan` liegt im selben Modul und bekommt sie über `internal`.
- [ ] `public struct RecipeTranslationPlan: Sendable, Equatable`:
  - `enum Segment { case fixed(String); case ingredientsHeading(prefix: String); case stepsHeading(prefix: String); case servings(value: String); case source(value: String); case text(prefix: String, body: String, isIngredient: Bool) }`
  - `init(markdown: String)`, `var segments: [Segment]`
  - `var request: [(index: Int, text: String)]`: die `.text`-Segmente mit ihrem Segment-Index.
  - `static let maximumLines = 300`, `static let maximumCharacters = 12_000`, `var isWithinLimits: Bool`
  - `enum Failure: Error, Equatable { case indexMismatch, emptyLine, lineBreak, attachmentsChanged, linksChanged, amountsChanged, structureChanged, notARecipe }`
  - `func assembled(translations: [Int: String], language: VoiceLanguage) throws(Failure) -> String`: prüft die Punkte 1 bis 5 und liefert den neuen Text. Zeilenenden und ein abschließender Zeilenumbruch des Originals bleiben erhalten.
- [ ] Tests:
  - `segments_headingsAndLabelsStayLocal`, `segments_listMarkerAndCheckboxArePrefix`, `segments_numberedStepKeepsItsNumber`
  - `segments_attachmentOnlyLineIsFixed`, `segments_textOutsideSectionsIsTranslatable` (eigene Anmerkung unter dem Rezept)
  - `request_skipsBlankAndFixedLines`
  - `assembled_englishToGerman_keepsStructure` (Beispiel aus dem Mockup: „Red Lentil Curry“ → „Rotes Linsencurry“, Überschriften „Zutaten“/„Zubereitung“, „Portionen: 4“)
  - `assembled_germanAnleitung_becomesZubereitungOrInstructions`
  - `assembled_keepsInlineAttachmentReference`, `assembled_keepsTrailingNewline`
  - `assembled_missingIndex_throwsIndexMismatch`, `assembled_extraIndex_throwsIndexMismatch`
  - `assembled_droppedAttachment_throws`, `assembled_changedLink_throws`
  - `assembled_changedAmountInIngredient_throws` („250 g“ → „255 g“), `assembled_translatedUnit_isAccepted` („2 tbsp curry paste“ → „2 EL Currypaste“)
  - `assembled_otherHeadingTranslatedToZutaten_throwsStructureChanged`
  - `assembled_noteWithoutIngredients_throwsNotARecipe`
  - `isWithinLimits_falseAbove300Lines`
  - `outline_matchesParseClassification`, `headingLanguage_germanEnglishUnknown`
- [ ] `swift test` in `Packages/TagwerkCore`. Commit: `feat: add a line-based translation plan for recipe notes`

## Task A2: `RecipeTranslator` (eine Anfrage an ChatGPT)

**Files:** Create `Tagwerk/Shopping/RecipeTranslator.swift`, `TagwerkTests/RecipeTranslatorTests.swift`. Modify `Tagwerk/App/AppEnvironment.swift`.

- [ ] `@MainActor final class RecipeTranslator`, aufgebaut wie `RecipeImporter` (`responder`, `model`, `hasConsent`, `timeout: .seconds(45)`):
  - `enum Failure: Error, Equatable { case consentMissing, network, signedOut, usageLimit, failed, tooLong, notARecipe, mismatch }` mit `message` (deutsche Texte; `mismatch`: „Die Übersetzung passt nicht zur Notiz. Versuch es noch einmal.“, `tooLong`: „Die Notiz ist zu lang zum Übersetzen.“, `notARecipe`: „Die Notiz hat keinen Abschnitt „Zutaten“.“).
  - `func translate(_ text: String, to language: VoiceLanguage) async throws -> String`:
    1. `RecipeNote.parse(text) != nil`, sonst `.notARecipe` (vor der Einwilligungsprüfung, es wird nichts gesendet).
    2. `hasConsent()`, sonst `.consentMissing`.
    3. Plan bauen, Grenzen prüfen (`.tooLong`).
    4. Eine Anfrage mit `jsonSchema: (name: "recipe_translation", schema:)`, Eingabe als JSON, Zielsprache über `RecipeLanguage.promptName`.
    5. Antwort mit `plan.assembled` prüfen; jeder `RecipeTranslationPlan.Failure` wird `.mismatch`.
  - Ein Stream ohne `completed` gilt als abgebrochen (`ChatGPTError.incomplete`), wie in `NoteSuggestionModel.collect`.
  - `static let instructions` (englisch): Zeilen eines Rezepts übersetzen; jede Zeile einzeln, gleiche Indizes; Zahlen genau so lassen; Einheiten in die übliche Abkürzung der Zielsprache; Markdown-Links, Adressen und `attachment:`-Verweise unverändert; keine Zeile zusammenfassen, teilen oder weglassen; Eigennamen bleiben.
- [ ] Die gemeinsamen Hilfen `collect`, `withTimeout` und `failure(for:)` aus `RecipeImporter` nicht kopieren, sondern in eine kleine Dateierweiterung `RecipeRequest` (im selben Ordner) ziehen, die beide nutzen. Verhalten von `RecipeImporter` bleibt gleich (bestehende Tests).
- [ ] `AppEnvironment`: `let recipeTranslator: RecipeTranslator`, `hasConsent: { settings.shoppingRecipeConsent }`.
- [ ] Tests (mit `FakePlanResponder`):
  - `translate_sendsOnlyTranslatableLines` (keine Überschrift „Ingredients“, kein Anhang-Verweis, keine Quelle in der Eingabe)
  - `translate_withoutConsent_neverCallsTheResponder`
  - `translate_noteWithoutIngredients_neverCallsTheResponder`
  - `translate_returnsAssembledText`
  - `translate_answerWithMissingLine_throwsMismatch`
  - `translate_cutStream_throwsFailed`
  - `translate_tooLong_throwsBeforeSending`
  - `failureMessages_neverContainNoteText`
- [ ] `app/test-all.sh`. Commit: `feat: translate a recipe note with one checked ChatGPT request`

## Task A3: Notiz mit Anhängen kopieren

**Files:** Modify `Tagwerk/Notes/NoteAttachmentStore.swift`, `Tagwerk/Notes/NoteStore.swift`, `Packages/TagwerkCore/Sources/TagwerkCore/MarkdownText.swift`. Tests in `NoteAttachmentStoreTests.swift`, `NoteStoreTests.swift`, `Tests/TagwerkCoreTests/MarkdownTextTests.swift`.

- [ ] `MarkdownText.replacingAttachmentIDs(in markdown: String, with mapping: [UUID: UUID]) -> String`: ersetzt nur Treffer des bestehenden Musters `attachmentReference`; IDs ohne Eintrag bleiben.
- [ ] `NoteAttachmentStore.duplicate(ids: [UUID], to noteID: UUID) -> [UUID: UUID]`: je Anhang ein neuer Datensatz mit neuer ID, gleichem Namen, Typ und `createdAt`, Datei kopiert (vollständiger Dateischutz wie in `write`). Ein Anhang ohne Datei wird ausgelassen. Rückgabe: alte ID → neue ID.
- [ ] `NoteStore.duplicate(_ id: UUID, text: String) -> NoteRecord?`:
  - Neue freie Notiz im selben Ordner, nicht angeheftet, `text` getrimmt (leer → `nil`).
  - Kopiert werden die Anhänge, auf die `text` verweist; die Verweise werden umgeschrieben. Ohne `attachments` (Tests) bleibt der Text unverändert.
  - Eine private oder gelöschte Notiz wird nicht kopiert (`nil`).
- [ ] Tests:
  - `replacingAttachmentIDs_imageAndFileReference`, `replacingAttachmentIDs_unknownIDStays`
  - `duplicateAttachments_newRecordsNewFiles`, `duplicateAttachments_missingFileIsSkipped`
  - `duplicate_createsNoteInSameFolderWithRewrittenReferences`
  - `duplicate_copySurvivesDeletingTheOriginal` (Original `delete`, danach `url(for:)` der Kopie vorhanden)
  - `duplicate_originalKeepsItsAttachments`
- [ ] `app/test-all.sh`. Commit: `feat: duplicate a note together with its attachments`

## Task A4: Einwilligungstext und Datenschutzhinweis

**Files:** Modify `Tagwerk/Shopping/RecipeSheets.swift` (`RecipeConsentView`), `Tagwerk/Shopping/ShoppingSettingsView.swift`, `Tagwerk/Settings/AISettingsView.swift` (`AIPrivacyView`), Kataloge.

- [ ] `RecipeConsentView`: Einleitung „Um ein Rezept zu lesen oder zu übersetzen, …“; unter „Gesendet wird“ der Zusatz „Beim Übersetzen der Text der einen Rezept-Notiz, ohne Anhänge.“; unter „Nur auf dein Tippen“ „Übersetzen“ ergänzen.
- [ ] Schalter „Rezepte mit ChatGPT lesen“ → „Rezepte mit ChatGPT lesen und übersetzen“ (der alte Schlüssel entfällt im Katalog; `scripts/find-unlocalized.py` prüft das).
- [ ] `AIPrivacyView`, Rezept-Absatz: Satz zum Übersetzen ergänzen („Übersetzt du eine Rezept-Notiz, geht ihr Text zeilenweise an ChatGPT; Überschriften, Anhänge und die Quelle bleiben auf dem iPhone.“).
- [ ] Englische Texte in `scripts/translations/en.json`. String-Prüfungen laufen lassen.
- [ ] Commit: `docs: extend the recipe consent to cover translating a recipe note`

## Task A5: Editor übernimmt Textänderungen von außen

**Files:** Modify `Tagwerk/Notes/NoteEditorView.swift`. Create `Tagwerk/Notes/NoteEditorSync.swift`, `TagwerkTests/NoteEditorSyncTests.swift`.

- [ ] Reine Regel `enum NoteEditorSync`: `static func resolution(local: String, lastSaved: String, stored: String?, isTrashed: Bool) -> Resolution` mit `.keep`, `.adopt(String)`, `.close`.
  - `stored == nil` oder `isTrashed` → `.close`.
  - `stored == lastSaved` → `.keep`.
  - `stored != lastSaved` → `.adopt(stored)` (die Änderung kam nicht vom Editor).
- [ ] `NoteEditorView`: `@State lastSavedText`; jede eigene Schreibstelle (`store.updateText`) geht über eine Funktion `saveText()`, die `lastSavedText` mitführt. `.onChange(of: store.revision)` wertet `resolution` aus: `.adopt` setzt `text` und `lastSavedText`, `.close` setzt `wasDeleted = true` und schließt die Seite.
- [ ] Tests: `resolution_ownSaveKeeps`, `resolution_externalChangeAdopts`, `resolution_trashedCloses`, `resolution_missingNoteCloses`.
- [ ] `app/test-all.sh`. Commit: `fix: let the note editor adopt text that changed outside of it`

## Task A6: Blatt und Menüeintrag

**Files:** Create `Tagwerk/Notes/RecipeTranslationModel.swift`, `Tagwerk/Notes/RecipeTranslationSheet.swift`, `TagwerkTests/RecipeTranslationModelTests.swift`. Modify `Tagwerk/Notes/NoteEditorView.swift`.

- [ ] `@MainActor @Observable final class RecipeTranslationModel`:
  - `enum Phase: Equatable { case choosing, translating, preview(original: String, translated: String), failed(String) }`
  - `var target: VoiceLanguage` (Vorauswahl nach Ablauf Punkt 2)
  - `static func isOffered(_ note: NoteRecord, store: NoteStore) -> Bool` (frei, nicht gelöscht, Ordnerrolle `.recipes`, `RecipeNote.parse != nil`)
  - `func translate() async`: liest den gespeicherten Text der Notiz, prüft `isOffered`, ruft `RecipeTranslator`. Ein Zähler `generation` verwirft Antworten nach `cancel()` oder Schließen (Muster `NoteSuggestionModel`).
  - `func replace() -> Bool`: nur wenn der gespeicherte Text noch `original` ist, sonst `failed` („Die Notiz wurde inzwischen geändert.“). Schreibt über `NoteStore.updateText`.
  - `func saveCopy() -> NoteRecord?`: `NoteStore.duplicate(noteID, text: translated)`.
- [ ] `RecipeTranslationSheet`: `NavigationStack`, Schritt 1 und 2 wie im Ablauf; `RecipeConsentView` als Blatt am `Form` bzw. an der äußeren Ansicht; Vorschau mit `NoteMarkdownView` (Anhänge über `store.attachments`, in der Vorschau nicht antippbar). `interactiveDismissDisabled` während `translating`.
- [ ] `NoteEditorView.moreMenu`: Zeile „Übersetzen …“ (`systemImage: "globe"`) nach „Zutaten auf die Einkaufsliste“, sichtbar bei `RecipeTranslationModel.isOffered`. Vor dem Öffnen `saveText()`. Nach „Ersetzen“ übernimmt Task A5 den Text; nach „Kopie“ zeigt der bestehende Hinweis-Alert den Text „Als „…“ gesichert.“ (`shoppingNotice` in `notice` umbenennen).
- [ ] Tests:
  - `isOffered_onlyStructuredNotesInRecipesFolder`
  - `preselection_englishRecipe_offersGerman`, `preselection_unknown_usesRecipeLanguageSetting`
  - `translate_showsPreviewAndChangesNothing`
  - `replace_writesTranslatedText`, `replace_afterNoteChanged_fails`
  - `saveCopy_keepsOriginalAndCopiesAttachments`
  - `cancel_dropsLateAnswer`
  - `translatedNote_stillOffersIngredientsForShopping` (`RecipeImporter.read(.note(...))` liest die übersetzte Notiz lokal, gleiche Zahl an Kandidaten)
- [ ] Strings deutsch und englisch („Übersetzen …“ / „Translate …“, „Rezept übersetzen“, „Übersetzen nach“, „Übersetzung“, „Original“, „Original ersetzen“ / „Replace original“, „Als Kopie sichern“ / „Save as copy“ usw.).
- [ ] Voller Lauf `app/test-all.sh`. Commit: `feat: translate a recipe note from its menu with a preview`

### Gerätetests Block A

1. Englische Rezept-Notiz mit eigener Anmerkung und Foto → Deutsch → „Original ersetzen“: Anmerkung übersetzt, Foto an derselben Stelle, „Zutaten auf die Einkaufsliste“ funktioniert ohne ChatGPT.
2. „Als Kopie sichern“, danach Original löschen und Papierkorb leeren: Die Kopie zeigt das Foto.
3. Erste Nutzung ohne Rezept-Einwilligung: Blatt erscheint, „Nicht jetzt“ sendet nichts.
4. Flugmodus: Fehlermeldung, Notiz unverändert.
5. Englische Oberfläche: Menüeintrag, Blatt, Hinweise.

---

# Block B: Notizen mit ChatGPT (#233)

## Regeln (verbindlich)

- **Sichtbar für ChatGPT** ist eine Notiz, wenn sie nicht gelöscht ist und `NoteStore.isPrivate` falsch ergibt. Für alles andere antworten die Werkzeuge wie bei einer unbekannten ID („Notiz nicht gefunden.“). Die Existenz privater Notizen ist damit nicht ablesbar.
- **Sitzung:** die Lebensdauer der `Conversation` des Notiz-Chats im Arbeitsspeicher. Sie endet mit dem Beenden der App, dem Wechsel in einen anderen Chat (`switchThread`), „Verlauf löschen“ und dem Widerruf der Einwilligung. Danach muss ChatGPT eine Notiz neu lesen.
- **Gespeichert** wird für `list_notes` nur die Anzahl, für `read_note` nur die Titel, für `create_note`/`update_note` nur Titel und IDs. Antworten des Assistenten und Nachrichten des Nutzers bleiben wie bisher im Verlauf und können Notizinhalt zitieren; das steht im Einwilligungsblatt.
- **Ändern:** `update_note` setzt voraus, dass die Notiz in dieser Sitzung gelesen wurde und seitdem unverändert ist. Die Menge der Anhang-IDs im neuen Text muss gleich der im alten sein. Eine Notiz, die beim Lesen gekürzt wurde, kann nicht überarbeitet werden.
- **Anlegen:** nur freie Notizen, in „Notizen“ oder in einem sichtbaren Ordner, der eigene Notizen annimmt (`acceptsOwnNotes`, nicht privat).
- **Löschen:** `NoteStore.trash`. Kein Werkzeug leert den Papierkorb, stellt wieder her, verschiebt oder heftet an.
- **Chat:** ein eigener Verlauf mit dem Schlüssel `"notes"` für beide Kontexte. Die Notiz-Werkzeuge gibt es nur dort.

## Werkzeuge (verbindlich)

| Name | Art | Argumente | Ergebnis |
|---|---|---|---|
| `list_notes` | lesend | `folder_id` (nullable), `query` (nullable, mindestens 2 Zeichen) | `notes`: ID `note:<UUID>`, `title`, `folder`, `updated` (YYYY-MM-DD), bei `query` zusätzlich `matched_in` (`title`/`text`); `folders`: ID und Name der sichtbaren Ordner; `total`. Höchstens 200 Notizen, neueste zuerst. Nie Text. |
| `read_note` | lesend | `note_ids` (1 bis 5) | je Notiz `id`, `title`, `text`, `truncated`; `not_read` für IDs, die nicht mehr in das Ergebnis passten. Text je Notiz höchstens 12 000 Zeichen, Ergebnis insgesamt höchstens 14 000 Zeichen (unter der 16-KB-Grenze von `Conversation.clipped`). |
| `create_note` | schreibend | `text` (erste Zeile ist der Titel), `folder_id` (nullable) | `ok`, `id`, `title` |
| `update_note` | schreibend | `note_id`, `text` (vollständiger neuer Text) | `ok`, `title` |
| `delete_note` | schreibend | `note_id`, `reason` (nullable, kurzer Grund für die Karte) | `ok`, `title`, `trash_days: 30` |

Im Kontext „Notiz …“ (`scope` gesetzt) fehlt `list_notes`; `read_note`, `update_note` und `delete_note` nehmen nur diese eine ID an. `create_note` bleibt möglich.

## Task B1: Privat-Regel über die Ordnerkette

**Files:** Modify `Packages/TagwerkCore/Sources/TagwerkCore/NoteFolderRules.swift`, `Tagwerk/Notes/NoteStore.swift`, `Tagwerk/Shopping/RecipeNotePicker.swift`. Tests in `NoteFolderRulesTests.swift`, `PrivateNotesTests.swift`.

- [ ] `NoteFolderRules.privateFolderIDs(in folders: [NoteFolderInfo]) -> Set<UUID>`: jeder Ordner mit privater Rolle und alle Ordner darunter. Ein Zyklus bricht ab (wie `tree`).
- [ ] `NoteFolderRules.mayLeaveDevice(kind: NoteKind, folderID: UUID?, privateFolderIDs: Set<UUID>) -> Bool`.
- [ ] `NoteStore.isPrivate(_ note: NoteRecord) -> Bool`: `!NoteFolderRules.mayLeaveDevice(kind: note.kind, folderID: note.folderID, privateFolderIDs: …)`.
- [ ] `RecipeNoteSource.isOffered` nutzt `store.isPrivate(note)` (schließt eine heute mögliche Lücke bei Unterordnern, Befund 4).
- [ ] Tests:
  - `privateFolderIDs_includesSubfolders`, `privateFolderIDs_ignoresRecipesAndBrainDump`, `privateFolderIDs_cycleTerminates`, `mayLeaveDevice_freeNoteInJournalFolder_isFalse`, `mayLeaveDevice_dreamKind_isFalse`
  - `storeIsPrivate_freeNoteInJournalFolder`, `storeIsPrivate_freeNoteInSubfolderOfBibleStudy`, `storeIsPrivate_dreamNote`
  - `recipeSource_neverOffersNoteBelowPrivateFolder`
  - `moveFolder_intoSystemFolder_isRejectedOrStaysPrivate`: klärt Befund 4; das Ergebnis in den Abschnitt „Stand der Umsetzung“ schreiben.
- [ ] `app/test-all.sh`. Commit: `fix: treat notes below a private folder as private`

## Task B2: AIKit – gespeicherte Kurzform und sichtbare Lesezeilen

**Files:** Modify `Packages/AIKit/Sources/AIKit/Conversation.swift`. Tests in `Packages/AIKit/Tests/AIKitTests/ConversationTests.swift`.

- [ ] `ToolHandler` (Protokollerweiterung mit Standardverhalten, bestehende Handler bleiben unverändert):
  - `func storedForm(of call: ToolCall, output: String?) -> (arguments: String, output: String?)`: Standard gibt beides unverändert zurück.
  - `func showsActivity(_ name: String) -> Bool`: Standard `false`.
- [ ] `Conversation.storableHistory: [InputItem]`: wie `history`, aber jedes Paar aus `.functionCall` und `.functionOutput` läuft durch `tools.storedForm`. Die Reihenfolge und die `callID`s bleiben; ein Aufruf ohne Ergebnis wird mit `output: nil` übergeben.
- [ ] `ChatMessage.Content` bekommt `case activity(ToolCall, output: String?)`. `Conversation.messages` liefert ihn für lesende Aufrufe mit `tools.showsActivity(name) == true`, an der Stelle des Aufrufs. Alle anderen lesenden Aufrufe bleiben unsichtbar.
- [ ] Tests:
  - `storableHistory_defaultEqualsHistory`
  - `storableHistory_usesStoredFormForCallAndOutput`
  - `storableHistory_keepsCallIDsAndOrder`
  - `messages_showActivityOnlyForOptedInReadTools`
  - `restoredFromPersistableHistory_isValidInput` (keine offenen Aufrufe, `openCallIDs` leer)
- [ ] Alle `switch`-Stellen über `ChatMessage.Content` prüfen (`ChatView.row`, `VoiceModeSheet`, `AssistantModel.reportTurn`/`readNewOutput`); wo `default` steht, ändert sich nichts.
- [ ] `swift test` in `Packages/AIKit`, dann `app/test-all.sh`. Commit: `feat: let tool handlers shorten what a stored chat keeps`

## Task B3: Einwilligung „Notizen mit ChatGPT“

**Files:** Modify `Tagwerk/Persistence/AppSettings.swift`, `Tagwerk/Backup/BackupDTOs.swift`, `Tagwerk/Settings/AISettingsView.swift`. Create `Tagwerk/Notes/NoteAssistantConsentSheet.swift`. Tests in `BackupTests.swift`, `RoutineStoreTests.swift` (Standardwert).

- [ ] `AppSettings.noteAssistantConsent: Bool = false` mit Kommentar („the assistant may list, read and change non-private notes“). `BackupDTOs`: optionales Feld nach dem Muster `mailSummaryConsent`; alte Sicherungen bleiben lesbar.
- [ ] `NoteAssistantConsentSheet` (Aufbau wie `NoteConsentSheet`), Titel „Notizen mit ChatGPT“:
  - Einleitung: „Damit der Assistent deine Notizen durchgehen, überarbeiten, anlegen und löschen kann, sendet Tagwerk Notizen an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.“
  - „**Gesendet wird:** die Titel deiner Notizen und der Text der Notizen, um die es im Gespräch geht, mit den Namen ihrer Anhänge.“
  - „**Nie gesendet werden:** Tagebuch mit Gott, Bible Study und Dream Log, gelöschte Notizen und die Anhänge selbst.“
  - „**Nichts ändert sich ohne dich:** Jede Änderung, jede neue Notiz und jedes Löschen bestätigst du einzeln.“
  - „**Nur im Gespräch:** Ohne deine Nachricht an den Assistenten verlässt nichts das iPhone. Gelesene Notiztexte werden nicht im Verlauf gespeichert; die Antworten des Assistenten schon.“
  - Knöpfe „Einverstanden“ und „Nicht jetzt“; Fußzeile „Du kannst das in den Einstellungen unter „KI“ widerrufen.“
- [ ] Einstellungen › KI: Schalter „Notizen mit ChatGPT“ mit Fußnote („Der Assistent liest und ändert Notizen nur im Notiz-Chat. Tagebuch mit Gott, Bible Study und Dream Log gehen nie an ChatGPT.“). `AIPrivacyView`: eigener Absatz mit denselben Aussagen und der Sitzungsregel.
- [ ] Tests: `noteAssistantConsent_defaultsToFalse`, `backup_roundTripsNoteAssistantConsent`, `backup_withoutTheField_keepsCurrentValue`.
- [ ] `app/test-all.sh`. Commit: `feat: add the consent for the assistant to work with notes`

## Task B4: `NoteToolAccess`, `NoteSession` und die lesenden Werkzeuge

**Files:** Create `Tagwerk/AI/NoteToolAccess.swift`, `Tagwerk/AI/NoteSession.swift`, `Tagwerk/AI/NoteChatTools.swift`, `Tagwerk/AI/NoteChatTools+Definitions.swift`, `TagwerkTests/NoteChatToolsTests.swift`.

- [ ] `@MainActor struct NoteToolAccess { let store: NoteStore }` – die einzige Stelle, die Notizen für ChatGPT auswählt:
  - `func visibleNotes() -> [NoteRecord]` (nicht gelöscht, nicht privat), `func visibleNote(key: String) -> NoteRecord?` (`note:<UUID>`), `func visibleFolders() -> [NoteFolderInfo]`, `func acceptsNewNote(folderID: UUID?) -> Bool`.
  - `func entries(folderID: UUID?, query: String?) -> [Entry]` (Titel über `NoteText.title`, leer → „Ohne Titel“; `query` prüft Titel und Text lokal, jedes Wort muss vorkommen).
- [ ] `@MainActor final class NoteSession`: `private(set) var readTexts: [UUID: String]`, `truncated: Set<UUID>`, `func remember(_:text:truncated:)`, `func reset()`. Wird nirgends gespeichert.
- [ ] `@MainActor final class NoteChatTools: ToolHandler` (Muster `TaskChatTools`):
  - `init(base: AppTools, access: NoteToolAccess, session: NoteSession, hasConsent:, now:)`, `var scope: UUID?`
  - `static let noteReadTools: Set<String> = ["list_notes", "read_note"]`, `static let noteWriteTools: Set<String> = ["create_note", "update_note", "delete_note"]`
  - `definitions`: `base.definitions` plus Notiz-Definitionen (ohne `list_notes` bei gesetztem `scope`); ohne Einwilligung nur `base.definitions`.
  - `run`: ohne Einwilligung `{"error":"Die Einwilligung „Notizen mit ChatGPT“ fehlt."}`.
  - `showsActivity`: wahr für `list_notes` und `read_note`.
  - `storedForm`: `list_notes` → `{"ok":true,"listed":N}`; `read_note` → `{"ok":true,"read":["Titel",…],"note":"Der Text ist nicht mehr verfügbar. Lies die Notiz erneut, wenn du ihn brauchst."}`; `create_note`/`update_note` → Argumente ohne `text`, dafür `title` (erste Zeile, höchstens 80 Zeichen); alles andere unverändert über `base`.
- [ ] `read_note` schreibt jeden gelieferten Text in `NoteSession`. Anhang-Verweise bleiben im Text.
- [ ] Die Schema-Helfer aus `AppTools+Definitions.swift` (`tool`, `string`, `strings`, `object`) von `private` auf intern (`static`) stellen, damit `NoteChatTools+Definitions.swift` sie nutzt statt sie zu kopieren.
- [ ] Tests:
  - `listNotes_excludesPrivateTrashedAndSubfolderOfPrivate`
  - `listNotes_neverContainsText`, `listNotes_queryMatchesTextButReturnsOnlyTitle`
  - `listNotes_folderFilter`, `listNotes_privateFolderID_answersNotFound`
  - `readNote_privateOrTrashedID_answersLikeUnknown` (gleicher Fehlertext wie bei einer erfundenen ID)
  - `readNote_longNote_isTruncatedAndFlagged`, `readNote_overBudget_reportsNotRead`
  - `readNote_remembersTextInSession`
  - `scope_hidesListNotesAndRejectsOtherIDs`
  - `withoutConsent_offersNoNoteToolsAndRunsNone`
  - `storedForm_readNote_keepsTitlesOnly`, `storedForm_listNotes_keepsCountOnly`
  - `baseToolsStillWork` (`list_tasks` läuft über `base`)
- [ ] `app/test-all.sh`. Commit: `feat: add note tools that list and read non-private notes`

## Task B5: Schreibende Werkzeuge

**Files:** Modify `Tagwerk/AI/NoteChatTools.swift`. Tests in `NoteChatToolsTests.swift`.

- [ ] `create_note`: Text getrimmt, nicht leer, höchstens 12 000 Zeichen; `folder_id` über `access.acceptsNewNote`; ohne `folder_id` der Ordner des Kontexts (siehe B6), sonst „Notizen“. Keine `attachment:`-Verweise im Text (Fehler). Der neue Text gilt in der Sitzung als gelesen.
- [ ] `update_note`, in dieser Reihenfolge geprüft, jeweils mit eigenem deutschem Fehlertext:
  1. sichtbar (sonst „Notiz nicht gefunden.“)
  2. in dieser Sitzung gelesen und nicht gekürzt
  3. gespeicherter Text gleich dem gelesenen (sonst „Die Notiz wurde inzwischen geändert. Lies sie erneut.“)
  4. neuer Text nicht leer, höchstens 12 000 Zeichen, vom alten verschieden
  5. gleiche Menge an Anhang-IDs
  Danach `store.updateText` und `session.remember` mit dem neuen Text.
- [ ] `delete_note`: sichtbar, dann `store.trash`. Ergebnis nennt den Titel.
- [ ] `storedForm` für die drei schreibenden Werkzeuge mit Tests abdecken.
- [ ] Tests:
  - `createNote_landsInGivenFolder`, `createNote_privateFolder_isRejected`, `createNote_routineFolder_isRejected`, `createNote_withAttachmentReference_isRejected`
  - `updateNote_withoutRead_isRejected`, `updateNote_afterExternalChange_isRejected`, `updateNote_truncatedRead_isRejected`
  - `updateNote_droppingAttachment_isRejected`, `updateNote_writesTextAndAllowsFollowUp`
  - `updateNote_privateNote_isRejected` (ID direkt übergeben)
  - `deleteNote_movesToTrashAndKeepsAttachments`, `deleteNote_privateNote_isRejected`, `deleteNote_alreadyTrashed_answersNotFound`
  - `storedForm_updateNote_dropsText`, `storedForm_createNote_dropsText`
- [ ] `app/test-all.sh`. Commit: `feat: let the note tools create, revise and trash notes after confirmation`

## Task B6: Kontext, eigener Chat und Anweisungen

**Files:** Modify `Tagwerk/AI/AssistantModel.swift`, `Tagwerk/AI/ChatView.swift`, `Tagwerk/App/AppEnvironment.swift`. Tests in `AssistantModelTests.swift` (neue Suite `AssistantNotesTests.swift`).

- [ ] `AssistantModel.Context`: `case notes(folderID: UUID?)`, `case note(UUID)`.
- [ ] `ChatStore.notesKey = "notes"`. `AssistantModel`: `@ObservationIgnored var noteTools: NoteChatTools?`, `var hasNoteConsent: () -> Bool`.
  - `func open(notes folderID: UUID?)` und `func open(note id: UUID)`: ohne Einwilligung oder ohne `noteTools` geschieht nichts (die Oberfläche fragt vorher). Setzt `noteTools.scope`, wechselt mit `switchThread(to: ChatStore.notesKey, tools: noteTools)`.
  - `switchThread` ruft beim Verlassen des Notiz-Chats `noteTools.session.reset()`; `clear()` ebenso.
  - `persist()` speichert `conversation.storableHistory` statt `conversation.history`.
- [ ] `instructions()`: bei Notiz-Kontext ein zusätzlicher deutscher Abschnitt:
  - Werkzeuge und Reihenfolge: zuerst `list_notes`, Text nur der Notizen lesen, die für die Bitte nötig sind.
  - Jede Änderung als eigener Funktionsaufruf, nie mehrere Notizen in einem und höchstens eine Änderung je Notiz und Antwort; nicht im Text um Bestätigung bitten.
  - `update_note` braucht den vollständigen neuen Text; die erste Zeile ist der Titel; Markdown; Verweise der Form `(attachment:…)` unverändert übernehmen.
  - Papierkorb, Verschieben und Anhänge stehen nicht zur Verfügung.
  - Fester Satz (`AssistantModel.privateNotesSentence`): „Darauf habe ich keinen Zugriff. Tagebuch mit Gott, Bible Study und Dream Log bleiben auf deinem iPhone und werden nie an ChatGPT gesendet.“ Fragt der Nutzer nach diesen Ordnern, antwortet das Modell mit genau diesem Satz (englisch: eigene Fassung im Katalog, gewählt nach der Antwortsprache).
  - `contextText()`: „Ansicht: Notizen (N sichtbare Notizen; Einzelheiten über list_notes).“ bzw. mit Ordnername und -ID; für `.note`: „Das Gespräch betrifft die Notiz „Titel“ (id note:…). Lies sie mit read_note.“ Kein Notiztext in den Anweisungen.
- [ ] `ChatView`:
  - `contextText`: „Kontext: Notizen · ohne Tagebuch, Bible Study, Dream Log“ (mit `lock`-Symbol statt `scope`), mit Ordner „Kontext: Notizen in „Brain Dump“ · ohne …“, für eine Notiz „Kontext: Notiz „Titel“ · ohne …“. Die Namen der privaten Ordner kommen aus dem Store (umbenannte Ordner).
  - Zeile für `.activity`: grau, klein, `assistant.activityText(call, output:)` → „Gelesen: 42 Titel“, „Gelesen: 9 Titel aus „Brain Dump““, „Gelesen: „A“, „B““. Die Texte entstehen aus dem Ergebnis-JSON und funktionieren auch mit der gespeicherten Kurzform.
  - Leerer Notiz-Chat: eigener Hinweistext („Frag nach deinen Notizen oder bitte um Änderungen. Jede Änderung bestätigst du einzeln.“).
- [ ] `AppEnvironment`: `NoteChatTools` aus `tools`, `notes`, `settings.noteAssistantConsent` bauen und an `assistant` hängen.
- [ ] Tests (mit `FakePlanResponder`, der Funktionsaufrufe liefert):
  - `openNotes_withoutConsent_doesNothing`
  - `openNotes_usesNotesThreadAndOffersNoteTools`, `openGeneral_offersNoNoteTools`
  - `readNote_storedHistoryHoldsTitlesOnly_memoryHoldsText`
  - `updateNote_storedHistoryHoldsNoText` (weder alter noch neuer Text in `ChatStore.history(for: "notes")`)
  - `reopenedAfterRestart_updateNeedsNewRead`
  - `switchingToGeneralChat_resetsSession`
  - `instructions_notesContext_containPrivateSentenceAndNoNoteText`
  - `activityText_fromFullAndFromStoredOutput`
- [ ] `app/test-all.sh`. Commit: `feat: open a notes chat with its own context and session-only note text`

## Task B7: Notiz-Karten, „Änderung ansehen“ und Einzelbestätigung

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/NoteDiff.swift`, `Tests/TagwerkCoreTests/NoteDiffTests.swift`, `Tagwerk/AI/NoteChangeSheet.swift`. Modify `Tagwerk/AI/ActionCardDescriber.swift`, `Tagwerk/AI/AssistantModel.swift`, `Tagwerk/AI/ChatView.swift`. Tests in `AssistantNotesTests.swift`, `ActionCardDescriberTests` (bestehende Datei suchen, sonst neu).

- [ ] `NoteDiff` (TagwerkCore): `static func lines(old: String, new: String) -> [Line]` mit `Line.Kind { same, added, removed }` (über `CollectionDifference` auf Zeilen); `struct Summary { added: Int, removed: Int, titleChanged: Bool }`, `static func summary(old:new:)`.
- [ ] `AssistantModel.ActionCard` bekommt optionale Felder mit Standardwerten: `detail: NoteCardDetail? = nil`, `confirmTitle: String? = nil`, `isDestructive = false`. `enum NoteCardDetail: Equatable { case update(title: String, before: String, after: String); case create(text: String); case delete(text: String) }`. Bestehende Karten bleiben unverändert.
- [ ] `ActionCardDescriber`: `var noteAccess: NoteToolAccess?`. Texte:
  - `update_note`: Titel „Notiz „X“ überarbeiten“, Kurztext aus `NoteDiff.summary` („3 Zeilen neu · 2 entfernt · Titel geändert“; gesprochen ohne „·“).
  - `create_note`: „Neue Notiz „Titel““, „Ordner „Brain Dump“ · 8 Zeilen“, `confirmTitle` „Anlegen“.
  - `delete_note`: „Notiz „X“ löschen“, Grund (falls gegeben) und „Kommt nach „Zuletzt gelöscht“ und bleibt dort 30 Tage wiederherstellbar.“, `confirmTitle` „Löschen“, `isDestructive`.
  - Mit gespeicherter Kurzform (kein `text`) oder nicht mehr sichtbarer Notiz: Titel aus `title`, kein `detail`.
  - `detail` wird nur für offene Karten gefüllt; der Text stammt aus dem Store bzw. den Argumenten und wird nur angezeigt, nicht gesendet.
- [ ] `ActionCardView`: Verweis „Änderung ansehen ›“ bzw. „Notiz ansehen ›“ bei `detail != nil`; Knopfbeschriftung aus `confirmTitle`; roter Knopf bei `isDestructive`; Kopfzeile „Vorschlag i von n · noch nicht ausgeführt“, wenn mehrere Notiz-Karten offen sind; nach dem Löschen „✓ Ausgeführt · 09:42 · In „Zuletzt gelöscht““.
- [ ] `NoteChangeSheet`: für `update` Umschalter „Vorher“ / „Nachher“ / „Änderungen“ (Änderungen als Zeilenliste mit „+“/„−“, Farbe und Accessibility-Label „neu“/„entfernt“, keine Durchstreichung), für `create` und `delete` nur der Text. Unten „Verwerfen“ und der Bestätigungsknopf; beide schließen das Blatt und rufen `assistant.decline`/`confirm`. Das Blatt hängt an der `ChatView`, nicht an der Kartenzeile im `LazyVStack`.
- [ ] `AssistantModel`:
  - `var batchConfirmable: [ToolCall]`: offene Karten ohne `NoteChatTools.noteWriteTools`.
  - `confirmAll()` bestätigt nur `batchConfirmable`.
  - Nach einer erfolgreich bestätigten Karte von `update_note` oder `delete_note` werden weitere offene Karten zur selben `note_id` automatisch verworfen (`conversation.decline`). Ohne das würde eine zweite Überarbeitung, die noch auf dem alten Text beruht, die erste überschreiben: Die Prüfung „seit dem Lesen unverändert“ greift hier nicht, weil die Sitzung nach dem ersten Schreiben den neuen Text als gelesen führt.
- [ ] `ChatView.composer`: „Alle bestätigen (n)“ nur bei `batchConfirmable.count > 1`, n ist deren Zahl. Sind Notiz-Karten offen, darunter klein „Notiz-Änderungen bestätigst du einzeln.“
- [ ] Tests:
  - `NoteDiffTests`: `summary_addedRemovedAndTitle`, `lines_keepOrder`, `summary_identicalTexts_isEmpty`
  - `describe_updateNote_summarisesAndCarriesBeforeAfter`, `describe_createNote_namesFolderAndLines`, `describe_deleteNote_mentionsTrash`
  - `describe_storedForm_hasNoDetail`
  - `confirmAll_skipsNoteCards` (zwei Aufgaben-Karten und eine Notiz-Karte: danach ist nur die Notiz-Karte offen, die Notiz unverändert)
  - `batchConfirmable_onlyNoteCards_isEmpty`
  - `confirmUpdate_declinesOtherOpenCardsForTheSameNote`
- [ ] `app/test-all.sh`. Commit: `feat: show note changes as cards with a before and after sheet`

## Task B8: Sprachmodus

**Files:** Modify `Packages/TagwerkCore/Sources/TagwerkCore/Voice/VoiceReply.swift`, `VoiceModeMachine.swift`, `ActionAnnouncement.swift`, `Tagwerk/AI/AssistantModel.swift`. Tests in `VoiceModeMachineTests.swift`, `VoiceReplyTests.swift`, `AssistantNotesTests.swift`.

- [ ] `OpenCards`: neues Feld `notes: Int = 0` (Karten von `create_note`/`update_note`). `delete_note` zählt zu `deletes` und braucht damit wie heute „Ja, löschen“.
- [ ] `VoiceModeMachine`: `.confirmAll where cards.notes > 0` → `say(.notesNeedSingle)`, eingeordnet nach der Prüfung auf `deletes`. Neue Ansage: „Notiz-Änderungen bitte einzeln bestätigen.“ / „Please confirm changes to notes one by one.“
- [ ] `AssistantModel.openCards` füllt `notes` und zählt `delete_note` bei `deletes` mit. `confirmCards`: mehrere Karten nur, wenn keine davon eine Notiz-Karte ist (zusätzlich zur bestehenden Bedingung).
- [ ] Tests:
  - `confirmAll_withNoteCard_isRejectedWithNotice`
  - `confirm_singleNoteCard_startsCountdown`
  - `confirm_singleDeleteNote_asksForDelete`
  - `confirmCards_twoIDsWithNoteCard_isRejected`
  - `openCards_countsNoteCards`
- [ ] `swift test` in `Packages/TagwerkCore`, `app/test-all.sh`. Commit: `feat: confirm note cards by voice only one at a time`

## Task B9: Einstiege in den Notizen

**Files:** Modify `Tagwerk/Notes/NotesFoldersView.swift`, `Tagwerk/Notes/NotesListView.swift`, `Tagwerk/Notes/NoteEditorView.swift`, `Tagwerk/App/EntrySheets.swift`. Create `Tagwerk/Notes/NoteAssistantButton.swift`. Tests in `AssistantNotesTests.swift`, UI-Test nach dem Muster der bestehenden `TagwerkUITests`.

- [ ] `NoteAssistantToolbarItems(target:)` mit `enum Target { case overview, folder(UUID?), note(UUID) }`: gleicher lila Knopf wie `AssistantButton` (Label „Assistent“, Hinweis „Öffnet ChatGPT für deine Notizen“). Tippen: mit Einwilligung `assistant.open(notes:)` bzw. `open(note:)`, sonst `NoteAssistantConsentSheet`; „Einverstanden“ setzt `noteAssistantConsent` und öffnet den Chat. Das Blatt hängt an der Seite, nicht am Toolbar-Element.
- [ ] Sichtbarkeit als reine Funktion `NoteAssistantEntry.isOffered(target:store:)`:
  - Übersicht, „Alle Notizen“, „Notizen“ und eigene Ordner: ja.
  - Privater Ordner (auch Unterordner) und „Zuletzt gelöscht“: nein.
  - Notiz: nur wenn sichtbar nach `NoteToolAccess`; vor dem Öffnen `saveText()` (Task A5).
- [ ] `NoteEditorView` bekommt `showsAssistant: Bool = true`; `NoteEditorSheet` übergibt `false` (Befund 8).
- [ ] Nach einer bestätigten Überarbeitung zeigt die offene Notiz den neuen Text, nach bestätigtem Löschen schließt sie sich (Task A5).
- [ ] Tests:
  - `isOffered_privateFolderAndTrash_false`, `isOffered_privateNote_false`, `isOffered_ownFolder_true`
  - `openNote_setsScopeToThatNote`
  - UI-Test `notesAssistant_consentThenChat`: Knopf in der Übersicht, Einwilligungsblatt, Kontextzeile sichtbar (Demo-Transport).
- [ ] Voller Lauf `app/test-all.sh`. Commit: `feat: open the notes chat from the notes overview, a folder and a note`

### Gerätetests Block B

1. Übersicht → Assistent → „Welche Notizen zum Umzug sind doppelt?“: Zeilen „Gelesen: N Titel“ und „Gelesen: „…““, eine Löschkarte; nach „Löschen“ liegt die Notiz in „Zuletzt gelöscht“.
2. „Was steht in meinem Tagebuch von gestern?“: fester Satz, keine Lesezeile.
3. Offene Notiz → Assistent → „Mach daraus eine saubere Liste“: Karte, „Änderung ansehen“ mit drei Ansichten, nach „Bestätigen“ zeigt die Notiz dahinter den neuen Text.
4. Notiz mit Foto überarbeiten lassen: Das Foto bleibt.
5. Drei Notiz-Vorschläge: kein „Alle bestätigen“; zusammen mit zwei Aufgaben-Karten erfasst „Alle bestätigen (2)“ nur diese.
6. App beenden und neu öffnen: Verlauf zeigt „Gelesen: …“ und die erledigten Karten; eine erneute Überarbeitung liest die Notiz neu.
7. Sprachmodus: „ja“ bestätigt eine einzelne Notiz-Karte, „alle bestätigen“ wird mit der Ansage abgelehnt, Löschen verlangt „ja, löschen“.
8. Einwilligung in Einstellungen › KI ausschalten: Der Knopf fragt wieder, ein offener Notiz-Chat hat keine Notiz-Werkzeuge mehr.
9. Englische Oberfläche: Einwilligung, Kontextzeile, Karten, Blatt.

---

## Reihenfolge und Abhängigkeiten

```
Block A (#232):  A1 → A2 → A6
                 A3 ─────→ A6
                 A4 ─────→ A6
                 A5 ─────→ A6
Block B (#233):  B1 → B4 → B5 → B6 → B7 → B8
                 B2 ──────────→ B6
                 B3 → B4
                 A5, B6, B7 → B9
```

- A1, A3, A4 und A5 sind voneinander unabhängig und können parallel laufen.
- B1, B2 und B3 sind voneinander unabhängig. B1 und B2 sind die Bausteine, die auch `2026-11-20-decisions-173.md` baut (dort Task 3 und 4); B7 überschneidet sich mit dessen Task 2. Nur einer der beiden Branches baut sie, der andere setzt darauf auf.
- Block B setzt aus Block A nur A5 voraus.

## Nicht im Umfang

- Umrechnen von Einheiten beim Übersetzen, Übersetzen anderer Notizen als Rezept-Notizen, weitere Sprachen.
- Verschieben, Anheften und Wiederherstellen von Notizen durch den Assistenten, Papierkorb leeren, Anhänge lesen oder anlegen.
- Notiz-Werkzeuge im allgemeinen Assistenten und im Aufgaben-Chat (Ausnahme: `search` nach #173, siehe Abstimmung).
- Versionsgeschichte für Notizen.

## Offene Fragen (mit Empfehlung)

1. **Fester Antwortsatz zu privaten Notizen (NC5b).** Das Mockup sagt, der Satz komme von Tagwerk. Technisch gesichert ist nur, dass die Werkzeuge nichts Privates liefern; den Wortlaut der Antwort schreibt das Modell nach Anweisung. Eine lokale Abfangregel (Nachricht nennt einen privaten Ordner → Tagwerk antwortet selbst) würde auch harmlose Bitten blockieren („Leg die Notiz „Tagebuch kaufen“ an“). **Empfehlung:** Satz in den Anweisungen, Wortlaut nicht garantiert; keine lokale Abfangregel.
2. **Sitzungsende.** Der Plan nimmt die Lebensdauer der `Conversation` im Arbeitsspeicher. Strenger wäre: Texte verfallen schon beim Schließen des Chat-Blatts. Das würde offene Karten ungültig machen. **Empfehlung:** wie geplant.
3. **Dateinamen von Anhängen** stehen im Notiztext und gehen beim Lesen mit. Maskieren wäre möglich, kostet aber eine Rückübersetzung beim Schreiben. **Empfehlung:** mitsenden, im Einwilligungsblatt nennen (ist eingeplant).
4. **Mengenprüfung beim Übersetzen.** Die Regel „gleiche Zahlen in Zutatenzeilen“ lehnt ab, wenn ChatGPT „1 1/2“ zu „1,5“ macht. **Empfehlung:** streng bleiben und in der Anweisung verlangen, Zahlen unverändert zu lassen; lockern erst, wenn Gerätetests häufige Ablehnungen zeigen.
5. **Unstrukturierte Notizen im Ordner „Rezepte“** bekommen kein „Übersetzen …“. **Empfehlung:** so lassen; ohne Abschnitt „Zutaten“ gibt es keine Struktur, die zu prüfen wäre.
6. **`list_notes` mit `query`** überschneidet sich mit der Notiz-Suche aus #173. **Empfehlung:** `query` behalten (der Notiz-Chat braucht die Suche auch ohne #173, und `list_notes` liefert anders als `search` keinen Ausschnitt).
7. **Ein oder zwei Schalter für Notizen beim Assistenten.** #173 plant „Notizen in der Suche des Assistenten“ (Titel und Ausschnitt), dieser Plan „Notizen mit ChatGPT“ (ganzer Text, Ändern, Anlegen, Löschen). Ein gemeinsamer Schalter wäre einfacher, würde aber jeden, der nur die Suche will, in den weiteren Umfang einwilligen lassen. **Empfehlung:** zwei Schalter; der weitere schließt die Suche ein.
8. **Kürzen im Arbeitsspeicher nach Zugende** (#173, D4) gegen „gilt für die laufende Sitzung“ (#233). **Empfehlung:** je Werkzeug wählbar (`forgetsAfterTurn`), `read_note` behält den Text bis zum Sitzungsende.

## Risiken

- **Zeilenweise Übersetzung:** Ein Absatz über mehrere Zeilen wird zeilenweise übersetzt; die Zeilen gehen in einer Anfrage mit, ChatGPT sieht also den Zusammenhang, die Satzstellung kann trotzdem holpern. Die Vorschau zeigt das vor dem Übernehmen.
- **Strenge Prüfung:** Jede Abweichung führt zu einer Fehlermeldung statt zu einem Ergebnis. Bei langen Rezepten kann das mehrere Versuche kosten.
- **`ChatMessage.Content` wächst um einen Fall:** Jede erschöpfende `switch`-Stelle muss angepasst werden (Task B2 listet sie).
- **Gespeicherte Argumente werden verändert:** Der wiederhergestellte Verlauf enthält für `update_note` Argumente ohne `text`. Das Modell sieht dann einen eigenen früheren Aufruf, der nicht zum Schema passt. Die Responses-API prüft frühere Aufrufe nicht gegen das Schema (Annahme, am Gerät zu prüfen, Gerätetest 6).
- **Antworten zitieren Notizen:** Der gespeicherte Verlauf kann über die Antworten des Assistenten Notizinhalt enthalten. Das ist benannt, aber nicht verhindert.
- **Voller Text je Überarbeitung:** `update_note` schickt den ganzen neuen Text als Argument. Bei langen Notizen ist das langsam; über 12 000 Zeichen ist Überarbeiten ausgeschlossen.
- **Zwei offene Karten zur selben Notiz:** Nach der ersten Bestätigung wird die zweite automatisch verworfen (Task B7). Das ist gewollt, kann aber überraschen; die Anweisungen verlangen deshalb höchstens eine Änderung je Notiz und Antwort.
