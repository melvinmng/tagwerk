# Phase 2b-1b: Geräte-Feedback – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das freigegebene Geräte-Feedback zu 2b-1 umsetzen (Design §13). Dazu gehören:
- Tagesansicht mit neuem Kopf und Restzeit.
- Zeitblöcke, die sich ändern lassen: Menü, Lücken, Stundenraster.
- Ablage „Ungeplant“, Monatsauswahl und das neue Kontextmenü.
- Aufgaben-Tab mit Mehrfachauswahl und Sprung.
- Fälliges, das von selbst erscheint, und zusammengefasste doppelte Termine.
- Termine in allen Kalendern anlegen, ändern und löschen.

**Architecture:** Reine Regeln kommen nach `TagwerkCore`. Das sind Restkapazität, Raster und Lücken, das Zusammenfassen doppelter Termine und die Schreibbarkeit von Terminen. `CalendarStore` in `RemindersKit` wird vom Plan-Kalender auf alle beschreibbaren Kalender erweitert, mit `EventSpan` für Serien. `PlanningModel` bekommt Block-, Termin- und Fälligkeitsaktionen. Die Oberflächen folgen dem freigegebenen Mockup und werden im Simulator mit `-TagwerkDemoData` geprüft.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, EventKit und EventKitUI (`EKEventEditViewController`), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-17-phase-2b-design.md` §13 (geht §6, §7 und §11 vor). Mockups: `docs/superpowers/mockups/2026-11-18-phase-2b-feedback-mockups.html`; freigegeben sind A1, B1, C1–C4, D1, E1+E2, F1 (Rückfall F2), G1–G4, H1, I1, J1+J2+J4–J6. K1 und K3 gehören zu Plan 2b-2. Issues #45–#55, Epic #2.

## Global Constraints

- Alle Global Constraints aus Plan 2b-1 gelten weiter. **Ausnahme:** „Tagwerk schreibt nur in den Plan-Kalender“ entfällt (§13.10). Geschrieben wird nur in Kalender mit `allowsContentModifications`; Einladungen anderer werden nie geändert.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Prüfung: `app/test-all.sh` ist grün. Neue Dateien: vorher `pgrep -x Xcode` und prüfen, dass Xcode das Projekt nicht offen hat, dann `xcodegen`.
- Jede Änderung an einem Termin lädt ihn neu und prüft die Version (`CalendarBlockRules.checkVersion`). Serien fragen „Nur dieser Termin“ / „Dieser und alle folgenden“ (= `EKSpan.thisEvent` / `.futureEvents`).
- Neue Termine landen standardmäßig im Plan-Kalender. Neue SwiftData-Attribute sind optional oder haben Standardwerte.
- Dauerformat: `CapacityText.duration` schreibt Minuten zweistellig („2 h 05“).
- Raster für Ziehen und ±-Schritte: 15 min. Die Restzeit heute läuft ab jetzt, auf volle Minuten abgerundet.
- Keine persönlichen Daten in Code, Tests, Commits und Demo-Daten. Commits ohne KI-Hinweis.
- UI-Tasks enden mit einer Prüfung im Simulator: Startargument `-TagwerkDemoData`, steuern über die T3-Geräte-Tools. Erweitert dafür die Demo-Daten, wo nötig.

## Review Focus

1. **Termin in einem schreibgeschützten Kalender oder Einladung:** Bearbeiten und Löschen fehlen. Ein Schreibversuch über das Modell wirft einen Fehler und ändert nichts. Test in Task 4.
2. **Serientermin ändern:** „Nur dieser Termin“ ändert ausschließlich das Vorkommen, die ID mit `|<Sekunden>` wird korrekt aufgelöst. Test in Task 4.
3. **Tageswechsel um Mitternacht oder App über Nacht offen:** „Heute“, Restzeit und „Heute fällig“ beziehen sich auf das aktuelle Datum, nicht auf den Starttag. Test in Task 1 (Restzeit mit `now` am Folgetag).
4. **Zusammengefasster doppelter Termin, von dem nur einer verknüpft ist:** Die Zeile behält die Verknüpfung, und die Kapazität ändert sich nicht. Test in Task 2.
5. **Ziehen eines Blocks über Mitternacht oder vor den Tagesbeginn:** Der Block wird auf den Tag geklemmt und rutscht nicht in den Vortag. Test in Task 5.

---

### Task 1: Restzeit ab jetzt und erledigte Vorkommen (B1, §13.2–13.3) – Issue #46

**Files:**
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/Capacity.swift`, `app/Tagwerk/Planning/CapacityBar.swift`, `app/Tagwerk/Planning/RecurringEffortStore.swift`, `app/Tagwerk/Planning/PlanningModel.swift`, `app/Tagwerk/Tasks/TaskListModel.swift`, `app/Tagwerk/App/AppEnvironment.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/CapacityTests.swift` (neu, falls nicht vorhanden), `app/TagwerkTests/PlanningModelTests.swift`

**Interfaces:**
- Produces:
  - `CapacityInput.nowMinutes: Int?` mit Standardwert `nil`. Ist der Wert gesetzt, beginnt die Arbeitszeit bei `max(start, nowMinutes)`.
  - `DayCapacity.remainingMinutes: Int?`: nur heute gesetzt, sonst `nil`.
  - `DayPlan.isPast: Bool`.
  - `RecurringEffortStore.markDone(reminderID: String, day: PlanDay)` und `isDone(reminderID:day:) -> Bool`, neues `@Model RecurringOccurrenceDone` mit eindeutigem `key`.
  - `TaskListModel.onCompleted: ((TaskItem, Date) -> Void)?`.
  - `PlanningModel.didComplete(_ task: TaskItem, at: Date)`.
  - `CapacityText.remaining(_ capacity: DayCapacity) -> String`.

- [ ] **Step 1: Failing tests (Core)**
  - `capacity_withNow_countsOnlyRemainingWorkTime`: Arbeit 09–18, Mittag 12–13, jetzt 14:00 ergibt `remainingMinutes == 240`, `availableMinutes` unverändert 480.
  - `capacity_nowAfterWork_remainingZero`
  - `capacity_nowBeforeWork_remainingEqualsAvailable`
  - Abgezogen werden nur noch nicht vergangene Teile von Terminen: ein Termin 13:30–15:00 bei jetzt 14:00 kostet 60 min, plus Puffer nach dem Ende.
  - Geplante Last: Für die Restzeit zählen Blöcke, die nach jetzt enden. Eine Aufgabe ohne Block zählt voll.
- [ ] **Step 2: Failing tests (Model)**
  - `dayPlan_today_hasRemaining_otherDaysNot`
  - `dayPlan_pastDay_isPast`
  - `completingRecurringToday_freesItsEffort`: Aufwand 60 min, `didComplete` mit `now` ergibt eine um 60 höhere Restzeit, und `recurring` des Tages zeigt den Eintrag als erledigt. Dafür bekommt `RecurringItem.isDone: Bool` den Standardwert `false`.
  - `completingNonRecurring_doesNotMarkOccurrence`
  - `duration_padsMinutes`: `CapacityText.duration(125) == "2 h 05"`
- [ ] **Step 3: Implementieren**
  - `capacity(_:)` schneidet die Arbeitszeit für die Restzeit auf `[max(start, now), end)`.
  - `PlanningModel.dayPlan` setzt `nowMinutes` nur für `day == today`. Reservierten Aufwand von erledigten Vorkommen zieht es heute nicht mehr ab.
  - `AppEnvironment` verbindet `taskList.onCompleted` mit `planning.didComplete`. `TaskListModel.complete` ruft den Hook nach erfolgreichem Schreiben auf.
  - `CapacityText.remaining`: „1 h 10 noch frei“; überbucht: „30 min zu viel“.
- [ ] **Step 4: Tests grün:** `xcodebuild test … -only-testing:TagwerkTests/PlanningModelTests` und Paket `TagwerkCore`.
- [ ] **Step 5: Im Simulator prüfen**, was EventKit beim Abhaken einer täglich wiederholten Erinnerung tut: Wird sie neu fällig oder bleibt sie erledigt? Das Ergebnis kommt ins Commit und in den Abschlussbericht. Ändert sich die ID, muss `didComplete` den Schlüssel vor dem Schreiben merken; dazu gibt es einen Test mit dem Fake.
- [ ] **Step 6: Commit** `feat: show remaining free time from now and free effort of completed occurrences`

### Task 2: Gleiche Termine zusammenfassen (I1, §13.11) – Issue #54

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/EventMerging.swift`
- Modify: `CalendarEvent.swift` (Feld `mergedCalendarIDs: [String]`, Standard `[]`), `AppSettings.swift` (`mergeDuplicateEvents: Bool = true`), `PlanningModel.swift`, `EventDetailView.swift`, `PlanningSettingsSection.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/EventMergingTests.swift`, `PlanningModelTests.swift`

**Interfaces:**
- Produces: `public func mergingDuplicates(_ events: [CalendarEvent], links: [String: TaskID]) -> [CalendarEvent]`.
  - Schlüssel: normalisierter Titel (wie `LinkResolver.normalized`), `start`, `end`, `isAllDay`.
  - Behalten wird bevorzugt der verknüpfte Termin, sonst der erste.
  - Die Kalender-IDs der anderen kommen in `mergedCalendarIDs`.
  - Termine aus demselben Kalender werden nie zusammengefasst.

- [ ] **Step 1: Failing tests**
  - `sameTitleAndTime_inTwoCalendars_becomesOne`
  - `sameCalendar_staysSeparate`
  - `differentEnd_staysSeparate`
  - `linkedCopy_isKept`
  - Modelltest: zwei „Seminar“-Termine ergeben eine Zeile in `timeline` und unveränderte `capacity.availableMinutes`. Ist `settings.mergeDuplicateEvents = false`, sind es zwei Zeilen.
- [ ] **Step 2: Implementieren.** `PlanningModel.reload` fasst nach `resolveLinks` zusammen; Kapazität und Deadlines rechnen weiter mit den ungefilterten Terminen. `EventDetailView` zeigt „In N Kalendern“. „Getrennt anzeigen“ setzt `mergeDuplicateEvents = false`, mit Hinweis auf die Einstellung. In den Einstellungen gibt es den Schalter „Gleiche Termine zusammenfassen“.
- [ ] **Step 3: Tests grün, im Simulator prüfen** (die Demo-Daten enthalten „Seminar“ doppelt), **Commit** `feat: merge identical events from several calendars`

### Task 3: Heute Fälliges und „Von früher offen“ (H1, §13.9) – Issue #53

**Files:** Modify `PlanningModel.swift`, `PlanStore.swift`, `DayView.swift`; Test `PlanningModelTests.swift`

**Interfaces:**
- Produces:
  - `DayPlan.dueToday: [TaskItem]`: offene Aufgaben mit Fälligkeit heute, ohne Arbeitstag und ohne Block heute. Nur gesetzt, wenn `day == today`.
  - `PlanningModel.overdue: [TaskItem]` ersetzt `leftovers`. Darin stehen Aufgaben mit Arbeitstag vor heute **oder** mit Fälligkeit vor heute und ohne Arbeitstag, jeweils offen. Sortiert nach Fälligkeit, dann Titel.

- [ ] **Step 1: Failing tests**
  - `dueToday_appearsAndCountsAsLoad`: Aufgabe „Abgabe“ mit Fälligkeit heute ergibt `dueToday` mit Aufgabe und `plannedMinutes` 30.
  - `dueToday_withAssignmentElsewhere_notShown`
  - `overdue_includesPastDueWithoutAssignment_notCounted`
  - `overdue_afterAssignToday_movesIntoAssigned`
  - `recurringReminderDueToday_countsOnceViaEffort`: eine wiederkehrende Erinnerung zählt nicht zusätzlich mit 30 min.
- [ ] **Step 2: Implementieren.** DayView bekommt die Abschnitte „Heute fällig“ und „Von früher offen“, letzterer mit „Heute“ und „Neu einplanen“.
- [ ] **Step 3: Tests grün, Simulator** („Literatur sichten“ steht unter „Heute fällig“, „Bericht überarbeiten“ unter „Von früher offen“), **Commit** `feat: show tasks due today and overdue tasks in today's plan`

### Task 4: Termine in allen Kalendern schreiben (J, §13.10) – Issue #55, Teil Daten

**Files:**
- Modify:
  - `app/Packages/RemindersKit/Sources/RemindersKit/CalendarStore.swift` und `EventKitGateway.swift`.
  - `CalendarEvent.swift`: neue Felder `isRecurring: Bool`, `isEditable: Bool` (Kalender beschreibbar und keine fremde Einladung), `isInvitation: Bool`, `notes: String?`, `location: String?`; alle mit Standardwerten.
  - `app/TagwerkTests/Fakes/FakeCalendarStore.swift`, `PlanningModel.swift`, `BlockPlanner.swift`.
- Test: `app/Packages/RemindersKit/Tests/RemindersKitTests/` (Regeln), `PlanningModelTests.swift`

**Interfaces:**
- Produces in `RemindersKit`:
  - `public enum EventSpan: Sendable { case thisEvent, futureEvents }`.
  - `public struct EventDraft: Sendable, Equatable { title, start, end, isAllDay, calendarID, notes: String?, location: String?, url: URL? }`.
  - `CalendarStore`:
    - `writableCalendars() -> [ListInfo]`
    - `createEvent(_ draft: EventDraft) throws -> CalendarEvent`
    - `updateEvent(id: String, with draft: EventDraft, span: EventSpan, expectedVersion: String?) throws -> CalendarEvent`
    - `deleteEvent(id: String, span: EventSpan, expectedVersion: String?) throws`
  - `moveBlock` und `deleteBlock` bleiben als dünne Hüllen bestehen. Sie rufen `updateEvent` bzw. `deleteEvent` mit `.thisEvent` auf.
  - `CalendarBlockRules.checkEditable(_ event: CalendarEvent) throws`: wirft `TaskWriteError.failed("Dieser Termin kann in Tagwerk nicht geändert werden.")`.
- Produces in `PlanningModel`:
  - `createEvent(_ draft: EventDraft) async -> CalendarEvent?`
  - `updateEvent(_ event: CalendarEvent, with draft: EventDraft, span: EventSpan) async`
  - `deleteEvent(_ event: CalendarEvent, span: EventSpan) async`
  - `var writableCalendars: [ListInfo]`
  - `var defaultEventCalendarID: String?` liefert den Plan-Kalender.

- [ ] **Step 1: Failing tests**
  - Regeln: `checkEditable_readOnlyCalendar_throws`, `checkEditable_invitation_throws`.
  - Modell mit Fake:
    - `updateEvent_changesTitleAndTime`
    - `updateEvent_staleVersion_conflictNoChange`
    - `deleteEvent_readOnly_errorAndUnchanged`
    - `createEvent_defaultsToPlanCalendar`
    - `updateRecurring_thisEvent_onlyOccurrence`: Der Fake simuliert Vorkommen mit `id|sekunden`.
- [ ] **Step 2: EventKit umsetzen.**
  - `isEditable` ergibt sich aus `calendar.allowsContentModifications` und `!isInvitation`.
  - `isInvitation` gilt, wenn `hasAttendees` und der Organisator nicht `isCurrentUser` ist.
  - `isRecurring` entspricht `hasRecurrenceRules`.
  - `span` wird auf `EKSpan` abgebildet.
- [ ] **Step 3: Tests grün, Commit** `feat: create, change and delete events in all writable calendars`

### Task 5: Blöcke ändern, Lücken und Raster (Modell, C1–C3) – Issue #47, Teil Modell

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/TimeGrid.swift`
- Modify: `PlanningModel.swift`, `BlockPlanner.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/TimeGridTests.swift`, `PlanningModelTests.swift`

**Interfaces:**
- Produces in `TagwerkCore`:
  - `public func snapped(minutes: Int, step: Int = 15) -> Int`: rundet auf den nächsten Schritt.
  - `public func clampedBlock(startMinutes: Int, duration: Int, dayLength: Int) -> Range<Int>`: bleibt in `0..<dayLength`, Mindestdauer 15.
  - `public func freeGaps(hours: WorkHours, busy: [Range<Int>], lunch: Range<Int>?, buffer: Int, from: Int?, minimum: Int = 15) -> [Range<Int>]`
- Produces in `PlanningModel`:
  - `moveBlock(_ block: CalendarEvent, toStartMinutes: Int, on day: PlanDay) async`
  - `resizeBlock(_ block: CalendarEvent, minutes: Int) async`
  - `deleteBlock(_ block: CalendarEvent) async`
  - `gaps(for plan: DayPlan) -> [Range<Int>]`
  - `createBlock(for:start:minutes:)` bleibt.

- [ ] **Step 1: Failing tests**
  - `snapped_roundsToQuarterHour` (7→0, 8→15, 52→45)
  - `clampedBlock_beforeMidnightStaysOnDay`: Start 23:30 mit 60 min ergibt `1380..<1440`.
  - `clampedBlock_negativeStartClampsToZero`
  - `freeGaps_betweenEventsWithBuffer`: Arbeit 9–18, Termin 10–11, Puffer 10, Mittag 12–13 ergibt `[540..<590, 670..<720, 780..<1080]`.
  - `freeGaps_today_startsAtNow`
  - Modell:
    - `moveBlock_changesEventAndAssignment` (anderer Tag setzt den Arbeitstag)
    - `resizeBlock_keepsStart`
    - `deleteBlock_removesEvent_assignmentStays`
    - `moveBlock_conflict_setsLastError`
- [ ] **Step 2: Implementieren** (die Blöcke laufen über `updateEvent` aus Task 4).
- [ ] **Step 3: Tests grün, Commit** `feat: move, resize and delete time blocks`

### Task 6: Tagesansicht – Kopf, Wischen, Restzeit, Abschnitte (A1, B1) – Issue #45

**Files:**
- Create: `app/Tagwerk/Planning/DayHeader.swift`, `app/Tagwerk/Planning/DatePickerPopover.swift`
- Modify: `PlanView.swift`, `DayView.swift`, `DeadlineCard.swift`, `CapacityBar.swift`

**Interfaces:**
- Consumes: `DayCapacity.remainingMinutes`, `DayPlan.isPast` (Task 1), `dueToday` und `overdue` (Task 3).
- Produces: `PlanView` zeigt den Datumskopf nur für Woche und Monat; der Tag zeichnet `DayHeader` selbst. `PlanningModel.step(_ direction: Int)` wandert aus `PlanView` ins Modell, damit Wischen und Pfeile dieselbe Logik nutzen. Dazu gibt es einen Test `step_day_week_month`.

- [ ] **Step 1: Failing test** `step_day_week_month` (aus `PlanView.step` übernommen), dann verschieben.
- [ ] **Step 2: UI nach Mockup A1.**
  - Kopfzeile „HEUTE · KW 47“ bzw. „vor 2 Tagen“, darunter ein großer Datumstitel (`.largeTitle`, 28 pt) mit ⌄.
  - Antippen öffnet `DatePickerPopover` (`DatePicker(.graphical)` als `.popover` mit `.presentationCompactAdaptation(.popover)`) mit „Heute“ und „Monatsansicht ›“.
  - Waagerechtes Wischen über `DragGesture(minimumDistance: 30)` am Listen-Container wechselt den Tag, wenn |dx| > 80 und |dx| > 2·|dy|. Mit `.refreshable` testen.
  - Die Wischaktionen „Zeitblock“ und „Ausplanen“ entfallen; beide wandern ins Kontextmenü der Zeile.
  - Die Kapazitätskarte zeigt `CapacityText.remaining` (heute), „Vergangen“ (`isPast`) oder wie bisher.
  - „Ganztägig“ wird als Chip-Zeile dargestellt.
- [ ] **Step 3: Simulator:** Wischen links und rechts, Popover mit Auswahl, Restzeit an heute, morgen und gestern; Screenshots ansehen.
- [ ] **Step 4: Commit** `feat: redesign the day header with swipe and date picker`

### Task 7: Zeitleiste mit Block-Menü, Lücken und Stundenraster (C1–C3, Schalter) – Issue #47, Teil UI

**Files:**
- Create: `app/Tagwerk/Planning/TimelineList.swift` (Zeilen und Lücken), `app/Tagwerk/Planning/HourGrid.swift` (Raster), `app/Tagwerk/Planning/BlockMenu.swift`
- Modify: `DayView.swift`, `AppSettings.swift` (`dayTimelineStyle: String = "list"`; Werte `list` und `grid`)

**Interfaces:**
- Consumes: `moveBlock`, `resizeBlock`, `deleteBlock`, `gaps`, `createBlock` (Task 5); `updateEvent` (Task 4).

- [ ] **Step 1: Schalter** im Abschnittskopf „Ablauf“ (Symbol `list.bullet` bzw. `calendar.day.timeline.left`), gespeichert in `dayTimelineStyle`.
- [ ] **Step 2: Liste (C1, C2).**
  - Antippen eines Blocks öffnet `BlockMenu`: Beginn −15/+15, Dauer −15/+15, „Auf anderen Tag …“, „Aufgabe zeigen“, „Löschen“.
  - Antippen eines fremden Termins öffnet die Termin-Detailansicht (Task 8).
  - Lückenzeilen „frei 13:00–14:30“ sind Drop-Ziele (`dropDestination(for: String.self)`). Eine abgelegte Aufgabe wird ein Block zur Lücken-Startzeit mit `estimateMinutes ?? 60`.
- [ ] **Step 3: Raster (C3).**
  - `ScrollView` mit 60 pt pro Stunde, Termine maßstäblich, Überlappungen nebeneinander. Die Spaltenaufteilung ist eine reine Funktion `columns(for: [Range<Int>]) -> [Int]` in `TimeGrid.swift` mit Test `columns_overlapsSideBySide`.
  - Blöcke ziehen (Körper = verschieben, Griff unten = Dauer) mit `snapped`; Loslassen ruft `moveBlock` bzw. `resizeBlock`.
  - Bei Bedienungshilfen-Schriftgrößen zeigt der Schalter einen Hinweis, das Raster bleibt aber wählbar.
- [ ] **Step 4: Simulator:** einen Block per Menü um 15 min verschieben, im Raster ziehen und die Dauer ändern, eine Aufgabe in eine Lücke ziehen. Danach die Kalender-Termine prüfen (ein frischer Start mit Demo-Daten zeigt sie).
- [ ] **Step 5: Commit** `feat: edit time blocks from the timeline and an hour grid`

### Task 8: Termin-Detail, Kurzform und Systemeditor (J1, J2, J4–J6) – Issue #55, Teil UI

**Files:**
- Create: `app/Tagwerk/Planning/EventEditSheet.swift` (Kurzform), `app/Tagwerk/Planning/SystemEventEditor.swift` (`UIViewControllerRepresentable` für `EKEventEditViewController`)
- Modify: `EventDetailView.swift`, `DayView.swift` (＋ im Kopf: „Neuer Termin“), `project.yml` (EventKitUI, falls nötig)

**Interfaces:** Consumes Task 4 (`EventDraft`, `EventSpan`, `writableCalendars`, `defaultEventCalendarID`, `isEditable`, `isInvitation`).

- [ ] **Step 1: Detail.**
  - Schreibgeschützter Kalender: Kopfzeile mit Grund, keine Bearbeiten-/Löschen-Aktionen (J4).
  - Einladung: „Eingeladen von“ und „In Kalender-App antworten“ (J5).
  - Sonst: „Bearbeiten“ und „Termin löschen“. Bei Serien fragt ein `confirmationDialog` nach „Nur diesen Termin …“ / „Diesen und alle folgenden …“ (J6).
  - „Aufgabe öffnen“ heißt jetzt „Aufgabe zeigen“ (G3, Task 11).
- [ ] **Step 2: Kurzform.**
  - Felder: Titel, Ganztägig, Beginn, Ende, Kalender (beschreibbare zuerst, nicht beschreibbare gedimmt mit Grund), Notiz.
  - Abgleich mit der freien Zeit des Tages als Zeile („passt in die Lücke 14:00–15:30“ oder „überschneidet Seminar“).
  - „Weitere Optionen …“ öffnet `SystemEventEditor` für denselben Termin. Bei neuen Terminen wird zuerst gespeichert, dann geöffnet.
- [ ] **Step 3: Simulator:**
  - einen neuen Termin im Plan-Kalender anlegen
  - „Seminar“ umbenennen
  - einen Feiertag öffnen: keine Bearbeitung möglich
  - einen Serientermin der Demo-Daten mit „Nur diesen“ verschieben (vorher Serie „Sport“ wöchentlich zu `DemoData` hinzufügen)
- [ ] **Step 4: Commit** `feat: view, create and edit events in Tagwerk`

### Task 9: Planung im Bearbeiten-Sheet (C4, G4) – Issue #48

**Files:** Create `app/Tagwerk/Editor/PlannedSection.swift`; Modify `TaskEditorView.swift`, `RootView.swift`, `TaskListView.swift`; Test `PlanningModelTests.swift`

**Interfaces:**
- Consumes: Task 5 (`moveBlock`, `resizeBlock`, `deleteBlock`), `assign` und `resolveBlocks`, `recurringItem(for:on:)`, `setRecurringEffort`.
- Produces: `PlanningModel.assign(_ id: TaskID, to day: PlanDay, moveBlocks: Bool) async` ohne Dialog; `assign(_:to:)` bleibt für den Dialogweg.

- [ ] **Step 1: Failing test** `assign_withMoveBlocksFlag_movesWithoutPendingDecision`; dann implementieren.
- [ ] **Step 2: `PlannedSection`.**
  - Zeile „Arbeitstag“: `DatePicker` plus Knopf „Zum Tag ›“.
  - Schalter „Zeitblöcke mitverschieben“.
  - Je Block: Beginn (`DatePicker .hourAndMinute`), Dauer (`EstimateField`), Löschen.
  - „Zeitblock hinzufügen“ öffnet `BlockSheet`.
  - Änderungen gelten erst mit „Sichern“ des Sheets; ein Abbruch verwirft sie.
- [ ] **Step 3: Wiederkehrende Erinnerungen (G4).**
  - Karte „Erinnerung“ mit Titel und Fälligkeit; der Hinweis „gilt für alle Tage“ ist fest.
  - Karte „In Tagwerk“ mit Aufwand und „Nur heute / Alle ab heute“ (`setRecurringEffort`).
- [ ] **Step 4: Simulator:** Block von „Pretest vorbereiten“ im Sheet auf 16:00 und 90 min setzen und sichern, Tagesansicht prüfen. „Training“ öffnen und beide Karten prüfen.
- [ ] **Step 5: Commit** `feat: edit planned day and time blocks in the task editor`

### Task 10: Ablage „Ungeplant“ und Monatsauswahl (D1, E1, E2) – Issues #49, #50

**Files:** Create `app/Tagwerk/Planning/UnplannedDrawer.swift`, `app/Tagwerk/Planning/MonthDayDetail.swift`; Modify `WeekView.swift`, `MonthView.swift`, `PlanView.swift`, `PlanningModel.swift`; Test `PlanningModelTests.swift`

**Interfaces:**
- Produces:
  - `PlanningModel.unplannedSections(search: String) -> (dueInRange: [TaskItem], other: [TaskItem])`.
  - `PlanningModel.selectedDay: PlanDay?` für den Monat; Standard ist heute, wenn heute im Monat liegt, sonst der Erste.

- [ ] **Step 1: Failing tests**
  - `unplannedSections_dueInRangeFirst_thenOthers`
  - `unplannedSections_searchFiltersBoth`
  - `selectedDay_defaultsToTodayInMonth_elseFirst`
- [ ] **Step 2: Ablage (D1).**
  - Untere Leiste „Ungeplant · N“, die per Tipp oder Ziehen ein Sheet mit `presentationDetents([.height(72), .medium, .large])`, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` und `.interactiveDismissDisabled()` öffnet.
  - Inhalt: Suche, zwei Abschnitte, Zeilen ziehbar (`draggable`), dazu „＋“ je Zeile mit einem Tagesmenü der Woche.
  - Am Gerät prüfen, ob Ziehen aus einem Sheet in die Woche funktioniert. Sonst fällt die Ablage auf ein `safeAreaInset`-Panel mit eigenem Höhenwechsel zurück. Die Entscheidung wird im Commit vermerkt.
- [ ] **Step 3: Monat (E1, E2).**
  - Tippen wählt einen Tag (Rahmen) und zeigt darunter `MonthDayDetail` mit Deadlines, Terminen, Aufgaben und „Tag öffnen ›“.
  - Ein zweiter Tipp auf denselben Tag öffnet „Tag“.
  - Langes Drücken öffnet ein `contextMenu` mit „Tag öffnen“, „Aufgabe hier einplanen …“, „Neuer Termin“ und „Arbeitszeit an diesem Tag …“.
- [ ] **Step 4: Simulator:** Woche und Ablage in allen Höhen, eine Aufgabe auf Donnerstag ziehen, den Monat antippen, ein zweiter Tipp, langes Drücken.
- [ ] **Step 5: Commit** `feat: add the unplanned drawer and day selection in the month`

### Task 11: Kontextmenü F1 und Aufgaben-Tab (F1/F2, G1–G3, ↻) – Issues #51, #52

**Files:** Modify `TaskContextMenu.swift`, `TaskListView.swift`, `TaskRow.swift`, `TaskListModel.swift`, `RootView.swift`, `PlanView.swift`, `WeekView.swift`, `DayView.swift`; Test `TaskListModelTests.swift`, `PlanningModelTests.swift`

**Interfaces:**
- Produces:
  - `TaskListModel.highlightedTaskID: TaskID?` mit `highlight(_ id: TaskID)`, das sich nach 2 s selbst löscht. Testbar über einen injizierten `clearAfter`-Schlafer oder eine prüfbare Methode `clearHighlight()`.
  - `PlanningModel.planToday(_ ids: [TaskID]) async` mit Summe `plannedMinutes(for ids: [TaskID]) -> Int`.
  - `TaskMenuActions.dueText: String?` (aktuelle Fälligkeit für den Abschnittstitel) und `sourceName: String` („GitHub“, „Erinnerung“, „Tagwerk“).

- [ ] **Step 1: Failing tests**
  - `planToday_assignsAllWithoutWritingSource`
  - `plannedMinutes_usesEstimateOrDefault`
  - `highlight_setsAndClears`
- [ ] **Step 2: Menü F1.**
  - `Section("Einplanen · nur in Tagwerk")` mit zwei `ControlGroup`s zu je zwei beschrifteten Elementen (Heute/Morgen, Wochenende/Nächste Woche), dazu „Anderer Tag …“.
  - `Section("Fälligkeit · ändert \(sourceName)")` mit „Fälligkeit verschieben“ und dem aktuellen Wert.
  - Danach Erledigt, Aufwand ändern, Löschen.
  - Im Simulator prüfen. Erscheinen die Gruppen nicht als 2 × 2, gilt **F2**: eine Dreierreihe Heute/Morgen/Nächste Woche, Wochenende als Zeile.
  - Wird die Vorschau-Überlappung aus Screenshot 6 sichtbar, bekommt sie `.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22))`.
- [ ] **Step 3: Aufgaben-Tab.**
  - G1: „Auswählen“ in der Toolbar schaltet `EditMode`. Die untere Leiste zeigt „N ausgewählt · X h“ gegen die Restzeit heute und „Für heute einplanen“.
  - G2: führende Wischaktion „Heute“ neben „Erledigt“, in eigener Farbe.
  - G3: „Aufgabe zeigen“ aus Termin, Block und Monat ruft in `RootView` `selectedTab = 1` und `taskList.highlight(id)` auf. `TaskListView` scrollt per `ScrollViewReader` dorthin und hebt die Zeile 2 s hervor.
  - ↻ in `TaskRow` für wiederkehrende Erinnerungen. Die Information kommt aus `planning.recurringReminderIDs` und wird als Parameter übergeben.
- [ ] **Step 4: Simulator:** Menü in Aufgaben, Tag und Woche; drei Aufgaben auswählen und für heute einplanen; „Aufgabe zeigen“ aus einem Block.
- [ ] **Step 5: Commit** `feat: clearer planning menu, multi-select and task highlighting`

### Task 12: Abschluss

- [ ] `app/test-all.sh` ist grün.
- [ ] Ganzer Durchlauf im Simulator mit frischen Demo-Daten nach der Prüfliste der Issues #45–#55; Auffälligkeiten beheben.
- [ ] Auf das iPhone installieren (`TAGWERK_FORCE=1 ~/Library/Developer/Tagwerk/src/scripts/refresh-install.sh`).
- [ ] Issues #45–#55 auf „In review“ setzen (`t3gh move`), `t3gh sync`, Prüfliste für den Nutzer schreiben.
