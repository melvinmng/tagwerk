import Foundation
import GitHubKit
import Observation
import TagwerkCore

/// Where the search reads from. Everything is a closure so the model needs no EventKit, network or phase 5 types.
struct SearchSources {
    /// Open tasks in app order; already loaded, so reading them is instant.
    var openTasks: @MainActor () -> [TaskItem]
    /// Events of a period; `nil` means no calendar access. The result is already prepared (time blocks dropped,
    /// duplicates merged). The real source fetches off the main thread.
    var events: @MainActor (DateInterval) async -> [CalendarEvent]?
    var calendarNames: @MainActor () -> [String: String]
    var completedTasks: @MainActor () async -> [CompletedTask]
    var notes: @MainActor () -> [NoteSearchItem] = { [] }
    var shopping: @MainActor () -> [ShoppingSearchItem] = { [] }
    /// The hits in the settings for a search text, best first (the index of the settings matches titles and keywords).
    var settings: @MainActor (String) -> [SettingsSearchItem] = { _ in [] }
    /// The repositories and projects of the signed-in GitHub account, read once per search from what is stored on the device (a
    /// request only when nothing is stored yet); `nil` while GitHub is not connected. The text of a search never leaves the device.
    var githubTargets: (@MainActor () async -> [GitHubTargetSearchItem])?
    /// Checks a shopping item off; `nil` while no shopping list is set up.
    var checkOffShopping: (@MainActor (String) async -> Void)?
    /// GitHub issue search for one text; `nil` while GitHub is not connected.
    var searchOnline: (@MainActor (String) async throws -> [OnlineIssue])?
}

/// State of the search sheet: text, filter, loading, paging. Lives as long as the sheet is open and keeps no
/// copy of events or reminders beyond that.
@MainActor
@Observable
final class SearchModel {
    enum EventState: Equatable { case idle, loading, loaded, noAccess }
    enum OnlineState: Equatable { case idle, loading, loaded, failed(IssueSearchError) }

    /// Rows shown per section at first and added by each tap on "Weitere zeigen".
    static let pageSize = 25
    static let debounce = Duration.milliseconds(250)

    var text = "" { didSet { if text != oldValue { textChanged() } } }
    var filter: SearchFilter = .all { didSet { if filter != oldValue { resetPaging(); evaluate() } } }
    var includeCompleted = false { didSet { if includeCompleted != oldValue { includeCompletedChanged() } } }

    private(set) var results: SearchResults = .empty
    private(set) var query: SearchQuery?
    private(set) var eventState: EventState = .idle
    private(set) var onlineState: OnlineState = .idle
    /// Start of the searched period.
    private(set) var windowStart: Date
    private(set) var canExtendWindow = true
    private(set) var isExtendingWindow = false
    private(set) var isLoadingCompleted = false
    /// Set by `close()`; answers that arrive afterwards change nothing.
    private(set) var isClosed = false

    @ObservationIgnored private let sources: SearchSources
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void

    @ObservationIgnored private var loadedEvents: [CalendarEvent] = []
    /// Periods fetched so far: the initial window, then one per extension. A refetch repeats each one,
    /// because EventKit answers at most four years per request.
    @ObservationIgnored private var fetchedIntervals: [DateInterval] = []
    @ObservationIgnored private var completed: [CompletedTask] = []
    @ObservationIgnored private var completedLoaded = false
    @ObservationIgnored private var online: [OnlineIssue]?
    /// Candidates for the section "Repositories & Projekte"; empty until `loadGitHubTargets` has read them (and when GitHub is not connected).
    @ObservationIgnored private var githubTargets: [GitHubTargetSearchItem] = []
    @ObservationIgnored private var githubTargetsTask: Task<Void, Never>?
    @ObservationIgnored private var visibleCounts: [SearchSectionKind: Int] = [:]
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var completedTask: Task<Void, Never>?
    @ObservationIgnored private var refetchRequested = false
    @ObservationIgnored private var onlineGeneration = 0

    init(sources: SearchSources, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk,
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sources = sources
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
        self.windowStart = SearchWindow.initial(now: now(), calendar: calendar).start
    }

    // MARK: Input

    private func textChanged() {
        guard !isClosed else { return }
        let newQuery = SearchQuery(text)
        if newQuery != query {
            query = newQuery
            online = nil
            onlineState = .idle
            onlineGeneration += 1
            resetPaging()
        }
        evaluate()
        guard query != nil else {
            debounceTask?.cancel()
            return
        }
        if eventState == .idle { scheduleEventLoad() }
        loadGitHubTargetsOnce()
    }

    private func includeCompletedChanged() {
        guard !isClosed else { return }
        resetPaging()
        // Every switch-on reads again: tasks may have been completed or reopened while the switch was off.
        if includeCompleted, !isLoadingCompleted { loadCompleted() }
        evaluate()
    }

    // MARK: Events

    /// The first fetch starts 250 ms after the last keystroke; a new keystroke restarts the wait.
    private func scheduleEventLoad() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            await sleep(Self.debounce)
            guard !Task.isCancelled, !isClosed, query != nil, eventState == .idle else { return }
            startInitialLoad()
        }
    }

    private func startInitialLoad() {
        eventState = .loading
        let interval = SearchWindow.initial(now: now(), calendar: calendar)
        windowStart = interval.start
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await sources.events(interval)
            guard !isClosed else { return }
            if let result {
                loadedEvents = result
                fetchedIntervals = [interval]
                eventState = .loaded
                canExtendWindow = SearchWindow.canExtend(lastYearWasEmpty: false, start: windowStart, now: now(), calendar: calendar)
            } else {
                loadedEvents = []
                eventState = .noAccess
            }
            evaluate()
            if refetchRequested {
                refetchRequested = false
                await refetchEvents()
            }
        }
    }

    /// "Ältere Termine durchsuchen": one more year before the searched period; stays until the sheet closes.
    func extendWindow() async {
        guard !isClosed, eventState == .loaded, canExtendWindow, !isExtendingWindow else { return }
        isExtendingWindow = true
        defer { isExtendingWindow = false }
        let interval = SearchWindow.extended(before: windowStart, calendar: calendar)
        guard let result = await sources.events(interval), !isClosed else { return }
        let known = Set(loadedEvents.map(\.id))
        loadedEvents += result.filter { !known.contains($0.id) }
        fetchedIntervals.append(interval)
        windowStart = interval.start
        canExtendWindow = SearchWindow.canExtend(lastYearWasEmpty: result.isEmpty, start: windowStart, now: now(), calendar: calendar)
        evaluate()
    }

    /// EventKit reported a change: fetch the searched period again.
    func eventStoreChanged() {
        guard !isClosed else { return }
        switch eventState {
        case .loaded: Task { await refetchEvents() }
        case .loading: refetchRequested = true
        case .idle, .noAccess: break
        }
    }

    /// After a sheet over the search closed: events, completed tasks and rows are read again.
    func refresh() async {
        guard !isClosed else { return }
        if eventState == .loaded { await refetchEvents() }
        if includeCompleted, completedLoaded { await reloadCompleted() }
        evaluate()
    }

    private func refetchEvents() async {
        let intervals = fetchedIntervals
        var fresh: [CalendarEvent] = []
        var seen = Set<String>()
        for interval in intervals {
            guard let part = await sources.events(interval) else { return }
            for event in part where seen.insert(event.id).inserted { fresh.append(event) }
        }
        guard !isClosed, intervals == fetchedIntervals else { return }
        loadedEvents = fresh
        evaluate()
    }

    // MARK: Completed tasks

    private func loadCompleted() {
        isLoadingCompleted = true
        completedTask = Task { [weak self] in
            guard let self else { return }
            await reloadCompleted()
        }
    }

    private func reloadCompleted() async {
        isLoadingCompleted = true
        let result = await sources.completedTasks()
        guard !isClosed else { return }
        completed = result
        completedLoaded = true
        isLoadingCompleted = false
        evaluate()
    }

    // MARK: Online

    /// "Auf GitHub suchen" is offered while GitHub is connected, a text is there and events are not the only filter.
    var showsOnlineSearchRow: Bool {
        guard sources.searchOnline != nil, query != nil, filter != .events else { return false }
        switch onlineState {
        case .idle, .failed: return true
        case .loading, .loaded: return false
        }
    }

    /// The tap on "Auf GitHub suchen": the only moment a search text leaves the device.
    func searchOnline() async {
        guard !isClosed, let source = sources.searchOnline, let query, onlineState != .loading else { return }
        let generation = onlineGeneration
        onlineState = .loading
        let outcome: Result<[OnlineIssue], Error>
        do { outcome = .success(try await source(query.text)) } catch { outcome = .failure(error) }
        // A newer text or a closed sheet makes this answer obsolete.
        guard !isClosed, generation == onlineGeneration else { return }
        switch outcome {
        case .success(let issues):
            online = issues
            onlineState = .loaded
        case .failure(let error):
            online = nil
            onlineState = .failed((error as? IssueSearchError) ?? .failed(error.localizedDescription))
        }
        evaluate()
    }

    // MARK: GitHub repositories and projects

    /// Reads the repositories and projects at the first search text; no later keystroke asks again. A failed read leaves the list empty
    /// without a message: the section is simply not there (offline, not signed in).
    private func loadGitHubTargetsOnce() {
        guard let source = sources.githubTargets, githubTargetsTask == nil else { return }
        githubTargetsTask = Task { [weak self] in
            let items = await source()
            guard let self, !isClosed, !Task.isCancelled else { return }
            githubTargets = items
            evaluate()
        }
    }

    // MARK: Shopping

    /// The circle of a shopping row: the source checks the item off, then the rows are read again.
    func checkOff(_ item: ShoppingSearchItem) async {
        guard !isClosed, let checkOff = sources.checkOffShopping else { return }
        await checkOff(item.id)
        evaluate()
    }

    // MARK: Results

    /// Filters everything that is loaded for the current text; tasks, notes and shopping are always current.
    func evaluate() {
        guard !isClosed, let query else {
            results = .empty
            return
        }
        let input = SearchInput(events: eventState == .loaded ? loadedEvents : nil, calendarNames: sources.calendarNames(),
                                openTasks: sources.openTasks(), completed: completedLoaded ? completed : [], online: online,
                                notes: sources.notes(), shopping: sources.shopping(),
                                settings: filter == .all ? sources.settings(query.text) : [],
                                githubTargets: filter == .all ? githubTargets : [])
        results = SearchResults.make(query: query, filter: filter, includeCompleted: includeCompleted, input: input,
                                     now: now(), calendar: calendar)
    }

    /// Name of the calendar an event comes from, for the row.
    func calendarName(of event: CalendarEvent) -> String? {
        sources.calendarNames()[event.calendarID]
    }

    func visibleRows(in section: SearchSection) -> [SearchRow] {
        Array(section.rows.prefix(visibleCounts[section.kind] ?? Self.pageSize))
    }

    func hiddenCount(in section: SearchSection) -> Int {
        max(0, section.rows.count - (visibleCounts[section.kind] ?? Self.pageSize))
    }

    func showMore(_ kind: SearchSectionKind) {
        visibleCounts[kind] = (visibleCounts[kind] ?? Self.pageSize) + Self.pageSize
    }

    private func resetPaging() {
        visibleCounts = [:]
    }

    /// Stops running work; answers that arrive later change nothing.
    func close() {
        isClosed = true
        debounceTask?.cancel()
        loadTask?.cancel()
        completedTask?.cancel()
        githubTargetsTask?.cancel()
        // Nothing of the search outlives the sheet.
        loadedEvents = []
        githubTargets = []
        completed = []
        online = nil
        results = .empty
    }

    #if DEBUG
    /// Lets tests wait for the debounce and the running fetch.
    func settle() async {
        await debounceTask?.value
        await loadTask?.value
        await completedTask?.value
        await githubTargetsTask?.value
    }
    #endif
}
