import Foundation
import RemindersKit
import SwiftData
import TagwerkCore

/// Day assignments and per-day working-hour overrides in SwiftData.
@MainActor
final class PlanStore {
    private let context: ModelContext
    /// Called after a task's planned day moved from one day to another, with the day before and the day after. First planning, removal
    /// from the plan and assigning the same day again do not call it. The activity log of the project progress listens (#332).
    var onDayMoved: ((TaskID, PlanDay, PlanDay) -> Void)?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Day assignments

    func assign(_ id: TaskID, to day: PlanDay) {
        var previous: PlanDay?
        if let existing = record(for: id) {
            previous = existing.planDay
            existing.planDay = day
        } else {
            context.insert(DayAssignment(taskKey: id.key, day: day))
        }
        save()
        if let previous, previous != day { onDayMoved?(id, previous, day) }
    }

    func unassign(_ id: TaskID) {
        if let existing = record(for: id) {
            context.delete(existing)
            save()
        }
    }

    func assignment(for id: TaskID) -> PlanDay? {
        record(for: id)?.planDay
    }

    func assignments(in range: ClosedRange<PlanDay>) -> [TaskID: PlanDay] {
        var result: [TaskID: PlanDay] = [:]
        for record in allAssignments() where range.contains(record.planDay) {
            if let id = TaskID(key: record.taskKey) { result[id] = record.planDay }
        }
        return result
    }

    /// Open tasks whose planned day lies before `today` (shown as "Von früher übrig").
    func leftovers(before today: PlanDay, openTaskIDs: Set<TaskID>) -> [TaskID] {
        allAssignments()
            .filter { $0.planDay < today }
            .sorted { ($0.planDay, $0.order) < ($1.planDay, $1.order) }
            .compactMap { TaskID(key: $0.taskKey) }
            .filter(openTaskIDs.contains)
    }

    /// Removes assignments of tasks that are no longer open (completed, deleted, closed).
    func prune(keeping openTaskIDs: Set<TaskID>) {
        var changed = false
        for record in allAssignments() where !(TaskID(key: record.taskKey).map(openTaskIDs.contains) ?? false) {
            context.delete(record)
            changed = true
        }
        if changed { save() }
    }

    // MARK: Overrides

    func override(on day: PlanDay) -> DayOverride? {
        overrideRecord(on: day)?.value
    }

    func setOverride(_ value: DayOverride?, on day: PlanDay) {
        let existing = overrideRecord(on: day)
        switch (value, existing) {
        case (nil, let record?): context.delete(record)
        case (let value?, let record?): record.apply(value)
        case (let value?, nil): context.insert(DayOverrideRecord(day: day, override: value))
        case (nil, nil): return
        }
        save()
    }

    func overrides(in range: ClosedRange<PlanDay>) -> [PlanDay: DayOverride] {
        let records = (try? context.fetch(FetchDescriptor<DayOverrideRecord>())) ?? []
        return Dictionary(records.filter { range.contains($0.planDay) }.map { ($0.planDay, $0.value) },
                          uniquingKeysWith: { first, _ in first })
    }

    // MARK: Private

    private func record(for id: TaskID) -> DayAssignment? {
        let key = id.key
        var descriptor = FetchDescriptor<DayAssignment>(predicate: #Predicate { $0.taskKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func allAssignments() -> [DayAssignment] {
        (try? context.fetch(FetchDescriptor<DayAssignment>())) ?? []
    }

    private func overrideRecord(on day: PlanDay) -> DayOverrideRecord? {
        let key = DayOverrideRecord.key(day)
        var descriptor = FetchDescriptor<DayOverrideRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        try? context.save()
    }
}

/// `EstimateStore` for reminders, backed by SwiftData.
@MainActor
final class SwiftDataEstimateStore: EstimateStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func minutes(for reminderID: String) -> Int? {
        record(reminderID)?.minutes
    }

    func setMinutes(_ minutes: Int?, for reminderID: String) {
        let existing = record(reminderID)
        switch (minutes, existing) {
        case (nil, let record?): context.delete(record)
        case (let value?, let record?): record.minutes = value
        case (let value?, nil): context.insert(ReminderEstimateRecord(reminderID: reminderID, minutes: value))
        case (nil, nil): return
        }
        try? context.save()
    }

    private func record(_ reminderID: String) -> ReminderEstimateRecord? {
        var descriptor = FetchDescriptor<ReminderEstimateRecord>(predicate: #Predicate { $0.reminderID == reminderID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
