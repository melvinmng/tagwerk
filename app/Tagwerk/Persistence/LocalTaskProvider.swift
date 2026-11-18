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

    init(context: ModelContext) {
        self.context = context
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
        if case .set(let title) = edit.title { task.title = title }
        if case .set(let notes) = edit.notes { task.notes = notes }
        if case .set(let due) = edit.due { task.due = due }
        if case .set(let priority) = edit.priority { task.priority = priority }
        if case .set(let minutes) = edit.estimateMinutes { task.estimateMinutes = minutes }
        if case .set(let completed) = edit.isCompleted {
            if completed != task.isCompleted { task.completedAt = completed ? .now : nil }
            task.isCompleted = completed
        }
        task.revision += 1
        try save()
        return Self.item(task)
    }

    /// Completion moments of local tasks within `interval`, for the weekly review.
    func completionDates(in interval: DateInterval) -> [Date] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<LocalTask>(predicate: #Predicate { task in
            task.isCompleted && task.completedAt != nil
        })
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.completedAt).filter { $0 >= start && $0 < end }
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
        let task = LocalTask(title: draft.title)
        task.notes = draft.notes
        task.due = draft.due
        task.priority = draft.priority
        task.estimateMinutes = draft.estimateMinutes
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
            editableFields: [.title, .notes, .due, .priority, .estimate]
        )
    }
}
