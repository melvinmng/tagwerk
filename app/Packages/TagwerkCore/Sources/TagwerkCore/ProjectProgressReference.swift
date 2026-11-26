import Foundation

/// Identifies one project of the project progress (#332): a GitHub Project, a GitHub repository, a reminder list or the
/// local tasks. The value is what the overview, the detail page and the global search exchange, so it only carries the
/// identity and a title to show before anything is loaded.
public struct ProjectProgressReference: Hashable, Codable, Sendable, Identifiable {
    /// Where the tasks of the project come from.
    public enum Kind: String, Hashable, Codable, Sendable, CaseIterable {
        case gitHubProject
        case gitHubRepository
        case remindersList
        case local
    }

    public let kind: Kind
    /// Stable identifier within the kind: the node ID of a GitHub Project, "owner/name" of a repository, the identifier of a
    /// reminder list, or `ProjectProgressReference.localID`.
    public let id: String
    /// Name to show; the detail page uses it until fresher data is there.
    public let title: String

    public init(kind: Kind, id: String, title: String) {
        self.kind = kind
        self.id = id
        self.title = title
    }

    /// The identifier of the one local "project".
    public static let localID = "local"

    /// The reference of the local tasks.
    public static func local(title: String) -> ProjectProgressReference {
        ProjectProgressReference(kind: .local, id: localID, title: title)
    }

    /// Identity of a project across sources; two references with the same kind and ID are the same project, whatever the title.
    public var key: String { "\(kind.rawValue):\(id)" }
}

extension ProjectProgressReference {
    /// The `key` of every project a task belongs to: its repository, reminder list or "Lokal", plus each GitHub Project it sits in.
    public static func keys(of item: TaskItem) -> [String] {
        var keys: [String] = []
        switch item.id.source {
        case .github: keys.append("\(Kind.gitHubRepository.rawValue):\(item.container.id)")
        case .reminders: keys.append("\(Kind.remindersList.rawValue):\(item.container.id)")
        case .local: keys.append("\(Kind.local.rawValue):\(localID)")
        }
        keys += item.subContainers.map { "\(Kind.gitHubProject.rawValue):\($0.id)" }
        return keys
    }
}
