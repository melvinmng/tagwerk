import GitHubKit
import TagwerkCore

/// Turns the stored GitHub catalog into the candidates of the search for repositories and projects.
enum GitHubTargetSearch {
    /// Repositories first (in the order of the catalog, the most recently pushed first), then the projects (by number). A project has
    /// no owner of its own in the catalog; the owners of its linked repositories stand in for it.
    static func items(from catalog: GitHubCatalog) -> [GitHubTargetSearchItem] {
        let repositories = catalog.repositories.map { fullName -> GitHubTargetSearchItem in
            let parts = owner(of: fullName)
            return GitHubTargetSearchItem(kind: .repository, targetID: fullName, title: parts.name, ownerText: parts.owner)
        }
        let projects = catalog.projects.map { project -> GitHubTargetSearchItem in
            var owners: [String] = []
            for repository in project.repositories {
                let name = owner(of: repository).owner
                if !name.isEmpty, !owners.contains(name) { owners.append(name) }
            }
            return GitHubTargetSearchItem(kind: .project, targetID: project.id, title: project.title,
                                          ownerText: owners.joined(separator: ", "), projectNumber: project.number)
        }
        return repositories + projects
    }

    private static func owner(of fullName: String) -> (owner: String, name: String) {
        guard let slash = fullName.firstIndex(of: "/") else { return ("", fullName) }
        return (String(fullName[..<slash]), String(fullName[fullName.index(after: slash)...]))
    }

    /// The source of the search: what is stored on the device; only when nothing is stored yet one request fills the catalog.
    /// Without a connection the answer is empty and the search shows no hits of this kind, no error.
    @MainActor
    static func source(provider: GitHubTaskProvider) -> @MainActor () async -> [GitHubTargetSearchItem] {
        {
            let stored = provider.storedCatalog
            let catalog: GitHubCatalog?
            if let stored { catalog = stored } else { catalog = await provider.catalog(maxAge: 0) }
            return catalog.map(items(from:)) ?? []
        }
    }
}
