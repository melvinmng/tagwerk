import Foundation
import TagwerkCore

/// In-memory task source that records every write.
@MainActor
final class FakeTaskProvider: TaskProvider {
    struct AppliedEdit {
        let edit: TaskEdit
        let id: TaskID
        let expectedVersion: String?
    }

    let source: TaskSource
    var tasks: [TaskItem]
    var readError: TaskWriteError?
    /// When set, the next `apply` throws `.conflict(current:)` with this item and replaces the stored one.
    var conflictOnNextApply: TaskItem?
    var applyError: TaskWriteError?
    var offlineSince: Date?
    var offlineReason: String?
    var cached: [TaskItem] = []
    var cachedTasks: [TaskItem] { cached }
    /// When set, `openTasks` takes its snapshot first and then waits for the gate (a slow source).
    var gate: Gate?
    private(set) var openTasksCalls = 0
    private(set) var appliedEdits: [AppliedEdit] = []
    private var revision = 100

    init(source: TaskSource, tasks: [TaskItem] = []) {
        self.source = source
        self.tasks = tasks
    }

    func openTasks() async throws -> [TaskItem] {
        openTasksCalls += 1
        if let readError { throw readError }
        let snapshot = tasks.filter { !$0.isCompleted }
        if let gate { await gate.wait() }
        return snapshot
    }

    func task(id: TaskID) async throws -> TaskItem? {
        tasks.first { $0.id == id }
    }

    func containers() async throws -> [TaskContainer] {
        Array(Set(tasks.map(\.container)))
    }

    func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        appliedEdits.append(AppliedEdit(edit: edit, id: id, expectedVersion: expectedVersion))
        if let applyError { throw applyError }
        if let conflict = conflictOnNextApply {
            conflictOnNextApply = nil
            replace(conflict)
            throw TaskWriteError.conflict(current: conflict)
        }
        guard var item = tasks.first(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        if case .set(let title) = edit.title { item.title = title }
        if case .set(let notes) = edit.notes { item.notes = notes }
        if case .set(let due) = edit.due { item.due = due }
        if case .set(let priority) = edit.priority { item.priority = priority }
        if case .set(let minutes) = edit.estimateMinutes { item.estimateMinutes = minutes }
        if case .set(let completed) = edit.isCompleted { item.isCompleted = completed }
        revision += 1
        item.version = String(revision)
        replace(item)
        return item
    }

    private(set) var deleted: [(TaskID, String?)] = []

    func delete(_ id: TaskID, expectedVersion: String?) async throws {
        deleted.append((id, expectedVersion))
        if let applyError { throw applyError }
        if let conflict = conflictOnNextApply {
            conflictOnNextApply = nil
            replace(conflict)
            throw TaskWriteError.conflict(current: conflict)
        }
        tasks.removeAll { $0.id == id }
    }

    func create(_ draft: TaskDraft) async throws -> TaskItem {
        revision += 1
        let item = TaskItem(
            id: TaskID(source: source, rawValue: "new-\(revision)"), title: draft.title, notes: draft.notes,
            due: draft.due, priority: draft.priority, estimateMinutes: draft.estimateMinutes, isCompleted: false,
            container: TaskContainer(id: draft.containerID ?? "default", name: "Standard", colorHex: nil),
            url: nil, version: String(revision), editableFields: [.title, .notes, .due, .priority]
        )
        tasks.append(item)
        return item
    }

    private func replace(_ item: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == item.id }) {
            tasks[index] = item
        } else {
            tasks.append(item)
        }
    }
}

func makeTask(_ title: String, source: TaskSource, due: DueDate? = nil, version: String = "1") -> TaskItem {
    TaskItem(
        id: TaskID(source: source, rawValue: title), title: title, notes: nil, due: due, priority: nil,
        estimateMinutes: nil, isCompleted: false,
        container: TaskContainer(id: source.rawValue, name: source.rawValue, colorHex: nil),
        url: nil, version: version, editableFields: [.title, .notes, .due, .priority]
    )
}

func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.locale = Locale(identifier: "de_DE")
    return calendar
}

/// Wednesday, 2026-11-18 10:00 in Berlin.
func testNow() -> Date {
    testCalendar().date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10))!
}

/// Suspends callers until `open()` is called.
@MainActor
final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Yields until `condition` holds (bounded), so tests can observe intermediate states.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        await Task.yield()
    }
}
