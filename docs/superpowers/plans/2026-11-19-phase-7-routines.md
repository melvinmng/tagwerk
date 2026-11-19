# Phase 7: Routinen und Gewohnheiten – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026 zum freigegebenen Design. Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Die Stundenwerte sind die Schätzungen aus dem Design §16, nicht gemessen.

**Goal:** Tagwerk bildet die täglichen Routinen ab: Gewohnheiten abhaken (mit automatischer Erfüllung), Tagesstart mit Fokus, Tagesabschluss mit Abend-Checkliste und Erinnerungen, Gedanken-Notiz mit Vorschlägen als Aktionskarten, Wochenreflexion und Leitfragen-Vorlage.

**Architecture:** Reine Regeln liegen in `TagwerkCore` (`HabitRules`, `RoutineSchedule`, `NoteTemplate`) und sind ohne App testbar. Die App bekommt einen Ordner `app/Tagwerk/Routines/` mit SwiftData-Typen, zwei Stores (`HabitStore`, `RoutineStore`), zwei Modellen (`HabitsModel`, `RoutinesModel`) und den Blättern. Vorhandenes wird erweitert, nicht ersetzt: „Erfassen“, Planen-Kopf, Kapazitätskarte, Wochenrückblick, Snapshot/Widget, Kurzbefehle, `AppRouter`, `ActionCardView`, `AppTools.run`. Die Vorschläge aus der Notiz laufen über ein eigenes `NoteSuggestionModel` mit genau einem Aufruf je Tipp, ohne `Conversation` und ohne `ChatStore`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, EventKit, HealthKit, UserNotifications, App Intents, WidgetKit, Swift Testing; XcodeGen (`app/project.yml`, Quellordner werden als Ganzes eingelesen).

**Spec:** `docs/superpowers/specs/2026-11-19-phase-7-routines-design.md` (freigegeben 19.11.2026; §9.2: KI-Kontext sind die offenen Aufgaben und Termine der **nächsten 7 Tage**).

**Mockup:** `docs/superpowers/mockups/2026-11-19-phase-7-routines-mockups.html` (gültig: GO1, GA1, GF1, GH1, GH3, GR2, GS1, GS·E, GS·B, GN1, GZ1, GK1, GW1, GB1, GL2).

**Epic:** GitHub #140 mit #141 bis #146. Jede Aufgabe nennt ihr Issue und die Zeile aus dem Aufgabenschnitt (Design §16).

**Reihenfolge der Vorhaben (verbindlich):** (1) #136 Issue-Zuweisung → (2) Phase 5 Einkaufsliste und Notizen (#113) → (3) Suche → (4) Phase 7. Die Tasks 13 und 14 setzen Phase 5 als gebaut voraus (`NoteRecord`, `NoteStore`, Notizen-Liste). Task 4 nutzt daraus nur den reinen Helfer `NoteDayKey`; alle übrigen Tasks hängen nicht an Phase 5.

## Global Constraints

- Kein neuer Tab. Die Tab-Leiste bleibt Planen, Aufgaben, Erfassen, Einstellungen. Die Einstellungs-Hauptliste bekommt genau eine Zeile „Routinen“.
- „Planen“ bekommt über dem Ablauf genau **ein** neues Element (Routine-Karte). Der Tagesabschluss ist eine Zeile in der vorhandenen Kapazitätskarte.
- Ein SwiftData-Store, lokal, nicht im Group-Container (`ModelContainerFactory.swift:5–22`). Kein Store-Umzug. Jedes neue Attribut hat einen Standardwert oder ist optional. Neue Typen kommen in `ModelContainerFactory.schema`; `ModelStoreLocationTests` bleibt grün.
- Jedes Textfeld ist optional, nichts blockiert einen Schritt. Kein Blatt öffnet sich von selbst.
- Kein KI-Aufruf ohne Tippen. Notiztext verlässt das iPhone nur mit `noteSuggestionConsent == true` **und** Tippen auf „Vorschläge holen“. Dankbarkeit, Gewohnheiten, Wochenreflexion und Health-Werte gehen nie an ChatGPT, nie in Sperrbildschirm-Widgets, nie in Siri-Antworten. Notiztext steht in keinem Verlauf und in keinem Log.
- Der Assistent bekommt keine Routine-Funktionen. Gewohnheiten und Checklistenpunkte sind keine Aufgabenquelle; Aufgaben aus einer Notiz entstehen nur in den vorhandenen Quellen.
- Benachrichtigungen: Budget des `NotificationScheduler` bleibt 50; Routinen belegen fest höchstens 5 (4 Abend, 1 Morgen) außerhalb davon. Normale lokale Mitteilungen, keine Time-Sensitive Notifications, keine Aktionen in Mitteilungen.
- Grenzen aus dem Design: Name 40 Zeichen; höchstens 10 nicht pausierte Gewohnheiten; je automatischer Quelle höchstens eine Gewohnheit; Rückblick-Fenster 90 Tage („90+“ Tage, „12+“ Wochen); höchstens 3 Fokus-Marken je Tag; höchstens 8 Checklistenpunkte, davon 4 mit Erinnerung; Abstand 0–240 min in 5er-Schritten; Abendgrenze 04:00; Tagesstart-Karte 04:00–12:00; höchstens 5 Vorschlagskarten; KI-Kontext höchstens 60 Aufgaben und 100 Termine.
- Deeplinks `tagwerk://routine/start` und `tagwerk://routine/evening`; Links navigieren nur und schreiben nichts.
- Deutsch ist Quellsprache; jeder neue Text steht deutsch und englisch in den String Catalogs (Leitbegriffe: Design §12). Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch.
- Commits: Conventional Commits auf Englisch (`feat: …`, `fix: …`, `docs: …`, `test: …`), ohne Hinweis auf KI, ohne `Co-Authored-By`.

## Review Focus

1. **Mitternacht und 04:00-Grenze:** Das Blatt „Tagesabschluss“ wird um 23:50 geöffnet und um 00:10 mit „Fertig“ geschlossen. Erwartet: Abschluss, Häkchen und Notiz landen auf dem Tag, für den das Blatt geöffnet wurde. Test in Task 9 (`finishEvening_afterMidnight_writesTheDayTheSheetWasOpenedFor`).
2. **Health nicht lesbar** (iPhone gesperrt, Siri im Hintergrund, Zugriff entzogen): Erwartet: Der Zähler fällt nicht von „3 von 5“ auf „1 von 5“; die zuletzt gelesenen Werte desselben Tages bleiben, sonst bleibt die Gewohnheit offen und von Hand abhakbar. Test in Task 5 (`failedHealthRead_keepsLastFactsOfTheSameDay`).
3. **Fokus-Aufgabe verschwindet** (in Erinnerungen erledigt, gelöscht, Quelle lädt noch): Erwartet: Während die Quelle lädt, bleibt die Zeile offen; danach gilt sie als erledigt und bleibt mit ihrem gemerkten Titel durchgestrichen sichtbar. Test in Task 12 (`vanishedTask_isDoneOnlyAfterItsSourceSettled`).
4. **Notiz wird schnell geschlossen oder geleert:** Tippen und sofort wischen; nur Leerzeichen; Diktat mitten im Text. Erwartet: Der letzte Stand ist gespeichert, nur Leerraum löscht den Datensatz, diktierter Text steht an der Schreibmarke. Tests in Task 13 (`close_flushesThePendingSave`, `whitespaceOnly_deletesTheNote`, `dictation_insertsAtTheCursor`).
5. **Antwort von ChatGPT kommt nach dem Schließen des Blatts oder nach einer Textänderung:** Erwartet: Sie wird verworfen, es entstehen keine Karten zu einem Blatt, das nicht mehr offen ist. Test in Task 14 (`lateAnswerAfterReset_isDiscarded`).

---

## Ausgangslage (Befund)

Alle Stellen der Tabelle in Design §3 wurden am 19.11.2026 im Worktree nachgelesen und stimmen. Zusätzlich für die Umsetzung wichtig:

| Stelle | Ist |
|---|---|
| `app/Tagwerk/Tasks/TaskListModel.swift:75, 213–220` | `items` enthält nur **offene** Aufgaben; `complete(_:)` entfernt die Aufgabe und ruft `onCompletionChanged(id, true)`. Erledigte Aufgaben sind danach nicht mehr abfragbar. |
| `app/Tagwerk/App/AppEnvironment.swift:337–346` | Erledigungen je Zeitraum gibt es nur für Erinnerungen (`gateway.completionDates(in:listIDs:)`) und lokale Aufgaben (`LocalTaskProvider.completionDates(in:)`), nicht für GitHub. |
| `app/Tagwerk/Capture/IntakeStore.swift:45, 52` | Getränke nur je Tag (`drinks(on:calendar:)`), Trainings je Zeitraum (`workouts(in:)`). |
| `app/Tagwerk/Capture/CaptureModel.swift:135–178, 207–217` | `reload()` liest Health für die gezeigte Woche; `onTodayChanged` ist **eine** Closure, die `AppEnvironment.startSnapshotUpdates()` setzt. |
| `app/Tagwerk/Capture/CaptureModel.swift:221–226` | `planHeaderLine` ist `nil`, solange heute nichts erfasst ist oder `showsIntakeInPlan` aus ist. |
| `app/Tagwerk/Planning/PlanHeader.swift:113–132` | `PlanIntakeLine` zeigt nur mit `planHeaderLine != nil`. |
| `app/Tagwerk/Planning/DayView.swift:67–71, 206–221` | `summary(_:)` baut die Elemente über dem Ablauf; `CapacityCard` zeigt die Abendzeile nur mit `model.eveningEntry`. |
| `app/Tagwerk/Planning/PlanningModel.swift:128, 136, 138, 300, 1213` | `recurringReminderIDs`, `planStore`, `blocks`, `planInputs(in:)` und `nextPlanDay` sind von außen lesbar. |
| `app/Tagwerk/App/AppRouter.swift:38–48`, `RootView.swift:135–145` | Beide `switch` über `AppRoute` sind erschöpfend; neue Routen brauchen dort je einen Fall. |
| `app/Tagwerk/Notifications/NotificationNavigator.swift:53–75`, `AppEnvironment.swift:42` | Der `NotificationDelegate` kennt nur den `NotificationNavigator`. |
| `app/Tagwerk/Notifications/NotificationCenterClient.swift:73–82` | `PendingNotification.fireDate` kommt aus `nextTriggerDate()`; das gilt auch für wiederholende Auslöser. |
| `app/Tagwerk/Voice/VoiceInputModel.swift:14–19`, `TagwerkCore/Voice/DictationMachine.swift:63, 81, 242–244` | Die Spracheingabe hängt über `readDraft`/`writeDraft`/`onSend` am Feld; der erkannte Text wird an `draftBefore` **angehängt**. |
| `app/Tagwerk/AI/AssistantModel.swift:397–488` | `describe(_:language:)` braucht nur `planning`; `ActionCardView` (`ChatView.swift:267`) nimmt `AssistantModel.ActionCard` und `ChatMessage.ActionStatus`. |
| `app/Tagwerk/AI/AppTools.swift:106–148, 173` | `listTasks`/`listEvents` liefern die Felder, die §9.2 nennt; `update_event` prüft nur „bearbeitbar“, nicht „Zeitblock“. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/WidgetSnapshot.swift:53–72, 134–141` | `SnapshotDay` und `replacingIntake(_:on:createdAt:)`. |
| `app/TagwerkTests/Fakes/FakeTaskProvider.swift:116–127` | `testCalendar()` (Europe/Berlin, Montag) und `testNow()` = Mittwoch, 18.11.2026 10:00. Alle Beispielwerte unten rechnen mit diesem Tag. |

## Abweichungen vom Spec

| Nr. | Spec | Befund im Code | Auflösung in diesem Plan |
|---|---|---|---|
| A1 | Regel 14: „Aufgaben erledigt e von n“, n einschließlich erledigter Aufgaben von heute | Erledigte Aufgaben fehlen in `TaskListModel.items` | e = Erledigungen des Tages aus Erinnerungen und lokalen Aufgaben (dieselben Leser wie der Wochenrückblick), n = e + offene Aufgaben von heute nach Regel 12. GitHub-Issues zählen nur als offen mit; die Zeile trägt den Fußtext „Erledigt: Erinnerungen und lokale Aufgaben, ohne GitHub“. Bekannte Ungenauigkeit, kein neuer Datentyp. |
| A2 | `FocusMarkRecord` ohne Titel; erledigte Zeilen bleiben durchgestrichen sichtbar | Titel einer erledigten Aufgabe ist nicht mehr lesbar | `FocusMarkRecord` bekommt `title: String = ""` (Stand beim Markieren, bei jedem Laden nachgezogen). Feld mit Standardwert, keine Migration. |
| A3 | §6: Health je Lauf höchstens drei Abfragen über 90 Tage | Getränke gibt es nur je Tag | `IntakeStore.drinks(in: DateInterval)` wird ergänzt (eine Abfrage statt 90). |
| A4 | §7.3: Zähler hängt an der Zeile unter dem Datum; Festlegung 12: er steht auch allein | `planHeaderLine` ist ohne Einträge `nil` | Die Zeile wird in `PlanIntakeLine` aus Ernährungstext und Zähler zusammengesetzt (`PlanHeaderText.statusLine`). `CaptureModel.planHeaderLine` bleibt unverändert. |
| A5 | §7.6: erkannter Text „an der Schreibmarke“ | `DictationMachine` hängt an | Das Notizfeld übergibt als Entwurf nur den Text **vor** der Schreibmarke und setzt den Text dahinter beim Schreiben wieder an. Keine Änderung an `DictationMachine`. |
| A6 | §8.3: Delegate reicht `route` an den `AppRouter` | Delegate kennt nur den Navigator | `NotificationDelegate` bekommt zusätzlich den Router. |
| A7 | §9.3: `update_event` gilt nur für Tagwerk-Zeitblöcke | Kein Kennzeichen am Termin | Zeitblock = Termin im Plan-Kalender (`settings.planCalendarID`) mit verknüpfter Aufgabe (`planning.linkedTask(eventID:)`). Nur diese Kennungen sind für `update_event` zulässig. |
| A8 | §10: „`replacingIntake` ersetzt künftig Tageswerte und Zähler“ | Funktion trägt nur `intake` | Umbenannt in `replacingToday(intake:habits:on:createdAt:)`; der einzige Aufrufer (`AppEnvironment.writeSnapshot`) zieht mit. |
| A9 | §5.4: „Geschrieben wird nur über `NoteStore`“; Methodennamen stehen nicht im Phase-5-Design | Der Phase-5-Plan (`2026-11-19-phase-5-shopping-notes.md`, Task 13) legt sie fest: `note(kind:dayKey:)`, `create(text:kind:dayKey:wasDictated:)`, `updateText(_:text:)`, `markProcessed(_:at:)`, `delete(_:)` | Phase 7 nutzt diese Namen und ergänzt in einer `extension NoteStore` nur `saveThought` und `addDerivedAction` (Task 13). |
| A10 | §16: Reihenfolge 1, 2, 3 in #141; Tageslicht-Spike „sinnvollerweise nach Aufgabe 3“ | – | Auftrag: Spikes zuerst. Der Tageslicht-Spike braucht nur eine Debug-Ansicht und läuft deshalb vorab. Innerhalb von #141 kommt das Modell (Zeile 3) vor der Oberfläche (Zeile 2), weil die Oberfläche es anzeigt. |

## Schnittstellen zu den anderen Plänen

**Consumes (Phase 5, Namen aus `2026-11-19-phase-5-shopping-notes-design.md` §„Daten“ und §5.6):**
- `NoteRecord` mit `id: UUID`, `text: String`, `createdAt: Date`, `updatedAt: Date`, `kindRaw: String` (`"free"`, `"morning"`, `"evening"`), `dayKey: String?` („YYYY-MM-DD“), `isPinned: Bool`, `wasDictated: Bool`, `processedAt: Date?`.
- `NoteStore` (`environment.notes`) als einzige schreibende Stelle; aus dem Phase-5-Plan (Task 13): `note(id:)`, `note(kind:dayKey:)`, `create(text:kind:dayKey:wasDictated:)` (legt je Art und Tag höchstens eine Gedanken-Notiz an und aktualisiert sie sonst), `updateText(_:text:)`, `markProcessed(_:at:)`, `delete(_:)`.
- `NoteKind` (`.free`, `.morning`, `.evening`), `NoteDayKey.string(_:)`/`NoteDayKey.day(_:)`, `NoteText.title(_:)` aus `TagwerkCore/NoteText.swift`.
- Notizen-Liste `NotesListView` (`app/Tagwerk/Notes/NotesListView.swift`) mit `NotesListView.footer(for:now:calendar:)`, Filter „Alle · Gedanken · Eigene“, `NoteEditorView` und Fußnote.
- `VoiceInputFactory.make(_:)`, `VoiceMicrophoneButton`, `VoiceRecordingBar` (`app/Tagwerk/Voice/VoiceComposer.swift`, schon vorhanden).
- `shoppingListID: String?` in `AppSettings` nur mittelbar: Fokus-Auswahl, Tagesrückblick und KI-Kontext lesen über `TaskListModel`/`PlanningModel` und erben den Ausschluss der Einkaufsliste.

**Consumes (Issue-Zuweisung #136):** die dann gültige Definition von `create_task` in `AppTools.allDefinitions`; Task 14 filtert nur nach Namen und übernimmt neue Parameter ohne Änderung.

**Produces:**
- `NoteRecord.derivedActionCount: Int = 0` (neues Feld mit Standardwert) und die Fußzeilen-Ergänzung „· n Aufgaben daraus“.
- Geänderte Fußnote der Notizen-Liste (Design §7.8).
- `AppRoute.routineStart` (`"routine/start"`), `AppRoute.routineEvening` (`"routine/evening"`).
- `SnapshotDay.habits: SnapshotHabits?`.
- Für die Suche: nichts. Gedanken-Notizen sind gewöhnliche `NoteRecord`; Gewohnheiten, Dankbarkeit, Checkliste und Wochenreflexion sind kein Suchziel.

## Betroffene Dateien

| Datei | Verantwortung |
|---|---|
| `app/Packages/TagwerkCore/Sources/TagwerkCore/HabitRules.swift` (neu) | `Habit`, `HabitSource`, `HabitPause`, `HabitFacts`, `HabitStreak`, `HabitCounter`, `HabitRules`, `PlanDay.dayKey` (ruft `NoteDayKey` aus Phase 5 auf) |
| `…/TagwerkCore/RoutineSchedule.swift` (neu) | `ChecklistItem`, `RoutineDayValue`, `RoutineNotification`, `RoutineSchedule` (Zeitanker, Abendgrenze, Sichtbarkeit, Mitteilungen), `FocusRules` |
| `…/TagwerkCore/NoteTemplate.swift` (neu) | Leitfragen-Vorlage |
| `…/TagwerkCore/AppRoute.swift`, `WidgetSnapshot.swift`, `NotificationPlan.swift`, `WeekReview.swift` | Routen, `SnapshotHabits`, Präfix `tagwerk.routine.`, Wochenwerte der Gewohnheiten |
| `app/Tagwerk/Routines/HabitRecords.swift` (neu) | `HabitRecord`, `HabitCheckRecord`, `HabitStore` |
| `app/Tagwerk/Routines/HabitsModel.swift` (neu) | Fakten laden, Zeilen und Zähler berechnen |
| `app/Tagwerk/Routines/HabitsSection.swift`, `HabitListView.swift`, `HabitSheet.swift`, `HabitText.swift` (neu) | Abschnitt in „Erfassen“, Liste „Bearbeiten“, Blatt „Gewohnheit“, Texte |
| `app/Tagwerk/Routines/RoutineRecords.swift` (neu) | `RoutineDayRecord`, `EveningChecklistItemRecord`, `FocusMarkRecord`, `WeekReflectionRecord`, `RoutineStore` |
| `app/Tagwerk/Routines/RoutinesModel.swift` (neu) | Blatt-Ziel, Karte und Abendzeile, Fokus, Tagesrückblick |
| `app/Tagwerk/Routines/EveningSheet.swift`, `MorningSheet.swift`, `RoutineCard.swift`, `RoutineSettingsView.swift` (neu) | Blätter, Karte in „Planen“, Einstellungen › Routinen |
| `app/Tagwerk/Routines/RoutineNotificationScheduler.swift` (neu) | wiederholende Anfragen entfernen und neu anlegen |
| `app/Tagwerk/Routines/NoteField.swift`, `NoteStore+Routines.swift`, `NoteConsentSheet.swift`, `NoteSuggestionModel.swift`, `NoteSuggestionContext.swift` (neu) | Notizfeld, Zugriff, Zustimmung, Aufruf, Kontext und Prüfung |
| `app/Tagwerk/Routines/WeekReflectionSections.swift` (neu) | drei Abschnitte im Wochenrückblick |
| `app/Tagwerk/AI/ActionCardDescriber.swift` (neu) | herausgelöste Kartentexte; `AssistantModel.describe` ruft sie auf |
| `app/Tagwerk/Persistence/AppSettings.swift`, `ModelContainerFactory.swift` | sechs Felder, sieben neue Typen im Schema |
| `app/Tagwerk/App/AppEnvironment.swift`, `AppRouter.swift`, `RootView.swift`, `TagwerkApp.swift` | Verdrahtung, Routen, Blatt an `RootView`, Neu-Einplanen beim Start |
| `app/Tagwerk/Capture/CaptureView.swift`, `IntakeStore.swift`, `WeekReviewModel.swift`, `WeekReviewView.swift` | Abschnitte, `drinks(in:)`, Wochenreflexion |
| `app/Tagwerk/Planning/PlanHeader.swift`, `DayView.swift`, `TimelineCanvas.swift`, `app/Tagwerk/Tasks/TaskContextMenu.swift`, `NewTaskSheet.swift` | Zähler, Karte, Abendzeile, Stern, Menü, Vorbelegung |
| `app/Tagwerk/Notifications/NotificationCenterClient.swift`, `NotificationScheduler.swift`, `NotificationNavigator.swift` | `addRepeating`, Ausschluss, Sprung über den Router |
| `app/Tagwerk/Intents/TagwerkIntents.swift`, `IntentServices.swift`, `app/Tagwerk/Settings/SettingsView.swift`, `CaptureSettingsView.swift` | `CheckHabitIntent`, Zeile „Routinen“, neue Phrase |
| `app/TagwerkWidget/WidgetViews.swift` | Zähler im Widget „Heute“ |
| `app/Tagwerk/Localizable.xcstrings`, `AppShortcuts.xcstrings`, `InfoPlist.xcstrings`, `app/TagwerkWidget/Localizable.xcstrings`, `TagwerkCore/Resources/Localizable.xcstrings` | deutsch und englisch |
| Tests | `TagwerkCoreTests`: `HabitRulesTests`, `RoutineScheduleTests`, `FocusRulesTests`, `NoteTemplateTests`, Ergänzungen in `AppRouteTests`, `WidgetSnapshotTests`. `TagwerkTests`: `HabitStoreTests`, `HabitsModelTests`, `HabitTextTests`, `RoutineStoreTests`, `RoutinesModelTests`, `RoutineNotificationTests`, `NoteFieldModelTests`, `NoteSuggestionModelTests`, `WeekReflectionTests`, Ergänzungen in `NotificationSchedulerTests`, `IntentServicesTests`, `AppRouterTests`, `PlanHeaderTextTests`, `ModelStoreLocationTests`, `AssistantModelTests`; Fakes `FakeNotificationCenter`, `FakeHealthStore` |

## Befehle

```bash
# CORE <Suite>: ein Test-Suite in TagwerkCore
cd app/Packages/TagwerkCore && xcodebuild test -testLanguage de -testRegion DE -scheme TagwerkCore \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkCoreTests/<Suite>

# APP <Suite>: ein Test-Suite der App
cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>

# ALL: alle Stufen einschließlich String-Catalog-Prüfung
app/test-all.sh        # erwartet: "ALL TESTS PASSED"
```

Heißt das Paket-Schema `TagwerkCore-Package`, gilt die Auflösung aus `app/test-all.sh`. „Rot“ heißt im Folgenden: Der Lauf scheitert am fehlenden Typ oder an der Erwartung. „Grün“: Der Lauf meldet die Tests als bestanden.

## Aufgabenübersicht

| Task | Inhalt | Issue | Design §16 Zeile | h |
|---|---|---|---|---|
| 1 | Spike Tageslicht | #141 | 14 | 2 |
| 2 | Spike antippbares Widget | #141 | 14 | 3 |
| 3 | Spike Aktionen in Mitteilungen | #142 | 14 | 2 |
| 4 | Datentypen und `HabitRules` | #141 | 1 | 5 |
| 5 | `HabitsModel`, automatische Erfüllung, Zähler in „Planen“ | #141 | 3 | 3 |
| 6 | Abschnitt „Gewohnheiten“, Liste, Blatt | #141 | 2 | 5 |
| 7 | Kurzbefehl, Snapshot, Widget | #141 | 4 | 4 |
| 8 | Tageseintrag, Checkliste, `RoutineSchedule`, Einstellungen › Routinen | #142 | 5 | 4 |
| 9 | Blatt „Tagesabschluss“, Abendzeile, Zeilen in „Erfassen“, Routen | #142 | 6 | 4 |
| 10 | Wiederholende Mitteilungen | #142 | 7 | 3 |
| 11 | Blatt „Tagesstart“, Erinnerung am Morgen | #145 | 8 | 4 |
| 12 | Fokus, Routine-Karte, Stern, Kontextmenü | #145 | 9 | 4 |
| 13 | Notizfeld, Spracheingabe, „Als Aufgabe anlegen“ | #143 | 10 | 5 |
| 14 | Zustimmung, `NoteSuggestionModel`, Karten | #143 | 11 | 8 |
| 15 | Wochenreflexion | #144 | 12 | 5 |
| 16 | Leitfragen-Vorlage | #146 | 13 | 2 |
| 17 | Optional: Quelle „Zeit bei Tageslicht“ | #141 | 15 | 3 |
| 18 | Geräte-Checkliste und Abschluss | #140 | §15.2 | – |

Summe 63 h, mit Task 17 66 h (wie Design §16).

---

## Tasks

### Task 1: Spike Tageslicht am Gerät (manuell) · #141 · Zeile 14

**Files:** Modify (nur Debug, wird nicht eingecheckt oder nach dem Spike entfernt): `app/Tagwerk/Settings/CalendarDiagnosticsView.swift` oder eine eigene Debug-Ansicht.

- [ ] **Step 1:** In einem Debug-Build `HKQuantityType(.timeInDaylight)` über eine **eigene** Lesefreigabe anfragen (nicht in `HealthKitStore.coreReadTypes`) und die Tagessummen der letzten 14 Tage per `HKStatisticsCollectionQuery` ausgeben.
- [ ] **Step 2:** Am iPhone des Nutzers mit Watch prüfen und im Issue #141 festhalten: (a) Gibt es Tageswerte für Tage mit Watch? (b) Was liefert ein Tag ohne Watch (kein Eintrag oder 0)? (c) Wie viele Minuten nach dem Aufenthalt draußen steht der Wert in Health? (d) Bleibt `access()` nach der Anfrage unverändert „verbunden“, und meldet `statusForAuthorizationRequest` für den Typ danach „unnecessary“?
- [ ] **Step 3:** Entscheidung festhalten.

**Bestanden**, wenn (a) ja, (b) „kein Eintrag“ von 0 unterscheidbar ist oder 0 als „kein Wert“ behandelt werden kann, und (d) ja. Dann wird Task 17 gebaut. **Nicht bestanden:** Task 17 entfällt; die Quelle `daylight` bleibt im Datentyp, erscheint aber nie in der Auswahl; „Draußen bei Tageslicht“ ist eine Gewohnheit von Hand. Kein Commit.

### Task 2: Spike antippbares Widget (manuell) · #141 · Zeile 14

- [ ] **Step 1:** Auf einem Wegwerf-Branch einen `Button(intent:)` mit einem Intent, der einen Zeitstempel in den App-Store schreibt, in das Widget „Heute“ setzen.
- [ ] **Step 2:** Am Gerät bei beendeter App tippen und prüfen: Läuft `perform()` im App-Prozess (Zugriff auf `AppDependencyManager`, Store außerhalb des Group-Containers)? Aktualisiert sich das Widget danach?
- [ ] **Step 3:** Ergebnis im Issue #141 festhalten; Branch verwerfen.

**Bestanden:** Folgeaufgabe „GB2 antippbares Widget“ wird als eigenes Issue vorgeschlagen. **Nicht bestanden:** GB2 bleibt verworfen. In beiden Fällen ändert sich an diesem Plan nichts (GB2 ist Nicht-Ziel). Kein Commit.

### Task 3: Spike Aktionen in Mitteilungen (manuell) · #142 · Zeile 14

- [ ] **Step 1:** Auf einem Wegwerf-Branch eine `UNNotificationCategory` mit den Aktionen „Abgehakt“ und „In 10 min“ an eine Test-Mitteilung hängen.
- [ ] **Step 2:** Am Gerät bei beendeter App prüfen: Wird die App für die Aktion im Hintergrund gestartet? Erreicht die Antwort den Delegate vor Ablauf der Zeit? Lässt sich aus der Aktion eine neue Anfrage anlegen?
- [ ] **Step 3:** Ergebnis im Issue #142 festhalten; Branch verwerfen.

**Bestanden:** Folgeaufgabe „GS3“ wird vorgeschlagen, frühestens wenn GS1 im Alltag läuft. **Nicht bestanden:** GS3 bleibt verworfen. Keine Änderung an diesem Plan. Kein Commit.

### Task 4: Datentypen und `HabitRules` · #141 · Zeile 1

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/HabitRules.swift`, `app/Tagwerk/Routines/HabitRecords.swift`
- Modify: `app/Tagwerk/Persistence/ModelContainerFactory.swift:5–11`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/HabitRulesTests.swift`, `app/TagwerkTests/HabitStoreTests.swift`, `app/TagwerkTests/ModelStoreLocationTests.swift`

**Interfaces:**
- Consumes: `PlanDay`, `IntakeRules.weekStart(containing:calendar:)`; aus Phase 5 `NoteDayKey.string(_:)` und `NoteDayKey.day(_:)` (`TagwerkCore/NoteText.swift`).
- Produces (TagwerkCore):

```swift
public extension PlanDay {
    var dayKey: String { get }            // "YYYY-MM-DD"; forwards to NoteDayKey.string(_:) of phase 5
    init?(dayKey: String)                 // forwards to NoteDayKey.day(_:)
}
public enum HabitSource: String, Sendable, Codable, CaseIterable { case manual, water, workout, steps, daylight }
public struct HabitPause: Sendable, Hashable, Codable { public var from: PlanDay; public var to: PlanDay }   // inclusive
public struct Habit: Sendable, Hashable, Identifiable {
    public var id: UUID; public var name: String; public var symbol: String; public var order: Int
    public var source: HabitSource; public var daysPerWeek: Int; public var daylightMinutes: Int
    public var start: PlanDay; public var pausedSince: PlanDay?; public var pauses: [HabitPause]
}
public struct HabitFacts: Sendable, Equatable {
    public var manualChecks: [UUID: Set<PlanDay>]
    public var waterMilliliters: [PlanDay: Int]
    public var workoutDays: Set<PlanDay>          // days with a workout of at least IntakeRules.minimumWorkoutMinutes
    public var steps: [PlanDay: Int]
    public var daylightMinutes: [PlanDay: Int]
    public var goalWaterMilliliters: Int
    public var goalSteps: Int
    public static let empty: HabitFacts
}
public enum HabitStreak: Sendable, Hashable { case days(Int, isCapped: Bool), weeks(Int, isCapped: Bool) }
public struct HabitCounter: Sendable, Hashable, Codable { public var done: Int; public var total: Int }
public enum HabitRules {
    public static let windowDays = 90
    public static let maximumActive = 10
    public static let nameLimit = 40
    public static func window(today: PlanDay, calendar: Calendar) -> ClosedRange<PlanDay>          // today − 89 ... today
    public static func isActive(_ habit: Habit, on day: PlanDay, today: PlanDay) -> Bool            // rule 1
    public static func isSourceFulfilled(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Bool
    public static func isFulfilled(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Bool      // rule 2
    public static func progress(_ habit: Habit, lastDays: Int, today: PlanDay, facts: HabitFacts, calendar: Calendar)
        -> (done: Int, counting: Int)                                                               // rule 3
    public static func rate(_ habit: Habit, lastDays: Int, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> Int?  // rule 4, percent
    public static func weekGoal(daysPerWeek: Int, countingDays: Int) -> Int                         // rule 6
    public static func weekProgress(_ habit: Habit, weekContaining day: PlanDay, today: PlanDay, facts: HabitFacts,
                                    calendar: Calendar) -> (done: Int, goal: Int, counting: Int)
    public static func streak(_ habit: Habit, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> HabitStreak  // rules 5–7
    public static func counter(_ habits: [Habit], today: PlanDay, facts: HabitFacts, calendar: Calendar) -> HabitCounter?  // rule 8
}
```

- Produces (App):

```swift
@Model final class HabitRecord        // fields exactly as design §5.1
@Model final class HabitCheckRecord   // habitID, year, month, day, checkedAt
@MainActor final class HabitStore {
    init(context: ModelContext)
    func habits() -> [Habit]                                   // by order
    func save(_ habit: Habit)                                  // insert or update by id; name cut to 40 characters
    func delete(_ id: UUID)                                    // removes the habit and its checks
    func reorder(_ ids: [UUID])
    func setPaused(_ id: UUID, _ paused: Bool, today: PlanDay) // resume appends {pausedSince ... yesterday} when not empty
    func checks(in range: ClosedRange<PlanDay>) -> [UUID: Set<PlanDay>]
    @discardableResult func setCheck(_ id: UUID, on day: PlanDay, checked: Bool, at date: Date) -> Bool   // false when nothing changed
}
```

- [ ] **Step 1: Tests schreiben (rot).** `HabitRulesTests`, heute = 18.11.2026 (Mittwoch), Kalender `makeCalendar()`:

```swift
@Test func active_respectsStartPausesAndFuture()
// start 10.11., pauses [12.11....13.11.]: 9.11. false, 10.11. true, 12.11. false, 14.11. true, 19.11. false
// pausedSince 17.11.: 16.11. true, 17.11. false, 18.11. false
@Test func fulfilled_byManualCheckOrSource()
// water, goal 2000: 2100 ml true, 1900 ml false, goal 0 false, manual check true
// workout: day in workoutDays true; steps 8000 of 8000 true; daylight without value false, 25 of 20 min true
@Test func progress_todayCountsOnlyOnceFulfilled()
// daily, start 1.11., checks 12,13,15,16,17: progress(lastDays: 7) == (5, 6); with a check on 18.11. == (6, 7)
@Test func rate_usesTargetDays()
// daysPerWeek 3, start 21.10., 9 fulfilled days, today open: 28 counting days, target 12, rate(lastDays: 30) == 75
@Test func rate_capsAtHundred()                    // same habit, 15 fulfilled days -> 100
@Test func rate_withoutCountingDays_isNil()        // start today, today open -> nil
@Test func dailyStreak_runsToYesterdayAndIncludesFulfilledToday()
// checks 15,16,17 -> .days(3, isCapped: false); plus 18 -> .days(4, ...); no check on 14 breaks it
@Test func dailyStreak_skipsPausedDays()           // checks 13,15,16,17, pause [14...14] -> .days(4, isCapped: false)
@Test func weekGoal_isProratedAndAtLeastOne()
// (3,7)==3, (3,4)==2, (3,1)==1, (5,2)==1, (2,1)==1
@Test func weeklyStreak_countsWeeksThatReachedTheGoal()
// daysPerWeek 3, start 26.10., checks 26,28,30.10. / 2,4,6.11. / 9,11,13.11. / 16,17.11. -> .weeks(3, isCapped: false)
// plus 18.11. -> .weeks(4, ...); week 9.–15.11. with only 9,10 -> .weeks(0, ...) while the running week is not reached
@Test func streak_capsAtTheWindow()
// start 1.8., every day checked: daily -> .days(90, isCapped: true); daysPerWeek 3 -> .weeks(12, isCapped: true)
@Test func counter_countsWeeklyGoalReachedAsDone()
// A daily fulfilled today, B daily open, C daysPerWeek 2 with checks 16,17 -> HabitCounter(done: 2, total: 3)
@Test func counter_withoutActiveHabits_isNil()     // only a paused habit -> nil
@Test func dayKey_roundTrips()                     // PlanDay(2026,11,8).dayKey == "2026-11-08"; PlanDay(dayKey: "2026-11-08") equal
```

`HabitStoreTests` (In-Memory-Container): `save_cutsNameToFortyCharacters`, `delete_removesChecksOfTheHabit`, `setCheck_twice_keepsOneRecord`, `setCheck_false_removesTheManualCheck`, `pauseAndResume_recordsTheClosedPause` (pausiert 16.11., fortgesetzt 18.11. → `pauses == [16.11....17.11.]`, `pausedSince == nil`), `reorder_writesOrder`. `ModelStoreLocationTests` bekommt die Erwartung, dass das Schema `HabitRecord` und `HabitCheckRecord` enthält und der bestehende Store öffnet.

- [ ] **Step 2:** `CORE HabitRulesTests`, `APP HabitStoreTests` → rot.
- [ ] **Step 3: Umsetzen.** `HabitRules` rechnet nur im Fenster. Zieltage = zählende Tage × `daysPerWeek` ÷ 7; Quote = `Int((Double(done) / target * 100).rounded())`, höchstens 100. Wochen sind Montag bis Sonntag (`IntakeRules.weekStart`). `HabitRecord.pausesData` ist JSON von `[HabitPause]`. Beide Klassen in `ModelContainerFactory.schema` ergänzen.
- [ ] **Step 4:** `CORE HabitRulesTests`, `APP HabitStoreTests`, `APP ModelStoreLocationTests` → grün.
- [ ] **Step 5: Commit.**

```bash
git add app/Packages/TagwerkCore app/Tagwerk/Routines/HabitRecords.swift app/Tagwerk/Persistence/ModelContainerFactory.swift app/TagwerkTests
git commit -m "feat: add habit records and habit rules"
```

### Task 5: `HabitsModel`, automatische Erfüllung, Zähler in „Planen“ · #141 · Zeile 3

**Files:**
- Create: `app/Tagwerk/Routines/HabitsModel.swift`
- Modify: `app/Tagwerk/Capture/IntakeStore.swift` (nach Zeile 50), `app/Tagwerk/App/AppEnvironment.swift` (Init, `startSnapshotUpdates`), `app/Tagwerk/Planning/PlanHeader.swift:5, 113–132`
- Test: `app/TagwerkTests/HabitsModelTests.swift`, `app/TagwerkTests/PlanHeaderTextTests.swift`, `app/TagwerkTests/IntakeStoreTests.swift`

**Interfaces:**
- Consumes: Task 4; `IntakeStore.workouts(in:)`, `HealthStoring.access()`, `foreignWorkouts(in:)`, `stepsAccess()`, `dailySteps(in:calendar:)`; `AppSettings.goalWaterMilliliters`, `goalStepsPerDay`.
- Produces:

```swift
extension IntakeStore { func drinks(in interval: DateInterval) -> [DrinkValue] }

@MainActor @Observable final class HabitsModel {
    struct Row: Identifiable, Equatable {
        var id: UUID { habit.id }
        let habit: Habit
        let isFulfilled: Bool
        let isAutomatic: Bool          // the source is fulfilled; the row cannot be unchecked
    }
    private(set) var habits: [Habit]            // all, paused ones too, by order
    private(set) var facts: HabitFacts
    private(set) var day: PlanDay
    private(set) var rows: [Row]                // habits active on `day`
    private(set) var todayCounter: HabitCounter?
    @ObservationIgnored var onChanged: (() -> Void)?
    let calendar: Calendar
    var today: PlanDay { get }
    init(store: HabitStore, intake: IntakeStore, health: any HealthStoring, settings: AppSettings,
         calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init)
    func reload(day: PlanDay? = nil) async      // nil keeps the shown day; at most three Health queries over the window
    func refreshLocal()                         // store and settings only, no Health
    func toggle(_ id: UUID) async               // manual check on `day`; ignored for automatic rows and future days
    @discardableResult func checkToday(_ id: UUID) async -> Bool   // Siri; false when already checked by hand
    func save(_ habit: Habit); func delete(_ id: UUID); func reorder(_ ids: [UUID]); func setPaused(_ id: UUID, _ paused: Bool)
    var canAddHabit: Bool { get }               // fewer than HabitRules.maximumActive unpaused habits
    func takenSources(excluding id: UUID?) -> Set<HabitSource>
}

extension PlanHeaderText {
    /// "~1.240 / 2.300 kcal · 2,1 l · ✓ 3 von 5"; the counter alone when there is no intake text.
    static func statusLine(intake: String?, habits: HabitCounter?) -> String?
    static func habitCounter(_ counter: HabitCounter) -> String      // "✓ 3 von 5"
}
```

- [ ] **Step 1: Tests schreiben (rot).** `HabitsModelTests` mit `FakeHealthStore`, heute = `testNow()`:

```swift
@Test func waterHabit_isAutomaticOnceTheGoalIsReached()
// goal 2000; drinks 1000 + 1100 on 18.11. -> rows.first: isFulfilled && isAutomatic; todayCounter == HabitCounter(done: 1, total: 1)
@Test func workoutHabit_countsOwnAndHealthWorkoutsFromTenMinutes()
// own workout 9 min -> open; Health workout 42 min on 17.11., reload(day: 17.11.) -> fulfilled
@Test func stepsHabit_staysOpenWithoutStepAccessAndCanBeCheckedByHand()
// stepsAccess not asked -> open, no step query made; toggle -> isFulfilled, isAutomatic == false
@Test func reload_readsHealthAtMostThreeTimesOverNinetyDays()
// health.foreignWorkoutQueries == 1, health.stepQueries == 1, each interval == 21.08.2026 00:00 ..< 19.11.2026 00:00 (today − 89 days ... end of today)
@Test func failedHealthRead_keepsLastFactsOfTheSameDay()
// first reload: 9000 steps of 8000 -> done; health.failsStepRead = true; reload -> still done on the same day
@Test func toggle_onAutomaticRowOrFutureDay_changesNothing()
@Test func toggle_twice_removesTheManualCheck()
@Test func checkToday_reportsAnExistingManualCheck()        // first call true, second false
@Test func goalChange_changesPastDaysToo()                  // design §14.14: raising the water goal reopens yesterday
```

`PlanHeaderTextTests`: `statusLine_appendsTheHabitCounter` (`statusLine(intake: "~1.240 / 2.300 kcal · 2,1 l", habits: .init(done: 3, total: 5)) == "~1.240 / 2.300 kcal · 2,1 l · ✓ 3 von 5"`), `statusLine_counterAlone` (`== "✓ 3 von 5"`), `statusLine_withoutBoth_isNil`. `IntakeStoreTests`: `drinksInInterval_returnsOnlyDrinksInside`. `FakeHealthStore` bekommt Zähler für Abfragen und `failsStepRead`.

- [ ] **Step 2:** `APP HabitsModelTests`, `APP PlanHeaderTextTests` → rot.
- [ ] **Step 3: Umsetzen.** `reload` liest Handhäkchen, Getränke und eigene Trainings aus dem Store und danach Health nur, wenn der jeweilige Zugriff schon erfragt wurde. Ein fehlgeschlagener Lesevorgang behält die Werte des letzten Laufs, solange `today` gleich ist. `AppEnvironment` legt `habits: HabitsModel` an; die vorhandene Closure `capture.onTodayChanged` ruft zusätzlich `habits.refreshLocal()`; `habits.onChanged` ruft `scheduleSnapshot()`. `TagwerkApp` lädt `habits` dort neu, wo `capture.reload()` läuft. `PlanIntakeLine` zeigt `PlanHeaderText.statusLine(intake: environment.capture.planHeaderLine, habits: environment.habits.todayCounter)`; die Flamme erscheint nur mit Ernährungstext; Tippen öffnet „Erfassen“ wie bisher.
- [ ] **Step 4:** `APP HabitsModelTests`, `APP PlanHeaderTextTests`, `APP IntakeStoreTests`, `APP CaptureModelTests` → grün.
- [ ] **Step 5: Commit.** `git commit -m "feat: compute habit fulfilment and show the counter in the plan header"`

### Task 6: Abschnitt „Gewohnheiten“, Liste „Bearbeiten“, Blatt „Gewohnheit“ · #141 · Zeile 2

**Files:**
- Create: `app/Tagwerk/Routines/HabitsSection.swift`, `HabitListView.swift`, `HabitSheet.swift`, `HabitText.swift`
- Modify: `app/Tagwerk/Capture/CaptureView.swift:60–66`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/HabitTextTests.swift`

**Interfaces:**
- Consumes: `HabitsModel` (Task 5), `HabitRules` (Task 4), `IntakeFormat.liters(_:)`, `CaptureModel.day`.
- Produces:

```swift
enum HabitText {
    static func header(_ counter: HabitCounter?) -> String                       // "Gewohnheiten · 3 von 5" / "Gewohnheiten"
    static func subtitle(_ habit: Habit, today: PlanDay, facts: HabitFacts, calendar: Calendar) -> String
    static func streak(_ streak: HabitStreak) -> String                          // "Serie 3", "Serie 4 Wochen", "Serie 90+", "Serie 12+ Wochen"
    static func sourceDetail(_ habit: Habit, on day: PlanDay, facts: HabitFacts, workout: WorkoutValue?) -> String?
    static let symbols: [String]                                                 // fixed SF Symbol choice, at least 12
}
struct HabitsSection: View { let model: HabitsModel }            // rows for the shown day, "Bearbeiten", empty state
struct HabitListView: View { let model: HabitsModel }            // all habits, sorting, create, opens HabitSheet
struct HabitSheet: View { let model: HabitsModel; let habit: Habit? }
```

- [ ] **Step 1: Tests schreiben (rot).** `HabitTextTests`:

```swift
@Test func subtitle_daily()        // == "7 Tage 5/7 · 30 Tage 73 % · Serie 3"
@Test func subtitle_weekly()       // == "Diese Woche 2 von 3 · 30 Tage 80 % · Serie 4 Wochen"
@Test func subtitle_withoutCountingDays_showsDash()   // contains "30 Tage –"
@Test func streak_capped()         // "Serie 90+" and "Serie 12+ Wochen"
@Test func sourceDetail_water()    // 2100 ml, goal 2000 -> "2,1 l von 2,0 l"
@Test func sourceDetail_healthWorkout()   // "Laufen 42 min aus Health"
@Test func header_withAndWithoutCounter()
```

- [ ] **Step 2:** `APP HabitTextTests` → rot.
- [ ] **Step 3: Umsetzen.** Reihenfolge in `CaptureView`: Schnellerfassung, Health-Karte, (Task 9: „Routinen“), `HabitsSection`, Mahlzeiten, Getränke, Trainings. Zeile nach Design §7.1: Häkchen, Symbol, Name, Unterzeile; automatisch erfüllte Zeile mit Marke „automatisch“ und `sourceDetail`, Tippen zeigt die Quelle und ändert nichts; offene Zeile ruft `model.toggle`. Künftige Tage gibt es in „Erfassen“ nicht (`canGoForward`). `HabitsSection` lädt mit `.task(id: capture.day) { await model.reload(day: capture.day) }`. `HabitSheet` nach Design §7.2: Name (40 Zeichen), Symbol, „Erfüllt durch“ (vergebene Quellen deaktiviert, `daylight` nicht in der Auswahl), „Tage pro Woche“ 1–7 mit dem Fußtext aus GR2, „Zählt ab“ (heute − 89 … heute), „Pausieren“, „Gewohnheit löschen“ mit Rückfrage. „Anlegen“ ist bei `!model.canAddHabit` deaktiviert mit Hinweis. Texte deutsch und englisch.
- [ ] **Step 4:** `APP HabitTextTests` → grün. Sichtprüfung im Simulator gegen GO1, GH1, GH3, GR2: hell, dunkel, größte Schriftstufe, Englisch, VoiceOver-Texte der Zeilen.
- [ ] **Step 5: Commit.** `git commit -m "feat: add the habits section, habit list and habit sheet"`

### Task 7: Kurzbefehl „Gewohnheit abhaken“, Zähler im Snapshot und im Widget · #141 · Zeile 4

**Files:**
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/WidgetSnapshot.swift:53–72, 115–141`, `app/Tagwerk/App/AppEnvironment.swift:351–385`, `app/Tagwerk/Intents/TagwerkIntents.swift`, `IntentServices.swift`, `app/TagwerkWidget/WidgetViews.swift:6–35, 155–170, 219–252`, `app/Tagwerk/Settings/CaptureSettingsView.swift:52–61`, `app/Tagwerk/AppShortcuts.xcstrings`, beide `Localizable.xcstrings`
- Test: `WidgetSnapshotTests.swift`, `IntentServicesTests.swift`, `WidgetSnapshotWriterTests.swift`

**Interfaces:**
- Consumes: `HabitsModel.todayCounter`, `checkToday(_:)`, `habits`.
- Produces:

```swift
public typealias SnapshotHabits = HabitCounter
// SnapshotDay: public var habits: SnapshotHabits?   (optional, schemaVersion stays 1)
public static func make(createdAt: Date, days: [SnapshotDayInput], todayIntake: SnapshotIntake?, todayHabits: SnapshotHabits? = nil,
                        showsNutrition: Bool, calendar: Calendar) -> WidgetSnapshot
public func replacingToday(intake: SnapshotIntake?, habits: SnapshotHabits?, on day: PlanDay, createdAt: Date) -> WidgetSnapshot
public func habits(at date: Date, calendar: Calendar) -> SnapshotHabits?     // today's counter only

struct HabitEntity: AppEntity { var id: UUID; var name: String }             // query: active habits of today
struct CheckHabitIntent: AppIntent { @Parameter(title: "Gewohnheit") var habit: HabitEntity }   // background
extension IntentServices {
    func activeHabits() -> [Habit]
    func checkHabit(id: UUID) async -> LocalizedStringResource
}
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// WidgetSnapshotTests
@Test func habits_belongToTodayOnly()                 // days[0].habits == .init(done: 3, total: 5); days[1].habits == nil
@Test func habits_stayWhenNutritionIsHidden()         // showsNutrition false -> intake nil, habits kept
@Test func oldFileWithoutHabits_decodes()             // JSON without "habits" -> habits == nil, schemaVersion == 1
@Test func replacingToday_replacesIntakeAndHabits_keepsEntries()
@Test func snapshot_containsNoHabitNames()            // encoded JSON does not contain "Lesen 20 min"
// IntentServicesTests
@Test func checkHabit_addsManualCheckForToday_writesSnapshot()
// reply == "Lesen 20 min ist für heute abgehakt."; snapshot days.first?.habits == .init(done: 1, total: 1)
@Test func checkHabit_twice_saysAlreadyChecked()      // "Lesen 20 min war heute schon abgehakt."
@Test func checkHabit_onAutomaticHabit_stillStoresTheManualCheck()
@Test func checkHabit_unknownOrPausedHabit_changesNothing()   // reply "Diese Gewohnheit gibt es nicht mehr."
```

- [ ] **Step 2:** `CORE WidgetSnapshotTests`, `APP IntentServicesTests` → rot.
- [ ] **Step 3: Umsetzen.** `AppEnvironment.makeSnapshot` übergibt `habits.todayCounter` nur, wenn `habits.today` der Snapshot-Tag ist; `writeSnapshot` ruft im Hintergrundweg `replacingToday`. `checkHabit` lädt `habits` neu, setzt das Handhäkchen, schreibt den Snapshot; die Antwort nennt weder Serie noch Quote. Phrasen: „\(\.$habit) in \(.applicationName) abhaken“ und „Gewohnheit in \(.applicationName) abhaken“, Kurztitel „Gewohnheit abhaken“, Symbol `checkmark.circle`. `habits.onChanged` ruft zusätzlich `TagwerkShortcuts.updateAppShortcutParameters()`. Widget „Heute“: Zeile „✓ 3 von 5“ in der rechten Spalte unter Wasser und Schritten, `privacySensitive`; ohne Ernährung (`content.intake == nil`) zeigt der Plan drei Zeilen und darunter den Zähler. `NextUpView` und alle Sperrbildschirm-Familien bleiben unverändert. `CaptureSettingsView` nennt die neue Phrase.
- [ ] **Step 4:** `CORE WidgetSnapshotTests`, `APP IntentServicesTests`, `APP WidgetSnapshotWriterTests` → grün. Sichtprüfung des Widgets im Simulator (mit und ohne Ernährung, GB1).
- [ ] **Step 5: Commit.** `git commit -m "feat: add the check-habit shortcut and the habit counter in the widget"`

### Task 8: Tageseintrag, Abend-Checkliste, `RoutineSchedule`, Einstellungen › Routinen · #142 · Zeile 5

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/RoutineSchedule.swift`, `app/Tagwerk/Routines/RoutineRecords.swift`, `RoutineSettingsView.swift`
- Modify: `app/Tagwerk/Persistence/AppSettings.swift` (nach Zeile 97), `ModelContainerFactory.swift`, `app/Tagwerk/Settings/SettingsView.swift:62–70`
- Test: `RoutineScheduleTests.swift` (Core), `RoutineStoreTests.swift`, `ModelStoreLocationTests.swift`

**Interfaces:**
- Produces (TagwerkCore):

```swift
public struct ChecklistItem: Sendable, Hashable, Identifiable {
    public var id: UUID; public var title: String; public var order: Int; public var offsetMinutes: Int?
}
public struct RoutineDayValue: Sendable, Hashable {
    public var gratitude: [String]            // at most 3, empty strings dropped
    public var startCompletedAt: Date?; public var startDismissed: Bool
    public var closeCompletedAt: Date?; public var checkedItemIDs: Set<UUID>
    public static let empty: RoutineDayValue
}
public enum RoutineSchedule {
    public static let eveningBoundaryMinutes = 240
    public static let morningCardEndMinutes = 720
    public static let fallbackEveningLeadMinutes = 90
    public static let maximumItems = 8
    public static let maximumReminders = 4
    public static let offsetRange = 0...240
    public static let offsetStep = 5
    public static let suggestedItems: [(title: String, offsetMinutes: Int)]     // 90, 60, 30 (design §11)
    public static func anchorMinutes(bedtimeMinutes: Int, offsetMinutes: Int) -> Int                     // rule 9
    public static func routineDay(at date: Date, calendar: Calendar) -> PlanDay                          // rule 10
    public static func showsMorningCard(minutesOfDay: Int, completed: Bool, dismissed: Bool) -> Bool     // rule 11
    public static func showsEveningLine(minutesOfDay: Int, bedtimeMinutes: Int, offsets: [Int]) -> Bool  // rule 11
    public static func reminderItems(_ items: [ChecklistItem]) -> [ChecklistItem]                        // first four with an offset, by order
    public static func checkedCount(_ day: RoutineDayValue, items: [ChecklistItem]) -> Int               // ignores ids of deleted items
}
```

- Produces (App): `RoutineDayRecord`, `EveningChecklistItemRecord` nach Design §5.2 und

```swift
@MainActor final class RoutineStore {
    init(context: ModelContext)
    func day(_ day: PlanDay) -> RoutineDayValue                                   // .empty without a record; reading never inserts
    func update(_ day: PlanDay, _ change: (inout RoutineDayValue) -> Void)        // inserts on the first write
    func checklist() -> [ChecklistItem]
    @discardableResult func saveItem(_ item: ChecklistItem) -> Bool               // false: ninth item or fifth reminder
    func deleteItem(_ id: UUID); func reorderItems(_ ids: [UUID])
    func adoptSuggestion()                                                        // only into an empty list
}
// AppSettings: bedtimeMinutes = 1380, eveningRemindersEnabled = true, morningReminderEnabled = false,
//              morningReminderMinutes = 450, showsRoutinesInPlan = true, noteSuggestionConsent = false
struct RoutineSettingsView: View     // sections as in design §11
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// RoutineScheduleTests
@Test func anchor_wrapsAroundMidnight()             // (1380, 90) == 1290; (30, 90) == 1380; (1380, 0) == 1380
@Test func routineDay_beforeFourBelongsToTheDayBefore()   // 19.11. 03:59 -> 18.11.; 19.11. 04:00 -> 19.11.
@Test func morningCard_showsFromFourToNoon()        // 239 false, 240 true, 719 true, 720 false; completed false; dismissed false
@Test func eveningLine_startsAtTheEarliestAnchor()  // bedtime 1380, offsets [90, 60, 30]: 1289 false, 1290 true, 100 true, 240 false
@Test func eveningLine_withoutAnchors_startsNinetyMinutesBeforeBedtime()   // bedtime 1380, []: 1289 false, 1290 true
@Test func eveningLine_bedtimeAfterMidnight()       // bedtime 60, offsets [30]: 1400 false, 29 false, 30 true, 239 true
@Test func reminderItems_areTheFirstFourWithAnOffset()
@Test func checkedCount_ignoresDeletedItems()
// RoutineStoreTests
@Test func readingADay_insertsNothing()
@Test func update_keepsAtMostThreeGratitudeEntries_andDropsEmptyOnes()
@Test func saveItem_rejectsTheNinthItem_andTheFifthReminder()
@Test func adoptSuggestion_createsThreeItems_onlyIntoAnEmptyList()   // offsets 90, 60, 30
@Test func settingsDefaults()                       // the six defaults of design §5.5
```

- [ ] **Step 2:** `CORE RoutineScheduleTests`, `APP RoutineStoreTests` → rot.
- [ ] **Step 3: Umsetzen.** `RoutineDayRecord.dayKey` ist `@Attribute(.unique)` wie `DayOverrideRecord`. `RoutineSettingsView` nach Design §11 (Tagesabschluss, Abend-Checkliste mit „n min vorher · Uhrzeit“ bzw. „ohne Erinnerung“, Tagesstart, Planen, Gewohnheiten › `HabitListView`, Gedanken-Notiz mit Schalter, der ohne ChatGPT-Anmeldung deaktiviert ist). `SettingsView` bekommt nach „Erfassen“ einen Abschnitt mit der Zeile „Routinen“ (Wert: Schlafzeit). Die Abschnitte „Tagesstart“ (Erinnerung) und „Gedanken-Notiz“ schalten in diesem Task nur die Felder; ihre Wirkung folgt in Task 10, 11 und 14.
- [ ] **Step 4:** `CORE RoutineScheduleTests`, `APP RoutineStoreTests`, `APP ModelStoreLocationTests` → grün. Sichtprüfung gegen GS·E.
- [ ] **Step 5: Commit.** `git commit -m "feat: add routine day records, evening checklist and routine settings"`

### Task 9: Blatt „Tagesabschluss“, Abendzeile, Zeilen in „Erfassen“, Routen · #142 · Zeile 6

**Files:**
- Create: `app/Tagwerk/Routines/RoutinesModel.swift`, `EveningSheet.swift`
- Modify: `TagwerkCore/AppRoute.swift:5–10`, `app/Tagwerk/App/AppRouter.swift:39–45`, `RootView.swift:56–62, 85–101, 120–145`, `AppEnvironment.swift`, `app/Tagwerk/Planning/DayView.swift:206–221`, `app/Tagwerk/Capture/CaptureView.swift`
- Test: `AppRouteTests.swift`, `AppRouterTests.swift`, `RoutinesModelTests.swift`, `FocusRulesTests.swift` (Core)

**Interfaces:**
- Consumes: Task 5, Task 8; `PlanningModel.planStore`, `blocks`, `recurringReminderIDs`, `nextPlanDay`, `today`, `calendar`; `gateway.completionDates(in:listIDs:)`, `LocalTaskProvider.completionDates(in:)`.
- Produces:

```swift
// AppRoute: case routineStart = "routine/start", case routineEvening = "routine/evening"
public enum FocusRules {                               // in RoutineSchedule.swift
    public static let maximumMarks = 3
    /// Open tasks of today (rule 12): planned for today, due today or with a time block today; no recurring occurrences.
    /// Sorted: P1 and due today first, then as `sortedTasks`.
    public static func candidates(_ tasks: [TaskItem], plannedToday: Set<TaskID>, blockedToday: Set<TaskID>,
                                  recurring: Set<TaskID>, today: PlanDay, calendar: Calendar) -> [TaskItem]
}
@MainActor @Observable final class RoutinesModel {
    enum Sheet: Identifiable, Equatable { case start(PlanDay), evening(PlanDay) }
    struct DayReview: Equatable { var tasksDone: Int; var tasksTotal: Int; var habits: HabitCounter?; var focus: HabitCounter? }
    struct EveningLine: Equatable { var bedtimeMinutes: Int; var checked: Int; var total: Int; var isDone: Bool }
    var sheet: Sheet?
    init(store: RoutineStore, planning: PlanningModel, taskList: TaskListModel, habits: HabitsModel, settings: AppSettings,
         completedCount: @escaping (DateInterval) async -> Int, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init)
    var eveningDay: PlanDay { get }                    // RoutineSchedule.routineDay(at: now())
    func openStart(_ day: PlanDay? = nil)              // nil: today
    func openEvening(_ day: PlanDay? = nil)            // nil: eveningDay
    func value(_ day: PlanDay) -> RoutineDayValue
    func checklist() -> [ChecklistItem]
    func toggleItem(_ id: UUID, on day: PlanDay)
    func finishEvening(_ day: PlanDay)
    func todayTasks() -> [TaskItem]                    // FocusRules.candidates with the model's data
    func dayReview(_ day: PlanDay) async -> DayReview  // deviation A1
    var eveningLine: EveningLine? { get }              // rule 11, only with showsRoutinesInPlan
    func captureEveningDetail(_ day: PlanDay) -> String   // "Schlafzeit 23:00 · Checkliste 0 von 3" / "✓ 22:10"
}
struct EveningSheet: View { let model: RoutinesModel; let day: PlanDay }
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// AppRouteTests
@Test func route_parsesRoutinePaths()        // tagwerk://routine/start -> .routineStart; tagwerk://routine/evening -> .routineEvening
// AppRouterTests
@Test func router_routineRoutes_haveNoPrefill()
// FocusRulesTests
@Test func candidates_arePlannedDueOrBlockedToday_withoutRecurring()
// A planned today, B due today, C block today, D due tomorrow, E recurring due today, F completed -> [B, A, C] when B is P1
// RoutinesModelTests (now = 18.11.2026 22:00 unless stated)
@Test func openEvening_beforeFour_opensTheDayBefore()          // now 19.11. 02:00 -> sheet == .evening(18.11.)
@Test func finishEvening_afterMidnight_writesTheDayTheSheetWasOpenedFor()
// sheet opened for 18.11., clock moves to 19.11. 00:10, finishEvening(18.11.) -> value(18.11.).closeCompletedAt != nil, value(19.11.) == .empty
@Test func toggleItem_twice_unchecks()
@Test func eveningLine_hiddenBeforeTheEarliestAnchor_andWhenSwitchedOff()   // 21:00 nil; 21:30 not nil; showsRoutinesInPlan false nil
@Test func eveningLine_countsOnlyExistingItems()               // EveningLine(bedtimeMinutes: 1380, checked: 1, total: 3, isDone: false)
@Test func dayReview_countsCompletionsPlusOpenTasksOfToday()   // completedCount 4, two open tasks of today -> tasksDone 4, tasksTotal 6
@Test func dayReview_withoutFocus_hasNoFocusLine()
@Test func captureEveningDetail_openAndDone()                  // "Schlafzeit 23:00 · Checkliste 0 von 3" and "✓ 22:10"
```

- [ ] **Step 2:** `CORE AppRouteTests`, `CORE FocusRulesTests`, `APP RoutinesModelTests`, `APP AppRouterTests` → rot.
- [ ] **Step 3: Umsetzen.** `AppEnvironment` legt `routines: RoutinesModel` an (`completedCount` aus den beiden Lesern des Wochenrückblicks). `RootView`: `.sheet(item:)` auf `environment.routines.sheet` zeigt `EveningSheet` bzw. (Task 11) `MorningSheet`; `openRouterTarget()` behandelt `.routineStart`/`.routineEvening` mit `showDay(planning.today)` und `routines.openStart()`/`openEvening()`; das Routinen-Blatt schließt wie die anderen, wenn der Assistent, eine Mitteilung oder eine Route öffnet. `EveningSheet` nach Design §7.5: „Heute“ (drei Zeilen, Fokus-Zeile nur mit Fokus, Fußtext aus A1), „Abend-Checkliste · Schlafzeit 23:00“ mit Uhrzeit je Punkt, ohne Punkte der Hinweis „Punkte in den Einstellungen anlegen“, Zeile „☾ Morgen planen · …“ nur mit `planning.nextPlanDay` (setzt `planning.anchor`, `environment.requestedTab = 0`, schließt das Blatt), „Fertig“ ruft `finishEvening(day)`. `CapacityCard`: Zeile „🛏 Tagesabschluss · Schlafzeit 23:00 · Checkliste 0 von 3 ›“ bei `plan.day == model.today` und `routines.eveningLine != nil`, unabhängig von `eveningEntry`, nach „Fertig“ mit Häkchen. `CaptureView`: Abschnitt „Routinen“ vor „Gewohnheiten“ mit der Zeile „Tagesabschluss“ für den gezeigten Tag (die Zeile „Tagesstart“ folgt in Task 11).
- [ ] **Step 4:** Tests aus Step 2 → grün. Sichtprüfung gegen GS·B und GA1 (abends).
- [ ] **Step 5: Commit.** `git commit -m "feat: add the evening wrap-up sheet, routine routes and the evening line"`

### Task 10: Wiederholende Mitteilungen, Ausschluss im Scheduler, Sprung über den Router · #142 · Zeile 7

**Files:**
- Create: `app/Tagwerk/Routines/RoutineNotificationScheduler.swift`
- Modify: `TagwerkCore/NotificationPlan.swift:20–28`, `TagwerkCore/RoutineSchedule.swift`, `TagwerkCore/Resources/Localizable.xcstrings`, `app/Tagwerk/Notifications/NotificationCenterClient.swift:18–48, 84–105`, `NotificationScheduler.swift:103`, `NotificationNavigator.swift:53–75`, `app/Tagwerk/App/AppEnvironment.swift:42`, `TagwerkApp.swift`, `RoutineSettingsView.swift`, `app/TagwerkTests/Fakes/FakeNotificationCenter.swift`
- Test: `RoutineScheduleTests.swift`, `RoutineNotificationTests.swift`, `NotificationSchedulerTests.swift`, `NotificationNavigatorTests.swift`

**Interfaces:**
- Consumes: Task 8, Task 9 (`AppRoute.routineEvening`).
- Produces:

```swift
// PlannedNotification: public static let routineIdentifierPrefix = "tagwerk.routine."
public struct RoutineNotification: Sendable, Hashable, Identifiable {
    public var id: String              // "tagwerk.routine.evening.<UUID>" or "tagwerk.routine.morning"
    public var hour: Int; public var minute: Int
    public var title: String; public var body: String
    public var route: AppRoute
}
extension RoutineSchedule {
    public static func eveningNotifications(items: [ChecklistItem], bedtimeMinutes: Int, enabled: Bool, locale: Locale) -> [RoutineNotification]
}
// NotificationCenterClient: func addRepeating(_ notification: RoutineNotification) async throws
// NotificationPayload: static let route = "route"
// NotificationDelegate.init(navigator: NotificationNavigator, router: AppRouter)
@MainActor final class RoutineNotificationScheduler {
    init(center: any NotificationCenterClient, store: RoutineStore, settings: AppSettings, locale: @escaping () -> Locale = { .current })
    func reschedule() async            // removes every pending "tagwerk.routine." request, then adds the wanted ones when authorized
}
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// RoutineScheduleTests
@Test func eveningNotifications_textAndTime()
// item "Handy weglegen", offset 60, bedtime 1380, de_DE -> hour 22, minute 0, title "Handy weglegen",
// body "Noch 60 min bis zur Schlafzeit (23:00)", route .routineEvening, id "tagwerk.routine.evening.<item id>"
@Test func eveningNotifications_atBedtime()          // offset 0 -> body "Schlafzeit (23:00)"
@Test func eveningNotifications_english()            // en_US -> "60 min until bedtime (11:00 PM)"
@Test func eveningNotifications_atMostFour_andNoneWhenDisabledOrWithoutItems()
// RoutineNotificationTests
@Test func reschedule_replacesAllRoutineRequests()   // seeded "tagwerk.routine.evening.OLD" is gone, wanted ones pending
@Test func reschedule_keepsDeadlineRequests()        // seeded "tagwerk.task.local:1" stays
@Test func reschedule_withoutPermission_addsNothing()
// NotificationSchedulerTests
@Test func routineRequests_areNeitherCountedNorRemoved()
// five seeded "tagwerk.routine." requests and 60 due tasks -> 50 task requests added, the five routine ids still pending
// NotificationNavigatorTests
@Test func routePayload_goesToTheRouter_notTheNavigator()
// userInfo ["route": "routine/evening"] -> router has a pending .routineEvening, navigator.hasPendingTarget == false
```

- [ ] **Step 2:** `CORE RoutineScheduleTests`, `APP RoutineNotificationTests`, `APP NotificationSchedulerTests`, `APP NotificationNavigatorTests` → rot.
- [ ] **Step 3: Umsetzen.** `SystemNotificationCenter.addRepeating`: `UNCalendarNotificationTrigger(dateMatching: DateComponents(hour:minute:), repeats: true)` ohne Zeitzone, `threadIdentifier = "routine"`, `interruptionLevel = .active`, `userInfo = ["route": route.rawValue]`. `NotificationScheduler.performReschedule` filtert `ours` zusätzlich mit `!$0.id.hasPrefix(PlannedNotification.routineIdentifierPrefix)`. Der Delegate reicht `userInfo["route"]` über `AppRoute(rawValue:)` an `router.open(_:)`, alles andere wie bisher an den Navigator. `reschedule()` läuft beim App-Start (`TagwerkApp`, nach `startNotificationUpdates()`), bei `.active` und nach jeder Änderung an Schlafzeit, Checkliste oder Schaltern in `RoutineSettingsView`. Fehlt die Erlaubnis, zeigt `RoutineSettingsView` den Hinweis und den Knopf der Benachrichtigungs-Einstellungen (`environment.notifications.requestAuthorization()`).
- [ ] **Step 4:** Tests aus Step 2 → grün.
- [ ] **Step 5: Geräteprüfung (Design §15.2), Ergebnis im Issue #142:** Mitteilung kommt ohne App-Start; überlebt Neustart und Drüberinstallieren; Verhalten im Fokus „Schlafen“; Tippen öffnet das Blatt „Tagesabschluss“ (auch bei beendeter App). **Schlägt „überlebt Neustart“ fehl:** kein Umbau; im Issue vermerken, dass erst der nächste App-Start neu einplant, und dem Nutzer melden.
- [ ] **Step 6: Commit.** `git commit -m "feat: schedule repeating evening reminders outside the deadline budget"`

### Task 11: Blatt „Tagesstart“ mit Dankbarkeit und Überblick; Erinnerung am Morgen · #145 · Zeile 8

**Files:**
- Create: `app/Tagwerk/Routines/MorningSheet.swift`
- Modify: `RoutinesModel.swift`, `TagwerkCore/RoutineSchedule.swift`, `RoutineNotificationScheduler.swift`, `app/Tagwerk/App/RootView.swift`, `app/Tagwerk/Capture/CaptureView.swift`
- Test: `RoutinesModelTests.swift`, `RoutineScheduleTests.swift`, `RoutineNotificationTests.swift`

**Interfaces:**
- Consumes: Task 8–10; `PlanningModel.planInputs(in:)`, `snapshotInput(from:days:)`.
- Produces:

```swift
extension RoutineSchedule {
    public static func morningNotification(enabled: Bool, minutes: Int, locale: Locale) -> RoutineNotification?
    // id "tagwerk.routine.morning", title "Tagesstart", body "Fokus für heute wählen?", route .routineStart
}
extension RoutinesModel {
    struct Overview: Equatable { var events: Int; var tasks: Int; var freeMinutes: Int }
    func overview() async -> Overview?                        // today only
    func setGratitude(_ entries: [String], on day: PlanDay)
    func finishStart(_ day: PlanDay)                          // sets startCompletedAt, also without any input
    func captureStartDetail(_ day: PlanDay) -> String         // "Fokus wählen" / "✓ 07:42" (+ " · Fokus: …" from Task 12)
    static func overviewText(_ overview: Overview) -> String  // "3 Termine · 5 Aufgaben · 3 h 30 frei"
}
struct MorningSheet: View { let model: RoutinesModel; let day: PlanDay }
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
@Test func morningNotification_textAndTime()        // 450 -> hour 7, minute 30, "Tagesstart", "Fokus für heute wählen?"
@Test func morningNotification_offByDefault()       // enabled false -> nil
@Test func reschedule_addsTheMorningRequest_whenEnabled()     // "tagwerk.routine.morning" pending; at most five routine requests in total
@Test func finishStart_withoutInput_marksTheDayCompleted()
@Test func swipeDismiss_savesGratitudeButDoesNotComplete()    // setGratitude only -> startCompletedAt == nil
@Test func gratitude_keepsAtMostThree()
@Test func overviewText_format()                    // Overview(events: 3, tasks: 5, freeMinutes: 210) -> "3 Termine · 5 Aufgaben · 3 h 30 frei"
@Test func captureStartDetail_openAndDone()         // "Fokus wählen" and "✓ 07:42"
```

- [ ] **Step 2:** `APP RoutinesModelTests`, `CORE RoutineScheduleTests`, `APP RoutineNotificationTests` → rot.
- [ ] **Step 3: Umsetzen.** `MorningSheet` nach Design §7.4: „Dankbar für“ (ein Feld; das zweite und dritte erscheinen nach Eingabe), „Heute“ mit `overviewText`, „Fertig“ rechts oben ruft `finishStart`; Wischen speichert nur. Die Abschnitte „Tagesfokus“ (Task 12) und „Gedanken“ (Task 13) kommen in ihren Tasks dazu. Für vergangene Tage fehlt „Heute“. `RootView` zeigt `MorningSheet` für `.start(day)`. `CaptureView`: Zeile „Tagesstart“ über „Tagesabschluss“. `RoutineNotificationScheduler.reschedule()` legt zusätzlich `morningNotification` an.
- [ ] **Step 4:** Tests aus Step 2 → grün. Sichtprüfung gegen GA1 (Blatt).
- [ ] **Step 5: Commit.** `git commit -m "feat: add the morning start sheet and the optional morning reminder"`

### Task 12: Fokus, Routine-Karte in „Planen“, Stern und Kontextmenü · #145 · Zeile 9

**Files:**
- Create: `app/Tagwerk/Routines/RoutineCard.swift`
- Modify: `RoutineRecords.swift` (`FocusMarkRecord`, Zugriffe im `RoutineStore`), `RoutinesModel.swift`, `MorningSheet.swift`, `EveningSheet.swift`, `ModelContainerFactory.swift`, `app/Tagwerk/Planning/DayView.swift:67–71, 435–458`, `TimelineCanvas.swift`, `app/Tagwerk/Tasks/TaskContextMenu.swift:5–21`, `app/Tagwerk/App/AppEnvironment.swift` (`taskList.onCompletionChanged`)
- Test: `RoutineStoreTests.swift`, `RoutinesModelTests.swift`

**Interfaces:**
- Consumes: `FocusRules` (Task 9), `TaskListModel.complete(_:)`, `sourceStates`, `loadingSources`, `onCompletionChanged`.
- Produces:

```swift
@Model final class FocusMarkRecord    // design §5.2 plus `var title: String = ""` (deviation A2)
struct FocusMark: Equatable, Identifiable { var id: String { taskKey }; var taskKey: String; var title: String; var order: Int; var doneAt: Date? }
extension RoutineStore {
    func focusMarks(on day: PlanDay) -> [FocusMark]
    @discardableResult func addFocus(_ task: TaskItem, on day: PlanDay) -> Bool      // false at three marks or when already marked
    func removeFocus(taskKey: String, on day: PlanDay)
    func setFocusDone(taskKey: String, on day: PlanDay, at date: Date?)
    func updateFocusTitle(taskKey: String, on day: PlanDay, title: String)
}
extension RoutinesModel {
    enum Card: Equatable {
        case morning(overview: String)                           // "Fokus wählen · 3 Termine, 5 Aufgaben"
        case focus(marks: [FocusMark], done: Int, total: Int)
    }
    var card: Card? { get }                                      // rule 11; never both states
    func dismissMorningCard()
    func focusMarks(_ day: PlanDay) -> [FocusMark]
    func isFocus(_ id: TaskID) -> Bool                           // today only
    func toggleFocus(_ task: TaskItem)                           // today only
    func completeFocus(_ mark: FocusMark) async                  // TaskListModel.complete; the mark itself never writes to a source
    func refreshFocus()                                          // sets doneAt for vanished tasks of settled sources, follows titles
    func focusChanged(_ id: TaskID, isCompleted: Bool)           // from taskList.onCompletionChanged
}
// TaskMenuActions: var toggleFocus: (() -> Void)? = nil; var isFocus = false
struct RoutineCard: View { let model: RoutinesModel }
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// RoutineStoreTests
@Test func addFocus_allowsAtMostThreePerDay()
@Test func sameTask_canBeFocusOnTwoDays()
// RoutinesModelTests
@Test func card_isMorningBetweenFourAndNoon_untilCompletedOrDismissed()
@Test func card_isFocusOnceAFocusIsChosen_andAnOpenFocusTaskRemains()   // .focus(marks: 2 marks, done: 1, total: 2)
@Test func card_isNil_whenAllFocusTasksAreDone_orRoutinesAreHiddenInPlan()
@Test func card_isNil_afterNoonWithoutFocus()
@Test func completeFocus_completesTheTaskInItsSource_andSetsDoneAt()    // FakeTaskProvider received the completion
@Test func undoComplete_clearsDoneAt()                                   // focusChanged(id, isCompleted: false)
@Test func vanishedTask_isDoneOnlyAfterItsSourceSettled()
// source loading: mark stays open; source loaded and task missing: doneAt set, title kept ("Exposé Kapitel 2")
@Test func toggleFocus_onARecurringOccurrence_isIgnored()
@Test func focusOfPastDays_isReadOnly()                                  // toggleFocus has no effect for a day before today
@Test func captureStartDetail_namesTheFirstFocus()                       // "✓ 07:42 · Fokus: Exposé Kapitel 2"
```

- [ ] **Step 2:** `APP RoutineStoreTests`, `APP RoutinesModelTests` → rot.
- [ ] **Step 3: Umsetzen.** `DayView.summary(_:)`: `RoutineCard` zwischen `PlanIntakeLine` und `DeadlineCard`, nur bei `model.scope == .day && model.anchor == model.today`. Tagesstart-Zustand einzeilig mit „Starten“ (öffnet das Blatt) und „✕“ (`dismissMorningCard`); Fokus-Zustand mit Kopf „Fokus heute · 1 von 2 · Ändern“ und höchstens drei Zeilen (Kreis, Titel, Zeitblock falls vorhanden, Stern; erledigte durchgestrichen). `MorningSheet` bekommt „Tagesfokus · n von 3 gewählt“ mit den ersten drei aus `todayTasks()` und „Alle n Aufgaben von heute zeigen“; für vergangene Tage nur lesbar. Stern an Fokus-Aufgaben in `PlannedTaskRow` und an ihren Zeitblöcken im Ablauf (Liste und Stundenraster), nicht im Tab „Aufgaben“. `DayView.plannedActions` setzt `toggleFocus`/`isFocus` nur in der Tagesansicht von heute; `TaskContextMenu` zeigt „Als Fokus markieren“ bzw. „Fokus entfernen“. `EveningSheet` zeigt die Zeile „★ Fokus 1 von 2“. Die vorhandene Closure `taskList.onCompletionChanged` in `AppEnvironment` ruft zusätzlich `routines.focusChanged`; `refreshFocus()` läuft nach jedem Laden der Aufgaben.
- [ ] **Step 4:** Tests aus Step 2 und `APP PlanningModelTests` → grün. Sichtprüfung gegen GF1 und GA1 (Karte), Höhe der Karte im Stundenraster auf dem kleinsten Gerät.
- [ ] **Step 5: Commit.** `git commit -m "feat: add the daily focus with the routine card and focus stars"`

### Task 13: Notizfeld auf `NoteRecord`/`NoteStore`, Spracheingabe, „Als Aufgabe anlegen“ · #143 · Zeile 10

**Voraussetzung:** Phase 5 ist gebaut (`NoteRecord`, `NoteStore`, Notizen-Liste).

**Files:**
- Create: `app/Tagwerk/Routines/NoteStore+Routines.swift`, `NoteField.swift`
- Modify: `app/Tagwerk/Notes/NoteRecord.swift` (Feld `derivedActionCount`), `app/Tagwerk/Notes/NotesListView.swift` (`footer(for:now:calendar:)`, Fußnote der Liste), `MorningSheet.swift`, `EveningSheet.swift`, `app/Tagwerk/Tasks/NewTaskSheet.swift:6–17`
- Test: `NoteFieldModelTests.swift`, Ergänzung im Listentest aus Phase 5 (`footer_thoughts_…`)

**Interfaces:**
- Consumes (Phase 5): `NoteRecord` (`id`, `text`, `createdAt`, `updatedAt`, `kindRaw`, `dayKey`, `isPinned`, `wasDictated`, `processedAt`), `NoteStore.note(kind:dayKey:)`, `create(text:kind:dayKey:wasDictated:)`, `delete(_:)`, `markProcessed(_:at:)`, `NoteKind`, `NoteText.title(_:)`, `NotesListView.footer(for:now:calendar:)`; `VoiceInputFactory.make(_:)`, `VoiceMicrophoneButton`, `VoiceRecordingBar`, `VoiceInputModel` (`readDraft`, `writeDraft`), `AppSettings.voiceInputEnabled`.
- Produces:

```swift
// NoteRecord: var derivedActionCount: Int = 0
extension NoteStore {
    /// Creates, updates or (for whitespace-only text) deletes the one thought note of that day and kind.
    /// `kind` is .morning or .evening; built on create(text:kind:dayKey:wasDictated:) and delete(_:).
    @discardableResult func saveThought(_ text: String, kind: NoteKind, dayKey: String, wasDictated: Bool) -> NoteRecord?
    func addDerivedAction(_ id: UUID)
}
@MainActor @Observable final class NoteFieldModel {
    var text: String
    var selection: TextSelection?
    private(set) var noteID: UUID?
    private(set) var wasDictated: Bool
    init(store: NoteStore, kind: NoteKind, day: PlanDay, debounce: Duration = .milliseconds(500),
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) })
    func textChanged()                         // debounced save
    func flush()                               // immediate save; called when the sheet closes
    func draftBeforeCursor() -> String         // for VoiceInputModel.readDraft
    func writeDictation(_ draft: String)       // for VoiceInputModel.writeDraft: draft + text behind the cursor
    var taskTitle: String? { get }             // NoteText.title(text); nil for an empty note
    func taskCreated()                         // addDerivedAction
}
struct NoteField: View { let model: NoteFieldModel }     // section "Gedanken"
// NewTaskSheet.init(model: TaskListModel, prefilledTitle: String? = nil, onCreated: (() -> Void)? = nil)
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// NoteFieldModelTests (sleep is a controllable fake)
@Test func typing_savesAfterTheDebounce_asOneNotePerDayAndKind()
// kindRaw == "evening", dayKey == "2026-11-18"; a second model for the same day and kind edits the same record
@Test func close_flushesThePendingSave()
@Test func whitespaceOnly_deletesTheNote()
@Test func unchangedText_doesNotTouchUpdatedAt()
@Test func dictation_insertsAtTheCursor()
// text "Anfang Ende", cursor after "Anfang ": draftBeforeCursor() == "Anfang "; writeDictation("Anfang Mitte") -> text == "Anfang Mitte Ende", wasDictated == true
@Test func taskTitle_isTheFirstNonEmptyLine()        // "\n  Einkauf planen \nmehr" -> "Einkauf planen"; "  \n" -> nil
@Test func taskCreated_incrementsDerivedActionCount()
@Test func freeNotes_areNeverReturnedAsThought()     // a "free" note with the same dayKey is ignored
```

Listentest (Testdatei von `NotesListView` aus Phase 5): `footer(for:now:calendar:)` liefert „Tagesabschluss · 18.11. · 2 Aufgaben daraus“ bei `derivedActionCount == 2`, ohne Zusatz bei 0; Fußnote der Liste lautet „Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Gedanken-Notiz nur, wenn du bei ihr auf ‚Vorschläge holen‘ tippst.“

- [ ] **Step 2:** `APP NoteFieldModelTests` → rot.
- [ ] **Step 3: Umsetzen.** `saveThought` ruft für Text mit Inhalt `create(text:kind:dayKey:wasDictated:)` (Phase 5 aktualisiert dabei die vorhandene Notiz des Tages und der Art) und löscht bei reinem Leerraum die vorhandene Notiz über `delete(_:)`. `NoteField` nach Design §7.6: mehrzeiliges Feld „Was geht dir durch den Kopf?“ mit `TextSelection`, Mikrofon nur bei `voiceInputEnabled` (eigener `VoiceInputModel` über `VoiceInputFactory.make(_:)` mit `readDraft = draftBeforeCursor`, `writeDraft = writeDictation`, `onSend = { _ in }`; `VoiceMicrophoneButton` und `VoiceRecordingBar` wie im Assistenten), darunter bei vorhandenem Text „＋ Als Aufgabe anlegen“ (öffnet `NewTaskSheet(model:prefilledTitle:onCreated:)`). „Vorschläge holen“ und der Fußtext folgen in Task 14. Beide Blätter bekommen den Abschnitt „Gedanken“ und rufen `flush()` beim Schließen. Die Notiz des Tagesabschlusses nutzt den Tag des Blatts (Regel 10).
- [ ] **Step 4:** Tests aus Step 2 und die Notiz-Tests aus Phase 5 → grün. Geräteprüfung (§15.2): Spracheingabe im Notizfeld außerhalb des Assistenten.
- [ ] **Step 5: Commit.** `git commit -m "feat: add the thoughts note to the morning and evening sheets"`

### Task 14: Zustimmung, `NoteSuggestionModel`, Kontext, Karten im Blatt · #143 · Zeile 11

**Voraussetzung:** Task 13; #136 ist gebaut (falls es `create_task` ändert).

**Files:**
- Create: `app/Tagwerk/AI/ActionCardDescriber.swift`, `app/Tagwerk/Routines/NoteSuggestionContext.swift`, `NoteSuggestionModel.swift`, `NoteConsentSheet.swift`
- Modify: `app/Tagwerk/AI/AssistantModel.swift:397–488`, `NoteField.swift`, `RoutineSettingsView.swift`, `app/Tagwerk/App/AppEnvironment.swift`
- Test: `NoteSuggestionModelTests.swift`, `AssistantModelTests.swift`

**Interfaces:**
- Consumes: `ResponseStreaming.respond(model:instructions:input:tools:jsonSchema:)`, `StreamEvent.functionCall`, `ToolCall`, `AppTools.allDefinitions`, `AppTools.run(_:)`, `AppTools.summary(_:)`, `AIEnvironment.selectedModel()`, `ActionCardView`, `ChatMessage.ActionStatus`, `NoteStore.markProcessed`/`addDerivedAction`, `AppSettings.noteSuggestionConsent`, `RoutineSchedule.routineDay`.
- Produces:

```swift
@MainActor struct ActionCardDescriber {
    let planning: PlanningModel
    func describe(_ call: ToolCall, language: VoiceLanguage = .app) -> AssistantModel.ActionCard
}
// AssistantModel.describe(_:language:) forwards to ActionCardDescriber

struct NoteSuggestionContext: Equatable {
    static let windowDays = 7
    static let maximumTasks = 60
    static let maximumEvents = 100
    var json: String                      // tasks and events of today ... today + 6, plus overdue tasks
    var taskIDs: Set<String>              // TaskID.key of every task sent
    var eventIDs: Set<String>
    var blockEventIDs: Set<String>        // deviation A7
    @MainActor static func make(taskList: TaskListModel, planning: PlanningModel, events: (DateInterval) -> [CalendarEvent],
                                planCalendarID: String?, now: Date) -> NoteSuggestionContext
}
enum NoteSuggestionRules {
    static let allowedTools: Set<String> = ["create_task", "reschedule_task", "assign_to_day", "create_time_block", "update_event"]
    static let maximumCards = 5
    static func accepted(_ calls: [ToolCall], context: NoteSuggestionContext) -> [ToolCall]
}
@MainActor @Observable final class NoteSuggestionModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }
    struct Card: Identifiable, Equatable {
        var id: String { call.id }
        let call: ToolCall
        let text: AssistantModel.ActionCard
        var status: ChatMessage.ActionStatus
        var time: Date?
    }
    private(set) var phase: Phase
    private(set) var cards: [Card]
    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String, tools: any ToolHandler,
         describer: ActionCardDescriber, notes: NoteStore, hasConsent: @escaping @MainActor () -> Bool,
         context: @escaping @MainActor () -> NoteSuggestionContext, now: @escaping () -> Date = Date.init)
    func fetch(noteID: UUID, text: String, kind: NoteKind) async        // exactly one request
    func confirm(_ id: String) async                                    // AppTools.run, no further request
    func decline(_ id: String)
    func confirmAll() async
    func reset()                                                        // sheet closed or text changed: drops cards and late answers
    var openCount: Int { get }
}
struct NoteConsentSheet: View { let onAgree: () -> Void; let onDecline: () -> Void }
// NoteFieldModel: var canSuggest: Bool   (signed in, text not empty, the sheet's day == RoutineSchedule.routineDay(at: now()))
```

- [ ] **Step 1: Tests schreiben (rot).** `NoteSuggestionModelTests` mit einem Fake-Responder, der Aufrufe zählt und `instructions`, `input`, `tools` mitschneidet:

```swift
@Test func fetch_withoutConsent_sendsNothing()                 // responder.calls == 0, the model closure was not called
@Test func fetch_sendsOneRequest_withExactlyTheFiveWriteTools()
// Set(tools.map(\.name)) == NoteSuggestionRules.allowedTools; no "list_tasks", "delete_event", "plan_period"
@Test func fetch_sendsTheNoteAndTheSevenDayContext_butNoRoutineData()
// input contains the note text and a task due on 24.11.; it does not contain a task due on 25.11.,
// the gratitude entry "Dankbar-Marker", the habit name "Lesen 20 min" or the reflection text "Reflexion-Marker"
@Test func context_keepsOverdueTasks_andCapsAtSixtyTasksAndHundredEvents()
@Test func context_omitsTaskNotes()                            // the notes of a task never appear in json
@Test func accepted_dropsUnknownIDs_andKeepsAtMostFive()
@Test func accepted_updateEvent_onlyForTagwerkBlocks()         // an ordinary event id is dropped, a block id stays
@Test func accepted_createTask_needsNoID()
@Test func fetch_setsProcessedAt()
@Test func confirm_runsTheToolOnce_withoutASecondRequest_andCountsTheAction()
// responder.calls stays 1; tools.runs == 1; card.status == .done(...); note.derivedActionCount == 1
@Test func confirm_withAToolError_showsTheErrorAndDoesNotCount()
@Test func confirmAll_runsOnlyPendingCards()
@Test func answerWithoutCalls_isEmpty()                        // phase == .empty
@Test func networkFailure_offersRetry()                        // phase == .failed("Keine Verbindung. Vorschläge brauchen Internet.")
@Test func lateAnswerAfterReset_isDiscarded()                  // reset() while loading -> cards stay empty, phase == .idle
@Test func olderDay_cannotSuggest()                            // sheet for 17.11. on 18.11. -> canSuggest == false
@Test func eveningSheetAfterMidnight_canStillSuggest()         // sheet for 18.11. at 19.11. 01:00 -> canSuggest == true
```

`AssistantModelTests`: die vorhandenen `describe`-Tests bleiben unverändert grün (Nachweis, dass das Herauslösen nichts ändert).

- [ ] **Step 2:** `APP NoteSuggestionModelTests` → rot.
- [ ] **Step 3: Umsetzen.** `fetch` prüft die Zustimmung vor allem, was OpenAI erreichen kann (auch vor der Modellliste), wie `MealEstimator.estimate`. Eingabe: ein `InputItem.user` mit Notiz, Art, Datum und Uhrzeit sowie `context.json`; Anweisung auf Englisch (Wortlaut frei, Design §18): nur Funktionsaufrufe aus der Liste, höchstens fünf, nur Kennungen aus dem Kontext, Antwortsprache der Karten nicht nötig. Aufrufe werden aus `StreamEvent.functionCall` gesammelt; ein Strom ohne `completed` ist ein Fehler. Fehlertexte nach dem Muster von `MealEstimator.Failure` (keine Verbindung, Anmeldung abgelaufen, Nutzungsgrenze, fehlgeschlagen). Nichts davon wird geloggt. `NoteField`: unter dem Feld „✦ Vorschläge holen“ (nur mit ChatGPT-Anmeldung, sonst Hinweis auf Einstellungen › KI; nur bei `canSuggest`), Fußtext aus Design §7.6, Abschnitt „n Vorschläge aus der Notiz“ mit `ActionCardView`, „Alle bestätigen (n)“ ab zwei offenen Karten, „Keine Vorschläge aus dieser Notiz.“, Fehler mit „Erneut versuchen“. Erstes Tippen bei ausgeschaltetem Schalter zeigt `NoteConsentSheet` (Aufbau wie `MealConsentSheet`, Texte aus Design §9.1 mit „der nächsten 7 Tage“); „Einverstanden und Vorschläge holen“ setzt `noteSuggestionConsent = true` und ruft `fetch`. Vor `fetch` läuft `flush()`. `reset()` beim Schließen des Blatts und bei jeder Textänderung nach dem Laden. Fußtext des Schalters in `RoutineSettingsView` an §9.2 anpassen.
- [ ] **Step 4:** `APP NoteSuggestionModelTests`, `APP AssistantModelTests`, `APP AppToolsTests` → grün. Sichtprüfung gegen GZ1 und GK1.
- [ ] **Step 5: Commit.** `git commit -m "feat: suggest actions from a thoughts note after consent"`

### Task 15: Wochenreflexion · #144 · Zeile 12

**Files:**
- Create: `app/Tagwerk/Routines/WeekReflectionSections.swift`
- Modify: `RoutineRecords.swift` (`WeekReflectionRecord`, Zugriffe), `ModelContainerFactory.swift`, `TagwerkCore/HabitRules.swift`, `app/Tagwerk/Capture/WeekReviewModel.swift`, `WeekReviewView.swift:15–42`, `AppEnvironment.swift:337–346`, `EveningSheet.swift`
- Test: `HabitRulesTests.swift`, `WeekReflectionTests.swift`, `WeekReviewModelTests.swift`

**Interfaces:**
- Consumes: Task 4, 5, 9.
- Produces:

```swift
public struct HabitWeekSummary: Sendable, Hashable, Identifiable {
    public var id: UUID { habit.id }
    public var habit: Habit; public var done: Int; public var total: Int; public var isRunning: Bool
}
extension HabitRules {
    /// Habits active on at least one day of the week. Daily habits: fulfilled of counting days; fewer than seven days
    /// per week: fulfilled days of the week goal.
    public static func weekSummaries(_ habits: [Habit], weekStart: PlanDay, today: PlanDay, facts: HabitFacts,
                                     calendar: Calendar) -> [HabitWeekSummary]
}
struct WeekReflection: Equatable {
    var wentWell = ""; var burdens = ""
    var plannedAppointments = false; var plannedHabits = false; var plannedTasks = false
}
extension RoutineStore {
    func reflection(weekStart: PlanDay) -> WeekReflection          // empty without a record; reading never inserts
    func saveReflection(_ value: WeekReflection, weekStart: PlanDay, at date: Date)
}
// WeekReviewModel: private(set) var habitSummaries: [HabitWeekSummary]; var reflection: WeekReflection;
//                  func saveReflection(); func planNextWeek()   (planning.scope = .week, anchor = weekStart + 7, requestedTab = 0)
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
// HabitRulesTests
@Test func weekSummaries_dailyHabit_runningWeek()      // week 16.–22.11., checks 16, 17, today open -> done 2, total 2, isRunning true
@Test func weekSummaries_weeklyHabit_usesTheWeekGoal() // daysPerWeek 3, checks 16, 17 -> done 2, total 3
@Test func weekSummaries_skipHabitsNotActiveInTheWeek()
// WeekReflectionTests
@Test func reflection_isStoredPerWeek_andPastWeeksStayEditable()   // weekKey "2026-11-16"
@Test func emptyReflection_isNotInserted()
// WeekReviewModelTests
@Test func reload_loadsHabitSummariesAndTheReflectionOfTheShownWeek()
@Test func planNextWeek_showsTheWeekViewOfTheFollowingWeek()
```

- [ ] **Step 2:** `CORE HabitRulesTests`, `APP WeekReflectionTests`, `APP WeekReviewModelTests` → rot.
- [ ] **Step 3: Umsetzen.** Drei Abschnitte am Ende von `WeekReviewView`, auch in einer sonst leeren Woche: „Gewohnheiten“ (je Zeile „3 von 4“, laufende Woche mit „bisher“, Balken), „Reflexion“ (zwei mehrzeilige Felder „Was lief gut?“, „Belastet mich etwas?“), „Neue Woche planen“ (drei Häkchen und „Woche planen ›“). Gespeichert wird entprellt und beim Verlassen. `makeWeekReviewModel()` übergibt `HabitStore`, `RoutineStore` und die Aktion für „Woche planen“. `EveningSheet` zeigt sonntags (Wochentag des Blatt-Tags) die Zeile „Wochenreflexion ›“, die das Blatt schließt und `router.open(.review)` aufruft. Nichts aus der Reflexion erreicht den Snapshot, Siri oder ChatGPT.
- [ ] **Step 4:** Tests aus Step 2 → grün. Sichtprüfung gegen GW1.
- [ ] **Step 5: Commit.** `git commit -m "feat: add habits, reflection and week planning to the weekly review"`

### Task 16: Leitfragen-Vorlage · #146 · Zeile 13

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/NoteTemplate.swift`
- Modify: `TagwerkCore/Resources/Localizable.xcstrings`, `app/Tagwerk/Routines/NoteField.swift`
- Test: `NoteTemplateTests.swift`

**Interfaces:**
- Produces:

```swift
public enum NoteTemplate {
    public static func guidingQuestions(locale: Locale) -> [String]            // six questions in the app language
    public static func appendingGuidingQuestions(to text: String, locale: Locale) -> String
    public static func containsGuidingQuestions(_ text: String, locale: Locale) -> Bool   // the first question is present
}
```

- [ ] **Step 1: Tests schreiben (rot).**

```swift
@Test func guidingQuestions_german()
// == ["Was war mein Ziel?", "Was hat geholfen?", "Was hat abgehalten?", "Erfahrungen mit anderen", "Meine eigene Rolle", "Nächste Schritte"]
@Test func appending_toEmptyText()
// == "Was war mein Ziel?\n\nWas hat geholfen?\n\nWas hat abgehalten?\n\nErfahrungen mit anderen\n\nMeine eigene Rolle\n\nNächste Schritte\n\n"
@Test func appending_keepsExistingText()             // "Heute war gut." -> starts with "Heute war gut.\n\nWas war mein Ziel?\n\n"
@Test func contains_hidesTheButtonOnceInserted()
@Test func guidingQuestions_english_haveSixEntries()
```

- [ ] **Step 2:** `CORE NoteTemplateTests` → rot.
- [ ] **Step 3: Umsetzen.** Knopf „Leitfragen einfügen“ im Kopf des Abschnitts „Gedanken“; er fehlt bei `containsGuidingQuestions`. Die Fragen werden in der App-Sprache eingefügt und sind danach Text der Notiz.
- [ ] **Step 4:** `CORE NoteTemplateTests`, `APP NoteFieldModelTests` → grün.
- [ ] **Step 5: Commit.** `git commit -m "feat: add the guiding questions template to the thoughts note"`

### Task 17 (optional, nur nach bestandenem Task 1): Quelle „Zeit bei Tageslicht“ · #141 · Zeile 15

**Files:**
- Modify: `app/Packages/HealthBridge/Sources/HealthBridge/HealthStoring.swift`, `HealthKitStore.swift:33–40`, `HealthEntries.swift`, `app/Tagwerk/Capture/DemoHealthStore.swift`, `app/TagwerkTests/Fakes/FakeHealthStore.swift`, `HabitsModel.swift`, `HabitSheet.swift`, `app/Tagwerk/InfoPlist.xcstrings`
- Test: `HabitsModelTests.swift`, `HealthMappingTests.swift`

**Interfaces:**
- Produces:

```swift
public struct DailyDaylight: Sendable, Hashable { public var start: Date; public var minutes: Int }
// HealthStoring:
func daylightAccess() async -> StepsAccess                       // own status, never part of access()
func requestDaylightAuthorization() async throws
func dailyDaylight(in interval: DateInterval, calendar: Calendar) async throws -> [DailyDaylight]
// HealthKitStore: static var daylightReadTypes: Set<HKObjectType>   (not in coreReadTypes, not in connectReadTypes)
```

- [ ] **Step 1: Tests schreiben (rot).** `daylightHabit_isAutomaticWithData_andManualWithout` (25 min bei Schwelle 20 → automatisch; Tag ohne Wert → offen und von Hand abhakbar), `daylight_isReadOnlyAfterItsOwnRequest` (ohne Anfrage keine Abfrage), `coreReadTypes_doNotContainDaylight`, `reload_readsHealthAtMostThreeTimes` (jetzt mit Tageslicht genau drei).
- [ ] **Step 2:** `APP HabitsModelTests` → rot.
- [ ] **Step 3: Umsetzen.** „Zeit bei Tageslicht“ in „Erfüllt durch“ mit Schwelle 5–120 min und dem Hinweis aus GH3; die Auswahl löst `requestDaylightAuthorization()` aus (nur nach Tippen). Werte, die laut Spike für Tage ohne Watch 0 sind, gelten als „kein Wert“.
- [ ] **Step 4:** `APP HabitsModelTests`, HealthBridge-Tests → grün. Geräteprüfung mit Watch.
- [ ] **Step 5: Commit.** `git commit -m "feat: fulfil a habit from time in daylight"`

### Task 18: Geräte-Checkliste und Abschluss · #140

- [ ] **Step 1:** `app/test-all.sh` → „ALL TESTS PASSED“ (einschließlich `check-strings.py --require-english` und `sync-strings.sh --check`).
- [ ] **Step 2:** Geräte-Checkliste aus Design §15.2, Ergebnis je Punkt im Epic #140: wiederholende Auslöser bei Zeitumstellung und Zeitzonenwechsel; Siri erkennt die deutsche Phrase mit Gewohnheitsnamen; Abhaken bei gesperrtem Gerät; fünf Routine-Mitteilungen bei vollen 50 Deadline-Plätzen; Höhe der Routine-Karte auf dem kleinsten Gerät.
- [ ] **Step 3:** Drüberinstallieren über einen Stand vor Phase 7: Der Store öffnet, vorhandene Daten sind da, das Widget liest eine alte Snapshot-Datei.
- [ ] **Step 4: Commit** nur, falls Step 1–3 Korrekturen brauchten: `git commit -m "fix: address findings of the routines device checklist"`

## Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| Phase 5 weicht beim Bauen von ihrem Plan ab | Task 13 passt nicht | Phase 7 hängt nur an den oben genannten Namen; `NoteStore+Routines.swift` und `NoteFieldModel` sind die einzigen Stellen, die sie aufrufen |
| Wiederholende Auslöser überleben Neustart nicht (Annahme) | Erinnerung fehlt bis zum nächsten App-Start | Neu-Einplanen bei jedem Start und bei `.active`; Geräteprüfung in Task 10 |
| Zähler „erledigt“ ohne GitHub (A1) | Tagesrückblick zu niedrig für GitHub-Nutzer | Fußtext nennt die Grenze; kein neuer Datentyp |
| Gelöschte Fokus-Aufgabe gilt als erledigt | Fokus „2 von 2“ trotz Löschen | bewusst (nicht unterscheidbar); „Ändern“ entfernt die Marke |
| 90-Tage-Abfrage an Health bei jedem Laden | Wartezeit in „Erfassen“ | höchstens drei Abfragen; Store-Werte erscheinen sofort (`refreshLocal`) |
| Neue Typen im Schema | Store öffnet nicht | nur neue Klassen und Felder mit Standardwert; `ModelStoreLocationTests`; Task 18 Step 3 |
| Notiztext gelangt in ein Log | Datenschutzverstoß | kein Logging im `NoteSuggestionModel`; Fehlertexte ohne Eingabe |

## Self-Review (am 19.11.2026 durchgeführt)

- **Spec-Abdeckung:** §5 → Tasks 4, 8, 12, 13, 15; §6 Regeln 1–8 → Task 4/5, 9–11 → Task 8, 12 und 14 → Task 9, 13 → Task 16; §7.1–7.2 → Task 6; §7.3 → Tasks 5, 9, 12; §7.4 → Tasks 11–13; §7.5 → Tasks 9, 12, 13, 15; §7.6 → Tasks 13, 14; §7.7 → Task 16; §7.8 → Task 13; §7.9 → Task 15; §8 → Tasks 9–11; §9 → Task 14; §10 → Task 7; §11 → Tasks 8, 10, 14; §12 → in jedem Task mit Texten, geprüft in Task 18; §15.1 → Tasks 1–3, 17; §15.2 → Tasks 10, 13, 18.
- **Typen:** `HabitCounter` wird als `SnapshotHabits` und für Fokus-Zähler wiederverwendet; `NoteKind` (aus Phase 5), `RoutinesModel.Sheet`, `RoutineNotification` und `FocusMark` sind je einmal definiert und in späteren Tasks gleich benannt.
- **Proportion:** Der Plan enthält Signaturen, Testnamen und Werte, keine Funktionsrümpfe.
