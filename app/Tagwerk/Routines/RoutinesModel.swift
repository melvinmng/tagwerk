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

        var id: String {
            switch self {
            case .start(let day): "start-\(day.dayKey)"
            case .evening(let day): "evening-\(day.dayKey)"
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

    init(store: RoutineStore, planning: PlanningModel, taskList: TaskListModel, habits: HabitsModel, settings: AppSettings,
         completedCount: @escaping (DateInterval) async -> Int, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.planning = planning
        self.taskList = taskList
        self.habits = habits
        self.settings = settings
        self.completedCount = completedCount
        self.calendar = calendar
        self.now = now
    }

    var today: PlanDay { PlanDay(date: now(), calendar: calendar) }

    /// The day the evening wrap-up belongs to right now (rule 10).
    var eveningDay: PlanDay { RoutineSchedule.routineDay(at: now(), calendar: calendar) }

    // MARK: Opening

    /// `nil`: today.
    func openStart(_ day: PlanDay? = nil) { sheet = .start(day ?? today) }

    /// `nil`: the evening day (before 04:00 that is yesterday).
    func openEvening(_ day: PlanDay? = nil) { sheet = .evening(day ?? eveningDay) }

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

    /// Open tasks of today for the focus and the review (rule 12).
    func todayTasks() -> [TaskItem] { tasks(of: today) }

    func tasks(of day: PlanDay) -> [TaskItem] {
        let planned = Set(planning.planStore.assignments(in: day...day).filter { $0.value == day }.keys)
        let recurring = Set(planning.recurringReminderIDs.map { TaskID(source: .reminders, rawValue: $0) })
        return FocusRules.candidates(taskList.items, plannedToday: planned, blockedToday: planning.taskIDsWithBlocks(on: day),
                                     recurring: recurring, today: day, calendar: calendar)
    }

    // MARK: Evening

    /// "Aufgaben erledigt e von n": completions of the day from reminders and local tasks (GitHub issues have no
    /// completion dates, deviation A1) plus the open tasks of the day.
    func dayReview(_ day: PlanDay) async -> DayReview {
        let interval = DateInterval(start: day.startDate(in: calendar), end: day.adding(days: 1, calendar: calendar).startDate(in: calendar))
        let done = await completedCount(interval)
        return DayReview(tasksDone: done, tasksTotal: done + tasks(of: day).count, habits: habits.counter(on: day), focus: nil)
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

    /// "Fokus wählen" or "✓ 07:42".
    func captureStartDetail(_ day: PlanDay) -> String {
        _ = revision
        guard let done = store.day(day).startCompletedAt else { return String(localized: "Fokus wählen") }
        return "✓ \(DateText.time(done, calendar: calendar))"
    }

    static func overviewText(_ overview: Overview) -> String {
        let events = overview.events == 1 ? String(localized: "1 Termin") : String(localized: "\(overview.events) Termine")
        let tasks = overview.tasks == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(overview.tasks) Aufgaben")
        let free = String(localized: "\(CapacityText.duration(overview.freeMinutes)) frei")
        return [events, tasks, free].joined(separator: " · ")
    }
}
