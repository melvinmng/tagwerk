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

    func store(_ catalog: GitHubCatalog) {
        do {
            try context.delete(model: CachedGitHubCatalog.self)
            context.insert(CachedGitHubCatalog(payload: try JSONEncoder().encode(catalog), fetchedAt: catalog.fetchedAt))
            try context.save()
        } catch {
            // The catalog is a convenience cache; the next refresh writes it again.
            context.rollback()
        }
    }

    func clear() {
        try? context.delete(model: CachedGitHubCatalog.self)
        try? context.save()
    }
}
