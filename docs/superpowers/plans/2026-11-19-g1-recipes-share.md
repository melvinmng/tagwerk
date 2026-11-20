# G1 Rezepte und Teilen – Implementation Plan

> **For agentic workers:** Setze den Plan Task für Task um, jeweils mit TDD. Schritte stehen als Checkbox (`- [ ]`).

> **Status:** Entwurf vom 20.11.2026, ohne Mockups. Die Designrunde folgt in #188. Grundlage ist `main` auf `7e1f989`. Nichts ist gebaut und nichts am Gerät geprüft.

**Goal:**
- **#214:** Rezepte liegen als Notizen in einem festen Ordner „Rezepte“, mit Titel, Portionen, Zutaten und Anleitung. Der Rezept-Import kann zusätzlich eine Rezept-Notiz anlegen. „Rezept hinzufügen“ nimmt eine Rezept-Notiz als Quelle. Ist die Notiz strukturiert, läuft das ohne ChatGPT.
- **#214, Erweiterung (Product Owner):** Ein Rezept lässt sich auch nur speichern, ohne die Einkaufsliste anzufassen. In den Notizen, Ordner „Rezepte“, gibt es dafür „Rezept mit ChatGPT anlegen“ (neben dem normalen „Neu“). Der Einstieg nutzt denselben Import (Foto, Text, Link, dieselben Einwilligungsregeln) und endet in einem Bestätigungsschritt, der das Ergebnis als strukturierte Rezept-Notiz (Titel, Portionen, Zutaten, Schritte) im Ordner „Rezepte“ sichert. Aus dieser Notiz läuft später „Zutaten zur Einkaufsliste“ mit der Portionsfrage. Umgekehrt behält der Einkaufs-Import den Schalter „Auch als Rezept-Notiz sichern“. Beide Wege teilen einen Lese-Schritt (`RecipeImporter.read`).
- **#215:** Vor dem Hinzufügen fragt Tagwerk nach der Portionszahl. Vorschlag ist die Zahl aus dem Rezept, die Mengen werden umgerechnet.
- **#216:** Die Zutaten kommen in der Sprache der App.
- **#217:** Geteilter Text aus Safari trägt die Adresse der Seite als Markdown-Link.

**Architecture:**
- **Reine Regeln** liegen in `TagwerkCore`:
  - `RecipeNote`: Format, Lesen und Schreiben der Rezept-Notiz
  - `IngredientLine`: Menge, Einheit und Name einer Zutatenzeile
  - `RecipeScaler`: Umrechnen und Runden
  - `NoteFolderRole.recipes`
  - `SharePayload`, `NewTaskPrefill`: Link als Markdown
- **Die App** erweitert die vorhandenen Bausteine:
  - `RecipeImporter`: Schema, Prompt, Ergebnis mit Portionen, Titel und Schritten
  - `RecipeSheets`: Quelle „Notiz“, Portionsfrage, „Als Rezept-Notiz sichern“
  - `NoteStore+DefaultFolders`, `NotesFoldersView`, `ShareNoteSheet`
  - die Teilen-Erweiterung: ein JavaScript-Vorverarbeitungsskript für Safari

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, XcodeGen. `swift-markdown` ist schon da (P5) und wird hier nur zum Rendern genutzt. Das Lesen der Rezept-Notiz geschieht zeilenbasiert in `TagwerkCore`.

**Issues:** #214, #215, #216, #217. **Branch:** `feat/recipes-notes-servings`.

## Global Constraints

- **Parallelbetrieb:**
  - G2 ändert das Widget-Target und `project.yml`.
  - G3 baut ein UI-Test-Target und ändert Accessibility-Modifier in vielen Views.
  - Deshalb nur kleine, rein ergänzende Eingriffe in geteilte Dateien: `project.yml` (nur die Info.plist bzw. Ressource der Erweiterung), `Localizable.xcstrings`, `scripts/translations/en.json`, `AppSettings`, `BackupDTOs`. Keine Umbenennungen.
- **Strings:**
  - Deutsch ist Quellsprache, jeder neue Text steht deutsch und englisch im Katalog.
  - Neue Schlüssel im bestehenden JSON-Format eintragen (sortierte Schlüssel, 2 Leerzeichen, `": "`). Nie den ganzen Katalog neu formatieren (siehe BRIEF).
  - Prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Datenschutz:**
  - Es gilt die Rezept-Zustimmung aus P5 (`shoppingRecipeConsent`).
  - Eine strukturierte Rezept-Notiz wird lokal gelesen, es geht nichts an ChatGPT.
  - Nur eine unstrukturierte Notiz, die der Nutzer ausdrücklich als Quelle wählt, geht nach Zustimmung und Tippen auf „Zutaten holen“ als Rezepttext an ChatGPT. Das ist dieselbe Regel wie bei eingefügtem Text.
  - Private Ordner (Tagebuch, Bible Study, Dream Log) erscheinen nie in der Auswahl.
- **SwiftData:** Es gibt kein neues Modell. Die Rezept-Notiz ist eine normale `NoteRecord` (`kind == .free`) im Ordner mit der Rolle `.recipes`. Gespeichert wird als Markdown im Notiztext.
- **SwiftUI-Falle:** Nie `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile innerhalb von `Form`/`List` hängen.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** `app/test-all.sh` läuft vor dem letzten Commit. Ab Task 4 läuft es nach jedem Task, der App-Code ändert.

## Format der Rezept-Notiz (verbindlich)

```
# Linsencurry

Portionen: 4

## Zutaten
- 250 g rote Linsen
- 1 Dose Kokosmilch (400 ml)
- 2 Zwiebeln
- Salz nach Geschmack

## Zubereitung
1. Zwiebeln würfeln und andünsten.
2. …

Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/…)
```

- **Überschriften:** Erkannt werden deutsch und englisch, ohne Rücksicht auf Groß- und Kleinschreibung: „Zutaten“/„Ingredients“, „Zubereitung“/„Anleitung“/„Instructions“/„Directions“, „Portionen“/„Servings“/„Personen“. Geschrieben wird immer in der Sprache der App.
- **Titel:** die erste `#`-Überschrift, sonst die erste Zeile (wie `NoteText.title`).
- **Zutaten:** Die Zeilen unter der Überschrift „Zutaten“ bis zur nächsten `##`-Überschrift. Spiegelstriche und nummerierte Punkte werden entfernt. Leere Zeilen werden übersprungen.
- **Strukturiert:** Eine Notiz gilt als strukturiert, wenn ein Abschnitt „Zutaten“ mit mindestens einer Zeile da ist. Die Portionen dürfen fehlen.
- **Quelle:** Die Zeile „Quelle“ steht nur bei einem Import per Link. Die Adresse wurde ohnehin geöffnet. Bei Text oder Foto fehlt sie.

## Review Focus

1. **Umrechnen und Runden:** Bei 4 → 6 Portionen wird „250 g“ zu „375 g“, „1 Dose“ zu „1,5 Dosen“ und „1 Ei“ zu „2 Eier“. Stückzahlen ohne Einheit werden aufgerundet. „Salz nach Geschmack“, „etwas Öl“ und „1 Prise“ bleiben unverändert. Tests in Task 2.
2. **Lokal statt ChatGPT:** Wird eine strukturierte Rezept-Notiz als Quelle gewählt, ruft Tagwerk den Responder nie auf, und die Kategorien kommen aus `ShoppingClassifier`. Test: `RecipeImporterTests.structuredNote_neverCallsTheResponder`.
3. **Übersetzung:** Bei englischer App-Sprache und deutschem Rezept nennt die Eingabe an ChatGPT die Sprache „English“, und die Anweisung verlangt Namen und Einheiten in dieser Sprache. Tests in Task 5.
4. **Teilen mit Link:** Markierter Text aus Safari ergibt eine Notiz mit dem Text und einer Zeile `[Seitentitel](https://…)`. Die rohe Adresse steht nicht zusätzlich darin. Tests in Task 8.

---

## Task 1: `IngredientLine` in TagwerkCore (#215)

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/IngredientLine.swift`, `Tests/TagwerkCoreTests/IngredientLineTests.swift`

- [ ] `public struct IngredientLine: Sendable, Hashable` mit diesen Feldern:
  - `amount: Decimal?`, `amountUpper: Decimal?` (Spannen wie „2–3“)
  - `unit: String?`
  - `name: String`
  - `note: String?` (Klammerzusatz)
  - `isToTaste: Bool`
- [ ] `static func parse(_ line: String) -> IngredientLine`. Es erkennt:
  - ganze Zahlen und Dezimalkomma bzw. -punkt
  - Brüche „1/2“ und „½ ¼ ¾ ⅓ ⅔“, gemischte Zahlen „1 1/2“, Spannen „2-3“ und „2–3“
  - Einheiten aus einer festen Liste, deutsch und englisch: g, kg, mg, ml, l, cl, dl, EL, TL, Tasse, Becher, Dose, Packung, Pck., Prise, Bund, Zehe, Scheibe, Stück, Stk., cup, tbsp, tsp, oz, lb, can, pinch, clove, slice, piece
  - „nach Geschmack“, „etwas“, „n. B.“, „to taste“, „some“ als `isToTaste`
  - Ohne Zahl ist `amount == nil`, und der Name ist die ganze Zeile.
- [ ] `func formatted(locale:) -> String` schreibt die Zeile zurück. Das Dezimaltrennzeichen folgt der `locale`, Brüche erscheinen als Dezimalzahl mit höchstens einer Nachkommastelle, und „1,0“ wird zu „1“.
- [ ] Tests:
  - `parse_gramsAndName`, `parse_decimalComma`, `parse_unicodeFraction`, `parse_mixedFraction`, `parse_range`
  - `parse_unitPlural_dosen`, `parse_noAmount_wholeLineIsName`, `parse_toTaste_german`, `parse_toTaste_english`
  - `parse_parenthesisKeptAsNote`, `formatted_roundTrip_german`, `formatted_englishDecimalPoint`

## Task 2: `RecipeScaler` in TagwerkCore (#215)

**Files:** Create `RecipeScaler.swift`, `Tests/TagwerkCoreTests/RecipeScalerTests.swift`

- [ ] `static func scale(_ line: IngredientLine, from base: Int, to target: Int) -> IngredientLine`:
  - Faktor ist `target / base`. Zeilen mit `isToTaste` oder ohne Menge bleiben unverändert, ebenso „Prise“ und „pinch“.
  - Gerundet wird so:
    - g und ml: unter 10 auf ganze Zahlen, unter 100 auf 5, sonst auf 10
    - kg und l: auf 0,1
    - EL, TL, Tasse, cup, tbsp, tsp: auf 0,5
    - Dose, Packung, Becher: auf 0,5
    - ohne Einheit oder Stück: auf ganze Zahlen aufrunden, mindestens 1
  - Mehrzahl und Einzahl gibt es nur für eine kleine Liste: „Ei/Eier“, „Zwiebel/Zwiebeln“, „Dose/Dosen“, „Zehe/Zehen“, „egg/eggs“, „can/cans“, „clove/cloves“. Sonst bleibt der Name, wie er ist.
- [ ] `static func scale(_ quantity: String?, from:to:locale:) -> String?` ist die Abkürzung für die freien Mengen-Strings des Imports: lesen mit `IngredientLine.parse("\(quantity) x")`, umrechnen, Menge zurückgeben.
- [ ] Tests:
  - `fourToSix_grams`, `fourToSix_cansBecomeOneAndAHalf`, `fourToSix_eggsRoundUp`, `twoToOne_smallGramsWhole`
  - `toTaste_unchanged`, `pinch_unchanged`, `range_scalesBothEnds`, `sameServings_identity`, `baseZero_unchanged`

## Task 3: `RecipeNote` in TagwerkCore (#214)

**Files:** Create `RecipeNote.swift`, `Tests/TagwerkCoreTests/RecipeNoteTests.swift`

- [ ] `public struct RecipeNote: Sendable, Hashable` mit `title`, `servings: Int?`, `ingredients: [String]` (Rohzeilen), `steps: [String]` und `sourceURL: URL?`.
- [ ] `static func parse(_ markdown: String) -> RecipeNote?`. Es liefert `nil`, wenn die Notiz nicht strukturiert ist (siehe Format oben).
- [ ] `func markdown(language: VoiceLanguage) -> String` schreibt das verbindliche Format. Die Überschriften kommen über `Localized.string` aus dem Katalog des Kernpakets.
- [ ] Tests:
  - `parse_germanHeadings`, `parse_englishHeadings`, `parse_numberedIngredients`, `parse_missingServings`
  - `parse_noIngredientsSection_isNil`, `parse_stopsAtNextHeading`
  - `markdown_roundTrip`, `markdown_sourceLinkOnlyWhenURL`

## Task 4: Fester Ordner „Rezepte“ (#214)

**Files:** Modify:
- `NoteFolderRules.swift`: `case recipes`, dazu `isPrivate = false`, `isInDefaultBackup = true`, `acceptsOwnNotes = true` und `noteKind = nil`
- `NoteStore+DefaultFolders.swift`: an `defaultFolderRoles` anhängen, Name „Rezepte“/„Recipes“
- `NotesFoldersView.swift`: Symbol `fork.knife`. Der Ordner steht in der ersten Sektion unter „Brain Dump“, nicht bei den Systemordnern (`systemFolders` filtert `.recipes` wie `.brainDump` heraus).
- jede andere exhaustive `switch` über `NoteFolderRole`, Liste per `git grep -n "\.dreamLog"`

- [ ] Tests:
  - Kernpaket: `NoteFolderRulesTests.recipes_acceptsOwnNotes_notPrivate_inDefaultBackup`
  - App: `NoteStoreTests.ensureDefaultFolders_createsRecipesOnce_keepsRename`
  - `BackupTests`: der Ordner ist ohne den Schalter für private Inhalte enthalten
- [ ] Bestehende Nutzer bekommen den Ordner beim nächsten `ensureDefaultFolders()` angelegt. Das gilt ohne Migration.

## Task 5: Import mit Titel, Portionen, Schritten und Sprache (#214, #215, #216)

**Files:** Modify `Tagwerk/Shopping/RecipeImporter.swift`, `TagwerkTests/RecipeImporterTests.swift`

- [ ] **Schema** erweitern:
  - neu auf oberster Ebene: `title` (string | null), `servings` (integer | null), `steps` (array of string, darf leer sein)
  - je Eintrag neu: `amount` (number | null), `unit` (string | null)
  - `quantity` bleibt für Texte wie „nach Geschmack“
  - Alle Felder sind `required`, `additionalProperties: false` (Strict-Schema).
- [ ] **Eingabe:** `inputText` bekommt `language: VoiceLanguage` und hängt `"language": "Deutsch"` bzw. `"English"` an das JSON an.
- [ ] **Anweisung:**
  - Die Zeile „Behalte die Sprache des Rezepts bei.“ wird ersetzt durch: „Schreibe Titel, name, unit, quantity und steps in der Sprache aus "language". Übersetze, wenn das Rezept eine andere Sprache hat. Übersetze keine Eigennamen.“
  - „servings“ ist die Portionszahl aus dem Rezept, `null` wenn keine genannt ist.
  - „steps“ sind die Zubereitungsschritte in Kurzform, höchstens 20.
- [ ] **Ergebnis:** `read` liefert jetzt `RecipeImporter.Result` mit `title`, `servings`, `candidates`, `steps` und `sourceURL` (nur bei `.link`). `Candidate` bekommt die strukturierte Menge `line: IngredientLine?`. `validate` übernimmt sie und kürzt `steps` auf 20 × 300 Zeichen.
- [ ] **Neue Quelle `Input.note(UUID)`:**
  - Ist die Notiz eine strukturierte `RecipeNote`, werden die Zeilen per `IngredientLine.parse` gelesen und die Kategorien per `ShoppingClassifier.categoryID` gesetzt. Es gibt dann keinen Responder-Aufruf und keine Zustimmungsprüfung, weil nichts das Gerät verlässt.
  - Sonst wird der Notiztext als `.text` behandelt. Dann gilt die Zustimmungsprüfung, und der Text geht an ChatGPT.
  - Für die Kategorienamen braucht `RecipeImporter` einen schmalen Zugriff auf Zuordnungen und Wörterbuch. Er wird als Parameter `localClassifier: (String) -> String?` übergeben (Name-Key → Kategoriename oder `nil` für „Sonstiges“), damit keine Store-Abhängigkeit entsteht.
- [ ] **Tests:**
  - `schema_hasServingsTitleStepsAmountUnit`, `inputText_namesTheAppLanguage`, `instructions_askForTheAppLanguage_notTheRecipeLanguage`
  - `validate_keepsServingsAndSteps`, `validate_capsSteps`, `validate_amountAndUnitBecomeIngredientLine`
  - `structuredNote_neverCallsTheResponder`, `structuredNote_withoutConsent_works`, `unstructuredNote_needsConsent`, `unstructuredNote_sendsTheText`
  - `link_resultCarriesSourceURL`

## Task 6: Portionsfrage im Ergebnis (#215)

**Files:** Modify `Tagwerk/Shopping/RecipeSheets.swift` (`RecipeResultView`), Create `TagwerkTests/RecipeServingsTests.swift`

- [ ] Oben in `RecipeResultView` steht ein Abschnitt „Portionen“:
  - **Zeile „Rezept für“:** zeigt die Zahl aus dem Rezept. Ohne Zahl ist sie leer und rot markiert, und „hinzufügen“ ist gesperrt, bis eine Zahl gesetzt ist. Darunter steht der Hinweis „Im Rezept steht keine Portionszahl.“
  - **Zeile „Ich koche für“:** Vorschlag ist die Zahl aus „Rezept für“.
  - Beide Zeilen sind ein `Stepper` von 1–50 mit der Zahl im Label. Die Zahl lässt sich vorerst nicht antippen, das kommt mit #218 in G4.
- [ ] Die Mengen in den Zeilen und in `selection` werden live mit `RecipeScaler` umgerechnet. Ohne `line` (freie Menge) gilt `RecipeScaler.scale(_ quantity:)`, scheitert das, bleibt die Menge unverändert.
- [ ] `RecipeImporter.apply` bekommt die umgerechneten Kandidaten.
- [ ] Tests (statische Helfer, keine View-Tests):
  - `RecipeResultView.scaled(candidates:base:target:)`
  - `servings_missingBase_blocksAdd`, `servings_defaultTargetIsBase`, `servings_scaledQuantitiesGoOnTheList`

## Task 7: Rezept-Notiz sichern und als Quelle wählen (#214)

**Files:** Modify `RecipeSheets.swift`, Create `Tagwerk/Shopping/RecipeNotePicker.swift`

- [ ] **Sichern:** Im Ergebnis gibt es unter den Zutaten einen Schalter „Auch als Rezept-Notiz sichern“. Er ist standardmäßig an, wenn die Quelle nicht schon eine Notiz ist.
  - Beim Hinzufügen legt `NoteStore.create(kind: .free, folderID: rezepteOrdner.id)` eine Notiz mit `RecipeNote(...).markdown(language:)` an. Titel und Portionen sind die aus dem Rezept, nicht die umgerechneten. Die Zutaten werden in der Originalmenge gespeichert.
  - Bei `.photo` wird das Foto nicht angehängt (bewusst: Datenmenge). Das ist ein Designpunkt.
- [ ] **Quelle „Notiz“:** Der Segmented Picker in `RecipeInputView` bekommt eine vierte Quelle „Notiz“.
  - Sie zeigt die Notizen im Ordner „Rezepte“, neueste zuerst, mit Titel und dem Hinweis „strukturiert“ bzw. „wird mit ChatGPT gelesen“. Darunter steht „Andere Notiz wählen …“ für eine Auswahl aus allen nicht privaten freien Notizen.
  - Bei einer strukturierten Notiz heißt der Knopf „Zutaten übernehmen“ statt „Zutaten holen“, und die Einwilligungsseite wird übersprungen.
- [ ] **Einwilligung:** `RecipeSheet` zeigt `RecipeConsentView` nur noch, wenn die gewählte Quelle ChatGPT braucht. Dafür wird die Prüfung vom Start des Blatts an den Knopf verlegt. Bestehender Ablauf: Mit Einwilligung ändert sich nichts.
- [ ] **Einstieg aus der Notiz:** In `NoteEditorView` steht für Notizen im Ordner „Rezepte“ ein Menüpunkt „Zutaten auf die Einkaufsliste“. Er öffnet `RecipeSheet` mit `start: .note(id)`. `RecipeStart` bekommt dafür `case note(UUID)`.
- [ ] **Tests:**
  - `RecipeNoteSaveTests.savesIntoRecipesFolder_withOriginalServings`
  - `RecipeNoteSaveTests.switchOff_savesNothing`
  - `RecipeSourceTests.recipesFolderListsNewestFirst_noPrivateNotes`

## Task 7b: Rezept nur speichern, ohne Einkaufsliste (#214, Erweiterung)

**Files:** Modify `RecipeSheets.swift` (gemeinsame Eingabe), `NotesFoldersView.swift`/Notizliste für den Einstieg; Create `Tagwerk/Shopping/RecipeNoteSaveSheet.swift` (Bestätigungsschritt), `TagwerkTests/RecipeSaveOnlyTests.swift`

- [ ] **Ein gemeinsamer Lese-Schritt:** `RecipeInputView` und `RecipeImporter.read` bleiben die einzige Stelle, die Foto, Text, Link und Notiz liest. Der Zweck (Einkaufsliste oder nur speichern) ändert nur, was nach dem Ergebnis passiert. Beim reinen Speichern gehen keine Kategorienamen und keine offenen Artikel in die Anfrage (nur „Sonstiges“); es gibt keine Abhängigkeit von `ShoppingModel`.
- [ ] **Einstieg:** Im Ordner „Rezepte“ steht in der Notizliste neben „Neu“ der Eintrag „Rezept mit ChatGPT anlegen“. Er öffnet `RecipeNoteSaveSheet` (Navigation: Einwilligung nur wenn die Quelle ChatGPT braucht → Eingabe → Bestätigung).
- [ ] **Bestätigung:** Zeigt Titel (bearbeitbar), Portionen (Stepper 1–50, leer erlaubt), Zutaten und Schritte. „Rezept speichern“ legt per `RecipeNoteWriter.save` eine Notiz im Ordner „Rezepte“ an (Originalmengen, `RecipeNote.markdown`). Es wird nichts auf die Einkaufsliste geschrieben und keine Zuordnung gelernt.
- [ ] **Danach:** In der Notiz bleibt „Zutaten auf die Einkaufsliste“ (Task 7) der Weg zur Liste, mit Portionsfrage.
- [ ] **Tests:** `RecipeSaveOnlyTests.saveOnly_writesNoteInRecipesFolder_andNoShoppingItems`, `saveOnly_noteIsStructured_roundTrips`, `saveOnly_requestSendsNoCategoryNamesOrOpenItems`, `saveOnly_withoutConsent_readsNothing`, `saveOnly_cancelSavesNothing`, `sharedRead_sameResultForBothPurposes`.

## Task 8: Link beim Teilen aus Safari (#217)

**Files:** Modify `Packages/TagwerkCore/Sources/TagwerkCore/Share/NewTaskPrefill.swift`, `Tagwerk/Share/ShareNoteSheet.swift`, `app/TagwerkShare/Info.plist`, `app/TagwerkShare/ShareExtractor.swift`; Create `app/TagwerkShare/SafariPreprocessing.js` (als Ressource der Erweiterung in `project.yml`)

- [ ] **Markdown-Link:** `NewTaskPrefill.markdownLink(title:url:) -> String` erzeugt `[Titel](url)`. Ohne Titel steht der Host da. `]` und `)` im Titel werden maskiert. `ShareNoteSheet.initialText` hängt diese Zeile an, statt die rohe Adresse. Im Aufgaben-Prefill bleibt die rohe Adresse, weil Aufgaben-Notizen kein Markdown rendern.
- [ ] **Vorverarbeitung für Safari:**
  - In `Info.plist` kommen `NSExtensionJavaScriptPreprocessingFile = SafariPreprocessing` und in die Aktivierungsregel `NSExtensionActivationSupportsWebPageWithMaxCount = 1`.
  - Das Skript gibt `{ url: document.URL, title: document.title, selection: String(window.getSelection()) }` zurück.
  - `ShareExtractor` liest `NSExtensionJavaScriptPreprocessingResultsKey` aus dem Property-List-Anhang (`UTType.propertyList`). Eine Auswahl wird als `.text`, die Adresse als `.url` übernommen. Die vorhandene Logik in `SharePayload` bildet daraus `kind: .url` mit Text und Titel.
- [ ] **Geräte-Spike in der Erfolgsmeldung vermerken:** Übergibt Safari beim Teilen aus dem Auswahlmenü (markierter Text → „Teilen…“) die Seite und das Skript? Wenn nicht, bleibt der Text ohne Link. Das ist eine bekannte Grenze, die Teilen-Taste der Seite funktioniert dann trotzdem.
- [ ] **Tests:**
  - `SharePayloadTests.textWithURL_becomesURLKindWithText`
  - `NewTaskPrefillTests.markdownLink_escapesBrackets`, `markdownLink_hostWhenNoTitle`
  - `ShareImportTextTests.noteFromSafari_hasMarkdownLink_notRawURL`
  - Lesen des JS-Ergebnisses: eine reine Funktion `ShareExtractor.values(fromPreprocessingResults:)` mit Test im App-Target. Hat die Erweiterung kein Test-Target, liegt die Funktion als `SafariPreprocessingResult` in `TagwerkCore/Share`.

## Task 9: Abschluss

- [ ] Prüfen, ob die Fußtexte im Rezept-Ablauf noch stimmen: Zustimmung, „Die Kategorien kommen von ChatGPT …“ (bei Notiz-Quelle lokal: „Kategorien aus deiner Einkaufsliste“) und Datenschutzhinweis unter Einstellungen › KI.
- [ ] `app/test-all.sh` grün, Kataloge geprüft. Danach den Abschnitt „Stand der Umsetzung“ in diesem Plan ergänzen.
- [ ] Simulator und DerivedData des Checkouts löschen (BRIEF).

---

## Designpunkte für #188

- Rezept-Notiz: Ansicht als normale Markdown-Notiz oder eigene Rezeptansicht (Portionen-Stepper direkt in der Notiz, Zutaten zum Abhaken)
- Ordner „Rezepte“: Symbol (`fork.knife`), Platz in der Ordnerliste (bei „Brain Dump“ oder bei den Systemordnern)
- Portionsfrage: zwei Stepper („Rezept für“, „Ich koche für“) oder eine Zeile mit Faktor; Darstellung der umgerechneten Mengen (alt durchgestrichen oder nur neu)
- Quelle „Notiz“: vierter Eintrag im Segment-Picker oder eigener Einstieg; Kennzeichnung „strukturiert“ / „wird mit ChatGPT gelesen“
- Schalter „Auch als Rezept-Notiz sichern“: Standard an oder aus; Foto beim Foto-Import anhängen ja/nein
- Menüpunkt „Zutaten auf die Einkaufsliste“ in der Notiz: Platz (Menü „…“ oder eigener Knopf)
- Geteilter Text: Link unter dem Text oder als Überschrift der Notiz

## Gerätetests

0. Notizen › Ordner „Rezepte“ › „Rezept mit ChatGPT anlegen“ (Foto, Text und Link): Nach der Bestätigung liegt eine strukturierte Notiz im Ordner, die Einkaufsliste ist unverändert. Danach „Zutaten auf die Einkaufsliste“ mit Portionsfrage.
1. Rezept per Link (deutsche Seite) bei englischer App-Sprache: Die Zutaten stehen englisch auf der Liste, die Rezept-Notiz ist englisch, und „Quelle“ verlinkt die Seite.
2. Rezept mit „für 4 Personen“ → 6 Portionen: Die Mengen stimmen und sind sinnvoll gerundet, „Salz nach Geschmack“ bleibt.
3. Rezept ohne Portionszahl (Foto): „Rezept für“ ist leer, „hinzufügen“ ist gesperrt, bis eine Zahl gesetzt ist.
4. Rezept-Notiz anlegen und von Hand ändern (Zutat ergänzen). Danach über „Zutaten auf die Einkaufsliste“: ohne Netz und ohne Zustimmung möglich, die Kategorien passen.
5. Eine freie, unstrukturierte Notiz als Quelle: Die Zustimmung wird abgefragt, ChatGPT liest sie.
6. Ordner „Rezepte“ nach dem Update: Er ist einmal da, ein Umbenennen bleibt, er ist in der Sicherung enthalten.
7. Safari, Teilen-Taste der Seite mit markiertem Text: Die Notiz enthält den Text und einen antippbaren Link.
8. Safari, markierter Text → „Teilen…“ aus dem Auswahlmenü: Hat die Notiz einen Link? Das Ergebnis in den Plan schreiben (Spike aus Task 8).
9. Englische Oberfläche: Überschriften der Rezept-Notiz, Portionsfrage und Quelle „Notiz“.

---

## Stand der Umsetzung

Umgesetzt auf `feat/recipes-share` (Basis `7e1f989`). Tests laufen mit `app/test-all.sh`. Nichts am Gerät geprüft.

**Erweiterungen des Product Owners (zusätzlich zum Plan)**

- **Rezept nur speichern (#214):** In den Notizen, Ordner „Rezepte“, steht „Rezept mit ChatGPT anlegen“ (neben dem normalen Anlegen). Foto, Text und Link laufen durch denselben Eingabeschritt und denselben `RecipeImporter.read` wie „Rezept hinzufügen“, mit denselben Einwilligungsregeln. Der Bestätigungsschritt (`RecipeNoteSaveView`) sichert Titel, Portionen, Zutaten und Schritte als strukturierte Rezept-Notiz. Die Einkaufsliste wird nicht angefasst. Beim reinen Speichern gehen keine Kategorienamen und keine offenen Artikel an ChatGPT. Der Schalter „Auch als Rezept-Notiz sichern“ im Einkaufs-Import bleibt. Tests: `RecipeSaveOnlyTests`.
- **Sprache für Rezepte (#216):** Einstellungen › KI › Sprache, „Sprache für Rezepte“: „Wie die App“ (Standard) oder Deutsch oder English. Gespeichert in `AppSettings.recipeLanguage`, im Backup als optionales Feld (alte Dateien bleiben unberührt). Die Sprache gilt für Titel, Zutaten und Schritte der Anfrage, für die Überschriften der Rezept-Notiz und für die Artikel auf der Einkaufsliste. Auswahlregel: `RecipeLanguage.resolve`. Tests: `RecipeLanguageTests`, `RecipeLanguageSettingTests`, Backup-Tests.

**Abweichungen vom Plan**

- **Runden von g und ml:** Der Plan nennt „sonst auf 10“, das Beispiel im Review-Fokus verlangt aber 250 g → 375 g. Umgesetzt: unter 10 ganze Zahlen, bis 1000 Fünferschritte, ab 1000 Zehnerschritte.
- **`Input.note`:** trägt den Notiztext (`.note(UUID, text:)`), damit der Importer keine Abhängigkeit zum `NoteStore` bekommt. Die Oberfläche prüft vorher, dass die Notiz nicht privat ist, auch nicht in einem privaten Ordner liegt (`RecipeNoteSource.isOffered`).
- **Neue Notizen-Quelle** gibt es nur beim Einkaufs-Import, nicht beim reinen Speichern.
- **Einwilligung:** Sie wird beim Tippen auf „Zutaten holen“ bzw. „Rezept holen“ abgefragt (Sheet am Formular), nicht mehr beim Start des Blatts.
- **Safari-Seitentitel:** `SharePayload` und `ShareInboxItem` bekommen das optionale Feld `pageTitle`, `SharePart` den Fall `.pageTitle`. Die Auswertung des Skriptergebnisses liegt als `SafariPreprocessingResult` in TagwerkCore/Share.
- **Eigener Ordner „Rezepte“ des Nutzers:** Ein bereits vorhandener eigener Ordner mit diesem Namen wird nicht übernommen. Es entsteht der feste Ordner zusätzlich.

**Eigene Entscheidungen**

- Mehr Einheiten als im Plan: mg, cl, dl, oz, lb, Bund, Scheibe, slice, piece. Zählbare Einheiten werden aufgerundet, cl, dl, oz und lb auf halbe Werte.
- Ein Name mit „Dose“ ohne Einheit („1 große Dose“) wird wie die Einheit Dose gerundet.
- Namen auf der Einkaufsliste bleiben beim Umrechnen im Singular („Ei“), in der Rezept-Notiz stehen Einheit und gezählte Namen im passenden Numerus („2 Zwiebeln“).
- Die Stepper der Portionsfrage starten bei 4, wenn noch keine Zahl da ist.
- „Salz nach Geschmack“ bleibt beim lokalen Lesen als Name der ganzen Zeile auf der Liste stehen.

**Offene Gerätetests:** die neun Punkte unter „Gerätetests“, dazu der Spike aus Task 8 (Teilen aus dem Auswahlmenü in Safari). Ergebnis des Spikes: noch offen.
