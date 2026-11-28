import Foundation
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
    /// The shopping list, if one is chosen: its reminders are not tasks and it receives no new task.
    private let excludedListID: @MainActor () -> String?

    public init(store: ReminderStore, estimates: EstimateStore? = nil,
                selectedListIDs: @escaping @MainActor () -> Set<String>?,
                excludedListID: @escaping @MainActor () -> String? = { nil }) {
        self.store = store
        self.estimates = estimates
        self.selectedListIDs = selectedListIDs
        self.excludedListID = excludedListID
    }

    public func openTasks() async throws -> [TaskItem] {
        try requireAccess()
        let lists = listsByID()
        let listIDs = ShoppingListFilter.taskListIDs(selected: selectedListIDs(), all: store.lists().map(\.id),
                                                     shopping: excludedListID())
        return await store.openReminders(in: listIDs).map { map($0, lists: lists) }
    }

    /// Reminders completed within `interval` in the lists that feed tasks (without the shopping list),
    /// for the search. Empty without full access.
    public func completedTasks(in interval: DateInterval) async -> [CompletedTask] {
        guard store.accessState == .fullAccess else { return [] }
        let lists = listsByID()
        let all = store.lists().map(\.id)
        let listIDs = ShoppingListFilter.taskListIDs(selected: selectedListIDs(), all: all, shopping: excludedListID())
            ?? Set(all)
        return await store.completedReminders(in: interval, listIDs: listIDs).map { record in
            CompletedTask(item: map(record, lists: lists), completedAt: record.completedAt)
        }
    }

    public func task(id: TaskID) async throws -> TaskItem? {
        try requireAccess()
        return store.reminder(id: id.rawValue).map { map($0, lists: listsByID()) }
    }

    public func containers() async throws -> [TaskContainer] {
        try requireAccess()
        let excluded = excludedListID()
        return store.lists()
            .filter { $0.id != excluded }
            .map { TaskContainer(id: $0.id, name: $0.title, colorHex: $0.colorHex) }
    }

    public func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        try requireAccess()
        guard let current = store.reminder(id: id.rawValue) else { throw TaskWriteError.notFound }
        let lists = listsByID()
        let currentItem = map(current, lists: lists)
        if let expectedVersion, expectedVersion != currentItem.version {
            throw TaskWriteError.conflict(current: currentItem)
        }
        var reminderEdit = edit
        reminderEdit.estimateMinutes = .unchanged
        reminderEdit.recurrence = try ReminderMapping.recurrenceChange(for: edit, current: current)
        // The local estimate is written only after validation and the EventKit save succeeded,
        // so a rejected edit never leaves a half-applied estimate behind.
        guard !reminderEdit.isEmpty else {
            persistEstimate(edit.estimateMinutes, for: current.id)
            return map(current, lists: lists)
        }
        let saved = try perform {
            try store.save(ReminderMapping.applying(reminderEdit, to: current), recurrence: reminderEdit.recurrence)
        }
        persistEstimate(edit.estimateMinutes, for: current.id)
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
        let listID = try ShoppingListFilter.listForNewReminder(
            requested: draft.containerID, defaultListID: store.defaultListID(), shopping: excludedListID(),
            selected: selectedListIDs(), lists: store.lists()
        )
        let record = try perform {
            try store.create(
                title: draft.title, notes: draft.notes, due: draft.due,
                ekPriority: ReminderMapping.ekPriority(from: draft.priority), listID: listID,
                recurrence: draft.recurrence
            )
        }
        if let minutes = draft.estimateMinutes { estimates?.setMinutes(minutes, for: record.id) }
        return map(record, lists: listsByID())
    }

    private func persistEstimate(_ change: FieldChange<Int?>, for reminderID: String) {
        if case .set(let minutes) = change { estimates?.setMinutes(minutes, for: reminderID) }
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
