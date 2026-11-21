import Foundation
import Observation
import TagwerkCore

/// Task source for issues assigned to the user in their open GitHub Projects.
@MainActor
@Observable
public final class GitHubTaskProvider: TaskProvider {
    public let source: TaskSource = .github
    public private(set) var offlineSince: Date?
    public private(set) var offlineReason: String?
    public private(set) var projects: [ProjectInfo] = []
    public private(set) var login: String?

    @ObservationIgnored public let api: GitHubAPI
    @ObservationIgnored let tokens: TokenManager
    @ObservationIgnored private let cache: GitHubCache
    @ObservationIgnored private let catalogStore: GitHubCatalogStore?
    @ObservationIgnored private let selectedProjectIDs: @MainActor () -> Set<String>?
    @ObservationIgnored let now: () -> Date
    /// Full records of visible issues, keyed by issue node ID (all placements, unfiltered).
    private(set) var records: [String: GitHubIssueRecord] = [:]

    public init(api: GitHubAPI, tokens: TokenManager, cache: GitHubCache, catalogStore: GitHubCatalogStore? = nil,
                selectedProjectIDs: @escaping @MainActor () -> Set<String>?, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.tokens = tokens
        self.cache = cache
        self.catalogStore = catalogStore
        self.selectedProjectIDs = selectedProjectIDs
        self.now = now
    }

    /// Tasks from the offline cache, available before the first request finishes.
    public var cachedTasks: [TaskItem] {
        if records.isEmpty, let cached = cache.load() {
            remember(cached.records)
            if projects.isEmpty { projects = Self.projects(in: cached.records) }
        }
        return displayed()
    }

    /// Projects selected when the user has not chosen any (design §12.1).
    public var defaultSelectedProjectIDs: Set<String> {
        GitHubMapping.defaultSelectedProjectIDs(projects: projects, visibleIssues: Array(records.values))
    }

    public func openTasks() async throws -> [TaskItem] {
        do {
            // An unreadable keychain throws here and shows the cache below; only missing credentials sign out.
            guard try await tokens.hasCredentials() else { throw TaskWriteError.signedOut }
            let result = try await api.openProjectIssues()
            let visible = result.issues.filter { GitHubMapping.isVisible($0, login: result.login) }
            login = result.login
            projects = result.projects
            remember(visible)
            // A sign-out during the request already cleared the cache; do not write it back.
            guard try await tokens.hasCredentials() else { throw TaskWriteError.signedOut }
            cache.store(visible, fetchedAt: now())
            offlineSince = nil
            offlineReason = nil
            return displayed()
        } catch {
            // Any read failure except an ended sign-in shows the cache (design §9: "Offline / Fehler").
            let mapped = Self.taskError(error)
            if mapped == .signedOut { throw mapped }
            guard let cached = cache.load() else {
                throw mapped == .offline ? TaskWriteError.failed(String(localized: "Keine Verbindung zu GitHub.", bundle: .module)) : mapped
            }
            remember(cached.records)
            if projects.isEmpty { projects = Self.projects(in: cached.records) }
            offlineSince = cached.fetchedAt
            if case .failed(let message) = mapped { offlineReason = message } else { offlineReason = nil }
            return displayed()
        }
    }

    public func task(id: TaskID) async throws -> TaskItem? {
        do {
            guard let record = try await api.issue(nodeID: id.rawValue) else { return nil }
            records[record.issueID] = record
            return GitHubMapping.taskItem(record)
        } catch GitHubAPIError.network {
            return records[id.rawValue].map(GitHubMapping.taskItem)
        } catch {
            throw Self.taskError(error)
        }
    }

    public func containers() async throws -> [TaskContainer] {
        Set(records.values.map(\.repository)).sorted().map { TaskContainer(id: $0, name: $0, colorHex: nil) }
    }

    /// Reloads the issue, compares versions and writes in a fixed order: issue fields (including closing),
    /// project fields, project status per project, reopening after a status change, assignees. The result
    /// is read again afterwards, because project workflows may change the status on their own.
    /// Repository, number and node ID of a loaded issue, for the issue chat (design §8.3).
    public func issueReference(for id: TaskID) -> (repository: String, number: Int, nodeID: String)? {
        records[id.rawValue].map { ($0.repository, $0.number, $0.issueID) }
    }

    public func addComment(_ body: String, to id: TaskID) async throws {
        guard let record = records[id.rawValue] else { throw TaskWriteError.notFound }
        struct Comment: Encodable, Sendable { let body: String }
        do {
            try await api.rest("POST", "repos/\(record.repository)/issues/\(record.number)/comments", body: Comment(body: body))
        } catch {
            throw Self.taskError(error)
        }
    }

    public func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        do {
            guard let current = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            let currentItem = GitHubMapping.taskItem(current)
            if let expectedVersion, expectedVersion != currentItem.version {
                records[current.issueID] = current
                throw TaskWriteError.conflict(current: currentItem)
            }
            if case .set(let change) = edit.assignees {
                // The own login decides below whether the issue stays remembered.
                if login == nil { login = try await api.viewerProjects().login }
                guard AssigneeRules.applying(change, to: current.assignees).count <= AssigneeRules.maximum else {
                    throw Self.tooManyAssignees
                }
            }
            try await write(edit, to: current)
            guard let fresh = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            if let login, !AssigneeRules.contains(fresh.assignees, login) {
                // Handed over: the issue no longer belongs to the user's lists. Closed issues stay
                // remembered as before, because completing and undoing build on the record.
                records[fresh.issueID] = nil
            } else {
                records[fresh.issueID] = fresh
            }
            offlineSince = nil
            let full = GitHubMapping.taskItem(fresh)
            // A listed issue comes back as the list shows it (placements of the selection only). An issue that left
            // the lists keeps all placements, so the capsule can name the other projects.
            guard unlistedReason(full) == nil else { return full }
            return displayedItem(fresh, selection: selectedProjectIDs() ?? defaultSelectedProjectIDs) ?? full
        } catch {
            throw Self.taskError(error)
        }
    }

    /// Issues are never deleted on GitHub: "delete" closes the issue as not planned and sets
    /// "Done" in all its projects, after the usual version check.
    public func delete(_ id: TaskID, expectedVersion: String?) async throws {
        do {
            guard let current = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            let currentItem = GitHubMapping.taskItem(current)
            if let expectedVersion, expectedVersion != currentItem.version {
                throw TaskWriteError.conflict(current: currentItem)
            }
            let writer = GitHubWriter(api: api)
            try await writer.updateIssue(current, title: nil, body: nil, labels: nil, state: .closeNotPlanned)
            for placement in current.placements where placement.project.canWrite {
                guard let done = GitHubMapping.doneOption(in: placement.project) else { continue }
                try await writer.setField(placement, fieldName: GitHubMapping.statusField, value: .singleSelect(done))
            }
            records[current.issueID] = nil
        } catch {
            throw Self.taskError(error)
        }
    }

    /// Posts a comment. A comment changes the issue's version, so the fresh item is returned when
    /// the issue was unchanged before posting; callers adopt its version to avoid a false conflict.
    /// Returns `nil` when the issue had changed meanwhile (the comment is posted anyway).
    public func addComment(to id: TaskID, body: String, expectedVersion: String) async throws -> TaskItem? {
        do {
            guard let before = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            let unchanged = GitHubMapping.taskItem(before).version == expectedVersion
            try await GitHubWriter(api: api).addComment(before, body: body)
            guard let fresh = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            records[fresh.issueID] = fresh
            return unchanged ? GitHubMapping.taskItem(fresh) : nil
        } catch {
            throw Self.taskError(error)
        }
    }

    /// Creates an issue in `draft.containerID` (repository), assigned to `draft.assignees` or, when
    /// those are `nil`, to the viewer, and adds it to every project in `draft.subContainerIDs` (none is
    /// allowed) with the draft's field values and status: `draft.startStatus`, otherwise "Ready" or the
    /// first stage of the project that is not "Done". The status is validated against every project
    /// before the issue is created. The returned item carries the assignees GitHub actually set; an issue
    /// that is not visible for the viewer (not assigned, or without a project) is returned but not remembered.
    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        guard let repository = draft.containerID else {
            throw TaskWriteError.failed(String(localized: "Bitte ein Repository wählen.", bundle: .module))
        }
        if let chosen = draft.assignees, chosen.count > AssigneeRules.maximum { throw Self.tooManyAssignees }
        do {
            let (viewer, available) = try await api.viewerProjects()
            login = viewer
            projects = available
            let targets = draft.subContainerIDs.compactMap { id in available.first { $0.id == id } }
            guard targets.count == draft.subContainerIDs.count else { throw TaskWriteError.notFound }
            let startStatuses = try targets.map { try Self.startStatus(in: $0, requested: draft.startStatus) }

            let writer = GitHubWriter(api: api)
            let issueID = try await writer.createIssue(repository: repository, title: draft.title, body: draft.notes,
                                                       assignees: draft.assignees ?? [viewer])
            for (project, status) in zip(targets, startStatuses) {
                try await addToProject(project, issueID: issueID, draft: draft, status: status, writer: writer)
            }

            guard let fresh = try await api.issue(nodeID: issueID) else { throw TaskWriteError.notFound }
            if GitHubMapping.isVisible(fresh, login: viewer) { records[fresh.issueID] = fresh }
            return GitHubMapping.taskItem(fresh)
        } catch {
            throw Self.taskError(error)
        }
    }

    /// Start status of a new issue in `project`: the requested one (it must exist there and must not be
    /// "Done", because the issue would be open but hidden), else the reopen option; `nil` skips the field.
    private static func startStatus(in project: ProjectInfo, requested: String?) throws -> String? {
        guard let requested else { return GitHubMapping.reopenOption(in: project) }
        if GitHubMapping.isDone(requested) {
            throw TaskWriteError.failed(String(localized: "Ein neues Issue kann nicht mit dem Status „Done“ beginnen.", bundle: .module))
        }
        guard let option = GitHubMapping.statusOption(named: requested, in: project) else {
            throw missingStatus(requested, in: project)
        }
        return option
    }

    private static func missingStatus(_ status: String, in project: ProjectInfo) -> TaskWriteError {
        .failed(String(localized: "Den Status „\(status)“ gibt es im Projekt „\(project.title)“ nicht.", bundle: .module))
    }

    private static var tooManyAssignees: TaskWriteError {
        .failed(String(localized: "Höchstens 10 Personen je Issue.", bundle: .module))
    }

    private func addToProject(_ project: ProjectInfo, issueID: String, draft: TaskDraft, status: String?,
                              writer: GitHubWriter) async throws {
        let itemID = try await writer.addToProject(projectID: project.id, contentID: issueID)
        let placement = ProjectPlacement(project: project, itemID: itemID, itemUpdatedAt: now(),
                                         status: nil, priority: nil, due: nil, estimateMinutes: nil)
        if let due = draft.due {
            try await writer.setField(placement, fieldName: GitHubMapping.dueField, value: .date(due))
        }
        if let priority = draft.priority, let option = GitHubMapping.priorityOption(priority, in: project) {
            try await writer.setField(placement, fieldName: GitHubMapping.priorityField, value: .singleSelect(option))
        }
        if let minutes = draft.estimateMinutes, let fieldName = GitHubMapping.estimateFieldName(in: project) {
            try await writer.setField(placement, fieldName: fieldName,
                                      value: .number(GitHubMapping.fieldValue(fromMinutes: minutes, fieldName: fieldName)))
        }
        if let status {
            try await writer.setField(placement, fieldName: GitHubMapping.statusField, value: .singleSelect(status))
        }
    }

    /// Repositories and projects for creating an issue: the stored catalog while it is younger than
    /// `maxAge`, otherwise fetched again. Offline, the stored catalog is returned regardless of age.
    public func catalog(maxAge: TimeInterval) async -> GitHubCatalog? {
        let stored = catalogStore?.load()
        if let stored, now().timeIntervalSince(stored.fetchedAt) < maxAge { return stored }
        do {
            async let repositories = api.ownedRepositories()
            async let viewer = api.viewerProjects()
            let fetched = try await repositories
            // Assignable people are loaded per repository on demand; a reload keeps them for repositories that remain.
            let kept = (stored?.assignable ?? [:]).filter { fetched.contains($0.key) }
            let fresh = GitHubCatalog(repositories: fetched, projects: try await viewer.projects, fetchedAt: now(), assignable: kept)
            catalogStore?.store(fresh)
            return fresh
        } catch {
            return stored
        }
    }

    /// The stored catalog without any request, for callers that cannot wait (assistant card).
    public var storedCatalog: GitHubCatalog? { catalogStore?.load() }

    /// People who can be assigned in `repository`: the stored list while it is younger than `maxAge`,
    /// otherwise fetched again. When fetching fails, the stored list of any age is returned, else `nil`.
    public func assignableUsers(in repository: String, maxAge: TimeInterval) async -> [String]? {
        let stored = catalogStore?.load()?.assignable[repository]
        if let stored, now().timeIntervalSince(stored.fetchedAt) < maxAge { return stored.logins }
        do {
            let logins = try await api.assignableUsers(repository: repository)
            // Without a stored catalog there is nothing to attach the list to; it is returned but not kept.
            if let catalog = catalogStore?.load() {
                catalogStore?.store(catalog.withAssignable(AssignableUsers(logins: logins, fetchedAt: now()), for: repository))
            }
            return logins
        } catch {
            return stored?.logins
        }
    }

    /// An issue that was just written belongs to the user's lists while the user is assigned and the
    /// issue sits in at least one project (`statuses` has one entry per placement, writable or not).
    /// Reading keeps using `GitHubMapping.isVisible`; this only covers the moment after a write.
    public func isListed(_ item: TaskItem) -> Bool {
        unlistedReason(item) == nil
    }

    /// Why a written issue is not in the lists: it sits in no project (the certain reason, also when others are
    /// assigned as well), it is not assigned to the user, or it is done in every selected project while it is
    /// still open in others. A closed issue is completed, not unlisted.
    public func unlistedReason(_ item: TaskItem) -> UnlistedReason? {
        let assignees = item.assignees ?? []
        if item.statuses.isEmpty {
            return .noProject(others: assignees.filter { !isLogin($0) })
        }
        if login != nil, !assignees.contains(where: isLogin) { return .handedOver }
        guard !item.isCompleted else { return nil }
        let selection = selectedProjectIDs() ?? defaultSelectedProjectIDs
        let inSelection = item.statuses.filter { selection.contains($0.subContainerID) }
        guard !inSelection.isEmpty, inSelection.allSatisfy({ GitHubMapping.isDone($0.current) }) else { return nil }
        let openElsewhere = item.statuses.filter { !selection.contains($0.subContainerID) && !GitHubMapping.isDone($0.current) }
        guard !openElsewhere.isEmpty else { return nil }
        return .doneInSelection(doneIn: inSelection.map(\.subContainerName), openIn: openElsewhere.map(\.subContainerName))
    }

    private func isLogin(_ candidate: String) -> Bool {
        login.map { $0.lowercased() == candidate.lowercased() } ?? false
    }

    /// Repositories offered when creating an issue.
    public func repositories() async throws -> [String] {
        do {
            return try await api.ownedRepositories()
        } catch {
            throw Self.taskError(error)
        }
    }

    // MARK: Helpers

    private func write(_ edit: TaskEdit, to record: GitHubIssueRecord) async throws {
        let writer = GitHubWriter(api: api)
        let writable = record.placements.filter(\.project.canWrite)
        // Everything that can fail on its own is checked before the first request, so no edit is written half.
        let explicitStatus = try Self.resolveStatusChanges(edit.statusChanges, in: writable)

        var state: IssueStateChange?
        var completion: Bool?
        if case .set(let completed) = edit.isCompleted {
            completion = completed
            state = completed ? .close : .reopen
        }
        // A status change can finish or reopen the issue on its own (design rules 3 and 4).
        var reopensAfterStatus = false
        if completion == nil, !explicitStatus.isEmpty {
            let resulting = writable.map { explicitStatus[$0.project.id] ?? $0.status }
            if record.isOpen, explicitStatus.values.contains(where: GitHubMapping.isDone), resulting.allSatisfy(GitHubMapping.isDone) {
                // Done in every writable project: the issue is finished, otherwise it would be open but hidden.
                state = .close
            } else if !record.isOpen, explicitStatus.values.contains(where: { !GitHubMapping.isDone($0) }) {
                // The status is written first, so a failure never leaves an open issue that is Done everywhere.
                state = .reopen
                reopensAfterStatus = true
            }
        }

        var title: String?
        if case .set(let value) = edit.title { title = value }
        var body: String??
        if case .set(let value) = edit.notes { body = .some(value) }
        var labels: [String]?
        if case .set(let value) = edit.labels { labels = value }
        try await writer.updateIssue(record, title: title, body: body, labels: labels, state: reopensAfterStatus ? nil : state)

        let targets = writable.filter { edit.targetSubContainerIDs?.contains($0.project.id) ?? true }
        for placement in targets {
            if case .set(let due) = edit.due {
                try await writer.setField(placement, fieldName: GitHubMapping.dueField, value: due.map { .date($0) })
            }
            if case .set(let priority) = edit.priority {
                let option = priority.flatMap { GitHubMapping.priorityOption($0, in: placement.project) }
                if priority == nil || option != nil {
                    try await writer.setField(placement, fieldName: GitHubMapping.priorityField, value: option.map { .singleSelect($0) })
                }
            }
            if case .set(let minutes) = edit.estimateMinutes, let fieldName = GitHubMapping.estimateFieldName(in: placement.project) {
                let value = minutes.map { ProjectFieldValue.number(GitHubMapping.fieldValue(fromMinutes: $0, fieldName: fieldName)) }
                try await writer.setField(placement, fieldName: fieldName, value: value)
            }
        }

        // Status per project: a chosen stage wins over the one that completing or reopening implies.
        for placement in writable {
            let project = placement.project
            let option: String?
            if let chosen = explicitStatus[project.id] {
                option = chosen
            } else if let completion {
                option = completion ? GitHubMapping.doneOption(in: project) : GitHubMapping.reopenOption(in: project)
            } else {
                option = nil
            }
            if let option {
                try await writer.setField(placement, fieldName: GitHubMapping.statusField, value: .singleSelect(option))
            }
        }
        if reopensAfterStatus {
            try await writer.updateIssue(record, title: nil, body: nil, labels: nil, state: .reopen)
        }

        // Assignees come last and as a difference: adding first, removing (possibly the user) at the very
        // end. When an earlier step fails, the user is still assigned and the issue stays visible.
        if case .set(let change) = edit.assignees {
            if !change.add.isEmpty { try await writer.addAssignees(record, logins: change.add) }
            if !change.remove.isEmpty { try await writer.removeAssignees(record, logins: change.remove) }
        }
    }

    /// Maps project IDs to the option names as the project spells them. Throws when a project is not a
    /// writable placement of the issue or lacks the chosen stage.
    private static func resolveStatusChanges(_ changes: [String: String], in writable: [ProjectPlacement]) throws -> [String: String] {
        var resolved: [String: String] = [:]
        for (projectID, name) in changes {
            guard let placement = writable.first(where: { $0.project.id == projectID }) else {
                throw TaskWriteError.failed(String(localized: "Der Status lässt sich in diesem Projekt nicht ändern.", bundle: .module))
            }
            guard let option = GitHubMapping.statusOption(named: name, in: placement.project) else {
                throw missingStatus(name, in: placement.project)
            }
            resolved[projectID] = option
        }
        return resolved
    }

    private func remember(_ visible: [GitHubIssueRecord]) {
        records = Dictionary(visible.map { ($0.issueID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Visible issues restricted to the selected projects, in a stable order.
    private func displayed() -> [TaskItem] {
        let selection = selectedProjectIDs() ?? defaultSelectedProjectIDs
        return records.values
            .sorted { ($0.repository, $0.number) < ($1.repository, $1.number) }
            .compactMap { displayedItem($0, selection: selection) }
    }

    /// The issue as the list shows it: placements of the selected projects only. `nil` when it is not open in any of them.
    private func displayedItem(_ record: GitHubIssueRecord, selection: Set<String>) -> TaskItem? {
        var shown = record
        shown.placements = record.placements.filter { selection.contains($0.project.id) }
        guard shown.placements.contains(where: { !GitHubMapping.isDone($0.status) }) else { return nil }
        var item = GitHubMapping.taskItem(shown)
        // The version must describe the whole issue, because writes compare against all its items.
        item.version = GitHubMapping.version(record)
        return item
    }

    static func projects(in records: [GitHubIssueRecord]) -> [ProjectInfo] {
        var seen: [String: ProjectInfo] = [:]
        for project in records.flatMap({ $0.placements.map(\.project) }) { seen[project.id] = project }
        return seen.values.sorted { $0.number < $1.number }
    }

    static func taskError(_ error: Error) -> TaskWriteError {
        switch error {
        case let error as TaskWriteError: error
        case GitHubAuthError.signedOut: .signedOut
        case GitHubAuthError.credentialsUnreadable: .failed(String(localized: "Anmeldung derzeit nicht lesbar.", bundle: .module))
        case GitHubAuthError.network: .offline
        case GitHubAuthError.server(let message): .failed(String(localized: "GitHub-Anmeldung: \(message)", bundle: .module))
        case GitHubAPIError.network: .offline
        case GitHubAPIError.graphQL(let message): .failed(message)
        case GitHubAPIError.http(let status): .failed(String(localized: "GitHub antwortet mit Fehler \(status).", bundle: .module))
        default: .failed(error.localizedDescription)
        }
    }
}
