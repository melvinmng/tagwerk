import Foundation
import TagwerkCore

/// A field of a GitHub Project. `options` maps option names to option IDs (single-select fields only).
public struct ProjectField: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let options: [String: String]

    public init(id: String, name: String, options: [String: String]) {
        self.id = id
        self.name = name
        self.options = options
    }
}

/// An open GitHub Project (v2) with its field definitions.
public struct ProjectInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let fields: [ProjectField]
    /// Repositories linked to the project ("owner/name"); empty when unknown.
    public let repositories: [String]

    public init(id: String, number: Int, title: String, fields: [ProjectField], repositories: [String] = []) {
        self.id = id
        self.number = number
        self.title = title
        self.fields = fields
        self.repositories = repositories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        fields = try container.decode([ProjectField].self, forKey: .fields)
        // Caches written before repositories existed lack the key.
        repositories = try container.decodeIfPresent([String].self, forKey: .repositories) ?? []
    }

    public func field(named name: String) -> ProjectField? {
        fields.first { $0.name == name }
    }
}

/// An issue's item in one project, with the project field values that Tagwerk uses.
public struct ProjectPlacement: Codable, Sendable, Equatable {
    public let project: ProjectInfo
    public let itemID: String
    public let itemUpdatedAt: Date
    public var status: String?
    public var priority: Priority?
    public var due: DueDate?
    public var estimateMinutes: Int?

    public init(project: ProjectInfo, itemID: String, itemUpdatedAt: Date, status: String?,
                priority: Priority?, due: DueDate?, estimateMinutes: Int?) {
        self.project = project
        self.itemID = itemID
        self.itemUpdatedAt = itemUpdatedAt
        self.status = status
        self.priority = priority
        self.due = due
        self.estimateMinutes = estimateMinutes
    }
}

/// A GitHub issue with all its placements in open projects. Identity is the issue, not the item.
public struct GitHubIssueRecord: Codable, Sendable, Equatable {
    public let issueID: String
    public let number: Int
    public let repository: String
    public var title: String
    public var body: String?
    public var isOpen: Bool
    public let url: URL
    public let updatedAt: Date
    public var labels: [String]
    public var assignees: [String]
    public var placements: [ProjectPlacement]

    public init(issueID: String, number: Int, repository: String, title: String, body: String?, isOpen: Bool,
                url: URL, updatedAt: Date, labels: [String], assignees: [String], placements: [ProjectPlacement]) {
        self.issueID = issueID
        self.number = number
        self.repository = repository
        self.title = title
        self.body = body
        self.isOpen = isOpen
        self.url = url
        self.updatedAt = updatedAt
        self.labels = labels
        self.assignees = assignees
        self.placements = placements
    }
}
