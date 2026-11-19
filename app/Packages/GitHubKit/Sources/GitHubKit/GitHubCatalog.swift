import Foundation

/// Repositories and projects offered when creating an issue, with the project ↔ repository links.
/// Cached locally so the "new issue" sheet opens without waiting for GitHub.
public struct GitHubCatalog: Codable, Sendable, Equatable {
    public let repositories: [String]
    public let projects: [ProjectInfo]
    public let fetchedAt: Date
    /// Assignable people per repository ("owner/name"), loaded on demand for one repository at a time.
    public let assignable: [String: AssignableUsers]

    public init(repositories: [String], projects: [ProjectInfo], fetchedAt: Date,
                assignable: [String: AssignableUsers] = [:]) {
        self.repositories = repositories
        self.projects = projects
        self.fetchedAt = fetchedAt
        self.assignable = assignable
    }

    /// Catalogs stored before assignees existed have no `assignable` key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try container.decode([String].self, forKey: .repositories)
        projects = try container.decode([ProjectInfo].self, forKey: .projects)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        assignable = try container.decodeIfPresent([String: AssignableUsers].self, forKey: .assignable) ?? [:]
    }

    /// Copy with the assignable people of `repository` replaced.
    public func withAssignable(_ users: AssignableUsers, for repository: String) -> GitHubCatalog {
        var updated = assignable
        updated[repository] = users
        return GitHubCatalog(repositories: repositories, projects: projects, fetchedAt: fetchedAt, assignable: updated)
    }

    /// Projects linked to `repository`, in project-number order.
    public func projectIDs(linkedTo repository: String) -> [String] {
        projects.filter { $0.repositories.contains(repository) }.sorted { $0.number < $1.number }.map(\.id)
    }
}

/// Logins that can be assigned to issues of one repository, with the time they were fetched.
public struct AssignableUsers: Codable, Sendable, Equatable {
    public let logins: [String]
    public let fetchedAt: Date

    public init(logins: [String], fetchedAt: Date) {
        self.logins = logins
        self.fetchedAt = fetchedAt
    }
}

/// Persistence of the catalog (SwiftData in the app, memory in tests).
@MainActor
public protocol GitHubCatalogStore: AnyObject {
    func load() -> GitHubCatalog?
    func store(_ catalog: GitHubCatalog)
}
