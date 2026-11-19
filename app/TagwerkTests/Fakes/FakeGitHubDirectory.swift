import Foundation
import GitHubKit
@testable import Tagwerk

/// GitHub catalog and assignable people in memory, for the assistant tools and cards.
@MainActor
final class FakeGitHubDirectory: GitHubDirectory {
    var login: String?
    var storedCatalog: GitHubCatalog?
    /// Assignable logins per repository; a missing repository answers `nil` (not loadable).
    var assignable: [String: [String]] = [:]
    private(set) var assignableRequests: [String] = []

    init(login: String? = "octo", catalog: GitHubCatalog? = nil, assignable: [String: [String]] = [:]) {
        self.login = login
        self.storedCatalog = catalog
        self.assignable = assignable
    }

    func catalog(maxAge: TimeInterval) async -> GitHubCatalog? { storedCatalog }

    func assignableUsers(in repository: String, maxAge: TimeInterval) async -> [String]? {
        assignableRequests.append(repository)
        return assignable[repository]
    }

    /// One repository "beispiel/app" linked to project PVT_1 "App", with three assignable people.
    static func single() -> FakeGitHubDirectory {
        let project = ProjectInfo(id: "PVT_1", number: 1, title: "App", fields: [], repositories: ["beispiel/app"])
        return FakeGitHubDirectory(
            catalog: GitHubCatalog(repositories: ["beispiel/app"], projects: [project], fetchedAt: Date(timeIntervalSince1970: 0)),
            assignable: ["beispiel/app": ["octo", "lea-m", "jonas-k"]])
    }
}
