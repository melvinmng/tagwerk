import TagwerkCore

/// Local effort for reminders: EventKit cannot store one, so it lives in Tagwerk.
@MainActor
public protocol EstimateStore: AnyObject {
    func minutes(for reminderID: String) -> Int?
    func setMinutes(_ minutes: Int?, for reminderID: String)
}

/// Task source for Apple Reminders with a version check before every write.
@MainActor
public final class RemindersTaskProvider: TaskProvider {
    public let source: TaskSource = .reminders
    private let store: ReminderStore
    private let estimates: EstimateStore?
    private let selectedListIDs: @MainActor () -> Set<String>?

    public init(store: ReminderStore, estimates: EstimateStore? = nil,
                selectedListIDs: @escaping @MainActor () -> Set<String>?) {
        self.store = store
        self.estimates = estimates
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
        if case .set(let minutes) = edit.estimateMinutes { estimates?.setMinutes(minutes, for: current.id) }
        var reminderEdit = edit
        reminderEdit.estimateMinutes = .unchanged
        reminderEdit.recurrence = try ReminderMapping.recurrenceChange(for: edit, current: current)
        guard !reminderEdit.isEmpty else { return map(current, lists: lists) }
        let saved = try perform {
            try store.save(ReminderMapping.applying(reminderEdit, to: current), recurrence: reminderEdit.recurrence)
        }
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
        try ReminderMapping.validateNew(recurrence: draft.recurrence, due: draft.due)
        let record = try perform {
            try store.create(
                title: draft.title, notes: draft.notes, due: draft.due,
                ekPriority: ReminderMapping.ekPriority(from: draft.priority), listID: draft.containerID,
                recurrence: draft.recurrence
            )
        }
        if let minutes = draft.estimateMinutes { estimates?.setMinutes(minutes, for: record.id) }
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
        let list = lists[record.listID] ?? ListInfo(id: record.listID, title: String(localized: "Erinnerungen", bundle: .module), colorHex: nil, kind: .other)
        var item = ReminderMapping.taskItem(record, list: list)
        if let estimates {
            item.estimateMinutes = estimates.minutes(for: record.id)
            item.editableFields.insert(.estimate)
        }
        return item
    }
}
