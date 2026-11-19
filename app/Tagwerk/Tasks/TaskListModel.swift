import Foundation
import Observation
import TagwerkCore

/// Source filter of the task list.
enum TaskFilter: CaseIterable, Hashable {
    case all, reminders, github, local

    var title: String {
        switch self {
        case .all: String(localized: "Alle")
        case .reminders: String(localized: "Erinnerungen")
        case .github: "GitHub"
        case .local: String(localized: "Lokal")
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
    static var tagwerk: Calendar { tagwerk(locale: .current) }

    /// The locale only names things (weekdays, months); the week rules stay Monday first and ISO 8601 numbering
    /// (week 1 holds the first Thursday), because the locale would otherwise change "KW" around New Year (en_US: 1 day).
    static func tagwerk(locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .autoupdatingCurrent
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
    /// Issue that just left the lists because the user is not assigned to it; shown as the "Vergeben" capsule.
    private(set) var lastHandedOver: HandedOverNotice?
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
    /// Called after a written task left the user's lists (handed over to others), so planning can clean up.
    @ObservationIgnored var onHandedOver: ((TaskID) async -> Void)?
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

    /// Every registered source finished loading with its data (live or cached); the widget plan may be rewritten.
    var allSourcesSettled: Bool {
        guard loadingSources.isEmpty, !providers.isEmpty else { return false }
        return providers.allSatisfy { provider in
            switch sourceStates[provider.source] {
            case .loaded?, .offline?: true
            default: false
            }
        }
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
            lastError = String(localized: "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell.")
            await reload(only: [id.source])
        } catch TaskWriteError.signedOut {
            signOut(id.source)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Actions on a selection (same as for one task)

    func complete(_ ids: [TaskID]) async {
        for id in ids { await complete(id) }
    }

    func reschedule(_ ids: [TaskID], option: RescheduleOption) async {
        for id in ids { await reschedule(id, option: option) }
    }

    func delete(_ ids: [TaskID]) async {
        for id in ids { await delete(id) }
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

    func dismissHandedOver() {
        lastHandedOver = nil
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
            let created = try await provider.create(draft)
            nextGeneration(for: source)
            await settle(created, provider: provider, announce: true)
            // The source may drop people silently (GitHub: logins that cannot be assigned).
            let missing = AssigneeRules.missing(requested: draft.assignees, actual: created.assignees)
            if !missing.isEmpty {
                lastError = Self.unassignedMessage(number: created.issueNumber, created: true, missing: missing)
            }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func containers(for source: TaskSource) async -> [TaskContainer] {
        (try? await provider(for: source)?.containers()) ?? []
    }

    /// Stores an item returned by the editor. `requestedAssignees` are the people the editor added;
    /// those missing from the saved item were dropped by the source and are reported.
    func didSave(_ item: TaskItem, requestedAssignees: [String] = []) {
        nextGeneration(for: item.id.source)
        let missing = AssigneeRules.missing(requested: requestedAssignees, actual: item.assignees)
        if !missing.isEmpty {
            lastError = Self.unassignedMessage(number: item.issueNumber, created: false, missing: missing)
        }
        if let previous = items.first(where: { $0.id == item.id }), previous.isCompleted != item.isCompleted,
           let hook = onCompletionChanged {
            Task { await hook(item.id, item.isCompleted) }
        }
        if item.isCompleted {
            items.removeAll { $0.id == item.id }
        } else if let provider = provider(for: item.id.source), !provider.isListed(item) {
            handOver(item, announce: true)
            if let hook = onHandedOver {
                Task { await hook(item.id) }
            }
        } else {
            replace(item)
        }
    }

    func clearError() {
        lastError = nil
    }

    /// Writes with the version of the displayed item. A conflict never overwrites: the list reloads instead.
    // MARK: Writes with results (assistant functions)

    /// Applies `edit` to the displayed version and throws instead of showing an error.
    @discardableResult
    func applyReturning(_ edit: TaskEdit, to id: TaskID) async throws -> TaskItem {
        guard let provider = provider(for: id.source) else { throw TaskWriteError.accessDenied }
        guard let item = items.first(where: { $0.id == id }) else { throw TaskWriteError.notFound }
        do {
            let updated = try await provider.apply(edit, to: id, expectedVersion: item.version)
            nextGeneration(for: id.source)
            if updated.isCompleted {
                items.removeAll { $0.id == id }
                if !item.isCompleted { await onCompletionChanged?(id, true) }
            } else {
                // The assistant reports a hand-over in its own text, so no capsule here.
                await settle(updated, provider: provider, announce: false)
            }
            return updated
        } catch TaskWriteError.conflict(let current) {
            await reload(only: [id.source])
            throw TaskWriteError.conflict(current: current)
        }
    }

    func createReturning(_ draft: TaskDraft, in source: TaskSource) async throws -> TaskItem {
        guard let provider = provider(for: source) else { throw TaskWriteError.accessDenied }
        let created = try await provider.create(draft)
        nextGeneration(for: source)
        // No capsule and no warning: the assistant reports number, link and dropped people in its answer.
        await settle(created, provider: provider, announce: false)
        return created
    }

    func completeReturning(_ id: TaskID) async throws -> TaskItem {
        var edit = TaskEdit()
        edit.isCompleted = .set(true)
        return try await applyReturning(edit, to: id)
    }

    func rescheduleReturning(_ id: TaskID, to due: DueDate?) async throws -> TaskItem {
        var edit = TaskEdit()
        edit.due = .set(due)
        return try await applyReturning(edit, to: id)
    }

    private func write(_ edit: TaskEdit, to id: TaskID, version: String? = nil) async -> TaskItem? {
        guard let provider = provider(for: id.source),
              let expected = version ?? items.first(where: { $0.id == id })?.version else { return nil }
        do {
            let updated = try await provider.apply(edit, to: id, expectedVersion: expected)
            nextGeneration(for: id.source)
            return updated
        } catch TaskWriteError.conflict {
            lastError = String(localized: "Die Aufgabe wurde inzwischen geändert. Die Liste ist jetzt aktuell.")
            await reload()
        } catch TaskWriteError.signedOut {
            signOut(id.source)
        } catch {
            lastError = Self.message(for: error)
        }
        return nil
    }

    /// Puts a written item into the list, or takes it out when the source says it no longer belongs
    /// to the user's lists. Returns whether the item is listed.
    @discardableResult
    private func settle(_ item: TaskItem, provider: any TaskProvider, announce: Bool) async -> Bool {
        guard !provider.isListed(item) else {
            replace(item)
            return true
        }
        handOver(item, announce: announce)
        await onHandedOver?(item.id)
        return false
    }

    private func handOver(_ item: TaskItem, announce: Bool) {
        items.removeAll { $0.id == item.id }
        if announce { lastHandedOver = HandedOverNotice(item: item) }
    }

    /// Warning for people the source dropped silently. `created` names the new issue number first.
    static func unassignedMessage(number: Int?, created: Bool, missing: [String]) -> String {
        let names = missing.formatted(.list(type: .and))
        if created, let number {
            return String(localized: "#\(number) angelegt, aber \(names) konnte nicht zugewiesen werden.")
        }
        return String(localized: "\(names) konnte nicht zugewiesen werden.")
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
        case TaskWriteError.accessDenied: String(localized: "Kein Zugriff auf diese Quelle.")
        case TaskWriteError.signedOut: String(localized: "Die Anmeldung ist abgelaufen. Bitte melde dich neu an.")
        case TaskWriteError.notFound: String(localized: "Die Aufgabe existiert nicht mehr.")
        case TaskWriteError.offline: String(localized: "Offline: Änderungen an GitHub sind gerade nicht möglich.")
        case TaskWriteError.conflict: String(localized: "Die Aufgabe wurde inzwischen geändert.")
        default: error.localizedDescription
        }
    }
}
