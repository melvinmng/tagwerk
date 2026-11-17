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

    func store(_ records: [GitHubIssueRecord], fetchedAt: Date) {
        let encoder = JSONEncoder()
        do {
            try context.delete(model: CachedGitHubIssue.self)
            try context.delete(model: GitHubSyncState.self)
            for record in records {
                context.insert(CachedGitHubIssue(issueID: record.issueID, payload: try encoder.encode(record), fetchedAt: fetchedAt))
            }
            context.insert(GitHubSyncState(fetchedAt: fetchedAt))
            try context.save()
        } catch {
            // The cache is a convenience; a failed write only means older offline data.
            context.rollback()
        }
    }
}
