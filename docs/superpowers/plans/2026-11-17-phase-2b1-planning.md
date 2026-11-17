# Phase 2b-1: Kalender & Planung – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ohne KI planen: Tag-, Wochen- und Monatsansicht mit Kapazität und wichtigen Deadlines, Aufgaben auf Tage ziehen, Zeitblöcke als echte Termine im Plan-Kalender, Verknüpfung Termin ↔ Aufgabe mit Sprung, wiederkehrender Aufwand, Gedrückthalten-Menü.

**Architecture:** Der Kalender ist die Quelle für Zeitblöcke (Design §4 A). Reine Logik (Tage, Arbeitszeit, Kapazität, Deadlines, Verknüpfung, Wiederholungen) liegt testbar in `TagwerkCore`. EventKit-Zugriff auf Termine kommt als `CalendarStore` in `RemindersKit`. Tageszuordnungen, Verknüpfungen, Aufwände und Tages-Abweichungen liegen in SwiftData im App-Target. Ein `PlanningModel` (`@MainActor @Observable`) verbindet alles für den neuen Tab „Planen“.

**Tech Stack:** wie Phase 2a (Swift 6, SwiftUI, SwiftData, EventKit, Swift Testing, XcodeGen); GitHub GraphQL für Epics.

**Spec:** `docs/superpowers/specs/2026-11-17-phase-2b-design.md` (§§ 4–7, 10, 11). Mockups: `docs/superpowers/mockups/2026-11-17-phase-2b-mockups.html`, freigegeben: a, b-A, c-A, d-A, e-A, f, g-A, h. Davor: Plan 2a, 2a-GitHub, 2a-Feinschliff (alle gemergt bzw. auf diesem Branch).

**Nicht in diesem Plan:** KI (Plan 2b-2), Benachrichtigungen und Hintergrund-Refresh (Plan 2b-3). Das Gedrückthalten-Menü bekommt hier keine KI-Einträge.

## Global Constraints

- Alle Global Constraints aus Plan 2a gelten weiter. Dazu gehören: SwiftData nur additiv ändern, nur geänderte Felder schreiben, Konfliktschutz, `app/test-all.sh` grün, keine persönlichen Daten.
- Tagwerk schreibt **nur** in den Plan-Kalender. Andere Kalender werden nur gelesen.
- Termine aus Zeitblöcken: Titel = Aufgabentitel, bei GitHub `#<Nummer> <Titel>`. URL-Feld `tagwerk://task/<quelle>/<prozentkodierte ID>`. Notiz „Geplant mit Tagwerk“.
- Standard-Arbeitszeit: Mo–Fr 09:00–18:00, Sa/So frei. Standard-Dauer für Aufgaben ohne Aufwand: 30 min.
- Einplanen (Arbeitstag) ≠ Fälligkeit (Design §11.1). Ziehen und „Einplanen …“ ändern nie die Quelle.
- Wichtige Deadline = P1 mit Fälligkeit, Epic (Label `epic`) mit „Due date“, oder Termin aus einem Deadline-Kalender (Design §6.2).
- Oberflächen nach den freigegebenen Mockups, Texte auf Deutsch. Der KI-Knopf aus Mockup e erscheint erst in 2b-2.

## Review Focus

1. **Termin im Plan-Kalender wird außerhalb geändert oder gelöscht:** Tagwerk zeigt den neuen Stand und stürzt beim nächsten Verschieben nicht ab. Schreibt es trotz veralteter Version, gibt es einen Konflikt, kein stilles Überschreiben. Test in Task 5.
2. **Zeitzonen- und Sommerzeitwechsel:** Ein Tag mit Zeitumstellung hat die richtige Länge in der Kapazität, und ein `PlanDay` verschiebt sich nicht. Test in Task 1.
3. **Plan-Kalender fehlt oder ist schreibgeschützt:** Das Schreiben von Blöcken ist gesperrt, mit „Neu anlegen“ oder „Anderen wählen“. Das Ziehen auf Tage funktioniert weiter. Test in Task 5.
4. **Aufgabe wird erledigt, gelöscht oder verschwindet aus der Quelle:** Ihre Tageszuordnung fällt weg, Termine bleiben. Es entstehen keine verwaisten Einträge in Woche und Monat. Test in Task 4.
5. **Wiederholungsregel, die Tagwerk nicht versteht** (z. B. „jeden 2. Dienstag“): Hinweis, Aufwand nur am nächsten Fälligkeitstag, kein Absturz. Test in Task 6.

---

### Task 1: Tage, Arbeitszeit und Kapazität (`TagwerkCore`)

**Files:**
- Create in `app/Packages/TagwerkCore/Sources/TagwerkCore/`: `PlanDay.swift`, `WorkSchedule.swift`, `Capacity.swift`, `CalendarEvent.swift`
- Test: `PlanDayTests.swift`, `WorkScheduleTests.swift`, `CapacityTests.swift`

**Interfaces (Produces, `public`, `Sendable`, `Hashable`, `Codable` wo sinnvoll):**
- `struct PlanDay: Comparable { year, month, day: Int }` mit `init(date: Date, calendar: Calendar)`, `func startDate(in: Calendar) -> Date`, `func adding(days: Int, calendar: Calendar) -> PlanDay`, `func weekday(in: Calendar) -> Int` (1 = So … 7 = Sa), `init(_ due: DueDate)`
- `struct WorkHours { startMinutes: Int; endMinutes: Int }` mit `var minutes: Int`
- `struct WeekSchedule { var hoursByWeekday: [Int: WorkHours] }` (fehlender Wochentag = frei), `static let standard` (2…6 → 540–1080)
- `enum DayOverride { case off, hours(WorkHours) }`
- `func workHours(on day: PlanDay, schedule: WeekSchedule, overrides: [PlanDay: DayOverride], calendar: Calendar) -> WorkHours?`
- `struct CalendarEvent: Identifiable { id: String; externalID: String?; calendarID: String; title: String; start: Date; end: Date; isAllDay: Bool; url: URL?; isBusy: Bool; version: String }`. Bei Serien enthält `id` das Datum des Vorkommens.
- `struct CapacityInput { hours: WorkHours?; lunchStartMinutes: Int; lunchMinutes: Int; bufferMinutes: Int; busyIntervals: [Range<Int>]; recurringMinutes: Int; plannedMinutes: Int; estimatedCount: Int }` (Intervalle in Minuten seit Tagesbeginn)
- `struct DayCapacity { availableMinutes: Int; plannedMinutes: Int; freeMinutes: Int; isOverbooked: Bool; isDayOff: Bool; estimatedCount: Int }`
- `func capacity(_ input: CapacityInput) -> DayCapacity`. Belegt ist die Vereinigung aus Mittagspause und den belegten Intervallen, letztere auf beiden Seiten um den Puffer erweitert und geschnitten mit der Arbeitszeit. `available = max(0, Arbeitszeit − belegt − wiederkehrend)`, `free = available − planned` (darf negativ sein), `isOverbooked = planned > available`.
- `func busyIntervals(events: [CalendarEvent], on day: PlanDay, calendar: Calendar, excluding linkedIDs: Set<String>) -> [Range<Int>]`. Ignoriert ganztägige Termine, Termine mit `!isBusy` und solche aus `linkedIDs`. Schneidet an den Tagesgrenzen ab.

- [ ] **Step 1: Failing tests.** Kalender Berlin, `firstWeekday = 2`.
  - `planDay_survivesTimeZoneChange` (`PlanDay(2026,11,20)` bleibt in New York der 20.)
  - `planDay_addingAcrossDST_isCalendarDay` (`PlanDay(2026,3,28).adding(days: 1)` ist der 29.03., `startDate` 00:00)
  - `workHours_standardWeek` (Mi 18.11. → 540–1080; Sa 21.11. → `nil`)
  - `workHours_overrideWins` (`.hours(600–1200)` am Sa → 600–1200; `.off` am Mi → `nil`)
  - `capacity_noEvents`: 9 h Arbeitszeit, 60 min Mittag → 480
  - `capacity_eventWithBuffer`: Termin 10:00–11:00, Puffer 10 → 480 − 80 = 400
  - `capacity_adjacentEventsShareBuffer`: 10–11 und 11–12 → 480 − 140 = 340
  - `capacity_eventOverlappingLunch`: 11:30–12:30 bei Mittag 12–13 → belegt 11:20–13:00, 420 − 100 = 380
  - `capacity_recurringAndPlanned`: wiederkehrend 180, geplant 360 → available 300, free −60, `isOverbooked`
  - `capacity_dayOff`: `hours == nil` → available 0, `isDayOff`
  - `busyIntervals_skipsAllDayFreeAndLinked`
  - `busyIntervals_clipsMultiDayEvent` (Termin 17.11. 22:00 bis 18.11. 02:00 → am 18. `0..<120`)
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(core): add plan days, work schedule and capacity`.

### Task 2: Wichtige Deadlines und Epics

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/ImportantDeadline.swift`. Test: `ImportantDeadlineTests.swift`
- Modify: `TagwerkCore/TaskItem.swift` (additiv: `var epic: EpicInfo? = nil`), `GitHubKit/ProjectsQuery.swift` (`parent` im Issue-Teil), `GitHubKit/GitHubIssueRecord.swift` (`var parent: ParentIssue?`, mit Standardwert beim Dekodieren), `GitHubKit/GitHubMapping.swift`. Tests: `GitHubKitTests/GitHubEpicTests.swift`, Fixture-Ergänzung.

**Interfaces:**
- `struct EpicInfo { id: String; number: Int; title: String; due: DueDate?; isEpic: Bool }` (`isEpic` = Label `epic`)
- `TaskItem.isEpic: Bool` (additiv, Standard `false`; GitHub setzt es bei Label `epic`)
- `enum DeadlineKind { case priorityOne, epic, deadlineCalendar }`
- `struct ImportantDeadline: Identifiable { id: String; title: String; day: PlanDay; time: Date?; kind: DeadlineKind; taskID: TaskID?; eventID: String? }`
- `func importantDeadlines(tasks: [TaskItem], events: [CalendarEvent], deadlineCalendarIDs: Set<String>, in range: ClosedRange<PlanDay>, calendar: Calendar) -> [ImportantDeadline]`. Ein Epic, das nicht in `tasks` steht, kommt über `task.epic` hinein und wird über die Epic-ID dedupliziert. Sortiert nach Tag und Uhrzeit.
- GraphQL: `parent { ... on Issue { id number title labels(first: 20) { nodes { name } } projectItems(first: 5) { nodes { project { id } fieldValues(first: 20) { … Due date … } } } } }`. Das „Due date“ des Parents kommt aus seinem ersten Project-Item mit einem Wert in diesem Feld.

- [ ] **Step 1: Failing tests:** `deadlines_includeP1WithDueOnly` (P1 ohne Fälligkeit fehlt, P2 fehlt), `deadlines_epicFromParentDeduplicated` (zwei Sub-Issues desselben Epics → ein Eintrag), `deadlines_deadlineCalendarEvents_allDayAndTimed`, `deadlines_outsideRangeExcluded`; GitHub: `api_readsParentEpicWithDueDate`, `mapping_epicLabel_setsIsEpic`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementieren. Danach die erweiterte Suche lesend gegen die echte API prüfen (`gh api graphql`, nur Fehler und Anzahl ausgeben).
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: detect important deadlines including GitHub epics`.

### Task 3: Termine lesen und Plan-Kalender (`RemindersKit`)

**Files:**
- Create: `RemindersKit/CalendarStore.swift`, `RemindersKit/TaskLinkURL.swift` (oder in TagwerkCore, siehe Interfaces). Test: `RemindersKitTests/CalendarStoreTests.swift` mit `FakeCalendarStore`, `TagwerkCoreTests/TaskLinkURLTests.swift`
- Modify: `EventKitGateway.swift` (konformiert zu `CalendarStore`)

**Interfaces:**
- `TagwerkCore`: `enum TaskLinkURL { static func make(_ id: TaskID) -> URL; static func parse(_ url: URL) -> TaskID? }`. Format `tagwerk://task/<source>/<id>`, die ID wird mit `.urlPathAllowed` ohne `/` prozentkodiert. `TaskID.key: String` (`"<source>:<rawValue>"`) und `init?(key:)`.
- `struct BlockDraft { title: String; start: Date; end: Date; taskID: TaskID }`
- `@MainActor protocol CalendarStore: AnyObject { func events(in: DateInterval, calendarIDs: Set<String>?) -> [CalendarEvent]; func event(id: String) -> CalendarEvent?; func planCalendar(id: String?) -> ListInfo?; func createPlanCalendar(named: String) throws -> ListInfo; func createBlock(_ draft: BlockDraft, in calendarID: String) throws -> CalendarEvent; func moveBlock(id: String, to start: Date, end: Date, expectedVersion: String?) throws -> CalendarEvent; func deleteBlock(id: String, expectedVersion: String?) throws }`
- `EventKitGateway`: `isBusy = availability != .free && participationStatus != .declined`. `version = lastModifiedDate`. Neuer Kalender: Quelle iCloud (`EKSource.sourceType == .calDAV` und Titel „iCloud“), sonst `.local`. `moveBlock` und `deleteBlock` werfen `TaskWriteError.conflict` bei abweichender Version und `.notFound`, wenn der Termin fehlt. Bei Serien wirken sie nur auf das Vorkommen (`.thisEvent`).

- [ ] **Step 1: Failing tests:** `taskLinkURL_roundTripsGitHubNodeID` (ID mit `=`, `_` und `/`), `taskLinkURL_rejectsForeignURL`, `taskID_keyRoundTrip`; Fake-basiert: `createBlock_setsURLAndTitle`, `moveBlock_staleVersion_throwsConflict`, `deleteBlock_missing_throwsNotFound`.
- [ ] **Step 2–4:** FAIL → implementieren → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: read calendar events and write blocks to the plan calendar`.

### Task 4: Tageszuordnungen, Abweichungen und Einstellungen (SwiftData)

**Files:**
- Create: `app/Tagwerk/Planning/DayAssignment.swift`, `DayOverrideRecord.swift`, `PlanStore.swift`, `app/Tagwerk/Persistence/ReminderEstimateRecord.swift`. Test: `app/TagwerkTests/PlanStoreTests.swift`
- Modify: `RemindersKit/RemindersTaskProvider.swift` (optionaler `EstimateStore`; `editableFields` + `.estimate`, wenn gesetzt; `apply` schreibt `estimateMinutes` nur in den Store, nie nach EventKit). Test: `RemindersTaskProviderTests.estimate_storedLocallyNotInEventKit`
- Modify: `AppSettings.swift` (additiv: `weekScheduleData: Data?`, `planCalendarID: String?`, `deadlineCalendarIDs: [String]? = nil`, `defaultTaskMinutes: Int = 30`, Zugriff `weekSchedule: WeekSchedule` mit Standard), `ModelContainerFactory.swift`

**Interfaces:**
- `@Model DayAssignment { taskKey: String (unique); year, month, day: Int; order: Int; createdAt: Date }`
- `@Model DayOverrideRecord { year, month, day: Int (eindeutig je Tag); isOff: Bool; startMinutes: Int?; endMinutes: Int? }`
- `@MainActor final class PlanStore` mit `init(context:)`:
  - `assign(_ id: TaskID, to day: PlanDay)`, `unassign(_ id: TaskID)`, `assignment(for: TaskID) -> PlanDay?`, `assignments(in: ClosedRange<PlanDay>) -> [TaskID: PlanDay]`
  - `leftovers(before today: PlanDay, openTaskIDs: Set<TaskID>) -> [TaskID]`
  - `prune(keeping openTaskIDs: Set<TaskID>)` entfernt Zuordnungen von Aufgaben, die es nicht mehr offen gibt (Design §11.8)
  - `override(on: PlanDay) -> DayOverride?`, `setOverride(_: DayOverride?, on: PlanDay)`, `overrides(in:) -> [PlanDay: DayOverride]`
- `RemindersKit`: `@MainActor protocol EstimateStore: AnyObject { func minutes(for reminderID: String) -> Int?; func setMinutes(_: Int?, for reminderID: String) }`. Die App implementiert es mit `@Model ReminderEstimateRecord { reminderID: String (unique); minutes: Int }` (Design §5.1, lokale Aufwandsschätzung für Erinnerungen).

- [ ] **Step 1: Failing tests:** `assign_replacesPreviousDay` (eine Zuordnung je Aufgabe), `leftovers_onlyOpenPastAssignments`, `prune_removesCompletedOrMissing`, `override_setAndClear`, `settings_weekSchedule_defaultsToStandard`, `settings_weekSchedule_roundTrip`.
- [ ] **Step 2–4:** FAIL → implementieren → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: store day assignments, day overrides and planning settings`.

### Task 5: Zeitblöcke und Verknüpfungen

**Files:**
- Create: `TagwerkCore/LinkResolver.swift` (Test `LinkResolverTests.swift`), `app/Tagwerk/Planning/EventTaskLink.swift`, `app/Tagwerk/Planning/BlockPlanner.swift` (Test `app/TagwerkTests/BlockPlannerTests.swift`)

**Interfaces:**
- `enum LinkOrigin: String { case url, manual, automatic }`
- `struct ResolvedLink { eventID: String; taskID: TaskID; origin: LinkOrigin }`
- `func resolveLinks(events: [CalendarEvent], tasks: [TaskItem], manual: [String: TaskID]) -> [ResolvedLink]` mit der Reihenfolge aus Design §6.4. Automatischer Treffer über `#<Nummer>` nur bei genau einem Issue mit dieser Nummer. Exakter Titel nach Normalisierung (kleingeschrieben, Leerraum zusammengefasst) nur bei genau einer Erinnerung oder lokalen Aufgabe. Mehrdeutig → kein Link.
- `@Model EventTaskLink { eventKey: String (unique); taskKey: String; createdAt: Date }`
- `@MainActor final class BlockPlanner` mit `init(store: CalendarStore, planStore: PlanStore, settings: AppSettings)`:
  - `var canWriteBlocks: Bool` (Plan-Kalender vorhanden und schreibbar)
  - `createBlock(for: TaskItem, start: Date, minutes: Int) throws -> CalendarEvent` setzt zusätzlich den Arbeitstag auf den Tag des Blocks (Design §11.3)
  - `futureBlocks(for: TaskID, after: Date) -> [CalendarEvent]`
  - `moveFutureBlocks(of: TaskID, to day: PlanDay)` behält die Uhrzeiten; `deleteFutureBlocks(of: TaskID)`
  - `link(eventID: String, to: TaskID)`, `unlink(eventID:)`
  - Fehlt der Plan-Kalender: `TaskWriteError.failed("Kein Plan-Kalender")`

- [ ] **Step 1: Failing tests:** `resolve_urlWins`, `resolve_manualBeforeAutomatic`, `resolve_issueNumberUnique`, `resolve_issueNumberAmbiguous_noLink`, `resolve_exactReminderTitle`; `createBlock_setsDayAssignment`, `createBlock_withoutPlanCalendar_throws`, `moveFutureBlocks_keepsTimeAndSkipsPast`, `staleBlock_moveThrowsConflict` (der Fake ändert die Version extern).
- [ ] **Step 2–4:** FAIL → implementieren → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: create time blocks and resolve event links`.

### Task 6: Wiederkehrender Aufwand

**Files:**
- Create: `TagwerkCore/Recurrence.swift` (Test `RecurrenceTests.swift`), `app/Tagwerk/Planning/RecurringEffortRecord.swift`, `app/Tagwerk/Planning/RecurringEffortStore.swift` (Test `RecurringEffortStoreTests.swift`)
- Modify: `RemindersKit/ReminderRecord.swift` (additiv: `var recurrence: RecurrenceRule?`), `EventKitGateway.record(_:)` (EK-Regel abbilden, nicht unterstützt → `.unsupported`)

**Interfaces:**
- `enum RecurrenceRule { case daily(interval: Int), weekly(interval: Int, weekdays: Set<Int>), monthly(interval: Int, day: Int), unsupported }`. Ende als `end: PlanDay?` bzw. `count: Int?` in `struct Recurrence { rule; start: PlanDay; end: PlanDay?; count: Int? }`.
- `func occurrences(of: Recurrence, in: ClosedRange<PlanDay>, calendar: Calendar) -> [PlanDay]`. `.unsupported` → nur `start`, falls im Bereich.
- `@Model RecurringEffortValue { reminderID: String; fromYear, fromMonth, fromDay: Int; minutes: Int }` (Grundwert ab einem Tag)
- `@Model RecurringEffortOverride { reminderID: String; year, month, day: Int; minutes: Int }`
- `@MainActor final class RecurringEffortStore`: `minutes(for reminderID: String, on: PlanDay) -> Int?` (Override vor dem jüngsten Grundwert mit `from ≤ Tag`), `setForAll(_ minutes: Int?, reminderID:, from: PlanDay)`, `setForDay(_ minutes: Int, reminderID:, day:)`, `reservedMinutes(on: PlanDay, reminders: [ReminderRecord], calendar:) -> Int`

- [ ] **Step 1: Failing tests:** `daily_everyDay`, `weekly_monWedFri`, `weekly_everySecondWeek`, `monthly_day31_skipsShortMonths`, `countLimitsOccurrences`, `unsupported_onlyStartDay`; Store: `setForAll_fromToday_keepsPastValue` (3 h bis gestern, 2 h ab heute), `setForDay_overridesOnlyThatDay`, `override_zero_removesEffort`, `reservedMinutes_sumsOccurringSeries`.
- [ ] **Step 2–4:** FAIL → implementieren → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: reserve time for recurring reminders`.

### Task 7: PlanningModel

**Files:**
- Create: `app/Tagwerk/Planning/PlanningModel.swift`. Test: `app/TagwerkTests/PlanningModelTests.swift` (Fakes: `FakeTaskProvider`, `FakeCalendarStore`, In-Memory-SwiftData)

**Interfaces:**
- `enum PlanScope { case day, week, month }`
- `struct DayPlan { day: PlanDay; capacity: DayCapacity; deadlines: [ImportantDeadline]; events: [CalendarEvent]; blocks: [CalendarEvent]; assigned: [TaskItem]; links: [String: TaskID]; isPastDue: Set<TaskID> }`. `isPastDue` enthält Aufgaben, deren Arbeitstag nach der Fälligkeit liegt.
- `@MainActor @Observable final class PlanningModel` mit `init(taskList: TaskListModel, calendarStore: CalendarStore, planStore: PlanStore, efforts: RecurringEffortStore, blocks: BlockPlanner, settings: AppSettings, reminders: () -> [ReminderRecord], now: () -> Date, calendar: Calendar)`:
  - `var scope: PlanScope`, `var anchor: PlanDay`, `private(set) var days: [DayPlan]`, `private(set) var unplanned: [TaskItem]`, `private(set) var leftovers: [TaskItem]`
  - `func reload()` liest den Zeitraum des Scopes (Woche Mo–So, Monat volle Wochen).
  - `assign(_: TaskID, to: PlanDay)` fragt bei vorhandenen zukünftigen Blöcken über `pendingBlockDecision` nach. Dazu `resolveBlocks(move: Bool)`. `unassign(_:)`.
  - `setDayOverride(_: DayOverride?, on:)`
  - `plannedMinutes(on:)`: Für Aufgaben mit Blöcken an diesem Tag zählen nur die Blöcke. Sonst zählt der Aufwand oder `defaultTaskMinutes` (als geschätzt). Verknüpfte Termine zählen als Planung (Design §11.4).

- [ ] **Step 1: Failing tests:** `reload_week_hasSevenDaysMondayFirst`, `reload_month_coversFullWeeks`, `capacity_countsLinkedEventAsPlannedNotBusy`, `capacity_defaultMinutesForTasksWithoutEstimate`, `unplanned_excludesAssignedAndCompleted`, `leftovers_showPastOpenAssignments`, `assign_afterDue_marksPastDue`, `assign_withFutureBlocks_asksAndMoves`, `dayOverride_changesCapacity`.
- [ ] **Step 2–4:** FAIL → implementieren → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat: add planning model for day, week and month`.

### Task 8: Planen-Tab (Mockups a, b-A, c-A)

**Files:**
- Create: `app/Tagwerk/Planning/PlanView.swift` (Segmented Tag/Woche/Monat, Navigation vor/zurück, „Heute“), `DayView.swift`, `WeekView.swift`, `MonthView.swift`, `CapacityBar.swift`, `DeadlineCard.swift`, `UnplannedTray.swift`, `DayOverrideSheet.swift`
- Modify: `RootView.swift` (Tabs „Planen“ | „Aufgaben“ | „Einstellungen“), `AppEnvironment.swift` (Stores, `PlanningModel`, Reload bei EventKit-Änderung)

**Interfaces:** Konsumiert `PlanningModel` (Task 7). Ziehen über `.draggable(TaskID.key)` und `.dropDestination(for: String.self)`. Jede Ziehaktion gibt es zusätzlich über das Menü aus Task 9, für VoiceOver auch als `accessibilityAction`.

- [ ] **Step 1:** UI-Tests für die Logik, die die Views brauchen, gibt es schon in Task 7. Hier kommt ein Test für die Ansichtsdaten dazu: `PlanningModelTests.dayView_ordersRowsByTime_allDayFirst`. Danach FAIL → implementieren.
- [ ] **Step 2:** Views nach den Mockups bauen:
  - Tag: Deadline-Karte fest oben, Kapazitätskarte mit Rechnung, Zeitleiste als Zeilen, Abschnitt „Von früher übrig“ mit „Auf heute“ und „Neu einplanen“. Die Arbeitszeit des Tages ist über die Kapazität änderbar (`DayOverrideSheet`).
  - Woche: Tage als Zeilen, Kapazitätsbalken, Deadline-Markierung, Ablage „Ungeplant“ unten.
  - Monat: Auslastungsbalken je Tag, Deadline als gefüllte Zelle, Deadline-Liste darunter. Tippen öffnet den Tag.
- [ ] **Step 3:** `app/test-all.sh` → grün. Im Simulator jede Ansicht einmal öffnen und Screenshots ansehen.
- [ ] **Step 4:** Commit `feat: add the planning tab with day, week and month`.

### Task 9: Gedrückthalten, Termin ↔ Aufgabe, Aufwand-Sheet (Mockups d-A, g-A, h)

**Files:**
- Create: `app/Tagwerk/Tasks/TaskContextMenu.swift`, `app/Tagwerk/Planning/EventDetailView.swift`, `app/Tagwerk/Planning/RecurringEffortSheet.swift`
- Modify: `TaskListView.swift`, `DayView.swift`, `WeekView.swift` (Kontextmenü an jeder Aufgabe), `TaskEditorView.swift` (Abschnitt „Geplant“ mit Blöcken, Arbeitstag und „Im Tag zeigen ›“)

**Interfaces:**
- `TaskContextMenu(item:, actions:)`:
  - Viererreihe (`ControlGroup`) mit Einplanen Heute / Morgen / Wochenende / Nächste Woche, dazu „Datum wählen …“
  - „Fälligkeit verschieben …“ (Optionen aus 2a)
  - Erledigt
  - Löschen bzw. „Als nicht geplant schließen“
  - bei wiederkehrenden Erinnerungen „Aufwand ändern …“
  - „Verknüpfte Termine“, falls vorhanden
  - Ab Schriftgröße AX1 eine flache Liste
- `PlanningModel.planDay(for option: RescheduleOption) -> PlanDay` nutzt `rescheduled` aus 2a für das Datum, schreibt aber nur die Zuordnung.
- `EventDetailView` zeigt bei einer Verknüpfung „Verknüpfte Aufgabe“ samt Herkunft und „Aufgabe öffnen“. Ohne Verknüpfung bietet es „Mit Aufgabe verknüpfen …“ (Auswahl). Dazu „Im Kalender öffnen“ (`calshow:`).
- `RecurringEffortSheet` mit `EstimateField` und der Wahl „Nur dieser Tag“ / „Alle“ (ab diesem Tag). Die Folge für die Kapazität ist sichtbar.

- [ ] **Step 1: Failing tests:** `planDay_forTodayTomorrowWeekend_matchesRescheduleDates`, `contextMenu_einplanen_doesNotWriteSource` (der Fake-Provider sieht kein `apply`), `eventDetail_linkManually_persists`.
- [ ] **Step 2–4:** FAIL → implementieren → grün. Auf dem Gerät prüfen, ob die Viererreihe beschriftet erscheint; sonst gilt für alle die flache Liste (Design-Mockup d, offener Punkt).
- [ ] **Step 5:** Commit `feat: add task context menu, event links and recurring effort editing`.

### Task 10: Einstellungen, Einrichtung, Geräteprüfung

**Files:**
- Modify: `SettingsView.swift` (Abschnitt „Planen“: Arbeitszeit je Wochentag, Plan-Kalender mit „Neu anlegen“, Deadline-Kalender als Mehrfachauswahl, Standard-Dauer), `SetupModel.swift` und `SetupView.swift` (Schritt „Plan-Kalender“ nach „Kalender“: „Kalender ‚Tagwerk‘ anlegen“ oder vorhandenen wählen), `README.md`
- Test: `SetupModelTests` (`planCalendarStep_createsTagwerkCalendar`, `planCalendarStep_skip_leavesNil`)

- [ ] **Step 1:** Tests FAIL → implementieren → `app/test-all.sh` grün.
- [ ] **Step 2:** `scripts/install-dev.sh`. **Geräteprüfung durch den Nutzer**:
  - Plan-Kalender anlegen und in der Kalender-App sehen
  - Woche planen per Ziehen und Menü
  - Zeitblock im Tag anlegen, im Kalender verschieben, in Tagwerk aktualisiert sehen
  - Termin „#<Nummer> …“ öffnet das Issue
  - Karteikarten-Aufwand „Nur dieser Tag“ / „Alle“
  - Uni-Kalender als Deadline-Kalender
  - Tag mit abweichender Arbeitszeit
- [ ] **Step 3:** Befunde beheben, jeweils mit einem Test zuerst. Commit `docs: describe planning` bzw. die einzelnen Fix-Commits.
