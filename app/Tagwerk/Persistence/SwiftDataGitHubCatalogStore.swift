import Foundation
import GitHubKit
import SwiftData

/// Keeps one `GitHubCatalog` in SwiftData; each `store` replaces the previous one.
@MainActor
final class SwiftDataGitHubCatalogStore: GitHubCatalogStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load() -> GitHubCatalog? {
        guard let cached = try? context.fetch(FetchDescriptor<CachedGitHubCatalog>()).first else { return nil }
        return try? JSONDecoder().decode(GitHubCatalog.self, from: cached.payload)
    }

    /// Replaces the catalog in a context of its own, so a failed write never rolls back the pending changes of the shared `context`.
    func store(_ catalog: GitHubCatalog) {
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        do {
            try writer.delete(model: CachedGitHubCatalog.self)
            writer.insert(CachedGitHubCatalog(payload: try JSONEncoder().encode(catalog), fetchedAt: catalog.fetchedAt))
            try writer.save()
        } catch {
            // The catalog is a convenience cache; the next refresh writes it again.
            writer.rollback()
        }
    }

    func clear() {
        try? context.delete(model: CachedGitHubCatalog.self)
        try? context.save()
    }
}
