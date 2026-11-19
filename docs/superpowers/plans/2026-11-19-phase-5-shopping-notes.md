# Phase 5: Einkaufsliste und Notizen einbinden – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026 zur freigegebenen Spec (Freigabe 19.11.2026). Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Die Aussagen zum Ist-Zustand stammen aus dem Quelltext dieses Standes; die Aussagen zu EventKit stammen aus der Spec (dort als [SDK]/[Annahme] markiert) und sind bis Task 1 ungeprüft.

**Goal:** Eine gewählte Erinnerungsliste wird zur Einkaufsliste mit eigener Seite (Kategorien, Abhaken, Eingabe mit Diktat, Siri, Assistent) und fällt aus Aufgaben, Planung, Wochenrückblick und Mitteilungen heraus; Notizen bekommen einen lokalen Speicher `NoteRecord` mit Liste, Schnellerfassung und Editor.

**Architecture:** Quelle der Wahrheit für Artikel bleibt Apple Erinnerungen; Tagwerk speichert nur Kategorien (`ShoppingCategory`) und die Zuordnung Artikelname → Kategorie (`ShoppingAssignment`). Reine Regeln (Zerlegen, Namensschlüssel, Einordnen, Reihenfolge, Listenfilter) liegen in `TagwerkCore` und `RemindersKit` und sind ohne EventKit testbar. Ein `ShoppingModel` in `AppEnvironment` ist die einzige Stelle, die Artikel liest und schreibt; `NoteStore` ist die einzige Stelle, die `NoteRecord` schreibt. Seite, Karte, Assistent, Kurzbefehl und später die Suche nutzen nur diese beiden.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, EventKit, App Intents, Swift Testing, XcodeGen, String Catalogs (Quellsprache Deutsch, Englisch gepflegt).

**Spec:** `docs/superpowers/specs/2026-11-19-phase-5-shopping-notes-design.md` (maßgeblich; Regeln R1–R12, §5.3–§5.10). Mockup: `docs/superpowers/mockups/2026-11-19-phase-5-shopping-notes-mockups.html` (EO2, EO2b, EQ1, EQ2, EG2, NQ1, EA2, ES1, ES2). Epic: GitHub #113.

**Umfang:** 17 Tasks, 62 h (Summe der Spec §11; Erfahrungswerte, keine Messung, ohne Review-Schleifen).

## Global Constraints

- Reihenfolge der Vorhaben: (1) #136 Issue-Zuweisung → (2) **Phase 5** → (3) Suche → (4) Phase 7. Dieser Plan setzt auf dem gemergten Stand von #136 auf (gleiche Dateien: `TaskListView`, `NewTaskSheet`, `AppTools+Definitions`).
- Schema: nur neue Modelle und neue Attribute mit Standardwert; kein `@Attribute(.unique)`, keine Beziehungen in den drei neuen Modellen; der Store bleibt an seinem Ort (`ModelContainerFactory.persistentConfiguration()` unverändert). `ModelStoreLocationTests` bleibt grün.
- Artikel werden nie lokal gespeichert. Es gibt kein Modell für Artikel.
- Abhaken setzt `isCompleted = true` über `ReminderStore.save`; gelöscht wird nur auf ausdrückliches „Löschen“ oder „Erledigte entfernen“.
- Artikelnamen verlassen das Gerät nur auf Tippen („Mit ChatGPT sortieren“, nach Einwilligung) oder wenn der Nutzer den Assistenten nach der Liste fragt. Notiztext verlässt das Gerät in Phase 5 nie; es gibt keine Notiz-Funktion im Assistenten.
- Schreibende Assistenten-Funktionen laufen erst nach „Bestätigen“ (`AppTools.readTools` enthält nur `list_shopping`).
- Kurzbefehl im Hintergrund braucht nur Gateway, Einstellungen, Kategorien und R3/R4: kein KI-Aufruf, kein Netz, keine geladene Aufgabenliste.
- Kein neuer Tab, kein neuer Knopf oben rechts in „Planen“ und „Aufgaben“, kein Widget, keine neuen Mitteilungen.
- Grenzen aus der Spec: 20 Artikel je Eingabe, Name höchstens 80 Zeichen, „Erledigt“ = 7 × 24 h ab jetzt, höchstens 30 Kategorien, Kategoriename 1–30 Zeichen, ChatGPT-Sortierung höchstens 60 Artikel und 3 neue Kategorien, Zeitgrenze 30 s, `list_shopping` höchstens 100 offene, `update_shopping` je höchstens 30, Notiztitel höchstens 60 Zeichen, automatisches Speichern entprellt 0,5 s.
- Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch. Nutzertexte deutsch im Quelltext, englisch im Katalog (Tabelle Spec §5.10); Pakettexte mit `bundle: .module`.
- Tests laufen deutsch (`-testLanguage de -testRegion DE`); Gesamtlauf `app/test-all.sh` (schließt `check-strings.py --require-english` und `sync-strings.sh --check` ein).
- Commits: englisch, konventionell (`feat: …`, `fix: …`, `test: …`, `docs: …`), kein Hinweis auf KI-Werkzeuge, kein `Co-Authored-By`.

## Review Focus

Eingaben und Zustände, die die Spec nahelegt, aber keine ihrer Testzeilen (§8) nennt. Jede Zeile hat ihren Test im genannten Task.

1. **Gleicher Artikelname zweimal in einer Eingabe** („Milch, milch, 2 Milch“): Es entsteht eine Erinnerung, nicht drei; die zuletzt genannte Menge gilt. → Task 8, `add_duplicateWithinOneInput_createsOne`.
2. **Einkaufsliste wird in Erinnerungen gelöscht, während Tagwerk läuft:** Seite und Karte zeigen „Liste verschwunden“; die Aufgaben zeigen dadurch nicht plötzlich alle Listen (`ShoppingListFilter` darf bei unbekannter Kennung nichts ausweiten); `add` schreibt nicht in Apples Standardliste. → Task 3, `taskListIDs_unknownShoppingID_keepsSelection`; Task 8, `add_listMissing_writesNothing`.
3. **Notizfeld der Erinnerung mit mehreren Zeilen** (in Erinnerungen von Hand eingetragen): Menge setzen über R4 oder das Blatt „Artikel“ überschreibt die Notiz nicht. → Task 8, `add_openItemWithLongNotes_keepsNotes`.
4. **Antwort von ChatGPT mit doppelten oder verfälschten Namen** (derselbe Artikel zweimal, Kategorie in anderer Schreibweise, neue Kategorie heißt wie eine vorhandene): Erster Eintrag je Artikel gilt, Kategorienamen werden ohne Beachtung der Großschreibung aufgelöst, eine „neue“ Kategorie mit vorhandenem Namen wird zur vorhandenen. → Task 12, `validate_duplicateItemAndCaseInsensitiveCategory`.
5. **Eingabe nur aus Trennzeichen, Leerraum oder Menge** („, ; und“, „2“, „500 g“): kein Artikel, kein Absturz, keine leere Erinnerung; „2“ allein bleibt ein Name „2“ (keine Menge ohne Name). → Task 5, `parse_separatorsOnly_isEmpty`, `parse_quantityWithoutName_isName`.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Packages/RemindersKit/Sources/RemindersKit/ReminderRecord.swift:5–30, 39–51` | `ReminderRecord` ohne Anlage- und Erledigungsdatum; `ListInfo` ohne Schreibbarkeit. |
| `…/RemindersKit/ReminderStore.swift:6–30` | Nur `openReminders(in:)` und `completionDates(in:listIDs:)` (Standard `[]` in der Protokoll-Erweiterung). Keine Auskunft über Apples Standardliste. |
| `…/RemindersKit/EventKitGateway.swift:65–78, 80–96, 141, 187–199, 224–227` | Offene Erinnerungen; erledigte nur als Datum; `create` fällt auf `defaultCalendarForNewReminders()` zurück; `record(_:)` und `listInfo(_:)` als Abbildung. |
| `…/EventKitGateway.swift:13–15` und `app/Tagwerk/App/AppEnvironment.swift:291–305` | `changes` ist ein `AsyncStream` mit **einem** Verbraucher (`startObservingChanges`). Ein zweiter Verbraucher würde Meldungen stehlen. |
| `…/RemindersKit/RemindersTaskProvider.swift:19–39, 67–79` | `init(store:estimates:selectedListIDs:)`; `containers()` liefert alle Listen; `create` reicht `draft.containerID` durch. |
| `app/Tagwerk/App/AppEnvironment.swift:16, 67–88, 343` | `gateway: EventKitGateway` wird fest erzeugt und ist zugleich `ReminderStore` für Aufgaben, Planung und Wochenrückblick; kein Einstieg für einen Test-Store. |
| `app/Tagwerk/Planning/PlanningModel.swift:232, 302` | `reminderStore.openReminders(in: nil)` für wiederkehrende Erinnerungen, an der Listenwahl vorbei; Ergebnis u. a. in `recurringReminderIDs` (`:128`). |
| `app/Tagwerk/Persistence/AppSettings.swift:7–97` | Ein SwiftData-Objekt, alle Felder mit Standardwert; Muster `mealEstimationConsent`. |
| `app/Tagwerk/Persistence/ModelContainerFactory.swift:5–12` | `schema` als Liste der Modelle. |
| `app/Tagwerk/Tasks/TaskListView.swift:29–60, 88–109` | `NavigationStack` ohne Pfad; `List(selection:)` mit Filter, Quellenhinweisen, Abschnitten. |
| `app/Tagwerk/App/RootView.swift:41–44, 135–145`, `App/AppRouter.swift:38–48` | Tab „Aufgaben“ = Wert 1; `openRouterTarget()` und `AppRouter.open` schalten erschöpfend über `AppRoute`. |
| `app/Tagwerk/Settings/SettingsView.swift:33–50, 117–119`, `SourceSelectionView.swift:5–44` | Abschnitt „Quellen“; Neuladen nur an `selectedReminderListIDs` der Einstellungsseite. |
| `app/Tagwerk/Capture/MealEstimator.swift:10–107`, `MealConsentSheet.swift` | Vorbild für `ShoppingSorter` (Einwilligung zuerst, 30 s, `jsonSchema`, `Failure`) und das Einwilligungsblatt. |
| `app/Tagwerk/AI/AppTools.swift:12–33, 50–102`, `AppTools+Definitions.swift:6–35`, `AssistantModel.swift:349, 411` | Muster für Funktionen, Schemas (`strict`), Systemhinweis, Aktionskarte. |
| `app/Tagwerk/Intents/IntentServices.swift:7–59`, `TagwerkIntents.swift:19–34, 113–133`, `App/TagwerkApp.swift:25–26` | Muster Hintergrund-Intent (`LogWaterIntent`), Vordergrund-Intent, Sätze. |
| `app/Tagwerk/Voice/VoiceComposer.swift:5–39` | `VoiceInputFactory.make(_:)`, `VoiceMicrophoneButton`, `VoiceRecordingBar`. |
| `app/TagwerkTests/Fakes/FakeAccessStore.swift` | Einziger `ReminderStore`-Fake der App-Tests; kennt keine Listen, kein Schreiben. Der vollständige Fake liegt nur im Paket (`RemindersKitTests/FakeReminderStore.swift`). |

## Abweichungen vom Spec

| Nr. | Spec | Code-Befund | Auflösung |
|---|---|---|---|
| A1 | R1, Zeile 5: `create(_:)` erkennt, dass Apples Standardliste die Einkaufsliste ist. Die Tabelle „Erweiterungen in RemindersKit“ nennt dafür keine Funktion | `ReminderStore` legt die Standardliste nicht offen (`EventKitGateway.swift:141` fragt sie intern ab) | Neue Protokollfunktion `defaultListID() -> String?` mit Standard `nil` (Task 2). Bei `nil` gibt es keinen Rückfall; Verhalten wie heute |
| A2 | §5.1: `ShoppingModel` lädt „bei Meldungen aus `EventKitGateway.changes`“; §5.4 ebenso für die Seite | `changes` verträgt nur einen Verbraucher | `ShoppingModel` liest den Strom nicht selbst. `AppEnvironment.startObservingChanges()` ruft zusätzlich `shopping.reload()`; die Seite beobachtet das Modell. Entprellung entfällt, weil der Strom schon auf den neuesten Wert puffert |
| A3 | §8 verlangt Tests für `ShoppingModel`, `IntentServices.addToShopping`, Wochenrückblick | `AppEnvironment` erzeugt `EventKitGateway()` fest; im Simulator ohne Zugriff | `AppEnvironment.init` bekommt `reminderStore: (any ReminderStore)? = nil` (Standard: das Gateway); neuer App-Fake `InMemoryReminderStore` (Task 4) |
| A4 | R6 Nr. 1: gelernte Zuordnung gilt, „wenn ihre Kategorie noch existiert“; §5.4: von Hand lässt sich auch „Sonstiges“ wählen | `ShoppingAssignment.categoryID` ist optional; „Sonstiges“ ist keine Kategorie (R7) | Eine Zuordnung mit `categoryID == nil` bedeutet „von Hand nach Sonstiges“ und schlägt das Wörterbuch. Sonst würde die Handwahl „Sonstiges“ nie halten |
| A5 | R3 Nr. 4: `parse(_:) -> [ParsedItem]`, „die Oberfläche meldet“ das Abschneiden | Aus der Rückgabe allein ist das Abschneiden nicht erkennbar | `parse(_:)` bleibt wie in der Spec; zusätzlich `parseAll(_:) -> ParseResult` mit `droppedCount` |
| A6 | R1: „Mitteilungen neu planen“ beim Wechsel der Liste | Mitteilungen und Snapshot folgen `taskList.items` schon über `Observations` (`AppEnvironment.swift:316–333, 401–433`) | `setShoppingList(_:)` ruft `scheduleSoon()` und `scheduleSnapshot()` trotzdem ausdrücklich; doppelte Auslösung ist durch die vorhandene Entprellung unschädlich |

Keine Entscheidung der Spec wird damit geändert.

## Schnittstellen zu den anderen Plänen

**Phase 5 produziert (stabil; Suche und Phase 7 verwenden genau diese Namen):**

| Name | Ort | Signatur / Inhalt |
|---|---|---|
| `AppSettings.shoppingListID` | `Persistence/AppSettings.swift` | `String?`, `nil` = keine Einkaufsliste |
| `AppEnvironment.setShoppingList(_:)` | `App/AppEnvironment.swift` | `func setShoppingList(_ id: String?) async`; einziger Schreibweg für `shoppingListID` |
| `AppEnvironment.taskReminderListIDs()` | ebd. | `-> Set<String>?`; Listenmenge der Aufgaben ohne Einkaufsliste |
| `ShoppingListFilter.taskListIDs` | `RemindersKit` | `static func taskListIDs(selected: Set<String>?, all: [String], shopping: String?) -> Set<String>?` |
| `ShoppingItem` | `TagwerkCore` | `id: String, name: String, quantity: String?, isCompleted: Bool, completedAt: Date?, createdAt: Date?, hasLongNotes: Bool`; `Sendable, Hashable, Identifiable` |
| `ShoppingModel` | `Tagwerk/Shopping/ShoppingModel.swift` | `environment.shopping`; `state`, `openItems: [ShoppingItem]` (Reihenfolge R8 über alle Abschnitte), `completedItems`, `sections`, `reload()`, `checkOff(id:)`, `reopen(id:)` |
| `ShoppingListView` | `Tagwerk/Shopping/ShoppingListView.swift` | `init(model: ShoppingModel)`; ohne eigenen `NavigationStack`, in Stack oder Blatt einbettbar |
| `AppRoute.shopping` | `TagwerkCore/AppRoute.swift` | Rohwert `"shopping"`, Link `tagwerk://shopping` |
| `TasksDestination` | `Tagwerk/Tasks/TasksDestination.swift` | `enum TasksDestination: Hashable { case shopping, shoppingSettings, shoppingCategories, notes, note(UUID) }`; `environment.tasksPath: [TasksDestination]` |
| `NoteRecord` | `Tagwerk/Notes/NoteRecord.swift` | Felder exakt nach Spec §5.1: `id: UUID`, `text: String`, `createdAt: Date`, `updatedAt: Date`, `kindRaw: String` (`"free"`/`"morning"`/`"evening"`), `dayKey: String?` (`"YYYY-MM-DD"`), `isPinned: Bool`, `wasDictated: Bool`, `processedAt: Date?`. Phase 7 darf nur Felder mit Standardwert ergänzen (`derivedActionCount: Int = 0`) |
| `NoteKind` | `TagwerkCore/NoteText.swift` | `enum NoteKind: String, Sendable, CaseIterable { case free, morning, evening }`; `NoteRecord.kind` liest `kindRaw`, unbekannt → `.free` |
| `NoteDayKey` | ebd. | `static func string(_ day: PlanDay) -> String`, `static func day(_ key: String) -> PlanDay?` |
| `NoteText` | ebd. | `static func title(_ text: String) -> String` (erste nicht leere Zeile, höchstens 60 Zeichen), `static func preview(_ text: String) -> String` |
| `NoteStore` | `Tagwerk/Notes/NoteStore.swift` | siehe Task 13; einzige Schreibstelle für `NoteRecord`; `environment.notes` |
| `NoteEditorView` | `Tagwerk/Notes/NoteEditorView.swift` | `init(noteID: UUID, store: NoteStore)`; ohne eigenen `NavigationStack`, als Blatt zeigbar |
| `NotesListView.footer(for:)` | `Tagwerk/Notes/NotesListView.swift` | `static func footer(for note: NoteRecord, now: Date, calendar: Calendar) -> String`; Phase 7 hängt „· 2 Aufgaben daraus“ an |

**Phase 5 konsumiert:** nichts aus den anderen drei Plänen. Aus #136 nur den gemergten Stand der Dateien `TaskListView.swift`, `NewTaskSheet.swift`, `AppTools+Definitions.swift` (keine Typen).

## Betroffene Dateien

Pfade relativ zu `app/`. `Core/` = `Packages/TagwerkCore/Sources/TagwerkCore/`, `RK/` = `Packages/RemindersKit/Sources/RemindersKit/`.

| Datei | Verantwortung |
|---|---|
| `RK/ReminderRecord.swift` (ändern) | `createdAt`, `completedAt`, `ListInfo.isWritable` |
| `RK/ReminderStore.swift` (ändern) | `completedReminders(in:listIDs:)`, `defaultListID()` |
| `RK/EventKitGateway.swift` (ändern) | beide Funktionen, neue Felder in `record(_:)` und `listInfo(_:)` |
| `RK/ShoppingListFilter.swift` (neu) | Listenmenge, Rückfall der Standardliste, Listenvorschlag (R1, R11) |
| `RK/RemindersTaskProvider.swift` (ändern) | `excludedListID` in `openTasks`, `containers`, `create` |
| `Core/ShoppingName.swift` (neu) | R2 |
| `Core/ShoppingInputParser.swift` (neu) | R3, `ParsedItem` |
| `Core/ShoppingItem.swift` (neu) | `ShoppingItem`, Menge aus dem Notizfeld |
| `Core/ShoppingClassifier.swift` (neu) | `ShoppingBuiltinCategory`, `ShoppingDictionary`, `ShoppingClassifier`, `ShoppingSections`, `ShoppingCategoryRules` (R6–R8, R10, R12) |
| `Core/Resources/ShoppingDictionary.json` (neu) | Wörterbuch, 400–600 Begriffe |
| `Core/NoteText.swift` (neu) | `NoteKind`, `NoteDayKey`, `NoteText` |
| `Core/AppRoute.swift` (ändern) | `case shopping` |
| `Tagwerk/Persistence/AppSettings.swift`, `ModelContainerFactory.swift` (ändern) | vier Felder; drei Modelle im Schema |
| `Tagwerk/Shopping/ShoppingRecords.swift` (neu) | `ShoppingCategory`, `ShoppingAssignment` |
| `Tagwerk/Shopping/ShoppingCategoryStore.swift` (neu) | Kategorien und Zuordnungen (R9, R10, R12) |
| `Tagwerk/Shopping/ShoppingModel.swift` (neu) | Laden, R4, R5, Bearbeiten, Löschen |
| `Tagwerk/Shopping/ShoppingListView.swift`, `ShoppingItemSheet.swift`, `ShoppingInputBar.swift` (neu) | Einkaufsseite §5.4 |
| `Tagwerk/Shopping/ShoppingCategoriesView.swift` (neu) | Seite „Kategorien“ §5.5 |
| `Tagwerk/Shopping/ShoppingSorter.swift`, `ShoppingSortSheets.swift` (neu) | ChatGPT-Sortierung, Einwilligungs- und Ergebnisblatt |
| `Tagwerk/Shopping/ShoppingSettingsView.swift` (neu) | Seite „Einkaufsliste“ §5.7 |
| `Tagwerk/Tasks/TasksDestination.swift`, `TasksEntrySection.swift` (neu) | Navigationsziele; Karten und Vorschlagskarte §5.3 |
| `Tagwerk/Notes/NoteRecord.swift`, `NoteStore.swift`, `NotesListView.swift`, `NoteEditorView.swift` (neu) | Notizen §5.6 |
| `Tagwerk/App/AppEnvironment.swift`, `AppRouter.swift`, `RootView.swift`, `DemoData.swift` (ändern) | Verdrahtung, `setShoppingList`, Deeplink, Demo-Daten |
| `Tagwerk/Planning/PlanningModel.swift` (ändern) | Ausschluss bei wiederkehrenden Erinnerungen |
| `Tagwerk/Tasks/TaskListView.swift` (ändern) | Pfad, Abschnitt am Listenkopf |
| `Tagwerk/Settings/SettingsView.swift`, `SourceSelectionView.swift`, `CaptureSettingsView.swift` (ändern) | Zeile „Einkaufsliste“, gesperrte Zeile, Siri-Sätze |
| `Tagwerk/AI/AppTools.swift`, `AppTools+Definitions.swift`, `AssistantModel.swift` (ändern) | `list_shopping`, `update_shopping`, Karte, Systemhinweis |
| `Tagwerk/Intents/IntentServices.swift`, `TagwerkIntents.swift` (ändern) | zwei Intents, Sätze |
| `Tagwerk/Localizable.xcstrings`, `AppShortcuts.xcstrings`, Paketkataloge (ändern) | deutsch und englisch |
| `TagwerkTests/Fakes/InMemoryReminderStore.swift` (neu) | Test-Store mit Listen, Schreiben, erledigten Erinnerungen |

## Tasks

Jeder Task: Tests zuerst (rot), dann Umsetzung (grün), dann Commit. „Paket“ nennt die Zeile aus Spec §11; daraus werden die GitHub-Issues unter Epic #113 geschnitten (ein Issue je Paket, Tasks desselben Pakets sind dessen Teilaufgaben).

Testbefehle:
- Paket: `cd app/Packages/<Paket> && xcodebuild test -testLanguage de -testRegion DE -scheme <Paket> -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:<Paket>Tests/<Suite>` (meldet `xcodebuild -list` kein Schema `<Paket>`, heißt es `<Paket>-Package`).
- App: `cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>`.
- Alles: `app/test-all.sh`, erwartet `ALL TESTS PASSED`.

---

### Task 1: Spike am Gerät (S1–S5)

**Paket 0 · 2 h · Issue „Phase 5: Spike am Gerät“.** Manuell, auf dem echten iPhone mit der echten Liste „Einkauf“. Wegwerf-Code auf einem eigenen Zweig oder als Abschnitt in `Settings/CalendarDiagnosticsView.swift` (nur `#if DEBUG`); nichts davon wird gemergt.

**Interfaces:** Produces: fünf Ergebnisse, die Tasks 2, 8, 9 und 16 an genau einer Stelle ändern (Spalte „Bei Fehlschlag“).

| Nr. | Schritt | Bestanden, wenn | Bei Fehlschlag |
|---|---|---|---|
| S1 | Über `EKEventStore` drei Erinnerungen („Milch“, „Bananen“, „Spülmittel“) in Apples Liste vom Typ „Einkaufsliste“ anlegen; in Erinnerungen nachsehen | Apple sortiert sie in Abschnitte ein | Kein Einfluss auf den Bau. Satz in den Nachtrag der Spec: „Neue Artikel erscheinen in Erinnerungen unsortiert.“ |
| S2 | Je einen Artikel auf dem iPhone und auf einem zweiten Gerät (Mac/iPad) anlegen und abhaken; `creationDate` und `completionDate` aller vier ausgeben | Alle vier Werte sind gefüllt | `creationDate` fehlt: nichts ändern (R8 fällt auf den Titel zurück). `completionDate` fehlt: Task 2, Schritt 3 setzt `completedAt = completionDate ?? lastModifiedDate` |
| S3 | In einer geteilten Liste: anlegen, abhaken, fremden Artikel löschen; auf dem zweiten Konto ändern und die Zeit bis zur `EKEventStoreChanged`-Meldung messen | Alle drei Schreibvorgänge gelingen; `allowsContentModifications == true` | Nicht beschreibbar: nichts ändern (Liste ist nach Festlegung 16 nicht wählbar). Löschen scheitert: nichts ändern (Fehlermeldung genügt). Verzögerung über 60 s: Satz in den Nachtrag |
| S4 | Ein Wegwerf-Intent mit `supportedModes = .background` legt eine Erinnerung an; per Siri bei gesperrtem Gerät und bei beendeter App auslösen | Die Erinnerung steht danach in der Liste | Task 16: `AddToShoppingListIntent.supportedModes = .foreground(.immediate)`; Antworttexte bleiben |
| S5 | `predicateForCompletedReminders` über 7 Tage auf der lang genutzten Liste, zehnmal, Dauer messen | Median unter 150 ms | Task 8: `reload()` lädt erledigte Artikel nicht mit; `loadCompleted()` läuft erst beim Aufklappen von „Erledigt“ (Task 9) und vor R4 |

- [ ] **Schritt 1:** S1–S5 durchführen, Messwerte notieren.
- [ ] **Schritt 2:** Ergebnis als Abschnitt „Nachtrag: Spike 0“ ans Ende der Spec schreiben (je Zeile: bestanden/nicht bestanden, Messwert, gewählte Folge) und in diesem Plan die betroffenen Schritte anpassen.
- [ ] **Schritt 3:** Commit: `git add docs/superpowers && git commit -m "docs: record phase 5 device spike results"`

---

### Task 2: RemindersKit – Datumsfelder, Schreibbarkeit, erledigte Erinnerungen

**Paket 2 · 3 h · Issue „Phase 5: RemindersKit erweitern“.**

**Files:**
- Modify: `RK/ReminderRecord.swift`, `RK/ReminderStore.swift`, `RK/EventKitGateway.swift:187–199, 224–227`
- Modify: `Packages/RemindersKit/Tests/RemindersKitTests/FakeReminderStore.swift`
- Test: `Packages/RemindersKit/Tests/RemindersKitTests/CompletedRemindersTests.swift` (neu)

**Interfaces:**
- Produces:
  - `ReminderRecord.createdAt: Date?`, `ReminderRecord.completedAt: Date?` (im `init` als letzte Parameter, Standard `nil`)
  - `ListInfo.isWritable: Bool` (im `init` letzter Parameter, Standard `true`)
  - `ReminderStore.completedReminders(in interval: DateInterval, listIDs: Set<String>) async -> [ReminderRecord]` (Standard `[]`)
  - `ReminderStore.defaultListID() -> String?` (Standard `nil`, Abweichung A1)
  - `FakeReminderStore`: echte `completedReminders`, `defaultListID()` liefert das vorhandene `defaultListID`; `save` setzt `completedAt` beim Wechsel auf erledigt (auf den Wert von `tick()`) und löscht es beim Wiederöffnen; `create` setzt `createdAt`.

- [x] **Schritt 1: Tests schreiben** (`CompletedRemindersTests`, `@MainActor struct`, Store wie in `RemindersTaskProviderTests`)

```swift
@Test func completedReminders_onlyInIntervalAndLists() async {
    // "a": list shop, completedAt = t0+10 · "b": list shop, completedAt = t0-100 · "c": list other, completedAt = t0+10 · "d": list shop, open
    let found = await store.completedReminders(in: DateInterval(start: t0, duration: 60), listIDs: ["shop"])
    #expect(found.map(\.id) == ["a"])
}
@Test func completedReminders_emptyListSet_returnsNothing() async {
    #expect(await store.completedReminders(in: DateInterval(start: t0, duration: 60), listIDs: []).isEmpty)
}
@Test func save_completing_setsCompletedAt_reopeningClearsIt() throws {
    var record = try #require(store.records["d"]); record.isCompleted = true
    #expect(try store.save(record, recurrence: .unchanged).completedAt != nil)
    record.isCompleted = false
    #expect(try store.save(record, recurrence: .unchanged).completedAt == nil)
}
@Test func newFields_defaultToNilAndWritable() {
    let record = ReminderRecord(id: "x", title: "", notes: nil, due: nil, ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil)
    #expect(record.createdAt == nil && record.completedAt == nil)
    #expect(ListInfo(id: "l", title: "L", colorHex: nil, kind: .local).isWritable)
}
```

- [x] **Schritt 2:** Suite `CompletedRemindersTests` ausführen. Erwartet: Übersetzungsfehler (`completedReminders` unbekannt).
- [x] **Schritt 3: Umsetzen.** `EventKitGateway.completedReminders` nach dem Muster von `completionDates` (`:80–96`), mit derselben Zugriffsprüfung und mit `Self.record` statt Datum; leere Auswahl → `[]`. `record(_:)`: `createdAt: reminder.creationDate`, `completedAt: reminder.completionDate`. `listInfo(_:)`: `isWritable: calendar.allowsContentModifications`. `defaultListID()`: `store.defaultCalendarForNewReminders()?.calendarIdentifier`. `save(_:recurrence:)` schreibt die beiden neuen Felder nie.
- [x] **Schritt 4:** Ganzes Paket `RemindersKit` testen. Erwartet: alle Tests grün (die vorhandenen unverändert).
- [x] **Schritt 5:** Commit: `git add app/Packages/RemindersKit && git commit -m "feat: read completed reminders, creation dates and list writability"`

---

### Task 3: RemindersKit – `ShoppingListFilter` und Ausschluss im Provider

**Paket 1 (Teil 1 von 2) · 1,5 h · Issue „Phase 5: Einkaufsliste aus den Aufgaben ausschließen“.**

**Files:**
- Create: `RK/ShoppingListFilter.swift`
- Modify: `RK/RemindersTaskProvider.swift:14–39, 67–79`
- Test: `Packages/RemindersKit/Tests/RemindersKitTests/ShoppingListFilterTests.swift` (neu), `RemindersTaskProviderTests.swift` (ergänzen)

**Interfaces:**
- Consumes: `ReminderStore.defaultListID()`, `ListInfo.isWritable` (Task 2).
- Produces:

```swift
public enum ShoppingListFilter {
    /// Without a shopping list, or when `shopping` is not in `all`: `selected` unchanged.
    /// Otherwise `(selected ?? all)` without the shopping list; an empty set means "no list", not "all".
    public static func taskListIDs(selected: Set<String>?, all: [String], shopping: String?) -> Set<String>?
    /// List for a new reminder. `requested` wins unless it is the shopping list. `nil` lets the store pick its default.
    /// If the store's default is the shopping list: first other selected list by title; none → throws
    /// `TaskWriteError.failed("Keine Erinnerungsliste gefunden")`.
    public static func listForNewReminder(requested: String?, defaultListID: String?, shopping: String?,
                                          selected: Set<String>?, lists: [ListInfo]) throws -> String?
    /// R11: the one writable list whose trimmed, lowercased title starts with one of
    /// "einkauf", "einkäufe", "lebensmittel", "groceries", "grocery", "shopping"; `nil` for zero or several.
    public static func suggestedList(in lists: [ListInfo]) -> ListInfo?
}
```
  - `RemindersTaskProvider.init(store:estimates:selectedListIDs:excludedListID:)` mit `excludedListID: @escaping @MainActor () -> String? = { nil }` als letztem Parameter.

- [ ] **Schritt 1: Tests schreiben**

```swift
// ShoppingListFilterTests
@Test func taskListIDs_noShopping_isUnchanged() {
    #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "s"], shopping: nil) == nil)
    #expect(ShoppingListFilter.taskListIDs(selected: ["a"], all: ["a", "s"], shopping: nil) == ["a"])
}
@Test func taskListIDs_allLists_dropsShopping() {
    #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "b", "s"], shopping: "s") == ["a", "b"])
}
@Test func taskListIDs_selection_dropsShopping() {
    #expect(ShoppingListFilter.taskListIDs(selected: ["a", "s"], all: ["a", "b", "s"], shopping: "s") == ["a"])
}
@Test func taskListIDs_onlyShoppingSelected_isEmptySetNotNil() {
    #expect(ShoppingListFilter.taskListIDs(selected: ["s"], all: ["a", "s"], shopping: "s") == Set<String>())
    #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["s"], shopping: "s") == Set<String>())
}
@Test func taskListIDs_unknownShoppingID_keepsSelection() {   // Review Focus 2
    #expect(ShoppingListFilter.taskListIDs(selected: nil, all: ["a", "b"], shopping: "gone") == nil)
    #expect(ShoppingListFilter.taskListIDs(selected: ["a"], all: ["a", "b"], shopping: "gone") == ["a"])
}
@Test func listForNewReminder_defaultIsShopping_picksFirstOtherSelectedByTitle() throws {
    // lists: s "Einkauf", z "Zuhause", u "Uni"; selected nil
    #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s", selected: nil, lists: lists) == "u")
    #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s", selected: ["z", "s"], lists: lists) == "z")
}
@Test func listForNewReminder_noOtherList_throws() {
    #expect(throws: TaskWriteError.self) {
        try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "s", shopping: "s", selected: ["s"], lists: lists)
    }
}
@Test func listForNewReminder_otherDefaultOrRequest_passesThrough() throws {
    #expect(try ShoppingListFilter.listForNewReminder(requested: nil, defaultListID: "u", shopping: "s", selected: nil, lists: lists) == nil)
    #expect(try ShoppingListFilter.listForNewReminder(requested: "z", defaultListID: "s", shopping: "s", selected: nil, lists: lists) == "z")
}
@Test func suggestedList_exactlyOneWritableMatch() {
    // "Einkauf" writable → match; "  Groceries " → match; "Einkauf" + "Shopping" → nil; "Einkauf" read-only → nil; "Wocheneinkauf" → nil
}

// RemindersTaskProviderTests (store: lists studium, privat, einkauf; excludedListID: { "einkauf" })
@Test func openTasks_excludesShoppingList() async throws          // no item with container.id == "einkauf", for selected == nil and selected == ["privat", "einkauf"]
@Test func containers_omitShoppingList() async throws             // ids == ["studium", "privat"]
@Test func create_defaultListIsShopping_usesFirstOtherList() async throws   // store.defaultListID = "einkauf" → created.container.id == "privat"
@Test func create_withoutExcludedList_behavesAsBefore() async throws        // default init: container.id == store.defaultListID
```

- [ ] **Schritt 2:** Beide Suiten ausführen. Erwartet: Übersetzungsfehler (`ShoppingListFilter` unbekannt).
- [ ] **Schritt 3: Umsetzen.** Im Provider: `openTasks()` ruft `store.openReminders(in: ShoppingListFilter.taskListIDs(selected: selectedListIDs(), all: store.lists().map(\.id), shopping: excludedListID()))`; `containers()` filtert `excludedListID()` heraus; `create(_:)` setzt `listID` über `listForNewReminder` (Sortierung der Titel mit `localizedStandardCompare`). `task(id:)`, `apply`, `delete` bleiben unverändert.
- [ ] **Schritt 4:** Paket `RemindersKit` testen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Packages/RemindersKit && git commit -m "feat: exclude the shopping list from reminder tasks"`

---

### Task 4: Einstellungen, Ausschluss in der App, zentrales Neuladen

**Paket 1 (Teil 2 von 2) · 2,5 h · Issue wie Task 3.**

**Files:**
- Modify: `Tagwerk/Persistence/AppSettings.swift` (nach `mealEstimationConsent`), `Tagwerk/App/AppEnvironment.swift:67–88, 291–305, 337–346`, `Tagwerk/Planning/PlanningModel.swift:232, 302`
- Create: `TagwerkTests/Fakes/InMemoryReminderStore.swift`
- Test: `TagwerkTests/ShoppingExclusionTests.swift` (neu), `TagwerkTests/PlanningModelTests.swift`, `TagwerkTests/NotificationSchedulerTests.swift` (ergänzen)

**Interfaces:**
- Consumes: `RemindersTaskProvider.init(…excludedListID:)`, `ShoppingListFilter.taskListIDs` (Task 3).
- Produces:
  - `AppSettings.shoppingListID: String? = nil`, `shoppingSuggestionDismissed: Bool = false`, `shoppingCategoriesSeeded: Bool = false`, `shoppingSortConsent: Bool = false`
  - `AppEnvironment.init(modelContainer:notificationCenter:health:snapshotWriter:reminderStore:)` mit `reminderStore: (any ReminderStore)? = nil`; `let reminderStore: any ReminderStore` (Standard: `gateway`), verwendet für `RemindersTaskProvider`, `PlanningModel(reminderStore:)` und den Wochenrückblick. Kalenderzugriffe bleiben am `gateway`.
  - `AppEnvironment.taskReminderListIDs() -> Set<String>?`
  - `AppEnvironment.setShoppingList(_ id: String?) async`: setzt `settings.shoppingListID`, dann `taskList.reload(only: [.reminders])`, `planning.reload()`, `notifications.scheduleSoon()`, `scheduleSnapshot()`. (Task 8 hängt `shopping.reload()` an.)
  - `InMemoryReminderStore` (App-Tests): `final class InMemoryReminderStore: ReminderStore` mit `accessState = .fullAccess`, `listInfos: [ListInfo]`, `records: [String: ReminderRecord]`, `defaultList: String?`, `now: () -> Date`, `failingDeleteIDs: Set<String>`, `private(set) var createCount`; `openReminders`, `completedReminders`, `reminder`, `save` (setzt/löscht `completedAt` wie der Paket-Fake, `lastModified = now()`), `create` (Kennung `"new-<n>"`, `createdAt = now()`), `delete` (wirft `TaskWriteError.notFound` bzw. `.failed` für `failingDeleteIDs`), `defaultListID()`.

- [ ] **Schritt 1: Tests schreiben**

```swift
// ShoppingExclusionTests: environment with InMemoryReminderStore(lists: uni, shop; open "task-1" in uni, "milk" in shop), setupCompleted = true
@Test func settings_newFieldsHaveSpecDefaults() throws {
    let settings = AppSettings()
    #expect(settings.shoppingListID == nil && !settings.shoppingSuggestionDismissed
            && !settings.shoppingCategoriesSeeded && !settings.shoppingSortConsent)
}
@Test func setShoppingList_removesItsRemindersFromTaskList() async throws {
    await environment.taskList.reload()
    #expect(environment.taskList.items.map(\.title).sorted() == ["Milch", "Seminararbeit"])
    await environment.setShoppingList("shop")
    #expect(environment.taskList.items.map(\.title) == ["Seminararbeit"])
    await environment.setShoppingList(nil)
    #expect(environment.taskList.items.count == 2)       // comes back when it was selected for tasks
}
@Test func taskReminderListIDs_excludeShoppingList_forWeekReview() async throws {
    await environment.setShoppingList("shop")
    #expect(environment.taskReminderListIDs() == ["uni"])
    environment.settings.selectedReminderListIDs = ["shop"]
    #expect(environment.taskReminderListIDs() == Set<String>())
}

// PlanningModelTests
@Test func recurringReminderInShoppingList_isIgnored() async {
    accessStore.accessState = .fullAccess
    accessStore.openRecords = [/* "shop-1": listID "shop", daily recurrence · "uni-1": listID "uni", daily recurrence */]
    settings.shoppingListID = "shop"
    await model.reload()
    #expect(model.recurringReminderIDs == ["uni-1"])
}

// NotificationSchedulerTests
@Test func shoppingItems_getNoNotification() async {
    // task list built from a RemindersTaskProvider with excludedListID { "shop" } and a due reminder in "shop":
    // after reschedule, no pending request mentions that reminder id
}
```

- [ ] **Schritt 2:** `ShoppingExclusionTests` ausführen. Erwartet: Übersetzungsfehler (`setShoppingList` unbekannt).
- [ ] **Schritt 3: Umsetzen.** `AppEnvironment`: Provider-Aufruf um `excludedListID: { settings.shoppingListID }` ergänzen; `makeWeekReviewModel()` nutzt `reminderStore.completionDates(in:listIDs: taskReminderListIDs())`. `PlanningModel`: private Funktion `planningReminders() async -> [ReminderRecord]` (liest `openReminders(in: nil)`, entfernt `listID == settings.shoppingListID`), an beiden Stellen (`:232`, `:302`) verwenden. `InMemoryReminderStore` anlegen.
- [ ] **Schritt 4:** Suiten `ShoppingExclusionTests`, `PlanningModelTests`, `NotificationSchedulerTests`, `WeekReviewModelTests`, `ModelStoreLocationTests` ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: add shopping list setting and exclude it from planning and review"`

---

### Task 5: Kernlogik – Namensschlüssel, Eingabe zerlegen, `ShoppingItem`

**Paket 3 (Teil 1 von 2) · 2,5 h · Issue „Phase 5: Kernlogik der Einkaufsliste“.**

**Files:**
- Create: `Core/ShoppingName.swift`, `Core/ShoppingInputParser.swift`, `Core/ShoppingItem.swift`
- Test: `Packages/TagwerkCore/Tests/TagwerkCoreTests/ShoppingInputParserTests.swift` (neu)

**Interfaces:**
- Produces:

```swift
public enum ShoppingName {
    /// R2: lowercased, trimmed, inner whitespace collapsed to one space, diacritics folded. No singular/plural folding.
    public static func key(_ name: String) -> String
}
public struct ParsedItem: Sendable, Hashable { public var name: String; public var quantity: String? }
public enum ShoppingInputParser {
    public static let maxItems = 20
    public static let maxNameLength = 80
    public struct ParseResult: Sendable, Equatable { public var items: [ParsedItem]; public var droppedCount: Int }
    public static func parseAll(_ text: String) -> ParseResult
    public static func parse(_ text: String) -> [ParsedItem]          // parseAll(text).items
}
public struct ShoppingItem: Sendable, Hashable, Identifiable {
    public var id: String, name: String, quantity: String?, isCompleted: Bool
    public var completedAt: Date?, createdAt: Date?, hasLongNotes: Bool
    /// Quantity = first line of the notes (trimmed, nil when empty); long = more than one non-empty line.
    public static func quantity(fromNotes notes: String?) -> (quantity: String?, hasLongNotes: Bool)
}
```
  - Zahlwörter → Ziffern: ein/eine/einen/eins = 1 … zwölf = 12; one … twelve. Einheiten exakt nach Spec R3 Nr. 2, ohne Beachtung der Großschreibung; die Einheit bleibt in der Schreibweise der Eingabe.
  - Trennung an ` und ` / ` and ` nur mit Leerraum auf beiden Seiten und ohne Beachtung der Großschreibung.

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func key_lowercasesTrimsCollapsesAndFolds() {
    #expect(ShoppingName.key("  Grüner   Tee ") == "gruner tee")
    #expect(ShoppingName.key("Crème fraîche") == "creme fraiche")
    #expect(ShoppingName.key("Äpfel") != ShoppingName.key("Apfel"))            // no singular/plural folding
}
@Test func parse_splitsOnCommaSemicolonNewlineAndUnd() {
    #expect(ShoppingInputParser.parse("Kaffee, Reis; Eier\nSalz und Pfeffer and milk").map(\.name)
            == ["Kaffee", "Reis", "Eier", "Salz", "Pfeffer", "Milk"])
}
@Test func parse_doesNotSplitInsideWords() {
    #expect(ShoppingInputParser.parse("Mundwasser, Sandwich").map(\.name) == ["Mundwasser", "Sandwich"])
}
@Test func parse_quantities() {
    #expect(ShoppingInputParser.parse("2 Zwiebeln") == [ParsedItem(name: "Zwiebeln", quantity: "2")])
    #expect(ShoppingInputParser.parse("500 g Hackfleisch") == [ParsedItem(name: "Hackfleisch", quantity: "500 g")])
    #expect(ShoppingInputParser.parse("zwei Packungen Hafermilch") == [ParsedItem(name: "Hafermilch", quantity: "2 Packungen")])
    #expect(ShoppingInputParser.parse("three cans tomatoes") == [ParsedItem(name: "Tomatoes", quantity: "3 cans")])
    #expect(ShoppingInputParser.parse("eine Gurke") == [ParsedItem(name: "Gurke", quantity: "1")])
}
@Test func parse_capitalizesFirstLetterOnly_andCutsAt80() {
    #expect(ShoppingInputParser.parse("grüner tee").first?.name == "Grüner tee")
    #expect(ShoppingInputParser.parse(String(repeating: "a", count: 100)).first?.name.count == 80)
}
@Test func parse_separatorsOnly_isEmpty() {                                    // Review Focus 5
    #expect(ShoppingInputParser.parse(" , ; und \n ").isEmpty)
    #expect(ShoppingInputParser.parse("").isEmpty)
}
@Test func parse_quantityWithoutName_isName() {                                // Review Focus 5
    #expect(ShoppingInputParser.parse("2") == [ParsedItem(name: "2", quantity: nil)])
    #expect(ShoppingInputParser.parse("500 g") == [ParsedItem(name: "500 g", quantity: nil)])
}
@Test func parseAll_keepsTwentyAndCountsTheRest() {
    let result = ShoppingInputParser.parseAll((1...23).map { "Artikel\($0)" }.joined(separator: ","))
    #expect(result.items.count == 20 && result.droppedCount == 3)
}
@Test func quantityFromNotes_firstLineAndLongFlag() {
    #expect(ShoppingItem.quantity(fromNotes: nil) == (nil, false))
    #expect(ShoppingItem.quantity(fromNotes: " 2 Packungen \n") == ("2 Packungen", false))
    #expect(ShoppingItem.quantity(fromNotes: "2\nnur die mit Schraubverschluss") == ("2", true))
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen** nach den Signaturen; Faltung mit `folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))`.
- [ ] **Schritt 4:** Suite ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Packages/TagwerkCore && git commit -m "feat: parse shopping input into items and quantities"`

---

### Task 6: Kernlogik – Wörterbuch, Einordnen, Abschnitte, Kategorienamen

**Paket 3 (Teil 2 von 2) · 3,5 h · Issue wie Task 5.**

**Files:**
- Create: `Core/ShoppingClassifier.swift`, `Core/Resources/ShoppingDictionary.json`
- Modify: `Core/Resources/Localizable.xcstrings` (zehn Kategorienamen, „Sonstiges“)
- Test: `Packages/TagwerkCore/Tests/TagwerkCoreTests/ShoppingClassifierTests.swift` (neu)

**Interfaces:**
- Consumes: `ShoppingName.key`, `ShoppingItem` (Task 5).
- Produces:

```swift
public enum ShoppingBuiltinCategory: String, Sendable, CaseIterable {   // order = default sortIndex
    case produce, bakery, chilled, meat, frozen, pantry, snacks, drinks, household, care
    public var localizedName: String                                    // names from spec R12, bundle: .module
}
public struct ShoppingCategoryInfo: Sendable, Hashable, Identifiable {
    public var id: UUID, name: String, sortIndex: Int, builtinKey: String?
}
public struct ShoppingDictionary: Sendable {
    public static let bundled: ShoppingDictionary                       // ShoppingDictionary.json from Bundle.module
    public init(entries: [String: [String]])                            // builtinKey → terms (already keys per R2)
    /// Longest match wins: (a) whole key, (b) one word of the key, (c) key ends with a term of at least 4 characters.
    public func builtinKey(forKey key: String) -> String?
}
public struct ShoppingAssignmentInfo: Sendable, Hashable { public var categoryID: UUID?; public var isManual: Bool }
public enum ShoppingClassifier {
    /// R6 (+ A4). Returns the category id, or `nil` for "Sonstiges".
    public static func categoryID(forKey key: String, assignments: [String: ShoppingAssignmentInfo],
                                  categories: [ShoppingCategoryInfo], dictionary: ShoppingDictionary) -> UUID?
}
public struct ShoppingSection: Sendable, Hashable, Identifiable {
    public var categoryID: UUID?            // nil = "Sonstiges"
    public var items: [ShoppingItem]
    public var id: String                   // categoryID?.uuidString ?? "other"
}
public enum ShoppingSections {
    /// R7/R8: by sortIndex, "Sonstiges" last, empty sections omitted; inside by createdAt ascending,
    /// ties and missing dates by title (missing dates after dated items).
    public static func make(open items: [ShoppingItem], assignments: [String: ShoppingAssignmentInfo],
                            categories: [ShoppingCategoryInfo], dictionary: ShoppingDictionary) -> [ShoppingSection]
}
public enum ShoppingCategoryRules {
    public static let maxCategories = 30
    public static let maxNameLength = 30
    public enum NameError: Error, Equatable { case empty, tooLong, duplicate, reserved, limitReached }
    /// R10: returns the trimmed name. `existing` are the other categories' names (the renamed one excluded).
    public static func validatedName(_ raw: String, existing: [String], isNew: Bool) throws(NameError) -> String
}
```
  - „Sonstiges“/„Other“ ist in beiden Sprachen reserviert, unabhängig von der App-Sprache.
  - `ShoppingDictionary.json`: Form `{ "produce": ["banane", "bananen", "apfel", …], … }`, Schlüssel genau die zehn `rawValue`s, 400–600 Begriffe gesamt, deutsch und englisch, jeder Begriff bereits `ShoppingName.key`-normalisiert und in genau einer Kategorie. Der Inhalt ist dem Umsetzenden überlassen (Spec §10); Pflichtbegriffe aus den Tests: `milch`, `brot`, `banane`, `bananen`, `eier`, `hackfleisch`, `spulmittel`, `kaffee`, `reis`, `zwiebeln`, `milk`, `bread`.

- [ ] **Schritt 1: Tests schreiben**

```swift
// dictionary used in logic tests: ["chilled": ["milch", "eier"], "bakery": ["brot"], "produce": ["banane", "bananen"], "pantry": ["kokosmilch"]]
@Test func dictionary_wholeKeyWordAndSuffix() {
    #expect(dict.builtinKey(forKey: "milch") == "chilled")                    // (a)
    #expect(dict.builtinKey(forKey: "frische bananen") == "produce")          // (b)
    #expect(dict.builtinKey(forKey: "hafermilch") == "chilled")               // (c) "milch"
    #expect(dict.builtinKey(forKey: "vollkornbrot") == "bakery")              // (c) "brot" has 4 characters
    #expect(dict.builtinKey(forKey: "kokosmilch") == "pantry")                // longest match wins over suffix "milch"
    #expect(dict.builtinKey(forKey: "sonnenmilch") == "chilled")              // documented false hit
    #expect(dict.builtinKey(forKey: "schrauben") == nil)
}
@Test func dictionary_suffixNeedsFourCharacters() {
    #expect(ShoppingDictionary(entries: ["produce": ["ei"]]).builtinKey(forKey: "brei") == nil)
}
@Test func classify_learnedBeatsDictionary_dictionaryBeatsOther() {
    // categories: chilled(builtinKey "chilled"), household(custom, builtinKey nil)
    #expect(classify("milch", assignments: ["milch": .init(categoryID: household.id, isManual: true)]) == household.id)
    #expect(classify("milch", assignments: [:]) == chilled.id)
    #expect(classify("schrauben", assignments: [:]) == nil)
}
@Test func classify_assignmentToDeletedCategory_fallsBackToDictionary() {
    #expect(classify("milch", assignments: ["milch": .init(categoryID: UUID(), isManual: true)]) == chilled.id)
}
@Test func classify_manualOther_beatsDictionary() {                           // A4
    #expect(classify("milch", assignments: ["milch": .init(categoryID: nil, isManual: true)]) == nil)
}
@Test func classify_builtinCategoryDeleted_goesToOther() {
    #expect(ShoppingClassifier.categoryID(forKey: "milch", assignments: [:], categories: [household], dictionary: dict) == nil)
}
@Test func sections_orderBySortIndex_otherLast_emptyOmitted_itemsByCreationThenTitle() {
    // chilled sortIndex 2, bakery sortIndex 0; items: Milch (created t2), Eier (created t1), Brot (nil), Baguette→bakery (nil), Schrauben
    #expect(sections.map(\.categoryID) == [bakery.id, chilled.id, nil])
    #expect(sections[0].items.map(\.name) == ["Baguette", "Brot"])            // no dates → by title
    #expect(sections[1].items.map(\.name) == ["Eier", "Milch"])               // by createdAt
}
@Test func categoryName_rules() throws {
    #expect(try ShoppingCategoryRules.validatedName("  Tierbedarf ", existing: [], isNew: true) == "Tierbedarf")
    #expect(throws: ShoppingCategoryRules.NameError.empty) { try ShoppingCategoryRules.validatedName("   ", existing: [], isNew: true) }
    #expect(throws: ShoppingCategoryRules.NameError.tooLong) { try ShoppingCategoryRules.validatedName(String(repeating: "a", count: 31), existing: [], isNew: true) }
    #expect(throws: ShoppingCategoryRules.NameError.duplicate) { try ShoppingCategoryRules.validatedName("kühlregal", existing: ["Kühlregal"], isNew: true) }
    #expect(throws: ShoppingCategoryRules.NameError.reserved) { try ShoppingCategoryRules.validatedName("sonstiges", existing: [], isNew: true) }
    #expect(throws: ShoppingCategoryRules.NameError.reserved) { try ShoppingCategoryRules.validatedName("Other", existing: [], isNew: true) }
    #expect(throws: ShoppingCategoryRules.NameError.limitReached) { try ShoppingCategoryRules.validatedName("Neu", existing: (1...30).map { "K\($0)" }, isNew: true) }
    #expect(try ShoppingCategoryRules.validatedName("Neu", existing: (1...29).map { "K\($0)" } , isNew: false) == "Neu")
}
@Test func bundledDictionary_isConsistent() {
    let entries = ShoppingDictionary.bundledEntries                           // internal accessor for this test
    #expect(Set(entries.keys) == Set(ShoppingBuiltinCategory.allCases.map(\.rawValue)))
    let all = entries.values.flatMap { $0 }
    #expect(all.count == Set(all).count)                                      // every term in one category only
    #expect(all.allSatisfy { $0 == ShoppingName.key($0) })
    #expect((400...600).contains(all.count))
    #expect(ShoppingDictionary.bundled.builtinKey(forKey: ShoppingName.key("Spülmittel")) == "household")
}
@Test func builtinNames_germanInTests() {
    #expect(ShoppingBuiltinCategory.produce.localizedName == "Obst & Gemüse")
    #expect(ShoppingBuiltinCategory.allCases.count == 10)
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen.** Wörterbuch einmal in ein `[String: String]` (Begriff → `builtinKey`) umdrehen; Endungssuche über die Begriffe mit mindestens 4 Zeichen, längster Treffer über (a)–(c) gemeinsam. `Package.swift` bleibt unverändert (`resources: [.process("Resources")]` erfasst die JSON-Datei).
- [ ] **Schritt 4:** Paket `TagwerkCore` testen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Packages/TagwerkCore && git commit -m "feat: classify shopping items with a bundled dictionary"`

---

### Task 7: Kategorien – Modelle und Speicher

**Paket 4 (Teil 1 von 2) · 3 h · Issue „Phase 5: Kategorien der Einkaufsliste“.**

**Files:**
- Create: `Tagwerk/Shopping/ShoppingRecords.swift`, `Tagwerk/Shopping/ShoppingCategoryStore.swift`
- Modify: `Tagwerk/Persistence/ModelContainerFactory.swift:5–12` (`ShoppingCategory.self, ShoppingAssignment.self` anhängen)
- Test: `TagwerkTests/ShoppingCategoryStoreTests.swift` (neu)

**Interfaces:**
- Consumes: `ShoppingBuiltinCategory`, `ShoppingCategoryInfo`, `ShoppingAssignmentInfo`, `ShoppingCategoryRules` (Task 6); `AppSettings.shoppingCategoriesSeeded` (Task 4).
- Produces: `@Model final class ShoppingCategory` und `ShoppingAssignment` mit genau den Feldern aus Spec §5.1, sowie

```swift
@MainActor final class ShoppingCategoryStore {
    init(context: ModelContext, settings: AppSettings, now: @escaping () -> Date = Date.init)
    func categories() -> [ShoppingCategoryInfo]                       // by sortIndex, ties by createdAt
    func assignments() -> [String: ShoppingAssignmentInfo]            // nameKey → info; isManual == (sourceRaw == "manual")
    func seedIfNeeded()                                               // R12, once; sets shoppingCategoriesSeeded
    @discardableResult func add(name: String) throws -> ShoppingCategoryInfo      // at the end; ShoppingCategoryRules.NameError
    func rename(_ id: UUID, to name: String) throws                  // keeps builtinKey
    func move(fromOffsets: IndexSet, toOffset: Int)                   // rewrites sortIndex 0…n-1
    func delete(_ id: UUID)                                           // R9: removes the category and all assignments pointing to it
    func restoreBuiltins()                                            // appends missing builtin categories, touches nothing else
    func assign(nameKey: String, to categoryID: UUID?, manual: Bool)  // upsert by nameKey (search before insert)
}
```
  - `assign(..., manual: false)` überschreibt nie eine vorhandene Zuordnung mit `sourceRaw == "manual"` (Festlegung 10).

- [ ] **Schritt 1: Tests schreiben** (In-Memory-Container über `ModelContainerFactory.make(inMemory: true)`)

```swift
@Test func seed_createsTenBuiltinsInOrder_once() {
    store.seedIfNeeded()
    #expect(store.categories().map(\.builtinKey) == ShoppingBuiltinCategory.allCases.map(\.rawValue))
    #expect(store.categories().first?.name == "Obst & Gemüse")
    store.delete(store.categories()[0].id); store.seedIfNeeded()
    #expect(store.categories().count == 9)                                    // not re-created after deletion
}
@Test func add_appendsAndValidates() throws {
    store.seedIfNeeded()
    #expect(try store.add(name: " Tierbedarf ").sortIndex == 10)
    #expect(throws: ShoppingCategoryRules.NameError.duplicate) { try store.add(name: "tierbedarf") }
}
@Test func rename_keepsBuiltinKey_andAllowsOwnNameWithOtherCase() throws
@Test func move_rewritesSortIndex()                                           // move last to first → names start with the moved one, sortIndex 0…n-1
@Test func delete_removesAssignmentsOfThatCategoryOnly()                      // R9
@Test func restoreBuiltins_appendsOnlyMissing_keepsRenamedAndCustom() throws  // delete "frozen", rename "chilled", add custom → count +1, last.builtinKey == "frozen", renamed name kept
@Test func assign_upsertsByNameKey_andAIDoesNotOverrideManual() {
    store.assign(nameKey: "milch", to: a, manual: true)
    store.assign(nameKey: "milch", to: b, manual: false)
    #expect(store.assignments()["milch"] == ShoppingAssignmentInfo(categoryID: a, isManual: true))
    store.assign(nameKey: "milch", to: b, manual: true)
    #expect(store.assignments().count == 1 && store.assignments()["milch"]?.categoryID == b)
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen.**
- [ ] **Schritt 4:** Suiten `ShoppingCategoryStoreTests`, `ModelStoreLocationTests` ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: store shopping categories and learned assignments"`

---

### Task 8: `ShoppingModel`

**Paket 5 · 5 h · Issue „Phase 5: ShoppingModel“.**

**Files:**
- Create: `Tagwerk/Shopping/ShoppingModel.swift`
- Modify: `Tagwerk/App/AppEnvironment.swift` (Eigenschaften `shoppingCategories`, `shopping`; `setShoppingList`; `startObservingChanges()`), `Tagwerk/App/TagwerkApp.swift:47–50` (nach `taskList.reload()` zusätzlich `await environment.shopping.reload()`)
- Test: `TagwerkTests/ShoppingModelTests.swift` (neu)

**Interfaces:**
- Consumes: `ReminderStore.completedReminders`, `ListInfo.isWritable` (Task 2); `ParsedItem`, `ShoppingItem`, `ShoppingName` (Task 5); `ShoppingSections`, `ShoppingDictionary` (Task 6); `ShoppingCategoryStore` (Task 7); `InMemoryReminderStore`, `AppEnvironment.reminderStore` (Task 4).
- Produces:

```swift
@MainActor @Observable final class ShoppingModel {
    enum State: Equatable { case noList, listMissing, accessDenied, ready }
    struct AddReport: Equatable {
        var added: [String] = [], reopened: [String] = [], alreadyOnList: [String] = []
        var failed: [String] = []                       // names that could not be written
        var errorMessage: String?                       // TaskListModel.message(for:) of the first failure
    }
    static let completedWindow: TimeInterval = 7 * 24 * 3600

    init(store: any ReminderStore, settings: AppSettings, categories: ShoppingCategoryStore,
         dictionary: ShoppingDictionary = .bundled, now: @escaping () -> Date = Date.init)

    private(set) var state: State
    private(set) var listTitle: String?
    private(set) var openItems: [ShoppingItem]          // flattened `sections`, order R8
    private(set) var completedItems: [ShoppingItem]     // last 7 days, newest first
    private(set) var sections: [ShoppingSection]

    func reload() async
    func add(_ items: [ParsedItem]) async -> AddReport                  // R4
    func checkOff(id: String) async throws                              // R5; TaskWriteError.notFound unless the reminder is in the shopping list
    func reopen(id: String) async throws
    func update(id: String, name: String, quantity: String?) async throws   // quantity ignored when hasLongNotes
    func delete(id: String) async throws
    @discardableResult func removeCompleted() async -> Int             // deletes exactly `completedItems`; returns the number deleted
    func setCategory(_ categoryID: UUID?, forItemID id: String)         // manual assignment by name key, then re-sections
    func refreshSections()                                              // after category changes (Task 10, 12)
    func categoryID(of item: ShoppingItem) -> UUID?
}
```
  - `AppEnvironment.shoppingCategories: ShoppingCategoryStore`, `AppEnvironment.shopping: ShoppingModel` (mit `reminderStore`).
  - `setShoppingList(_:)` und `startObservingChanges()` rufen zusätzlich `await shopping.reload()` (Abweichung A2).
  - Zustände: kein Vollzugriff → `.accessDenied`; `shoppingListID == nil` → `.noList`; Kennung nicht in `store.lists()` → `.listMissing`; in allen drei Fällen sind die Listen leer und alle Schreibfunktionen schreiben nichts (`add` meldet alles unter `failed`).
  - Schreibvorgänge prüfen vor dem Schreiben über `store.reminder(id:)`, dass `listID == settings.shoppingListID`.
  - Jede Schreibfunktion endet mit `reload()`.

- [ ] **Schritt 1: Tests schreiben** (Store mit Liste `shop` „Einkauf“ und `uni`; `now` fest; Kategorien geseedet)

```swift
@Test func reload_readsOpenAndRecentlyCompletedOfShoppingListOnly() async
    // open in shop: Milch, Bananen; open in uni: Seminararbeit; completed in shop 2 days ago: Eier; 8 days ago: Reis
    // → openItems names == ["Bananen", "Milch"] (produce before chilled), completedItems names == ["Eier"], state == .ready, listTitle == "Einkauf"
@Test func add_newItem_createsPlainReminderInShoppingList() async {
    let report = await model.add([ParsedItem(name: "Kaffee", quantity: "2 Packungen")])
    let record = try #require(store.records.values.first { $0.title == "Kaffee" })
    #expect(report.added == ["Kaffee"])
    #expect(record.listID == "shop" && record.notes == "2 Packungen" && record.due == nil && record.ekPriority == 0 && record.recurrence == nil)
}
@Test func add_openDuplicate_createsNothing_replacesQuantity() async
    // "milch" with quantity "2": createCount unchanged, notes == "2", report.alreadyOnList == ["Milch"]; without quantity: notes unchanged
@Test func add_openItemWithLongNotes_keepsNotes() async                    // Review Focus 3: notes "1\nnur Bio" stay; report.alreadyOnList
@Test func add_recentlyCompleted_reopensNewest() async
    // two completed "Eier" (1 and 3 days ago) → the 1-day-old one is open again, createCount unchanged, report.reopened == ["Eier"]
@Test func add_completedOlderThanSevenDays_createsNew() async              // "Reis" (8 days) → report.added == ["Reis"]
@Test func add_duplicateWithinOneInput_createsOne() async {                // Review Focus 1
    let report = await model.add([ParsedItem(name: "Hefe", quantity: nil), ParsedItem(name: "hefe", quantity: nil), ParsedItem(name: "Hefe", quantity: "2")])
    #expect(store.records.values.filter { ShoppingName.key($0.title) == "hefe" }.count == 1)
    #expect(report.added == ["Hefe"] && report.alreadyOnList.count == 2)
    #expect(store.records.values.first { $0.title == "Hefe" }?.notes == "2")
}
@Test func add_listMissing_writesNothing() async {                         // Review Focus 2
    store.listInfos.removeAll { $0.id == "shop" }
    await model.reload()
    let report = await model.add([ParsedItem(name: "Kaffee", quantity: nil)])
    #expect(model.state == .listMissing && store.createCount == 0 && report.failed == ["Kaffee"])
}
@Test func checkOff_completesWithoutDeleting_reopenRestores() async throws
    // record still exists with isCompleted == true, appears in completedItems; reopen → back in openItems
@Test func checkOff_reminderOutsideShoppingList_throwsNotFound() async     // id of "Seminararbeit" → throws, record stays open
@Test func removeCompleted_deletesOnlyLastSevenDays() async {
    #expect(await model.removeCompleted() == 1)                            // "Eier"
    #expect(store.records.values.contains { $0.title == "Reis" })          // 8 days old stays in Reminders
}
@Test func setCategory_appliesToEveryItemOfThatName() async
    // setCategory(household, forItemID: milk) → section household contains "Milch"; a later added "milch" lands there too
@Test func noAccess_stateAccessDenied() async
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen.** `ShoppingItem` aus `ReminderRecord` über `ShoppingItem.quantity(fromNotes:)`. R4 arbeitet auf dem frisch geladenen Stand und führt den Stand je verarbeitetem Artikel nach (dadurch greift Review Focus 1 ohne Sonderfall). Fällt Spike S2 für `completionDate` durch, gilt die Folge aus Task 1; fällt S5 durch, `loadCompleted()` abspalten.
- [ ] **Schritt 4:** Suiten `ShoppingModelTests`, `ShoppingExclusionTests` ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: add shopping model on top of reminders"`

---

### Task 9: Einkaufsseite

**Paket 6 · 8 h · Issue „Phase 5: Einkaufsseite“.**

**Files:**
- Create: `Tagwerk/Shopping/ShoppingListView.swift`, `ShoppingItemSheet.swift`, `ShoppingInputBar.swift`
- Modify: `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/ShoppingInputTests.swift` (neu)

**Interfaces:**
- Consumes: `ShoppingModel` (Task 8), `ShoppingInputParser` (Task 5), `ShoppingCategoryStore.categories()`/`add(name:)` (Task 7), `VoiceInputFactory.make(_:)`, `VoiceMicrophoneButton`, `VoiceRecordingBar`, `AssistantToolbarItems`.
- Produces:
  - `struct ShoppingListView: View { init(model: ShoppingModel) }`: kein eigener `NavigationStack`; Navigation zu „Kategorien“ über `NavigationLink { … }` in Closure-Form, alles andere über Blätter. Menüpunkte „Mit ChatGPT sortieren“ und „Kategorien verwalten“ sind vorhanden; ihre Ziele liefern Task 12 und Task 10 (bis dahin ausgegraut).
  - Reine, getestete Logik der Eingabezeile:

```swift
enum ShoppingInput {
    /// Chips are shown for more than one parsed item or dictated text; a single typed item is added directly.
    static func needsPreview(items: [ParsedItem], wasDictated: Bool) -> Bool
    /// "3 hinzugefügt" · "Eier steht schon drauf" · "Kaffee wieder geöffnet"; several parts joined with " · ";
    /// a failure appends `errorMessage`; `droppedCount > 0` appends "Höchstens 20 Artikel auf einmal".
    static func feedback(_ report: ShoppingModel.AddReport, droppedCount: Int) -> String
    static func chipTitle(_ item: ParsedItem) -> String              // "＋ 2 Zwiebeln", "＋ Kaffee"
}
```

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func preview_onlyForSeveralOrDictated() {
    let one = [ParsedItem(name: "Kaffee", quantity: nil)]
    #expect(!ShoppingInput.needsPreview(items: one, wasDictated: false))
    #expect(ShoppingInput.needsPreview(items: one, wasDictated: true))
    #expect(ShoppingInput.needsPreview(items: one + one, wasDictated: false))
}
@Test func feedback_texts() {
    #expect(ShoppingInput.feedback(.init(added: ["Kaffee", "Reis", "Zwiebeln"]), droppedCount: 0) == "3 hinzugefügt")
    #expect(ShoppingInput.feedback(.init(alreadyOnList: ["Eier"]), droppedCount: 0) == "Eier steht schon drauf")
    #expect(ShoppingInput.feedback(.init(reopened: ["Kaffee"]), droppedCount: 0) == "Kaffee wieder geöffnet")
    #expect(ShoppingInput.feedback(.init(added: ["Reis"], alreadyOnList: ["Eier"]), droppedCount: 3)
            == "1 hinzugefügt · Eier steht schon drauf · Höchstens 20 Artikel auf einmal")
}
@Test func chipTitle_showsQuantityBeforeName() {
    #expect(ShoppingInput.chipTitle(ParsedItem(name: "Zwiebeln", quantity: "2")) == "＋ 2 Zwiebeln")
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: `ShoppingInput` umsetzen**, Suite grün.
- [ ] **Schritt 4: Seite bauen** nach Spec §5.4, Punkt für Punkt:
  - Kopf: Titel „Einkaufsliste“, Unterzeile „%lld offen · Liste ‚%@‘ in Erinnerungen“; Leiste: Menü „⋯“ („Mit ChatGPT sortieren“, „Kategorien verwalten“, „Erledigte entfernen“) und Assistenten-Knopf (Kontext `.tasks`).
  - Abschnitte aus `model.sections`; Titel aus den Kategorien, `nil` → „Sonstiges“.
  - Zeile: Kreis (Tipp → `checkOff`, `UIImpactFeedbackGenerator(style: .light)`), Name, Menge sekundär; Tipp auf die Zeile → `ShoppingItemSheet`; Kontextmenü „Kategorie“ (alle Kategorien, Haken an der aktuellen, „Sonstiges“, „Neue Kategorie …“), „Bearbeiten“, „Löschen“; Wischen links „Löschen“ ohne Rückfrage.
  - `ShoppingItemSheet`: Name, Menge (nur lesbar mit „Längere Notiz, in Erinnerungen bearbeiten“ bei `hasLongNotes`), Kategorie-Auswahl, „Löschen“.
  - „Neue Kategorie …“: Dialog mit Textfeld → `categories.add(name:)`, dann `setCategory`; `NameError` als Meldung im Dialog.
  - „Erledigt · %lld“: eingeklappt (`DisclosureGroup`), Tipp auf den Kreis → `reopen`.
  - „Erledigte entfernen“: Rückfrage „%lld erledigte Artikel endgültig löschen?“ → `removeCompleted()`; ausgegraut ohne erledigte Artikel.
  - Eingabezeile `ShoppingInputBar` unten (`safeAreaInset`): Feld „Artikel hinzufügen“, Mikrofon nur bei `settings.voiceInputEnabled`, Senden-Knopf bei Text; Marken über der Zeile nach `needsPreview`, Tipp entfernt eine Marke, Senden legt an; nach dem Diktat nie ohne Tippen speichern; Rückmeldung über dem Feld (verschwindet nach 4 s).
  - Zustände: leer („Die Liste ist leer. Füge unten Artikel hinzu.“), `.accessDenied` (Knopf zu den iOS-Einstellungen), `.listMissing` und `.noList` (Knopf „Andere Liste wählen“ → `environment.tasksPath.append(.shoppingSettings)`, Ziel entsteht in Task 11); Schreibfehler als Meldung über dem Feld mit `TaskListModel.message(for:)`.
  - Aktualisierung: `.task { await model.reload() }`, `.refreshable`.
- [ ] **Schritt 5: Sichtprüfung im Simulator** (Erinnerungen im Simulator freigeben, dort eine Liste „Einkauf“ mit fünf Artikeln anlegen; bis Task 11 die Auswahlseite liefert, die Liste vorläufig in einem `#Preview` über `setShoppingList` wählen): hell, dunkel, größte Schriftstufe, Englisch, VoiceOver liest „Hafermilch, 2 Packungen, nicht erledigt“. Am Gerät nicht geprüft; das folgt in Task 17.
- [ ] **Schritt 6:** `app/test-all.sh`. Erwartet: `ALL TESTS PASSED` (Kataloge enthalten die neuen Texte deutsch und englisch).
- [ ] **Schritt 7:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: add shopping list page with input bar and dictation"`

---

### Task 10: Seite „Kategorien“

**Paket 4 (Teil 2 von 2) · 3 h · Issue wie Task 7.**

**Files:**
- Create: `Tagwerk/Shopping/ShoppingCategoriesView.swift`
- Modify: `Tagwerk/Shopping/ShoppingListView.swift` (Menüziel), `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/ShoppingCategoryStoreTests.swift` (ergänzen)

**Interfaces:**
- Consumes: `ShoppingCategoryStore` (Task 7), `ShoppingModel.sections`, `refreshSections()` (Task 8).
- Produces: `struct ShoppingCategoriesView: View { init(store: ShoppingCategoryStore, model: ShoppingModel) }` (ohne eigenen `NavigationStack`); `ShoppingCategoriesView.deleteQuestion(name: String, openCount: Int) -> String`; `ShoppingCategoriesView.message(for: ShoppingCategoryRules.NameError) -> String`.

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func deleteQuestion_namesOpenItemCount() {
    #expect(ShoppingCategoriesView.deleteQuestion(name: "Kühlregal", openCount: 3)
            == "„Kühlregal“ löschen? 3 Artikel werden neu einsortiert, meist unter „Sonstiges“.")
    #expect(ShoppingCategoriesView.deleteQuestion(name: "Tiefkühl", openCount: 0) == "„Tiefkühl“ löschen?")
}
@Test func nameErrorMessages_coverEveryCase() {
    for error in [ShoppingCategoryRules.NameError.empty, .tooLong, .duplicate, .reserved, .limitReached] {
        #expect(!ShoppingCategoriesView.message(for: error).isEmpty)
    }
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Seite bauen** nach Spec §5.5: `.task { store.seedIfNeeded() }`; Liste dauerhaft im Bearbeitungsmodus (`.environment(\.editMode, .constant(.active))`, `onMove`, `onDelete` mit Rückfrage); Zahl offener Artikel je Kategorie aus `model.sections`; Tipp auf den Namen → Dialog zum Umbenennen; letzte Zeile „Kategorie hinzufügen“; darunter fest und grau „Sonstiges · für alles ohne Kategorie“; Fußknopf „Standardkategorien wiederherstellen“. Nach jeder Änderung `model.refreshSections()`. Die Einkaufsseite ruft `seedIfNeeded()` ebenfalls in ihrem `.task` (R12).
- [ ] **Schritt 4:** `ShoppingCategoryStoreTests` ausführen. Erwartet: grün. Sichtprüfung im Simulator: Umsortieren, Umbenennen einer Standardkategorie, Löschen mit Rückfrage, Wiederherstellen.
- [ ] **Schritt 5:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: manage shopping categories"`

---

### Task 11: Einstieg in „Aufgaben“ und Einstellungen

**Paket 7 · 5 h · Issue „Phase 5: Einstieg und Einstellungen“.**

**Files:**
- Create: `Tagwerk/Tasks/TasksDestination.swift`, `Tagwerk/Tasks/TasksEntrySection.swift`, `Tagwerk/Shopping/ShoppingSettingsView.swift`
- Modify: `Tagwerk/Tasks/TaskListView.swift:29–60`, `Tagwerk/App/AppEnvironment.swift` (`var tasksPath: [TasksDestination] = []`), `Tagwerk/Settings/SettingsView.swift:33–50`, `Tagwerk/Settings/SourceSelectionView.swift`, `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/TasksEntryTests.swift` (neu)

**Interfaces:**
- Consumes: `ShoppingListFilter.suggestedList(in:)` (Task 3), `AppEnvironment.setShoppingList` (Task 4), `ShoppingModel` (Task 8), `ShoppingListView` (Task 9), `ShoppingCategoriesView` (Task 10). Die Zeile „Notizen“ zeigt bis Task 14 fest „Noch keine Notizen“ und führt auf `.notes`; Task 14 liefert Inhalt und Ziel.
- Produces:
  - `enum TasksDestination: Hashable { case shopping, shoppingSettings, shoppingCategories, notes, note(UUID) }`
  - `AppEnvironment.tasksPath`
  - reine Logik:

```swift
enum ShoppingEntryState: Equatable {
    case hidden                                   // no full access to reminders
    case suggestion(listID: String, title: String)
    case setup(previousListMissing: Bool)
    case list(subtitle: String, openCount: Int)
    /// Rows of spec §5.3. `lists` are all reminder lists.
    static func make(access: AccessState, setupCompleted: Bool, lists: [ListInfo], settings: AppSettings,
                     model: ShoppingModel) -> ShoppingEntryState
    /// "Hafermilch, Bananen, Eier und 4 weitere" · "Hafermilch, Bananen" · "Nichts offen"
    static func subtitle(openNames: [String]) -> String
}
enum ReminderListSummary {
    /// "3 von 3" without the shopping list.
    static func text(selected: [String]?, lists: [ListInfo], shopping: String?) -> String
}
```
  - `SourceSelectionView` bekommt `var lockedIDs: [String: LocalizedStringKey] = [:]` (Kennung → Vermerk); gesperrte Zeilen sind grau, nicht wählbar, ohne Haken, mit dem Vermerk rechts.
  - `struct ShoppingSettingsView: View` (ohne eigenen `NavigationStack`).

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func entry_hiddenWithoutFullAccess()                                   // access .denied → .hidden
@Test func entry_suggestsSingleMatchingList() {                              // lists "Einkauf", "Uni" → .suggestion(listID: "shop", title: "Einkauf")
}
@Test func entry_noSuggestionWhenDismissedOrSetupOpenOrTwoCandidates()       // each → .setup(previousListMissing: false)
@Test func entry_chosenListGone_showsSetupWithHint()                         // shoppingListID "gone" → .setup(previousListMissing: true)
@Test func entry_listWithItems_andEmpty() {
    #expect(ShoppingEntryState.subtitle(openNames: ["Hafermilch", "Bananen", "Eier", "A", "B", "C", "D"]) == "Hafermilch, Bananen, Eier und 4 weitere")
    #expect(ShoppingEntryState.subtitle(openNames: ["Hafermilch", "Bananen"]) == "Hafermilch, Bananen")
    #expect(ShoppingEntryState.subtitle(openNames: []) == "Nichts offen")
}
@Test func reminderListSummary_countsWithoutShoppingList() {
    // lists a, b, shop; selected nil; shopping "shop" → "2 von 2"; selected ["a", "shop"] → "1 von 2"
}
@Test func dismissSuggestion_keepsSetupRow() {                               // Festlegung 18: after "Nicht jetzt" state is .setup, not .hidden
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Logik umsetzen**, Suite grün.
- [ ] **Schritt 4: Oberfläche bauen.**
  - `TaskListView`: `NavigationStack(path: Bindable(environment).tasksPath)`; `.navigationDestination(for: TasksDestination.self)` (`.shopping` → `ShoppingListView`, `.shoppingSettings` → `ShoppingSettingsView`, `.shoppingCategories` → `ShoppingCategoriesView`, `.notes`/`.note` → Platzhalter bis Task 14). `TasksEntrySection` als erste `Section` nach Filter und `SourceProblemRow`s, vor `model.sections`; ausgeblendet bei `isSelecting`; unabhängig von `model.filter`; Zeilen als `Button` ohne `tag`, damit sie nicht auswählbar sind. Die Überlagerung „Keine Aufgaben“ (`:61–71`) würde die Karten verdecken, weil der Abschnitt jetzt immer Zeilen hat: Der leere Zustand und die Ladeanzeige werden deshalb zu einer Listenzeile unter `TasksEntrySection` (gleiche Texte und Symbole).
  - Vorschlagskarte EQ1: Texte nach Spec §5.3; Zahl offener Erinnerungen über `reminderStore.openReminders(in: [listID]).count` (eigene Abfrage); „Verwenden“ → `setShoppingList(listID)`; „Andere Liste …“ → `tasksPath.append(.shoppingSettings)`; „Nicht jetzt“ → `shoppingSuggestionDismissed = true`.
  - `ShoppingSettingsView` nach Spec §5.7: Einfachauswahl der beschreibbaren Listen (Farbpunkt, Titel) plus „Keine“ → `setShoppingList`; Fußtext wörtlich; Abschnitt „Kategorien“ mit Anzahl; Abschnitt „ChatGPT“ mit Schalter `shoppingSortConsent` und Fußtext wörtlich.
  - `SettingsView`, Abschnitt „Quellen“: neue Zeile „Einkaufsliste“ (Wert Listentitel oder „Keine“) unter „Erinnerungslisten“; „Erinnerungslisten“ mit `lockedIDs: [shoppingListID: "Einkaufsliste"]` und `ReminderListSummary.text`.
- [ ] **Schritt 5:** Sichtprüfung im Simulator: Vorschlagskarte, „Verwenden“ entfernt die Artikel sofort aus „Aufgaben“, Auswahlmodus blendet den Abschnitt aus, gesperrte Zeile in „Erinnerungslisten“. `app/test-all.sh` grün.
- [ ] **Schritt 6:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: add shopping and notes entry rows and shopping settings"`

---

### Task 12: „Mit ChatGPT sortieren“

**Paket 8 · 6 h · Issue „Phase 5: Mit ChatGPT sortieren“.**

**Files:**
- Create: `Tagwerk/Shopping/ShoppingSorter.swift`, `Tagwerk/Shopping/ShoppingSortSheets.swift`
- Modify: `Tagwerk/Shopping/ShoppingListView.swift` (Menüpunkt, „✦ Sortieren“ am Sonstiges-Abschnitt), `Tagwerk/App/AppEnvironment.swift` (`let shoppingSorter`), `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/ShoppingSorterTests.swift` (neu; Aufbau wie `MealEstimatorTests`)

**Interfaces:**
- Consumes: `ResponseStreaming`, `ChatGPTError` (AIKit); `ShoppingCategoryStore`, `ShoppingModel` (Tasks 7, 8); `AppSettings.shoppingSortConsent`; `ShoppingCategoryRules`.
- Produces:

```swift
@MainActor final class ShoppingSorter {
    enum Failure: Error, Equatable { case consentMissing, network, signedOut, usageLimit, failed
        var message: String }
    static let maxItems = 60
    static let maxNewCategories = 3
    struct Request: Equatable { var itemNames: [String]; var categoryNames: [String] }     // categoryNames ends with "Sonstiges"
    struct Change: Equatable, Identifiable { var itemName: String; var fromCategory: String; var toCategory: String
        var id: String { ShoppingName.key(itemName) } }
    struct Proposal: Equatable { var newCategories: [String]; var changes: [Change] }      // only differences to the current state

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String,
         hasConsent: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(30))

    /// Open items without a manual assignment (first 60, order of `sections`) and all category names.
    static func request(sections: [ShoppingSection], assignments: [String: ShoppingAssignmentInfo],
                        categories: [ShoppingCategoryInfo]) -> Request
    /// Checks consent first; nothing reaches OpenAI without it, not even the model list.
    func sort(_ request: Request, current: [String: String]) async throws -> Proposal      // current: item key → category name
    /// Pure validation of the model's answer (spec §5.5 Nr. 3).
    static func validate(_ answer: Data, request: Request, current: [String: String]) throws -> Proposal
    static let schema: Data                                                                // JSON schema "shopping_sort"
}
```
  - `ShoppingSortConsentSheet(onAgree:onDecline:)` und `ShoppingSortResultSheet(proposal:onApply:onDiscard:)`; `ShoppingSortResultSheet.selection(proposal:deselectedCategories:deselectedItems:) -> Proposal` (wird eine neue Kategorie abgewählt, fallen ihre Artikel heraus).
  - „Übernehmen“: gewählte neue Kategorien über `categories.add(name:)` am Ende anlegen, je Änderung `categories.assign(nameKey:to:manual: false)`, dann `model.refreshSections()`. Nie ein Schreibzugriff auf Erinnerungen.

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func sort_withoutConsent_sendsNothing() async {
    await #expect(throws: ShoppingSorter.Failure.consentMissing) { try await sorter(consent: false).sort(request, current: [:]) }
    #expect(responder.requests.isEmpty && modelCalls == 0)
}
@Test func request_skipsManualAssignments_capsAtSixty_sendsNoQuantities() {
    // 70 open items, 5 of them with isManual → itemNames.count == 60, none of the 5 included; categoryNames.last == "Sonstiges"
    // an item with quantity "2 Packungen": request contains only its name
}
@Test func validate_dropsUnknownItemsAndUnknownCategories() throws
    // answer assigns "Pizza" (not requested) and "Reis" → "Erfunden" (not existing, not in new_categories) → both dropped
@Test func validate_keepsOnlyChanges() throws {
    // "Milch" already in "Kühlregal" and answered "Kühlregal" → no change; "Sojasauce": "Sonstiges" → "Vorrat & Konserven" → one change
}
@Test func validate_newCategories_maxThree_andRuleR10() throws
    // five new names → first three valid kept; "Sonstiges" and a 31-character name are dropped together with their items
@Test func validate_duplicateItemAndCaseInsensitiveCategory() throws {       // Review Focus 4
    // "Reis" twice (first → "vorrat & konserven", second → "Getränke") → one change to "Vorrat & Konserven"
    // new_categories ["kühlregal"] while "Kühlregal" exists → newCategories is empty, its items point to "Kühlregal"
}
@Test func validate_noChanges_isEmptyProposal() throws                       // sheet shows "ChatGPT schlägt keine andere Einteilung vor."
@Test func sort_failures_mapLikeMealEstimator() async
    // ChatGPTError.network → .network; .notSignedIn → .signedOut; .usageLimit → .usageLimit; stream without `completed` → .failed; invalid JSON → .failed
@Test func sort_timeout_fails_andLateAnswerIsNotUsed() async                 // timeout .milliseconds(50), responder answers after 300 ms → .failed
@Test func selection_deselectedNewCategory_dropsItsItems()
@Test func apply_storesAIAssignments_keepsManualOnes_writesNoReminder() async
    // after apply: assignments()["sojasauce"] == (pantry.id, isManual: false); store.saveCount and createCount unchanged
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: `ShoppingSorter` umsetzen** nach dem Aufbau von `MealEstimator` (`estimate`, `collect`, `withTimeout`, `failure(for:)`); `tools: []`, `jsonSchema: (name: "shopping_sort", schema: Self.schema)`. Schema: `{ "assignments": [{ "item": string, "category": string }], "new_categories": [string] }`, `additionalProperties: false`, alle Felder erforderlich. Der Wortlaut des Auftrags ist dem Umsetzenden überlassen; er muss enthalten: nur die genannten Artikel einordnen, vorhandene Kategorien bevorzugen, höchstens 3 neue, „Sonstiges“ erlaubt.
- [ ] **Schritt 4: Blätter und Verdrahtung.** Menüpunkt ausgegraut mit Unterzeile „Anmeldung unter Einstellungen › KI“ ohne `environment.ai.isSignedIn`; „✦ Sortieren“ an der Abschnittszeile „Sonstiges“ nur angemeldet. Erstes Tippen ohne `shoppingSortConsent` zeigt `ShoppingSortConsentSheet` (Texte wörtlich aus Spec §5.5 Nr. 2, `.presentationDetents([.large])`, `.interactiveDismissDisabled()`); „Einverstanden und sortieren“ setzt die Einwilligung und startet. Während der Anfrage Fortschrittsanzeige mit „Abbrechen“. Fehler als Meldung mit `Failure.message` (Texte nach dem Muster von `MealEstimator.Failure`, auf „Sortieren“ bezogen).
- [ ] **Schritt 5:** `ShoppingSorterTests` und `app/test-all.sh`. Erwartet: grün. Sichtprüfung mit `-TagwerkDemoAI` (Antwort für `shopping_sort` in `DemoAITransport` ergänzen).
- [ ] **Schritt 6:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: sort shopping items with ChatGPT after consent"`

---

### Task 13: Notizen – Typen und `NoteStore`

**Paket 9 (Teil 1 von 2) · 3 h · Issue „Phase 5: Notizen“.** Unabhängig von den Tasks 5–12; kann nach Task 4 laufen.

**Files:**
- Create: `Core/NoteText.swift`, `Tagwerk/Notes/NoteRecord.swift`, `Tagwerk/Notes/NoteStore.swift`
- Modify: `Tagwerk/Persistence/ModelContainerFactory.swift` (`NoteRecord.self`), `Tagwerk/App/AppEnvironment.swift` (`let notes: NoteStore`)
- Test: `Packages/TagwerkCore/Tests/TagwerkCoreTests/NoteTextTests.swift`, `TagwerkTests/NoteStoreTests.swift` (neu)

**Interfaces:**
- Produces: `NoteKind`, `NoteDayKey`, `NoteText` (Signaturen in „Schnittstellen zu den anderen Plänen“), `@Model final class NoteRecord` (Felder exakt nach Spec §5.1, zusätzlich berechnet `var kind: NoteKind`), und

```swift
@MainActor @Observable final class NoteStore {
    enum Filter: Equatable { case all, thoughts, own }                 // thoughts = morning + evening, own = free
    init(context: ModelContext, now: @escaping () -> Date = Date.init)
    private(set) var revision: Int                                      // bumped by every write; views observe it
    func notes(_ filter: Filter = .all) -> [NoteRecord]                 // pinned first, then updatedAt descending
    func note(id: UUID) -> NoteRecord?
    func note(kind: NoteKind, dayKey: String) -> NoteRecord?            // for phase 7
    var hasThoughts: Bool { get }
    var count: Int { get }
    var latest: NoteRecord? { get }                                     // by updatedAt
    @discardableResult func create(text: String, kind: NoteKind = .free, dayKey: String? = nil, wasDictated: Bool = false) -> NoteRecord?
    func updateText(_ id: UUID, text: String)                           // updatedAt only when the text changed
    func setPinned(_ id: UUID, _ pinned: Bool)                          // does not touch updatedAt
    func markProcessed(_ id: UUID, at date: Date)                       // for phase 7
    func delete(_ id: UUID)
    func deleteIfEmpty(_ id: UUID)                                      // editor on disappear
}
```
  - `create` kürzt Leerraum außen; leerer Text → `nil`, nichts wird angelegt. Für `kind != .free` mit `dayKey`: gibt es schon eine Notiz dieser Art und dieses Tages, wird deren Text ersetzt und sie zurückgegeben (Eindeutigkeit im Code, Spec §5.1).

- [ ] **Schritt 1: Tests schreiben**

```swift
// NoteTextTests
@Test func title_isFirstNonEmptyLine_max60() {
    #expect(NoteText.title("\n  Ideen Hausarbeit \nGliederung") == "Ideen Hausarbeit")
    #expect(NoteText.title(String(repeating: "x", count: 90)).count == 60)
    #expect(NoteText.title("   ") == "")
}
@Test func preview_isTheRest() {
    #expect(NoteText.preview("Ideen Hausarbeit\nGliederung\nQuellen") == "Gliederung\nQuellen")
    #expect(NoteText.preview("Nur eine Zeile") == "")
}
@Test func dayKey_roundTrips_andRejectsGarbage() {
    #expect(NoteDayKey.string(PlanDay(year: 2026, month: 11, day: 8)) == "2026-11-08")
    #expect(NoteDayKey.day("2026-11-18") == PlanDay(year: 2026, month: 11, day: 18))
    #expect(NoteDayKey.day("18.11.2026") == nil)
}

// NoteStoreTests
@Test func create_trims_andIgnoresEmpty()                                   // create("  ") == nil, count == 0; create(" a ")?.text == "a", kindRaw == "free", dayKey == nil
@Test func notes_pinnedFirst_thenByUpdatedAtDescending()
@Test func updateText_changesUpdatedAtOnlyForNewText()                      // same text → updatedAt unchanged
@Test func setPinned_keepsUpdatedAt()
@Test func filter_thoughtsAndOwn() {
    // free "a", morning "b" (2026-11-18), evening "c" (2026-11-18) → .thoughts == [c, b] or by updatedAt; .own == [a]; hasThoughts == true
}
@Test func create_thoughtForSameKindAndDay_updatesExisting()                // two creates (.evening, "2026-11-18") → count == 1, text of the second
@Test func deleteIfEmpty_removesOnlyEmptyNotes()
@Test func unknownKindRaw_readsAsFree()                                     // record.kindRaw = "weekly" → record.kind == .free
@Test func schema_opensExistingStore()                                      // ModelStoreLocationTests stays green with NoteRecord in the schema
```

- [ ] **Schritt 2:** Beide Suiten ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen.**
- [ ] **Schritt 4:** `NoteTextTests`, `NoteStoreTests`, `ModelStoreLocationTests` ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Packages/TagwerkCore app/Tagwerk app/TagwerkTests && git commit -m "feat: add local note store"`

---

### Task 14: Notizen – Liste, Schnellerfassung, Editor

**Paket 9 (Teil 2 von 2) · 4 h · Issue wie Task 13.**

**Files:**
- Create: `Tagwerk/Notes/NotesListView.swift`, `Tagwerk/Notes/NoteEditorView.swift`
- Modify: `Tagwerk/Tasks/TasksEntrySection.swift` (Zeile „Notizen“), `Tagwerk/Tasks/TaskListView.swift` (Ziele `.notes`, `.note`), `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/NotesListTextTests.swift` (neu)

**Interfaces:**
- Consumes: `NoteStore`, `NoteRecord`, `NoteText`, `NoteDayKey`, `NoteKind` (Task 13); `TasksDestination` (Task 11); `VoiceInputFactory` (Diktat).
- Produces: `struct NotesListView: View { init(store: NoteStore) }`, `struct NoteEditorView: View { init(noteID: UUID, store: NoteStore) }` (beide ohne eigenen `NavigationStack`), sowie

```swift
extension NotesListView {
    /// free: "heute 08:12" · "Dienstag" (within the last 6 days) · "12. Nov."; with "· diktiert" when dictated.
    /// morning/evening: "Tagesstart · 18.11." / "Tagesabschluss · 18.11." from dayKey (without dayKey: the date of createdAt).
    static func footer(for note: NoteRecord, now: Date, calendar: Calendar) -> String
    /// "zuletzt: „Ideen Hausarbeit“ · heute 08:12" or "Noch keine Notizen".
    static func entrySubtitle(latest: NoteRecord?, now: Date, calendar: Calendar) -> String
}
```

- [ ] **Schritt 1: Tests schreiben**

```swift
@Test func footer_freeNote_relativeDates() {
    // now = Thu 2026-11-19 10:00; updatedAt today 08:12 → "heute 08:12"; Tue 2026-11-17 → "Dienstag"; 2026-11-12 → "12. Nov."
}
@Test func footer_dictatedSuffix()                                          // "heute 08:12 · diktiert"
@Test func footer_thoughts_nameOriginAndDay() {
    // kind evening, dayKey "2026-11-18" → "Tagesabschluss · 18.11."; kind morning → "Tagesstart · 18.11."
}
@Test func entrySubtitle_latestOrEmpty() {
    // latest "Ideen Hausarbeit\n…" updated today 08:12 → "zuletzt: „Ideen Hausarbeit“ · heute 08:12"; nil → "Noch keine Notizen"
}
```

- [ ] **Schritt 2:** Suite ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Texte umsetzen**, Suite grün.
- [ ] **Schritt 4: Oberfläche bauen** nach Spec §5.6: Karten (Titel fett, Vorschau zwei Zeilen, Fußzeile, 📌 bei angehefteten); Segmentleiste „Alle · Gedanken · Eigene“ nur bei `store.hasThoughts`; Eingabezeile unten „Neue Notiz“ (mehrzeilig, Mikrofon bei `voiceInputEnabled`; Senden → `create(text:wasDictated:)`, Feld leeren); Wischen links „Löschen“ mit Rückfrage, rechts „Anheften“/„Lösen“; Fußnote „Notizen liegen nur auf diesem iPhone. Sie werden nicht an ChatGPT gesendet.“; leerer Zustand „Noch keine Notizen. Schreib oder diktiere unten die erste.“. Editor: `TextEditor` über die ganze Fläche; Speichern entprellt 0,5 s (`task(id: text)` mit `Task.sleep`) und in `onDisappear`, dort zusätzlich `deleteIfEmpty`; Menü „Anheften“/„Lösen“, „Löschen“ (mit Rückfrage); Art und Tag sind nicht bearbeitbar. Tipp auf eine Karte → `environment.tasksPath.append(.note(id))`. Zeile „Notizen“ in `TasksEntrySection`: `entrySubtitle`, rechts `store.count`.
- [ ] **Schritt 5:** Sichtprüfung im Simulator inklusive einer von Hand über `NoteStore.create(text:kind:dayKey:)` angelegten Gedanken-Notiz (Demo-Daten, Task 17): Filter erscheint, Fußzeile stimmt. `app/test-all.sh` grün.
- [ ] **Schritt 6:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: add notes list, quick capture and editor"`

---

### Task 15: Assistent – `list_shopping`, `update_shopping`

**Paket 10 · 4 h · Issue „Phase 5: Einkaufsliste im Assistenten“.**

**Files:**
- Modify: `Tagwerk/AI/AppTools.swift:13, 23–29, 50–102`, `Tagwerk/AI/AppTools+Definitions.swift`, `Tagwerk/AI/AssistantModel.swift:349–369, 411 ff.`, `Tagwerk/App/AppEnvironment.swift:120–121`, `Tagwerk/Localizable.xcstrings`
- Test: `TagwerkTests/AppToolsTests.swift`, `TagwerkTests/AssistantModelTests.swift` (ergänzen)

**Interfaces:**
- Consumes: `ShoppingModel` (`state`, `listTitle`, `sections`, `completedItems`, `add`, `checkOff`, `categoryID(of:)`), `ShoppingCategoryStore.categories()`, `ShoppingInputParser.maxNameLength`.
- Produces:
  - `AppTools.init(taskList:planning:planner:events:shopping:)` mit `shopping: ShoppingModel? = nil` (vorhandene Tests bleiben unverändert); `AppTools.readTools` enthält zusätzlich `"list_shopping"`; `static let maxListedShoppingItems = 100`, `static let maxShoppingChanges = 30`.
  - `list_shopping { include_completed: boolean }` → `{"ok":true,"list":…,"open":[{"id","name","quantity","category"}],"completed":[{"id","name"}]}`; `quantity` als `null`, wenn leer; `category` = Name oder „Sonstiges“; `completed` ist `[]` ohne `include_completed`.
  - `update_shopping { add: [{name: string, quantity: string|null}], check_off: [string] }` → `{"ok":true,"added":[…],"reopened":[…],"already_on_list":[…],"checked_off":[…],"not_found":[…]}` (Namen bzw. bei `not_found` die Kennungen).
  - Karte: Titel „Einkaufsliste ändern“, Änderung „＋ Kaffee · ＋ Reis · ＋ Zwiebeln · ✓ Eier“ (Name zu einer Kennung aus `shopping.openItems`, sonst die Kennung).

- [ ] **Schritt 1: Tests schreiben** (in `AppToolsTests`: `ShoppingModel` mit `InMemoryReminderStore`, Liste `shop` mit „Milch“ (Menge „2“), „Eier“; `uni` mit „Seminararbeit“)

```swift
@Test func listShopping_isReadTool_andListsOpenWithCategory() async {
    #expect(tools.kind(of: "list_shopping") == .read && tools.kind(of: "update_shopping") == .write)
    let result = await run(tools, "list_shopping", #"{"include_completed":false}"#)
    #expect(result["list"] as? String == "Einkauf")
    let open = result["open"] as? [[String: Any]] ?? []
    #expect(open.map { $0["name"] as? String } == ["Eier", "Milch"])
    #expect(open.last?["quantity"] as? String == "2" && open.last?["category"] as? String == "Kühlregal")
    #expect((result["completed"] as? [Any])?.isEmpty == true)
}
@Test func listShopping_includeCompleted_onlyLastSevenDays() async
@Test func listShopping_capsAtHundred() async                              // 120 open items → open.count == 100
@Test func updateShopping_addsViaRuleR4_andChecksOff() async {
    let result = await run(tools, "update_shopping", #"{"add":[{"name":"Kaffee","quantity":null},{"name":"milch","quantity":"3"}],"check_off":["<id of Eier>"]}"#)
    #expect(result["added"] as? [String] == ["Kaffee"] && result["already_on_list"] as? [String] == ["Milch"])
    #expect(result["checked_off"] as? [String] == ["Eier"])
}
@Test func updateShopping_checkOffForeignReminder_isNotFound_andStaysOpen() async {
    let result = await run(tools, "update_shopping", #"{"add":[],"check_off":["<id of Seminararbeit>","nope"]}"#)
    #expect((result["not_found"] as? [String])?.count == 2)
    #expect(store.records["<id of Seminararbeit>"]?.isCompleted == false)
}
@Test func updateShopping_moreThanThirty_isError() async                   // 31 adds → {"error": …}, nothing created
@Test func shoppingTools_withoutList_returnSetupError() async {
    #expect(result["error"] as? String == "Es ist keine Einkaufsliste eingerichtet. Einstellungen › Einkaufsliste.")
}
@Test func definitions_areStrictWithAllFieldsRequired()                    // both new tools present; strict == true; "quantity" type == ["string","null"]
@Test func listTasks_containsNoShoppingItem() async                        // task list from a provider with excludedListID → no "Milch"

// AssistantModelTests
@Test func describe_updateShopping_isOneCollectiveCard() {
    #expect(card.title == "Einkaufsliste ändern" && card.change == "＋ Kaffee · ＋ Reis · ＋ Zwiebeln · ✓ Eier")
}
@Test func instructions_mentionShoppingTools()                             // contains "list_shopping", "update_shopping", "create_task"
```

- [ ] **Schritt 2:** Beide Suiten ausführen. Erwartet: Übersetzungsfehler bzw. rot.
- [ ] **Schritt 3: Umsetzen.** Vor beiden Funktionen `await shopping.reload()`; `state != .ready` oder `shopping == nil` → Fehlertext oben. `update_shopping`: Namen kürzen (leer verwerfen, höchstens 80 Zeichen), `add` über `ShoppingModel.add`, `check_off` je Kennung über `checkOff(id:)` (Fehler → `not_found`), Teilfehler brechen nicht ab. Schemas über die vorhandenen Helfer (`object`, `string(nullable:)`, `boolean`, Felder als `["type": "array", "items": …]`), Beschreibung von `update_shopping` endet mit „Needs confirmation.“. Systemhinweis: ein Satz nach dem Termin-Absatz: Einkaufsartikel stehen nicht in `list_tasks`; lesen mit `list_shopping`, ändern mit `update_shopping`; Artikel nie über `create_task` anlegen. Die Ansage im Sprachmodus folgt ohne weitere Änderung aus `describe(_:language:)`.
- [ ] **Schritt 4:** `AppToolsTests`, `AssistantModelTests` ausführen. Erwartet: grün.
- [ ] **Schritt 5:** Commit: `git add app/Tagwerk app/TagwerkTests && git commit -m "feat: let the assistant read and change the shopping list"`

---

### Task 16: Kurzbefehle und Deeplink

**Paket 11 · 3 h · Issue „Phase 5: Kurzbefehle und Deeplink“.**

**Files:**
- Modify: `Core/AppRoute.swift:5–10`, `Tagwerk/App/AppRouter.swift:38–48`, `Tagwerk/App/RootView.swift:135–145`, `Tagwerk/App/AppEnvironment.swift`, `Tagwerk/Intents/IntentServices.swift`, `Tagwerk/Intents/TagwerkIntents.swift`, `Tagwerk/Settings/CaptureSettingsView.swift:58–61`, `Tagwerk/AppShortcuts.xcstrings`, `Tagwerk/Localizable.xcstrings`
- Test: `Packages/TagwerkCore/Tests/TagwerkCoreTests/AppRouteTests.swift`, `TagwerkTests/AppRouterTests.swift`, `TagwerkTests/IntentServicesTests.swift` (ergänzen)

**Interfaces:**
- Consumes: `ShoppingModel.add`, `ShoppingInputParser.parseAll` (Tasks 5, 8); `TasksDestination`, `tasksPath` (Task 11); `AppEnvironment.init(…reminderStore:)` (Task 4).
- Produces:
  - `AppRoute.shopping = "shopping"`
  - `AppEnvironment.openShopping()`: `tasksPath = [settings.shoppingListID == nil ? .shoppingSettings : .shopping]`, `requestedTab = 1`
  - `IntentServices.addToShopping(text: String) async -> LocalizedStringResource`
  - `struct AddToShoppingListIntent: AppIntent` (Titel „Auf die Einkaufsliste“, `supportedModes = .background`, `@Parameter(title: "Artikel", requestValueDialog: "Was soll auf die Liste?") var items: String`, keine `authenticationPolicy`); `struct OpenShoppingListIntent: AppIntent` (Titel „Einkaufsliste zeigen“, `.foreground(.immediate)`, ruft `environment.router.open(.shopping)` über `IntentServices.openShopping()`).
  - Sätze: „Auf die Einkaufsliste in \(.applicationName)“, „Zur Einkaufsliste in \(.applicationName) hinzufügen“, „Einkaufsliste in \(.applicationName) ergänzen“; „Einkaufsliste in \(.applicationName) zeigen“.

- [ ] **Schritt 1: Tests schreiben**

```swift
// AppRouteTests
@Test func route_parsesShopping_andIgnoresParameters() {
    #expect(AppRoute(url: URL(string: "tagwerk://shopping")!) == .shopping)
    #expect(AppRoute(url: URL(string: "tagwerk://shopping?add=Bier")!) == .shopping)
    #expect(AppRoute.shopping.url.absoluteString == "tagwerk://shopping")
}
// AppRouterTests
@Test func router_shoppingLink_hasNoPrefill()                              // takeRequest(setupCompleted: true)?.prefill == nil
// IntentServicesTests (environment with InMemoryReminderStore; list "shop")
@Test func addToShopping_addsParsedItems_namesOnlyWhatWasSaid() async throws {
    await environment.setShoppingList("shop")
    #expect(String(localized: await services.addToShopping(text: "Kaffee, Reis und 2 Zwiebeln")) == "3 Artikel hinzugefügt: Kaffee, Reis, Zwiebeln.")
    #expect(String(localized: await services.addToShopping(text: "Kaffee")) == "Kaffee steht schon auf der Liste.")
}
@Test func addToShopping_singleItem_usesSingular() async throws            // "1 Artikel hinzugefügt: Hefe."
@Test func addToShopping_mixedResult_namesEachGroup() async throws         // added "Hefe", already "Kaffee" → "1 Artikel hinzugefügt: Hefe. Kaffee steht schon auf der Liste."
@Test func addToShopping_withoutList_asksToChooseOne() async throws {
    #expect(String(localized: await services.addToShopping(text: "Kaffee")) == "Wähle zuerst in Tagwerk unter Einstellungen › Einkaufsliste eine Liste.")
}
@Test func addToShopping_withoutAccess_saysSo() async throws               // store.accessState = .denied → "Tagwerk hat keinen Zugriff auf Erinnerungen."
@Test func addToShopping_emptyText_addsNothing() async throws              // " , " → "Ich habe keinen Artikel verstanden.", createCount == 0
@Test func addToShopping_needsNoLoadedTaskList() async throws              // taskList never reloaded, still adds (E10)
@Test func openShopping_withList_showsPage_withoutList_showsSettings() async throws {
    environment.openShopping()
    #expect(environment.tasksPath == [.shoppingSettings] && environment.requestedTab == 1)
    await environment.setShoppingList("shop"); environment.openShopping()
    #expect(environment.tasksPath == [.shopping])
}
```

- [ ] **Schritt 2:** Die drei Suiten ausführen. Erwartet: Übersetzungsfehler.
- [ ] **Schritt 3: Umsetzen.** `AppRouter.open`: `.shopping` ohne Prefill. `RootView.openRouterTarget()`: `case .shopping: environment.openShopping()`. `addToShopping`: `await environment.shopping.reload()`, Zustände `.accessDenied`/`.noList`/`.listMissing` → Texte oben (`.listMissing` wie `.noList`), sonst `parseAll` → `add` → Antwort; „wieder geöffnet“ zählt in der Antwort als hinzugefügt; bei `failed` der Satz „Das hat nicht geklappt: %@“ mit `errorMessage`. Kein Aufruf von `taskList`, `planning`, `ai`. Fällt Spike S4 durch: `supportedModes = .foreground(.immediate)`. Zwei `AppShortcut`-Einträge in `TagwerkShortcuts`; zwei Zeilen in `CaptureSettingsView` (`phrase("Auf die Einkaufsliste in Tagwerk", "Fügt Artikel hinzu, ohne Tagwerk zu öffnen")`, `phrase("Einkaufsliste in Tagwerk zeigen", "Öffnet die Einkaufsliste")`).
- [ ] **Schritt 4:** `AppRouteTests`, `AppRouterTests`, `IntentServicesTests` und `app/test-all.sh`. Erwartet: grün (auch `AppShortcuts.xcstrings` mit englischen Sätzen).
- [ ] **Schritt 5:** Commit: `git add app && git commit -m "feat: add shopping list shortcuts and deep link"`

---

### Task 17: Abschluss – Englisch, Demo-Daten, Geräte-Checkliste

**Paket 12 · 3 h · Issue „Phase 5: Abschluss“.**

**Files:**
- Modify: `Tagwerk/Localizable.xcstrings`, `Tagwerk/AppShortcuts.xcstrings`, `Packages/TagwerkCore/Sources/TagwerkCore/Resources/Localizable.xcstrings`, `Packages/RemindersKit/Sources/RemindersKit/Resources/Localizable.xcstrings`, `Tagwerk/App/DemoData.swift`, `TagwerkTests/LocalizedTests.swift`, Spec (Nachtrag)

- [ ] **Schritt 1: Englisch prüfen.** Jede Zeile der Tabelle Spec §5.10 steht wörtlich im Katalog; Mehrzahl („1 Artikel“/„3 Artikel“, „1 item“/„3 items“, „%lld offen“, „Erledigt · %lld“) über Plural-Varianten. Test in `LocalizedTests`:

```swift
@Test func shoppingTexts_haveEnglish() {
    #expect(Localized.string("Einkaufsliste", in: .english, bundle: .main) == "Shopping List")
    #expect(Localized.string("Mit ChatGPT sortieren", in: .english, bundle: .main) == "Sort with ChatGPT")
    #expect(Localized.string("Erledigte entfernen", in: .english, bundle: .main) == "Remove Completed")
    #expect(Localized.string("Einkaufsliste ändern", in: .english, bundle: .main) == "Change shopping list")
}
```

- [ ] **Schritt 2: Demo-Daten** (`-TagwerkDemoData`, nur Simulator): `DemoData` legt drei Notizen an (eine `free` angeheftet, eine `free` diktiert, eine `evening` mit `dayKey` von gestern) und seedet die Kategorien. Einen Demo-Store für Erinnerungen gibt es nicht: Die Einkaufsliste zeigt im Simulator die echten Erinnerungen des Simulators oder, ohne Freigabe, den Zustand ohne Zugriff.
- [ ] **Schritt 3:** `app/test-all.sh`. Erwartet: `ALL TESTS PASSED`.
- [ ] **Schritt 4: Geräte-Checkliste** (echtes iPhone, echte Liste; Ergebnis je Zeile festhalten):
  1. Diktat in der Eingabezeile: „Kaffee, Reis und zwei Zwiebeln“ erzeugt drei Marken, nichts wird ohne Tippen gespeichert.
  2. Siri erkennt „Auf die Einkaufsliste in Tagwerk“ und fragt „Was soll auf die Liste?“; auch bei gesperrtem Gerät.
  3. Kaltstart über `tagwerk://shopping` (Safari) öffnet die Einkaufsseite; ohne gewählte Liste die Einstellungsseite.
  4. Abhaken in der App „Erinnerungen“ erscheint ohne Neustart in Tagwerk (Seite und Zähler der Karte).
  5. Ein Artikel mit Fälligkeit in der Einkaufsliste löst keine Tagwerk-Mitteilung aus; er steht nicht in „Planen“, nicht im Widget, nicht im Wochenrückblick.
  6. Wörterbuch an der echten Liste: Anteil der Artikel unter „Sonstiges“ notieren (nur Beobachtung, kein Abnahmekriterium).
  7. „Mit ChatGPT sortieren“: Einwilligung erscheint einmal; Ergebnisblatt; Flugmodus → Meldung „Keine Verbindung“.
  8. Hell, dunkel, größte Schriftstufe, Englisch, VoiceOver auf Einkaufsseite, Kategorien und Notizen.
- [ ] **Schritt 5:** Nachtrag „Abweichungen bei der Umsetzung“ ans Ende der Spec (A1–A6 aus diesem Plan, Spike-Folgen, Ergebnis der Checkliste).
- [ ] **Schritt 6:** Commit: `git add app docs/superpowers && git commit -m "docs: record phase 5 device checks and deviations"`

## Reihenfolge und Abhängigkeiten der Tasks

`1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 15 → 16 → 17`; `13 → 14` jederzeit nach Task 4, spätestens vor Task 17 (Task 11 zeigt bis dahin eine leere Notizen-Zeile). Erster nutzbarer Stand nach Task 11: Liste aus den Aufgaben heraus, Einkaufsseite mit Kategorien.

| Paket (Spec §11) | Tasks | h |
|---|---|---|
| 0 Spike | 1 | 2 |
| 1 Ausschluss | 3, 4 | 4 |
| 2 RemindersKit | 2 | 3 |
| 3 Kernlogik | 5, 6 | 6 |
| 4 Kategorien | 7, 10 | 6 |
| 5 `ShoppingModel` | 8 | 5 |
| 6 Einkaufsseite | 9 | 8 |
| 7 Einstieg und Einstellungen | 11 | 5 |
| 8 ChatGPT-Sortierung | 12 | 6 |
| 9 Notizen | 13, 14 | 7 |
| 10 Assistent | 15 | 4 |
| 11 Kurzbefehle und Deeplink | 16 | 3 |
| 12 Abschluss | 17 | 3 |
| **Summe** | **17 Tasks** | **62** |

## Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| `completionDate` fehlt bei Artikeln von anderen Geräten (ungeprüfte Annahme) | „Erledigt“ bleibt leer, Wiederöffnen nach R4 greift nicht | Spike S2 vor Task 2; Ersatz `lastModifiedDate` |
| Hintergrund-Intent darf nicht schreiben (ungeprüft) | Kurzbefehl meldet Erfolg ohne Wirkung oder scheitert | Spike S4; Vordergrund-Modus als Rückfall |
| Zweiter Verbraucher von `gateway.changes` | Aufgaben oder Einkaufsliste aktualisieren sich nur noch jedes zweite Mal | A2: nur `AppEnvironment` liest den Strom; im Review prüfen, dass kein `for await … in gateway.changes` hinzukommt |
| Einkaufsliste ist Apples Standardliste und einzige Liste | Neue Aufgaben ohne Listenwahl scheitern mit „Keine Erinnerungsliste gefunden“ | Von der Spec so festgelegt (R1); die Meldung nennt den Grund |
| Endungsregel (c) des Wörterbuchs | Fehltreffer wie „Sonnenmilch“ → Kühlregal | Von Hand korrigierbar, Korrektur bleibt (A4, Task 8 `setCategory`); Trefferquote ist nicht belegt und wird erst in Task 17 beobachtet |
| Überschneidung mit #136 in `TaskListView` | Merge-Konflikte | Phase 5 startet auf dem gemergten Stand; Task 11 fügt nur Pfad, Ziel und eine `Section` hinzu |
| Schemaänderung | Store öffnet nicht | Nur neue Modelle und Felder mit Standardwert; `ModelStoreLocationTests` in Tasks 4, 7, 13 |
| Schätzung 62 h | Erfahrungswert, keine Messung | Je Paket gegen die Spec gespiegelt; Abweichungen im Nachtrag festhalten |

## Selbstprüfung (durchgeführt)

- **Spec-Abdeckung:** §5.1 → Tasks 2, 4, 5, 7, 8, 13 · R1 → 3, 4 · R2/R3 → 5 · R4/R5 → 8 · R6–R8, R10, R12 → 6, 7 · R9 → 7, 10 · R11 → 3, 11 · §5.3 → 11 · §5.4 → 9 · §5.5 → 10, 12 · §5.6 → 13, 14 · §5.7 → 11, 16 · §5.8 → 15 · §5.9 → 16 · §5.10 → jeweils, Abschluss 17 · §8 Tests → je Task · §10 Spikes und Checkliste → 1, 17.
- **Nicht durch Tests gedeckt, nur durch Sichtprüfung:** Layout und Gesten der drei Seiten (Tasks 9, 10, 14), Siri-Erkennung, Verhalten geteilter Listen. Das ist ein Prüfstand, kein Nachweis.
- **Typkonsistenz:** `AddReport`-Felder (`added`, `reopened`, `alreadyOnList`, `failed`, `errorMessage`) in Tasks 8, 9, 15, 16 gleich; `ShoppingAssignmentInfo(categoryID:isManual:)` in Tasks 6, 7, 8, 12 gleich; `TasksDestination`-Fälle in Tasks 9, 11, 14, 16 gleich; `InMemoryReminderStore` aus Task 4 in Tasks 8, 15, 16.
