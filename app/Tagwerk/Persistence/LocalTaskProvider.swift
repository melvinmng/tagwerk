import Foundation
import SwiftData
import TagwerkCore

/// Task source for tasks stored only in Tagwerk (SwiftData).
@MainActor
final class LocalTaskProvider: TaskProvider {
    /// Shown as the list name of local tasks, in the app language.
    static var container: TaskContainer { TaskContainer(id: "local", name: String(localized: "Lokal"), colorHex: nil) }

    let source: TaskSource = .local
    private let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    init(context: ModelContext, calendar: Calendar = .tagwerk, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    func openTasks() async throws -> [TaskItem] {
        let descriptor = FetchDescriptor<LocalTask>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map(Self.item)
    }

    func task(id: TaskID) async throws -> TaskItem? {
        try record(id).map(Self.item)
    }

    func containers() async throws -> [TaskContainer] {
        [Self.container]
    }

    func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        guard let task = try record(id) else { throw TaskWriteError.notFound }
        if let expectedVersion, expectedVersion != String(task.revision) {
            throw TaskWriteError.conflict(current: Self.item(task))
        }
        let resultingDue: DueDate? = if case .set(let due) = edit.due { due } else { task.due }
        let recurrence = try Self.recurrenceChange(for: edit.recurrence, resultingDue: resultingDue,
                                                   hasRecurrence: task.recurrenceData != nil)
        if case .set(let title) = edit.title { task.title = title }
        if case .set(let notes) = edit.notes { task.notes = notes }
        if case .set(let due) = edit.due { task.due = due }
        if case .set(let priority) = edit.priority { task.priority = priority }
        if case .set(let minutes) = edit.estimateMinutes { task.estimateMinutes = minutes }
        if case .set(let newRecurrence) = recurrence { task.recurrence = newRecurrence }
        task.revision += 1
        if case .set(let completed) = edit.isCompleted { setCompleted(completed, task) }
        try save()
        return Self.item(task)
    }

    /// Ticking off a repeating task moves it on to its next occurrence and keeps it open; the last occurrence
    /// completes it. Reopening an open repeating task undoes its last such move, as long as nothing changed since.
    private func setCompleted(_ completed: Bool, _ task: LocalTask) {
        if completed, !task.isCompleted, let due = task.due, let recurrence = task.recurrence,
           let advanced = advancedSeries(due: due, recurrence: recurrence, calendar: calendar) {
            context.insert(LocalOccurrenceCompletion(taskID: task.id, completedAt: now(), previousDue: due,
                                                     previousCount: recurrence.count, revision: task.revision))
            task.due = advanced.due
            task.recurrence = advanced.recurrence
            return
        }
        if !completed, !task.isCompleted {
            undoLastOccurrence(of: task)
            return
        }
        if completed != task.isCompleted { task.completedAt = completed ? now() : nil }
        task.isCompleted = completed
    }

    private func undoLastOccurrence(of task: LocalTask) {
        // The revision was already raised for this write; the completion recorded the one before.
        guard let last = occurrences(of: task.id).max(by: { $0.completedAt < $1.completedAt }),
              last.revision == task.revision - 1, var recurrence = task.recurrence else { return }
        task.due = last.previousDue
        recurrence.count = last.previousCount
        task.recurrence = recurrence
        context.delete(last)
    }

    /// The repetition to write for `change`: a repetition needs a due date (setting one without fails, clearing
    /// the due date removes it); `.unsupported` and invalid rules are never stored.
    private static func recurrenceChange(for change: FieldChange<Recurrence?>, resultingDue: DueDate?,
                                         hasRecurrence: Bool) throws -> FieldChange<Recurrence?> {
        let clearsDue = resultingDue == nil && hasRecurrence
        switch change {
        case .unchanged:
            return clearsDue ? .set(nil) : .unchanged
        case .set(nil):
            return .set(nil)
        case .set(let recurrence?):
            if case .unsupported = recurrence.rule { return clearsDue ? .set(nil) : .unchanged }
            try validate(recurrence, due: resultingDue)
            return .set(recurrence)
        }
    }

    private static func validate(_ recurrence: Recurrence, due: DueDate?) throws {
        guard due != nil else {
            throw TaskWriteError.failed(String(localized: "Eine Wiederholung braucht ein Fälligkeitsdatum."))
        }
        guard recurrence.isValid else {
            throw TaskWriteError.failed(String(localized: "Diese Wiederholung kann nicht gespeichert werden."))
        }
    }

    /// Completion moments of local tasks within `interval`, for the weekly review: completed tasks once, and
    /// every occurrence of a repeating task ticked off before its last one.
    func completionDates(in interval: DateInterval) -> [Date] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<LocalTask>(predicate: #Predicate { task in
            task.isCompleted && task.completedAt != nil
        })
        let tasks = ((try? context.fetch(descriptor)) ?? []).compactMap(\.completedAt)
        let occurrences = FetchDescriptor<LocalOccurrenceCompletion>(predicate: #Predicate { completion in
            completion.completedAt >= start && completion.completedAt < end
        })
        return tasks.filter { $0 >= start && $0 < end } + ((try? context.fetch(occurrences)) ?? []).map(\.completedAt)
    }

    func delete(_ id: TaskID, expectedVersion: String?) async throws {
        guard let task = try record(id) else { throw TaskWriteError.notFound }
        if let expectedVersion, expectedVersion != String(task.revision) {
            throw TaskWriteError.conflict(current: Self.item(task))
        }
        context.delete(task)
        try save()
    }

    func create(_ draft: TaskDraft) async throws -> TaskItem {
        if let recurrence = draft.recurrence { try Self.validate(recurrence, due: draft.due) }
        let task = LocalTask(title: draft.title)
        task.notes = draft.notes
        task.due = draft.due
        task.priority = draft.priority
        task.estimateMinutes = draft.estimateMinutes
        task.recurrence = draft.recurrence
        context.insert(task)
        try save()
        return Self.item(task)
    }

    private func record(_ id: TaskID) throws -> LocalTask? {
        guard id.source == .local, let uuid = UUID(uuidString: id.rawValue) else { return nil }
        var descriptor = FetchDescriptor<LocalTask>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func occurrences(of taskID: UUID) -> [LocalOccurrenceCompletion] {
        let descriptor = FetchDescriptor<LocalOccurrenceCompletion>(predicate: #Predicate { $0.taskID == taskID })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw TaskWriteError.failed(error.localizedDescription)
        }
    }

    private static func item(_ task: LocalTask) -> TaskItem {
        TaskItem(
            id: TaskID(source: .local, rawValue: task.id.uuidString),
            title: task.title,
            notes: task.notes,
            due: task.due,
            priority: task.priority,
            estimateMinutes: task.estimateMinutes,
            isCompleted: task.isCompleted,
            container: container,
            url: nil,
            version: String(task.revision),
            editableFields: [.title, .notes, .due, .priority, .estimate, .recurrence],
            recurrence: task.recurrence
        )
    }
}
