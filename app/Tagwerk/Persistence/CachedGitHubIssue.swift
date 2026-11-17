import Foundation
import SwiftData

/// One cached GitHub issue (JSON of `GitHubIssueRecord`) for offline display.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class CachedGitHubIssue {
    @Attribute(.unique) var issueID: String
    var payload: Data
    var fetchedAt: Date

    init(issueID: String, payload: Data, fetchedAt: Date) {
        self.issueID = issueID
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// Repositories and projects for creating issues (JSON of `GitHubCatalog`), a single object.
@Model
final class CachedGitHubCatalog {
    var payload: Data
    var fetchedAt: Date

    init(payload: Data, fetchedAt: Date) {
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// Time of the last successful GitHub fetch, kept separately so that an empty result is cached too.
@Model
final class GitHubSyncState {
    var fetchedAt: Date

    init(fetchedAt: Date) {
        self.fetchedAt = fetchedAt
    }
}
