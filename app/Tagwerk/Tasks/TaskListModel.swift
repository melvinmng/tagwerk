import Foundation
import Observation
import TagwerkCore

/// Source filter of the task list.
enum TaskFilter: CaseIterable, Hashable {
    case all, reminders, github, local

    var title: String {
        switch self {
        case .all: "Alle"
        case .reminders: "Erinnerungen"
        case .github: "GitHub"
        case .local: "Lokal"
        }
    }

    var sources: Set<TaskSource> {
        switch self {
        case .all: Set(TaskSource.allCases)
        case .reminders: [.reminders]
        case .github: [.github]
        case .local: [.local]
        }
    }
}

/// Load state of one source.
enum SourceState: Equatable {
    case loaded, noAccess, failed(String)
    /// Shown from the offline cache with the time of the cached data.
    case offline(since: Date)

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}

extension Calendar {
    /// Calendar used for all date logic: Gregorian, week starting on Monday, current time zone.
    static var tagwerk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }
}

/// State and actions of the task list across all sources.
@MainActor
@Observable
final class TaskListModel {
    var filter: TaskFilter = .all
    private(set) var items: [TaskItem] = []
    private(set) var sourceStates: [TaskSource: SourceState] = [:]
    private(set) var lastCompleted: TaskItem?
    private(set) var lastError: String?

    var providers: [any TaskProvider]
    let now: () -> Date
    let calendar: Calendar

    init(providers: [any TaskProvider], now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        self.providers = providers
        self.now = now
        self.calendar = calendar
    }

    /// Filters offered in the list; GitHub only appears once a GitHub source is registered.
    var availableFilters: [TaskFilter] {
        let registered = Set(providers.map(\.source))
        return TaskFilter.allCases.filter { $0 == .all || !$0.sources.isDisjoint(with: registered) }
    }

    var sections: [(TaskSection, [TaskItem])] {
        let visible = items.filter { filter.sources.contains($0.id.source) }
        return groupedSections(visible, now: now(), calendar: calendar)
    }

    func provider(for source: TaskSource) -> (any TaskProvider)? {
        providers.first { $0.source == source }
    }

    func reload() async {
        var loaded: [TaskItem] = []
        var states: [TaskSource: SourceState] = [:]
        for provider in providers {
            do {
                loaded += try await provider.openTasks()
                states[provider.source] = provider.offlineSince.map { .offline(since: $0) } ?? .loaded
            } catch TaskWriteError.accessDenied {
                states[provider.source] = .noAccess
            } catch {
                states[provider.source] = .failed(Self.message(for: error))
            }
        }
        items = loaded
        sourceStates = states
    }

    func complete(_ id: TaskID) async {
        var edit = TaskEdit()
        edit.isCompleted = .set(true)
        guard let updated = await write(edit, to: id) else { return }
        items.removeAll { $0.id == id }
        lastCompleted = updated
    }

    /// Reopens the task completed last ("Rückgängig").
    func undoComplete() async {
        guard let completed = lastCompleted else { return }
        lastCompleted = nil
        var edit = TaskEdit()
        edit.isCompleted = .set(false)
        guard let reopened = await write(edit, to: completed.id, version: completed.version) else { return }
        items.append(reopened)
    }

    func dismissUndo() {
        lastCompleted = nil
    }

    func reschedule(_ id: TaskID, option: RescheduleOption) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        var edit = TaskEdit()
        edit.due = .set(rescheduled(item.due, option: option, now: now(), calendar: calendar))
        guard let updated = await write(edit, to: id) else { return }
        replace(updated)
    }

    func create(_ draft: TaskDraft, in source: TaskSource) async {
        guard let provider = provider(for: source) else { return }
        do {
            items.append(try await provider.create(draft))
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func containers(for source: TaskSource) async -> [TaskContainer] {
        (try? await provider(for: source)?.containers()) ?? []
    }

    /// Stores an item returned by the editor.
    func didSave(_ item: TaskItem) {
        if item.isCompleted {
            items.removeAll { $0.id == item.id }
        } else {
            replace(item)
        }
    }

    func clearError() {
        lastError = nil
    }

    /// Writes with the version of the displayed item. A conflict never overwrites: the list reloads instead.
    private func write(_ edit: TaskEdit, to id: TaskID, version: String? = nil) async -> TaskItem? {
        guard let provider = provider(for: id.source),
              let expected = version ?? items.first(where: { $0.id == id })?.version else { return nil }
        do {
            return try await provider.apply(edit, to: id, expectedVersion: expected)
        } catch TaskWriteError.conflict {
            lastError = "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell."
            await reload()
        } catch {
            lastError = Self.message(for: error)
        }
        return nil
    }

    private func replace(_ item: TaskItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case TaskWriteError.failed(let message): message
        case TaskWriteError.accessDenied: "Kein Zugriff auf diese Quelle."
        case TaskWriteError.notFound: "Die Aufgabe existiert nicht mehr."
        case TaskWriteError.offline: "Offline: Änderungen an GitHub sind gerade nicht möglich."
        case TaskWriteError.conflict: "Die Aufgabe wurde inzwischen geändert."
        default: error.localizedDescription
        }
    }
}
