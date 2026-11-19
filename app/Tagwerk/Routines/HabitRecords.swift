import Foundation
import SwiftData
import TagwerkCore

/// A habit (phase 7 design §5.1). Every attribute has a default value so a later schema change stays additive.
@Model
final class HabitRecord {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "checkmark.circle"
    var order: Int = 0
    /// Raw value of `HabitSource`.
    var source: String = "manual"
    var daysPerWeek: Int = 7
    var daylightMinutes: Int = 20
    var startYear: Int = 1970
    var startMonth: Int = 1
    var startDay: Int = 1
    /// "YYYY-MM-DD" while the habit is paused.
    var pausedSinceKey: String? = nil
    /// JSON of `[HabitPause]`, the closed pauses.
    var pausesData: Data? = nil
    var createdAt: Date = Date.now

    init(_ habit: Habit, createdAt: Date) {
        self.id = habit.id
        self.createdAt = createdAt
        apply(habit)
    }

    func apply(_ habit: Habit) {
        name = habit.name
        symbol = habit.symbol
        order = habit.order
        source = habit.source.rawValue
        daysPerWeek = habit.daysPerWeek
        daylightMinutes = habit.daylightMinutes
        startYear = habit.start.year
        startMonth = habit.start.month
        startDay = habit.start.day
        pausedSinceKey = habit.pausedSince?.dayKey
        pausesData = habit.pauses.isEmpty ? nil : try? JSONEncoder().encode(habit.pauses)
    }

    var value: Habit {
        let pauses = pausesData.flatMap { try? JSONDecoder().decode([HabitPause].self, from: $0) } ?? []
        return Habit(id: id, name: name, symbol: symbol, order: order, source: HabitSource(rawValue: source) ?? .manual,
                     daysPerWeek: min(7, max(1, daysPerWeek)), daylightMinutes: daylightMinutes,
                     start: PlanDay(year: startYear, month: startMonth, day: startDay),
                     pausedSince: pausedSinceKey.flatMap { PlanDay(dayKey: $0) }, pauses: pauses)
    }
}

/// A manual check of a habit on one day. Automatic fulfilment is calculated and never stored.
@Model
final class HabitCheckRecord {
    var habitID: UUID = UUID()
    var year: Int = 1970
    var month: Int = 1
    var day: Int = 1
    var checkedAt: Date = Date.now

    init(habitID: UUID, day: PlanDay, checkedAt: Date) {
        self.habitID = habitID
        self.year = day.year
        self.month = day.month
        self.day = day.day
        self.checkedAt = checkedAt
    }

    var planDay: PlanDay { PlanDay(year: year, month: month, day: day) }
}

/// Reads and writes habits and their manual checks. Nothing here leaves the device.
@MainActor
final class HabitStore {
    private let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    /// All habits, paused ones included, by order.
    func habits() -> [Habit] {
        records().sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map(\.value)
    }

    /// Inserts or updates by id; the name is trimmed and cut to `HabitRules.nameLimit` characters.
    func save(_ habit: Habit) {
        var habit = habit
        habit.name = String(habit.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(HabitRules.nameLimit))
        habit.daysPerWeek = min(7, max(1, habit.daysPerWeek))
        if let record = record(habit.id) {
            record.apply(habit)
        } else {
            context.insert(HabitRecord(habit, createdAt: now()))
        }
        try? context.save()
    }

    /// Removes the habit and its manual checks.
    func delete(_ id: UUID) {
        if let record = record(id) { context.delete(record) }
        for check in checkRecords() where check.habitID == id { context.delete(check) }
        try? context.save()
    }

    func reorder(_ ids: [UUID]) {
        for (index, id) in ids.enumerated() { record(id)?.order = index }
        try? context.save()
    }

    /// Pausing starts an open pause today; resuming closes it at yesterday (a pause of zero days is dropped).
    func setPaused(_ id: UUID, _ paused: Bool, today: PlanDay, calendar: Calendar = .tagwerk) {
        guard let record = record(id) else { return }
        var habit = record.value
        if paused {
            guard habit.pausedSince == nil else { return }
            habit.pausedSince = today
        } else if let since = habit.pausedSince {
            let yesterday = today.adding(days: -1, calendar: calendar)
            if since <= yesterday { habit.pauses.append(HabitPause(from: since, to: yesterday)) }
            habit.pausedSince = nil
        }
        record.apply(habit)
        try? context.save()
    }

    /// The days with a manual check inside `range`, per habit.
    func checks(in range: ClosedRange<PlanDay>) -> [UUID: Set<PlanDay>] {
        var result: [UUID: Set<PlanDay>] = [:]
        for check in checkRecords() where range.contains(check.planDay) {
            result[check.habitID, default: []].insert(check.planDay)
        }
        return result
    }

    /// Sets or removes the manual check; `false` when nothing changed.
    @discardableResult
    func setCheck(_ id: UUID, on day: PlanDay, checked: Bool, at date: Date) -> Bool {
        let existing = checkRecords().filter { $0.habitID == id && $0.planDay == day }
        if checked {
            guard existing.isEmpty else { return false }
            context.insert(HabitCheckRecord(habitID: id, day: day, checkedAt: date))
        } else {
            guard !existing.isEmpty else { return false }
            existing.forEach { context.delete($0) }
        }
        try? context.save()
        return true
    }

    private func records() -> [HabitRecord] {
        (try? context.fetch(FetchDescriptor<HabitRecord>())) ?? []
    }

    private func record(_ id: UUID) -> HabitRecord? {
        records().first { $0.id == id }
    }

    private func checkRecords() -> [HabitCheckRecord] {
        (try? context.fetch(FetchDescriptor<HabitCheckRecord>())) ?? []
    }
}
