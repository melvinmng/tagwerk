import Foundation
import GitHubKit

/// What the assistant needs from GitHub: the signed-in login, the catalog of repositories and projects,
/// and the assignable people of one repository. A protocol so tests can replace the provider.
@MainActor
protocol GitHubDirectory: AnyObject {
    var login: String? { get }
    /// The stored catalog without a request, for the confirmation card.
    var storedCatalog: GitHubCatalog? { get }
    func catalog(maxAge: TimeInterval) async -> GitHubCatalog?
    func assignableUsers(in repository: String, maxAge: TimeInterval) async -> [String]?
}

extension GitHubTaskProvider: GitHubDirectory {}
