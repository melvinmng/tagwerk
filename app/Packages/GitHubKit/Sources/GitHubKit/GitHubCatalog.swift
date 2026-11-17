import Foundation

/// Repositories and projects offered when creating an issue, with the project ↔ repository links.
/// Cached locally so the "new issue" sheet opens without waiting for GitHub.
public struct GitHubCatalog: Codable, Sendable, Equatable {
    public let repositories: [String]
    public let projects: [ProjectInfo]
    public let fetchedAt: Date

    public init(repositories: [String], projects: [ProjectInfo], fetchedAt: Date) {
        self.repositories = repositories
        self.projects = projects
        self.fetchedAt = fetchedAt
    }

    /// Projects linked to `repository`, in project-number order.
    public func projectIDs(linkedTo repository: String) -> [String] {
        projects.filter { $0.repositories.contains(repository) }.sorted { $0.number < $1.number }.map(\.id)
    }
}

/// Persistence of the catalog (SwiftData in the app, memory in tests).
@MainActor
public protocol GitHubCatalogStore: AnyObject {
    func load() -> GitHubCatalog?
    func store(_ catalog: GitHubCatalog)
}
