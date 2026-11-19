import Foundation
import Observation
import TagwerkCore

/// The daily routines of "Planen" and "Erfassen" (phase 7): which sheet is open, the evening line, the evening wrap-up.
/// Everything is calculated from the stores; nothing here reaches the network.
@MainActor
@Observable
final class RoutinesModel {
    /// The sheet a card, a row, a notification or a link opened; held by `RootView`, so all of them open the same one.
    enum Sheet: Identifiable, Equatable {
        case start(PlanDay)
        case evening(PlanDay)
        /// "Unerledigtes verschieben" from the capacity card of today.
        case leftover
        /// The guided weekly planning (#164).
        case week

        var id: String {
            switch self {
            case .start(let day): "start-\(day.dayKey)"
            case .evening(let day): "evening-\(day.dayKey)"
            case .leftover: "leftover"
            case .week: "week"
            }
        }
    }

    /// "Heute" of the evening sheet.
    struct DayReview: Equatable {
        var tasksDone: Int
        var tasksTotal: Int
        var habits: HabitCounter?
        var focus: HabitCounter?
    }

    /// The line in the capacity card of "Planen".
    struct EveningLine: Equatable {
        var bedtimeMinutes: Int
        var checked: Int
        var total: Int
        var isDone: Bool
    }

    var sheet: Sheet?
    /// Bumped by every change of the stores this model shows, so views follow.
    private(set) var revision = 0

    let store: RoutineStore
    let planning: PlanningModel
    let taskList: TaskListModel
    let habits: HabitsModel
    let settings: AppSettings
    let calendar: Calendar
    @ObservationIgnored private let completedCount: (DateInterval) async -> Int
    @ObservationIgnored private let now: () -> Date
    /// Whether a task is an occurrence of a recurring reminder (not selectable as focus); defaults to the plan's list.
    @ObservationIgnored private let isRecurringOverride: ((TaskItem) -> Bool)?
    /// The overview shown in the morning card; refreshed by the card.
    private(set) var cardOverview: Overview?

    init(store: RoutineStore, planning: PlanningModel, taskList: TaskListModel, habits: HabitsModel, settings: AppSettings,
         completedCount: @escaping (DateInterval) async -> Int, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init,
         isRecurring: ((TaskItem) -> Bool)? = nil) {
        self.isRecurringOverride = isRecurring
        self.store = store
        self.planning = planning
        self.taskList = taskList
        self.habits = habits
        self.settings = settings
        self.completedCount = completedCount
        self.calendar = calendar
        self.now = now
        syncFocusToPlan()
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// The day the evening wrap-up belongs to right now (rule 10).
    var eveningDay: PlanDay { RoutineSchedule.routineDay(at: now(), calendar: calendar) }

    // MARK: Opening

    /// `nil`: today.
    func openStart(_ day: PlanDay? = nil) { sheet = .start(day ?? today) }

    /// `nil`: the evening day (before 04:00 that is yesterday).
    func openEvening(_ day: PlanDay? = nil) { sheet = .evening(day ?? eveningDay) }

    func openLeftover() { sheet = .leftover }

    func openWeek() { sheet = .week }

    /// "Unerledigtes verschieben" is offered in the wrap-up of the real today only (#163). After midnight the wrap-up still
    /// belongs to yesterday; the leftovers the planning knows then are those of the new day, so nothing is offered.
    func offersLeftover(for day: PlanDay) -> Bool {
        day == today && !planning.leftFromToday.isEmpty
    }

    func closeSheet() { sheet = nil }

    // MARK: Day values

    func value(_ day: PlanDay) -> RoutineDayValue { store.day(day) }

    func checklist() -> [ChecklistItem] { store.checklist() }

    func toggleItem(_ id: UUID, on day: PlanDay) {
        store.update(day) { value in
            if value.checkedItemIDs.contains(id) { value.checkedItemIDs.remove(id) } else { value.checkedItemIDs.insert(id) }
        }
        revision += 1
    }

    /// Writes the day the sheet was opened for, not the day the clock shows now (rule 10, review focus 1).
    func finishEvening(_ day: PlanDay) {
        store.update(day) { $0.closeCompletedAt = now() }
        revision += 1
        sheet = nil
    }

    // MARK: Tasks of a day

    /// Open tasks of a day for the review (rule 12).
    func tasks(of day: PlanDay) -> [TaskItem] {
        let planned = Set(planning.planStore.assignments(in: day...day).filter { $0.value == day }.keys)
        let recurring = Set(taskList.items.filter(isRecurring).map(\.id))
        return FocusRules.candidates(taskList.items, plannedToday: planned, blockedToday: planning.taskIDsWithBlocks(on: day),
                                     recurring: recurring, today: day, calendar: calendar)
    }

    // MARK: Evening

    /// "Aufgaben erledigt e von n": completions of the day from reminders and local tasks (GitHub issues have no
    /// completion dates, deviation A1) plus the open tasks of the day.
    func dayReview(_ day: PlanDay) async -> DayReview {
        let interval = DateInterval(start: day.startDate(in: calendar), end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let done = await completedCount(interval)
        let marks = store.focusMarks(on: day)
        let focus = marks.isEmpty ? nil : HabitCounter(done: marks.filter { $0.doneAt != nil }.count, total: marks.count)
        return DayReview(tasksDone: done, tasksTotal: done + tasks(of: day).count, habits: habits.counter(on: day), focus: focus)
    }

    /// The evening line in "Planen" (rule 11); `nil` when switched off or not yet due.
    var eveningLine: EveningLine? {
        _ = revision
        guard settings.showsRoutinesInPlan else { return nil }
        let items = store.checklist()
        let offsets = items.compactMap(\.offsetMinutes)
        guard RoutineSchedule.showsEveningLine(minutesOfDay: RoutineSchedule.minutesOfDay(now(), calendar: calendar),
                                               bedtimeMinutes: settings.bedtimeMinutes, offsets: offsets) else { return nil }
        let value = store.day(eveningDay)
        return EveningLine(bedtimeMinutes: settings.bedtimeMinutes, checked: RoutineSchedule.checkedCount(value, items: items),
                           total: items.count, isDone: value.closeCompletedAt != nil)
    }

    /// "Schlafzeit 23:00 · Checkliste 0 von 3" or, when done, "✓ 22:10".
    func captureEveningDetail(_ day: PlanDay) -> String {
        _ = revision
        let value = store.day(day)
        if let done = value.closeCompletedAt { return "✓ \(DateText.time(done, calendar: calendar))" }
        return Self.eveningDetail(bedtimeMinutes: settings.bedtimeMinutes, checked: RoutineSchedule.checkedCount(value, items: store.checklist()),
                                  total: store.checklist().count, calendar: calendar)
    }

    /// "Schlafzeit 23:00 · Checkliste 0 von 3"; without points only the bedtime.
    static func eveningDetail(bedtimeMinutes: Int, checked: Int, total: Int, calendar: Calendar) -> String {
        let bedtime = String(localized: "Schlafzeit \(DateText.time(minutes: bedtimeMinutes, calendar: calendar))")
        guard total > 0 else { return bedtime }
        return bedtime + " · " + String(localized: "Checkliste \(checked) von \(total)")
    }
}

// MARK: Morning start

extension RoutinesModel {
    /// "3 Termine · 5 Aufgaben · 3 h 30 frei" of the sheet.
    struct Overview: Equatable {
        var events: Int
        var tasks: Int
        var freeMinutes: Int
    }

    /// Today only; for other days the sheet shows no overview.
    func overview(for day: PlanDay) async -> Overview? {
        guard day == today else { return nil }
        let input = await planning.planInputs(in: day...day).first
        let free = input.map { max(0, $0.availableMinutes - $0.plannedMinutes) } ?? 0
        return Overview(events: input?.events.count ?? 0, tasks: tasks(of: day).count, freeMinutes: free)
    }

    func setGratitude(_ entries: [String], on day: PlanDay) {
        store.update(day) { $0.gratitude = entries }
        revision += 1
    }

    /// Marks the start as completed, also without any input; closes the sheet.
    func finishStart(_ day: PlanDay) {
        store.update(day) { $0.startCompletedAt = self.now() }
        revision += 1
        sheet = nil
    }

    /// "Starten" or "✓ 07:42".
    func captureStartDetail(_ day: PlanDay) -> String {
        _ = revision
        guard let done = store.day(day).startCompletedAt else { return String(localized: "Starten") }
        let time = "✓ \(DateText.time(done, calendar: calendar))"
        guard let first = store.focusMarks(on: day).first else { return time }
        return time + " · " + String(localized: "Fokus: \(first.title)")
    }

    static func overviewText(_ overview: Overview) -> String {
        let events = overview.events == 1 ? String(localized: "1 Termin") : String(localized: "\(overview.events) Termine")
        let tasks = overview.tasks == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(overview.tasks) Aufgaben")
        let free = String(localized: "\(CapacityText.duration(overview.freeMinutes)) frei")
        return [events, tasks, free].joined(separator: " · ")
    }
}

// MARK: Focus and card

extension RoutinesModel {
    /// The one new element above the timeline in "Planen": the morning card or the focus card, never both.
    enum Card: Equatable {
        case morning(overview: String)
        case focus(marks: [FocusMark], done: Int, total: Int)
    }

    /// Rule 11. A chosen focus replaces the morning card; with nothing left open there is no card.
    var card: Card? {
        _ = revision
        guard settings.showsRoutinesInPlan else { return nil }
        let marks = store.focusMarks(on: today)
        if !marks.isEmpty {
            let done = marks.filter { $0.doneAt != nil }.count
            return done < marks.count ? .focus(marks: marks, done: done, total: marks.count) : nil
        }
        let value = store.day(today)
        guard RoutineSchedule.showsMorningCard(minutesOfDay: RoutineSchedule.minutesOfDay(now(), calendar: calendar),
                                               completed: value.startCompletedAt != nil, dismissed: value.startDismissed) else { return nil }
        return .morning(overview: cardOverview.map(Self.shortOverviewText) ?? "")
    }

    /// Changes whenever the inputs of the overview change (tasks loaded, recurring reminders recognized), so the card
    /// recomputes its numbers instead of keeping the ones from its first appearance.
    var cardOverviewInputs: Int {
        var hasher = Hasher()
        for item in taskList.items { hasher.combine(item.id.rawValue) }
        for id in planning.recurringTaskIDs.sorted(by: { $0.rawValue < $1.rawValue }) { hasher.combine(id) }
        return hasher.finalize()
    }

    /// Reads the numbers of the morning card; the card calls it when it appears and when its inputs change.
    func refreshCardOverview() async {
        cardOverview = await overview(for: today)
    }

    /// "3 Termine, 5 Aufgaben" of the morning card.
    static func shortOverviewText(_ overview: Overview) -> String {
        let events = overview.events == 1 ? String(localized: "1 Termin") : String(localized: "\(overview.events) Termine")
        let tasks = overview.tasks == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(overview.tasks) Aufgaben")
        return events + ", " + tasks
    }

    func dismissMorningCard() {
        store.update(today) { $0.startDismissed = true }
        revision += 1
    }

    func focusMarks(_ day: PlanDay) -> [FocusMark] {
        _ = revision
        return store.focusMarks(on: day)
    }

    /// Today only.
    func isFocus(_ id: TaskID) -> Bool {
        store.focusMarks(on: today).contains { $0.taskKey == id.key }
    }

    func isRecurring(_ task: TaskItem) -> Bool {
        if let isRecurringOverride { return isRecurringOverride(task) }
        return planning.recurringTaskIDs.contains(task.id)
    }

    /// Marks or unmarks a task of today; recurring occurrences and a fourth mark are ignored.
    func toggleFocus(_ task: TaskItem) {
        let day = today
        if isFocus(task.id) {
            store.removeFocus(taskKey: task.id.key, on: day)
        } else if !isRecurring(task) {
            store.addFocus(task, on: day)
        }
        changedFocus()
    }

    /// Completes the task in its own source through the task list; the mark itself never writes to a source.
    func completeFocus(_ mark: FocusMark) async {
        guard let id = mark.taskID else { return }
        await taskList.complete(id)
        guard !taskList.items.contains(where: { $0.id == id }) else { return }
        store.setFocusDone(taskKey: mark.taskKey, on: today, at: now())
        changedFocus()
    }

    /// From `taskList.onCompletionChanged`: a completion or its undo, wherever it happened.
    func focusChanged(_ id: TaskID, isCompleted: Bool) {
        let day = today
        guard store.focusMarks(on: day).contains(where: { $0.taskKey == id.key }) else { return }
        store.setFocusDone(taskKey: id.key, on: day, at: isCompleted ? now() : nil)
        changedFocus()
    }

    /// After the tasks loaded: a mark whose task left the open list counts as done, but only once its source answered
    /// (review focus 3); an open task follows its title and reopens a mark that was set done. Runs for today only.
    func refreshFocus() {
        let day = today
        for mark in store.focusMarks(on: day) {
            guard let id = mark.taskID else { continue }
            if let task = taskList.items.first(where: { $0.id == id }) {
                store.updateFocusTitle(taskKey: mark.taskKey, on: day, title: task.title)
                if mark.doneAt != nil { store.setFocusDone(taskKey: mark.taskKey, on: day, at: nil) }
            } else if mark.doneAt == nil, isSettled(id.source) {
                store.setFocusDone(taskKey: mark.taskKey, on: day, at: now())
            }
        }
        changedFocus()
    }

    private func isSettled(_ source: TaskSource) -> Bool {
        guard !taskList.loadingSources.contains(source) else { return false }
        // Only data (live or cached) proves a task left the list; failed, no-access and signed-out sources cleared their items.
        switch taskList.sourceStates[source] {
        case .loaded?, .offline?: return true
        default: return false
        }
    }

    private func changedFocus() {
        revision += 1
        syncFocusToPlan()
    }

    /// The stars of "Planen" follow the open marks of today.
    func syncFocusToPlan() {
        let open = Set(store.focusMarks(on: today).filter { $0.doneAt == nil }.compactMap(\.taskID))
        if planning.focusTaskIDs != open { planning.focusTaskIDs = open }
    }
}
