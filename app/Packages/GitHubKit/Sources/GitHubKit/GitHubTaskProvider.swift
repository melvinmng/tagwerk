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
        guard await tokens.isSignedIn else { throw TaskWriteError.accessDenied }
        do {
            let result = try await api.openProjectIssues()
            let visible = result.issues.filter { GitHubMapping.isVisible($0, login: result.login) }
            login = result.login
            projects = result.projects
            remember(visible)
            cache.store(visible, fetchedAt: now())
            offlineSince = nil
            return displayed()
        } catch GitHubAPIError.network {
            guard let cached = cache.load() else { throw TaskWriteError.failed("Keine Verbindung zu GitHub.") }
            remember(cached.records)
            if projects.isEmpty { projects = Self.projects(in: cached.records) }
            offlineSince = cached.fetchedAt
            return displayed()
        } catch {
            throw Self.taskError(error)
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

    public func apply(_ edit: TaskEdit, to id: TaskID, expectedVersion: String?) async throws -> TaskItem {
        throw TaskWriteError.failed("Bearbeiten von GitHub-Issues folgt.")
    }

    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        throw TaskWriteError.failed("Anlegen von GitHub-Issues folgt.")
    }

    // MARK: Helpers

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
                return GitHubMapping.taskItem(shown)
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
        case GitHubAuthError.signedOut: .accessDenied
        case GitHubAPIError.network: .offline
        case GitHubAPIError.graphQL(let message): .failed(message)
        case GitHubAPIError.http(let status): .failed("GitHub antwortet mit Fehler \(status).")
        default: .failed(error.localizedDescription)
        }
    }
}
