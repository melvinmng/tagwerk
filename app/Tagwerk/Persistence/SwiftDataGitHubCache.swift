import Foundation
import GitHubKit
import SwiftData

/// GitHub read cache in SwiftData. Each `store` replaces the previous snapshot.
@MainActor
final class SwiftDataGitHubCache: GitHubCache {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load() -> (records: [GitHubIssueRecord], fetchedAt: Date)? {
        guard let state = try? context.fetch(FetchDescriptor<GitHubSyncState>()).first else { return nil }
        let decoder = JSONDecoder()
        let cached = (try? context.fetch(FetchDescriptor<CachedGitHubIssue>(sortBy: [SortDescriptor(\.issueID)]))) ?? []
        let records = cached.compactMap { try? decoder.decode(GitHubIssueRecord.self, from: $0.payload) }
        return (records, state.fetchedAt)
    }

    /// Removes all cached issues, e.g. after signing out.
    func clear() {
        try? context.delete(model: CachedGitHubIssue.self)
        try? context.delete(model: GitHubSyncState.self)
        try? context.save()
    }

    /// Replaces the snapshot in a context of its own: a failed write is rolled back there, and the pending changes of the
    /// shared `context` (other stores) are neither saved nor discarded with it.
    func store(_ records: [GitHubIssueRecord], fetchedAt: Date) {
        let encoder = JSONEncoder()
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        do {
            // Saved before the inserts: `issueID` is unique, so a delete and an insert of the same ID must not meet in one save.
            try writer.delete(model: CachedGitHubIssue.self)
            try writer.delete(model: GitHubSyncState.self)
            try writer.save()
            for record in records {
                writer.insert(CachedGitHubIssue(issueID: record.issueID, payload: try encoder.encode(record), fetchedAt: fetchedAt))
            }
            writer.insert(GitHubSyncState(fetchedAt: fetchedAt))
            try writer.save()
        } catch {
            // The cache is a convenience; a failed write only means older offline data (or an empty cache, never a partial one).
            writer.rollback()
        }
    }
}
