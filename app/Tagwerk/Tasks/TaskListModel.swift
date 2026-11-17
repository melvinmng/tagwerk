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

    /// Source preselected by "＋": the filtered source, or Reminders for "Alle"; Local if unavailable.
    func creationTarget(available: Set<TaskSource>) -> TaskSource {
        let preferred: TaskSource = switch self {
        case .all, .reminders: .reminders
        case .github: .github
        case .local: .local
        }
        return available.contains(preferred) ? preferred : .local
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
    /// The sign-in ended; the source was removed until the user signs in again.
    case signedOut
    /// Shown from the offline cache with the time of the cached data and, for errors other than a
    /// missing connection, the reason.
    case offline(since: Date, reason: String? = nil)

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}

extension Calendar {
    /// Calendar used for all date logic: Gregorian, week starting on Monday. The time zone follows
    /// system changes while the app runs, so "today" stays correct after travelling.
    static var tagwerk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .autoupdatingCurrent
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
    /// Task to scroll to and mark briefly after "Aufgabe zeigen" (design §13.8 G3).
    private(set) var highlightedTaskID: TaskID?
    private(set) var lastError: String?
    /// Sources whose current load has not finished yet.
    private(set) var loadingSources: Set<TaskSource> = []

    private(set) var providers: [any TaskProvider]
    /// Sources whose sign-in ended; their state stays visible until they are registered again.
    private var signedOutSources: Set<TaskSource> = []
    /// Load generation per source; results of older loads are discarded.
    @ObservationIgnored private var generations: [TaskSource: Int] = [:]
    /// Called once when a source reports that its sign-in ended.
    @ObservationIgnored var onSignedOut: ((TaskSource) -> Void)?
    /// Called after a task was completed (`true`) or reopened (`false`) through Tagwerk.
    @ObservationIgnored var onCompletionChanged: ((TaskID, Bool) async -> Void)?
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

    /// Loads the given sources (all when `nil`) concurrently and publishes each source as soon as
    /// it answers, so a slow source never delays the others.
    func reload(only sources: Set<TaskSource>? = nil) async {
        let targets = providers.filter { sources?.contains($0.source) ?? true }
        let loads = targets.map { provider in
            let generation = nextGeneration(for: provider.source)
            return Task { await self.load(provider, generation: generation) }
        }
        for load in loads { await load.value }

        // Drop items and states of sources that are no longer registered (signed-out states stay).
        let registered = Set(providers.map(\.source))
        items.removeAll { !registered.contains($0.id.source) }
        for source in sourceStates.keys where !registered.contains(source) && !signedOutSources.contains(source) {
            sourceStates[source] = nil
        }
    }

    private func load(_ provider: any TaskProvider, generation: Int) async {
        let source = provider.source
        loadingSources.insert(source)
        if !items.contains(where: { $0.id.source == source }) {
            items += provider.cachedTasks  // show the last known state while loading
        }
        let result: Result<[TaskItem], Error>
        do {
            result = .success(try await provider.openTasks())
        } catch {
            result = .failure(error)
        }
        // A newer load or a write to this source started meanwhile: this snapshot is stale.
        guard generations[source] == generation else { return }
        loadingSources.remove(source)

        switch result {
        case .success(let loaded):
            items.removeAll { $0.id.source == source }
            items += loaded
            sourceStates[source] = provider.offlineSince.map { .offline(since: $0, reason: provider.offlineReason) } ?? .loaded
        case .failure(TaskWriteError.signedOut):
            signOut(source)
        case .failure(TaskWriteError.accessDenied):
            items.removeAll { $0.id.source == source }
            sourceStates[source] = .noAccess
        case .failure(let error):
            items.removeAll { $0.id.source == source }
            sourceStates[source] = .failed(Self.message(for: error))
        }
    }

    @discardableResult
    private func nextGeneration(for source: TaskSource) -> Int {
        let next = (generations[source] ?? 0) + 1
        generations[source] = next
        return next
    }

    /// Adds a source (e.g. after signing in) and loads the list.
    func register(_ provider: any TaskProvider) async {
        providers.removeAll { $0.source == provider.source }
        providers.append(provider)
        signedOutSources.remove(provider.source)
        nextGeneration(for: provider.source)
        await reload()
    }

    /// Removes a source after a voluntary sign-out.
    func unregister(_ source: TaskSource) async {
        nextGeneration(for: source)  // results of loads still running are discarded
        loadingSources.remove(source)
        providers.removeAll { $0.source == source }
        signedOutSources.remove(source)
        await reload()
    }

    private func signOut(_ source: TaskSource) {
        nextGeneration(for: source)
        loadingSources.remove(source)
        providers.removeAll { $0.source == source }
        items.removeAll { $0.id.source == source }
        signedOutSources.insert(source)
        sourceStates[source] = .signedOut
        onSignedOut?(source)
    }

    func complete(_ id: TaskID) async {
        var edit = TaskEdit()
        edit.isCompleted = .set(true)
        guard let updated = await write(edit, to: id) else { return }
        items.removeAll { $0.id == id }
        lastCompleted = updated
        await onCompletionChanged?(id, true)
    }

    /// Reopens the task completed last ("Rückgängig").
    func undoComplete() async {
        guard let completed = lastCompleted else { return }
        lastCompleted = nil
        var edit = TaskEdit()
        edit.isCompleted = .set(false)
        guard let reopened = await write(edit, to: completed.id, version: completed.version) else { return }
        replace(reopened)
        await onCompletionChanged?(completed.id, false)
    }

    /// Deletes (GitHub: closes as not planned) with the displayed version, or `version` from the editor.
    func delete(_ id: TaskID, version: String? = nil) async {
        guard let provider = provider(for: id.source),
              let expected = version ?? items.first(where: { $0.id == id })?.version else { return }
        do {
            try await provider.delete(id, expectedVersion: expected)
            nextGeneration(for: id.source)
            items.removeAll { $0.id == id }
        } catch TaskWriteError.conflict {
            lastError = "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell."
            await reload(only: [id.source])
        } catch TaskWriteError.signedOut {
            signOut(id.source)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func highlight(_ id: TaskID) {
        highlightedTaskID = id
    }

    func clearHighlight() {
        highlightedTaskID = nil
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
            replace(try await provider.create(draft))
            nextGeneration(for: source)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func containers(for source: TaskSource) async -> [TaskContainer] {
        (try? await provider(for: source)?.containers()) ?? []
    }

    /// Stores an item returned by the editor.
    func didSave(_ item: TaskItem) {
        nextGeneration(for: item.id.source)
        if let previous = items.first(where: { $0.id == item.id }), previous.isCompleted != item.isCompleted,
           let hook = onCompletionChanged {
            Task { await hook(item.id, item.isCompleted) }
        }
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
            let updated = try await provider.apply(edit, to: id, expectedVersion: expected)
            nextGeneration(for: id.source)
            return updated
        } catch TaskWriteError.conflict {
            lastError = "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell."
            await reload()
        } catch TaskWriteError.signedOut {
            signOut(id.source)
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
        case TaskWriteError.signedOut: "Die Anmeldung ist abgelaufen. Bitte melde dich neu an."
        case TaskWriteError.notFound: "Die Aufgabe existiert nicht mehr."
        case TaskWriteError.offline: "Offline: Änderungen an GitHub sind gerade nicht möglich."
        case TaskWriteError.conflict: "Die Aufgabe wurde inzwischen geändert."
        default: error.localizedDescription
        }
    }
}
