import Foundation
import SwiftData
import TagwerkCore

/// One change the user made to a task through Tagwerk: completed, reopened, status changed, rescheduled, created (#332). GitHub and
/// Reminders keep no history of status changes or reschedules, so the log collects from its introduction on, on this device. It
/// cannot be rebuilt from any source, so it is part of the backup. Stage 1 only writes it; the evaluation follows in stage 3.
/// Schema rule: later attributes must have a default value (data survives reinstalls).
@Model
final class TaskActivityRecord {
    @Attribute(.unique) var id: UUID = UUID()
    /// `TaskID.key`.
    var taskKey: String = ""
    var title: String = ""
    var kindRaw: String = TaskActivityKind.created.rawValue
    var fromValue: String? = nil
    var toValue: String? = nil
    /// `ProjectProgressReference.key` of the projects at the time of the change.
    var projectKeys: [String] = []
    var occurredAt: Date = Date.distantPast

    init(_ entry: TaskActivityEntry, id: UUID = UUID()) {
        self.id = id
        taskKey = entry.taskKey
        title = entry.title
        kindRaw = entry.kind.rawValue
        fromValue = entry.from
        toValue = entry.to
        projectKeys = entry.projectKeys
        occurredAt = entry.occurredAt
    }

    var kind: TaskActivityKind { TaskActivityKind(rawValue: kindRaw) ?? .created }

    var entry: TaskActivityEntry {
        TaskActivityEntry(kind: kind, taskKey: taskKey, title: title, from: fromValue, to: toValue, projectKeys: projectKeys,
                          occurredAt: occurredAt)
    }
}

/// Reads and writes the local activity log.
@MainActor
final class TaskActivityStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(_ entries: [TaskActivityEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries { context.insert(TaskActivityRecord(entry)) }
        try? context.save()
    }

    /// Writes the entry of a task whose planned work day moved from `from` to `to`. The task is looked up among `items` (the loaded
    /// list) for its title and projects; a task that is not loaded gets no entry.
    func recordPlanDayMove(of id: TaskID, from: PlanDay, to: PlanDay, among items: [TaskItem], at date: Date) {
        guard let item = items.first(where: { $0.id == id }),
              let entry = TaskActivityRules.replanned(item, from: from, to: to, at: date) else { return }
        record([entry])
    }

    /// Drops the newest entry of a move of `id` from `from` to `to`, when an undo took that move back. Without such an entry (the task
    /// was not loaded when it moved) nothing changes.
    func removePlanDayMove(of id: TaskID, from: PlanDay, to: PlanDay) {
        let key = id.key, kind = TaskActivityKind.replanned.rawValue
        let fromText = TaskActivityRules.dayText(from), toText = TaskActivityRules.dayText(to)
        var descriptor = FetchDescriptor<TaskActivityRecord>(
            predicate: #Predicate { $0.taskKey == key && $0.kindRaw == kind && $0.fromValue == fromText && $0.toValue == toText },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        try? context.save()
    }

    /// The entries since `date`, newest first; all of them without a date.
    func entries(since date: Date? = nil) -> [TaskActivityEntry] {
        var descriptor = FetchDescriptor<TaskActivityRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        if let date { descriptor.predicate = #Predicate { $0.occurredAt >= date } }
        return ((try? context.fetch(descriptor)) ?? []).map(\.entry)
    }
}
