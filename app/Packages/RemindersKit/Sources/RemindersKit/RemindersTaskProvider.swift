import TagwerkCore

/// Task source for Apple Reminders with a version check before every write.
@MainActor
public final class RemindersTaskProvider: TaskProvider {
    public let source: TaskSource = .reminders
    private let store: ReminderStore
    private let selectedListIDs: @MainActor () -> Set<String>?

    public init(store: ReminderStore, selectedListIDs: @escaping @MainActor () -> Set<String>?) {
        self.store = store
        self.selectedListIDs = selectedListIDs
    }

    public func openTasks() async throws -> [TaskItem] {
        try requireAccess()
        let lists = listsByID()
        return await store.openReminders(in: selectedListIDs()).map { map($0, lists: lists) }
    }

    public func task(id: TaskID) async throws -> TaskItem? {
        try requireAccess()
        return store.reminder(id: id.rawValue).map { map($0, lists: listsByID()) }
    }

    public func containers() async throws -> [TaskContainer] {
        try requireAccess()
        return store.lists().map { TaskContainer(id: $0.id, name: $0.title, colorHex: $0.colorHex) }
    }

    public func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        try requireAccess()
        guard let current = store.reminder(id: id.rawValue) else { throw TaskWriteError.notFound }
        let lists = listsByID()
        let currentItem = map(current, lists: lists)
        if let expectedVersion, expectedVersion != currentItem.version {
            throw TaskWriteError.conflict(current: currentItem)
        }
        let saved = try perform { try store.save(ReminderMapping.applying(edit, to: current)) }
        return map(saved, lists: lists)
    }

    public func delete(_ id: TaskID, expectedVersion: String?) async throws {
        try requireAccess()
        guard let current = store.reminder(id: id.rawValue) else { throw TaskWriteError.notFound }
        let currentItem = map(current, lists: listsByID())
        if let expectedVersion, expectedVersion != currentItem.version {
            throw TaskWriteError.conflict(current: currentItem)
        }
        try perform { try store.delete(id: id.rawValue) }
    }

    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        try requireAccess()
        let record = try perform {
            try store.create(
                title: draft.title, notes: draft.notes, due: draft.due,
                ekPriority: ReminderMapping.ekPriority(from: draft.priority), listID: draft.containerID
            )
        }
        return map(record, lists: listsByID())
    }

    private func requireAccess() throws {
        guard store.accessState == .fullAccess else { throw TaskWriteError.accessDenied }
    }

    private func perform<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as TaskWriteError {
            throw error
        } catch {
            throw TaskWriteError.failed(error.localizedDescription)
        }
    }

    private func listsByID() -> [String: ListInfo] {
        Dictionary(store.lists().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func map(_ record: ReminderRecord, lists: [String: ListInfo]) -> TaskItem {
        let list = lists[record.listID] ?? ListInfo(id: record.listID, title: "Erinnerungen", colorHex: nil, kind: .other)
        return ReminderMapping.taskItem(record, list: list)
    }
}
