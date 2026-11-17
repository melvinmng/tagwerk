import Foundation
import TagwerkCore

/// Task source for issues assigned to the user in their open GitHub Projects.
@MainActor
public final class GitHubTaskProvider: TaskProvider {
    public let source: TaskSource = .github
    public private(set) var offlineSince: Date?
    public private(set) var projects: [ProjectInfo] = []
    public private(set) var login: String?

    let api: GitHubAPI
    let tokens: TokenManager
    private let cache: GitHubCache
    private let selectedProjectIDs: @MainActor () -> Set<String>?
    let now: () -> Date
    /// Full records of visible issues, keyed by issue node ID (all placements, unfiltered).
    private(set) var records: [String: GitHubIssueRecord] = [:]

    public init(api: GitHubAPI, tokens: TokenManager, cache: GitHubCache,
                selectedProjectIDs: @escaping @MainActor () -> Set<String>?, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.tokens = tokens
        self.cache = cache
        self.selectedProjectIDs = selectedProjectIDs
        self.now = now
    }

    /// Projects selected when the user has not chosen any (design §12.1).
    public var defaultSelectedProjectIDs: Set<String> {
        GitHubMapping.defaultSelectedProjectIDs(projects: projects, visibleIssues: Array(records.values))
    }

    public func openTasks() async throws -> [TaskItem] {
        guard await tokens.isSignedIn else { throw TaskWriteError.signedOut }
        do {
            let result = try await api.openProjectIssues()
            let visible = result.issues.filter { GitHubMapping.isVisible($0, login: result.login) }
            login = result.login
            projects = result.projects
            remember(visible)
            cache.store(visible, fetchedAt: now())
            offlineSince = nil
            return displayed()
        } catch {
            // Any read failure except an ended sign-in shows the cache (design §9: "Offline / Fehler").
            let mapped = Self.taskError(error)
            if mapped == .signedOut { throw mapped }
            guard let cached = cache.load() else {
                throw mapped == .offline ? TaskWriteError.failed("Keine Verbindung zu GitHub.") : mapped
            }
            remember(cached.records)
            if projects.isEmpty { projects = Self.projects(in: cached.records) }
            offlineSince = cached.fetchedAt
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

    /// Reloads the issue, compares versions and writes in a fixed order: issue fields, project fields,
    /// close/reopen, project status in all projects. The result is read again afterwards, because
    /// project workflows may change the status on their own.
    public func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        do {
            guard let current = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            let currentItem = GitHubMapping.taskItem(current)
            if let expectedVersion, expectedVersion != currentItem.version {
                records[current.issueID] = current
                throw TaskWriteError.conflict(current: currentItem)
            }
            try await write(edit, to: current)
            guard let fresh = try await api.issue(nodeID: id.rawValue) else { throw TaskWriteError.notFound }
            records[fresh.issueID] = fresh
            offlineSince = nil
            return GitHubMapping.taskItem(fresh)
        } catch {
            throw Self.taskError(error)
        }
    }

    public func addComment(to id: TaskID, body: String) async throws {
        guard let record = records[id.rawValue] else { throw TaskWriteError.notFound }
        do {
            try await GitHubWriter(api: api).addComment(record, body: body)
        } catch {
            throw Self.taskError(error)
        }
    }

    /// Creates an issue assigned to the viewer in `draft.containerID` (repository) and adds it to
    /// project `draft.subContainerID` with the draft's field values and status "Ready".
    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        guard let repository = draft.containerID, let projectID = draft.subContainerID else {
            throw TaskWriteError.failed("Bitte Repository und Project wählen.")
        }
        do {
            let (viewer, available) = try await api.viewerProjects()
            login = viewer
            projects = available
            guard let project = available.first(where: { $0.id == projectID }) else { throw TaskWriteError.notFound }

            let writer = GitHubWriter(api: api)
            let issueID = try await writer.createIssue(repository: repository, title: draft.title, body: draft.notes, assignee: viewer)
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
            try await writer.setField(placement, fieldName: GitHubMapping.statusField, value: .singleSelect(GitHubMapping.reopenStatus))

            guard let fresh = try await api.issue(nodeID: issueID) else { throw TaskWriteError.notFound }
            records[fresh.issueID] = fresh
            return GitHubMapping.taskItem(fresh)
        } catch {
            throw Self.taskError(error)
        }
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
        var state: IssueStateChange?
        if case .set(let completed) = edit.isCompleted { state = completed ? .close : .reopen }

        var title: String?
        if case .set(let value) = edit.title { title = value }
        var body: String??
        if case .set(let value) = edit.notes { body = .some(value) }
        var labels: [String]?
        if case .set(let value) = edit.labels { labels = value }
        try await writer.updateIssue(record, title: title, body: body, labels: labels, state: state)

        let targets = record.placements.filter { edit.targetSubContainerIDs?.contains($0.project.id) ?? true }
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

        if let state {
            let status = state == .close ? GitHubMapping.doneStatus : GitHubMapping.reopenStatus
            for placement in record.placements {
                try await writer.setField(placement, fieldName: GitHubMapping.statusField, value: .singleSelect(status))
            }
        }
    }

    private func remember(_ visible: [GitHubIssueRecord]) {
        records = Dictionary(visible.map { ($0.issueID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Visible issues restricted to the selected projects, in a stable order.
    private func displayed() -> [TaskItem] {
        let selection = selectedProjectIDs() ?? defaultSelectedProjectIDs
        return records.values
            .sorted { ($0.repository, $0.number) < ($1.repository, $1.number) }
            .compactMap { record in
                var shown = record
                shown.placements = record.placements.filter { selection.contains($0.project.id) }
                guard shown.placements.contains(where: { $0.status != GitHubMapping.doneStatus }) else { return nil }
                var item = GitHubMapping.taskItem(shown)
                // The version must describe the whole issue, because writes compare against all its items.
                item.version = GitHubMapping.version(record)
                return item
            }
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
        case GitHubAuthError.network: .offline
        case GitHubAuthError.server(let message): .failed("GitHub-Anmeldung: \(message)")
        case GitHubAPIError.network: .offline
        case GitHubAPIError.graphQL(let message): .failed(message)
        case GitHubAPIError.http(let status): .failed("GitHub antwortet mit Fehler \(status).")
        default: .failed(error.localizedDescription)
        }
    }
}
