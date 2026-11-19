import Foundation
import TagwerkCore

/// Builds the search text of the online issue search. The user's text goes into the search string, which travels
/// as a GraphQL variable; it is never part of the GraphQL document.
public enum IssueSearchQuery {
    public static let maxRepositories = 30

    /// "is:issue <text> repo:a/b …" for the first 30 repositories; without repositories "is:issue <text> user:<login>".
    public static func make(text: String, repositories: [String], login: String) -> String {
        guard !repositories.isEmpty else { return "is:issue \(text) user:\(login)" }
        let scopes = repositories.prefix(maxRepositories).map { "repo:\($0)" }
        return (["is:issue", text] + scopes).joined(separator: " ")
    }

    /// Fallback if GitHub refuses many `repo:` qualifiers: "is:issue <text> user:<login> org:<owner> …" for the
    /// owners of `repositories` (each owner once, the login's own repositories covered by `user:`).
    public static func makeByOwner(text: String, repositories: [String], login: String) -> String {
        var owners: [String] = []
        for repository in repositories {
            guard let owner = repository.split(separator: "/").first.map(String.init),
                  owner.lowercased() != login.lowercased(), !owners.contains(owner) else { continue }
            owners.append(owner)
        }
        return (["is:issue", text, "user:\(login)"] + owners.map { "org:\($0)" }).joined(separator: " ")
    }
}

/// One issue found by the online search.
public struct IssueSearchHit: Sendable, Equatable {
    /// Placements stay empty: the search does not read project fields.
    public let record: GitHubIssueRecord
    /// A non-archived item in a project that is not closed.
    public let hasOpenProject: Bool

    public init(record: GitHubIssueRecord, hasOpenProject: Bool) {
        self.record = record
        self.hasOpenProject = hasOpenProject
    }
}

public enum IssueSearchError: Error, Equatable, Sendable {
    case offline, rateLimited, signedOut
    case failed(String)

    /// Maps what API and token handling throw.
    static func from(_ error: Error) -> IssueSearchError {
        switch error {
        case let error as IssueSearchError: return error
        case GitHubAuthError.signedOut: return .signedOut
        case GitHubAuthError.network, GitHubAPIError.network: return .offline
        case GitHubAuthError.credentialsUnreadable:
            return .failed(String(localized: "Anmeldung derzeit nicht lesbar.", bundle: .module))
        case GitHubAPIError.http(401): return .signedOut
        case GitHubAPIError.http(403), GitHubAPIError.http(429): return .rateLimited
        case GitHubAPIError.http(let status):
            return .failed(String(localized: "GitHub antwortet mit Fehler \(status).", bundle: .module))
        case GitHubAPIError.graphQL(let message):
            return message.lowercased().contains("rate limit") ? .rateLimited : .failed(message)
        default: return .failed(error.localizedDescription)
        }
    }
}

extension ProjectsQuery {
    /// Issues by text. The search string is a variable, so no text can break out of the document.
    static let searchIssues = """
    query($query: String!) {
      search(query: $query, type: ISSUE, first: 20) {
        nodes { ... on Issue {
          \(issueSelection)
          projectItems(first: 20) { nodes { isArchived project { closed } } }
        } }
      }
    }
    """

    struct IssueSearchData: Decodable {
        struct Item: Decodable {
            struct Project: Decodable { let closed: Bool }
            let isArchived: Bool
            let project: Project?
        }

        struct Node: Decodable {
            let content: IssueContent
            let projectItems: Nodes<Item>?

            init(from decoder: Decoder) throws {
                content = try IssueContent(from: decoder)
                guard content.__typename == "Issue" else {
                    projectItems = nil
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                projectItems = try container.decodeIfPresent(Nodes<Item>.self, forKey: .projectItems)
            }

            enum CodingKeys: String, CodingKey { case projectItems }
        }

        struct Search: Decodable { let nodes: [Node?] }
        let search: Search
    }
}

private struct SearchVariables: Encodable, Sendable {
    let query: String
}

extension GitHubAPI {
    /// One request, first page, at most 20 issues, scoped to `repositories` (at most 30) or to `login`.
    /// Throws `IssueSearchError`.
    public func searchIssues(text: String, repositories: [String], login: String) async throws -> [IssueSearchHit] {
        let search = IssueSearchQuery.make(text: text, repositories: repositories, login: login)
        let data: ProjectsQuery.IssueSearchData
        do {
            data = try await query(ProjectsQuery.searchIssues, variables: SearchVariables(query: search), allowPartial: true)
        } catch {
            throw IssueSearchError.from(error)
        }
        return data.search.nodes.compactMap { $0 }.compactMap { node in
            guard let record = node.content.record(placements: []) else { return nil }
            let open = (node.projectItems?.nodes ?? []).contains { item in
                !item.isArchived && item.project.map { !$0.closed } == true
            }
            return IssueSearchHit(record: record, hasOpenProject: open)
        }
    }
}

extension GitHubTaskProvider {
    /// Online hits without the issues that are loaded already. The marker names why a hit is not among the tasks,
    /// in the order closed, unassigned, assigned to others, no project.
    public func searchOnline(_ text: String, excluding loadedIssueIDs: Set<String>) async throws -> [OnlineIssue] {
        let viewer: String
        if let login {
            viewer = login
        } else {
            do { viewer = try await api.viewerLogin() } catch { throw IssueSearchError.from(error) }
        }
        let catalog = await catalog(maxAge: .infinity)
        // Repositories of the user's projects first, then the owned ones; GitHub takes at most 30 qualifiers.
        var repositories: [String] = []
        for repository in (catalog?.projects.flatMap(\.repositories) ?? []) + (catalog?.repositories ?? [])
        where !repositories.contains(repository) {
            repositories.append(repository)
        }
        let hits = try await api.searchIssues(text: text, repositories: repositories, login: viewer)
        return hits.filter { !loadedIssueIDs.contains($0.record.issueID) }.map { hit in
            let record = hit.record
            let marker: OnlineIssueMarker? =
                if !record.isOpen { .closed }
                else if record.assignees.isEmpty { .unassigned }
                else if !AssigneeRules.contains(record.assignees, viewer) { .assignedToOthers }
                else if !hit.hasOpenProject { .noProject }
                else { nil }
            return OnlineIssue(id: record.issueID, number: record.number, title: record.title, repository: record.repository,
                               url: record.url, updatedAt: record.updatedAt, marker: marker)
        }
    }
}
