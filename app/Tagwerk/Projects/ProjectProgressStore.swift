import Foundation
import Observation
import TagwerkCore

/// The projects the app can show, and what is missing for the others.
struct ProjectCatalog: Equatable {
    var references: [ProjectProgressReference] = []
    /// GitHub is signed in; without it no GitHub project or repository is listed.
    var gitHubConnected = false
    /// Full access to Reminders; without it no reminder list is listed.
    var remindersAccess = false
}

/// The items of one project as loaded, with the time of loading.
struct ProjectFactsLoad: Equatable {
    var facts: [ProjectItemFact]
    /// The source stopped at its page limit; older or later items are missing.
    var isTruncated = false
    var fetchedAt: Date
}

/// Why the items of a project could not be loaded.
enum ProjectLoadFailure: Error, Equatable {
    case notConnected
    case noAccess
    case offline
    case rateLimited
    case other
}

/// Where the project progress gets its data: the list of projects and the items of one project. Closures, so the store runs without
/// EventKit and the network in tests and in the UI test mode.
struct ProjectProgressSources {
    var catalog: @MainActor () async -> ProjectCatalog
    var facts: @MainActor (ProjectProgressReference) async throws -> ProjectFactsLoad
    /// The time recorded for the given tasks (`TaskID.key`) inside a range: planned blocks, focus sessions, measured completions. It
    /// depends on the period, so it is not part of the loaded facts. Without a source no time is known.
    var time: @MainActor (Set<String>, ProjectRange) -> ProjectTimeInputs = { _, _ in ProjectTimeInputs() }
}

/// Loads and keeps the items of the projects for the overview and the project pages. One instance lives in the app environment, so a
/// page opened from the global search finds what the overview loaded a moment ago, and the other way round.
@MainActor
@Observable
final class ProjectProgressStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(ProjectFactsLoad)
        /// Loading failed; `stale` is the earlier result, if there is one.
        case failed(ProjectLoadFailure, stale: ProjectFactsLoad?)

        /// The items to show: the loaded ones, or the earlier ones after a failed reload.
        var load: ProjectFactsLoad? {
            switch self {
            case .loaded(let load): load
            case .failed(_, let stale): stale
            case .idle, .loading: nil
            }
        }
    }

    /// Age after which opening a page loads a project again.
    static let maxAge: TimeInterval = 5 * 60
    /// How many GitHub projects load at the same time in the overview (the requests are cheap, but a phone should not open 20 at once).
    static let concurrentLoads = 2

    private(set) var catalog = ProjectCatalog()
    private(set) var isCatalogLoaded = false
    private(set) var states: [String: LoadState] = [:]
    @ObservationIgnored private let sources: ProjectProgressSources
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var running: [String: Task<Void, Never>] = [:]

    init(sources: ProjectProgressSources, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.now = now
    }

    func state(of reference: ProjectProgressReference) -> LoadState { states[reference.key] ?? .idle }

    /// The items of a project that are loaded or stale, in the order the sources delivered them.
    func facts(of reference: ProjectProgressReference) -> ProjectFactsLoad? { state(of: reference).load }

    /// What the app recorded about time for the tasks of a project in `range`; read on the device, no request.
    func timeInputs(taskKeys: Set<String>, range: ProjectRange) -> ProjectTimeInputs {
        sources.time(taskKeys, range)
    }

    func reloadCatalog() async {
        catalog = await sources.catalog()
        isCatalogLoaded = true
    }

    /// Loads one project. A result younger than `maxAge` is kept unless `force`; a load that is running is awaited, not started twice.
    func load(_ reference: ProjectProgressReference, force: Bool = false) async {
        let key = reference.key
        if let task = running[key] {
            await task.value
            return
        }
        if !force, case .loaded(let load) = state(of: reference), now().timeIntervalSince(load.fetchedAt) < Self.maxAge { return }
        let stale = state(of: reference).load
        states[key] = .loading
        let task = Task { @MainActor [sources] in
            do {
                self.states[key] = .loaded(try await sources.facts(reference))
            } catch let failure as ProjectLoadFailure {
                self.states[key] = .failed(failure, stale: stale)
            } catch {
                self.states[key] = .failed(.other, stale: stale)
            }
        }
        running[key] = task
        await task.value
        running[key] = nil
    }

    /// Reads the catalog and loads every project, `concurrentLoads` at a time. Projects without a connection fail fast and show
    /// their reason in the row.
    func loadAll(force: Bool = false) async {
        await reloadCatalog()
        let references = catalog.references
        var index = 0
        while index < references.count {
            let batch = references[index..<min(index + Self.concurrentLoads, references.count)]
            let tasks = batch.map { reference in Task { await self.load(reference, force: force) } }
            for task in tasks { await task.value }
            index += Self.concurrentLoads
        }
    }

    // MARK: Entry row

    /// "5 Projekte · 1 ruht" from what is loaded; `nil` while nothing was loaded yet. Reads no source, so showing the entry row never
    /// starts a request.
    func entrySubtitle(calendar: Calendar) -> String? {
        let summaries = catalog.references.compactMap { reference -> ProjectSummary? in
            guard let load = facts(of: reference) else { return nil }
            return ProjectProgress.summary(facts: load.facts, period: .fourWeeks, now: now(), calendar: calendar)
        }
        guard !summaries.isEmpty else { return nil }
        let resting = summaries.filter { if case .resting = $0.trend { true } else { false } }.count
        let projects = String(localized: "\(summaries.count) Projekte")
        return resting > 0 ? projects + " · " + String(localized: "ruhend: \(resting)") : projects
    }
}
