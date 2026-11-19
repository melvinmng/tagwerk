import Foundation
import TagwerkCore

/// One option of a single-select project field.
public struct ProjectFieldOption: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A field of a GitHub Project. `orderedOptions` lists the options of a single-select field in board
/// order; `options` maps option names to option IDs.
public struct ProjectField: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let orderedOptions: [ProjectFieldOption]

    /// Option names to option IDs, derived from `orderedOptions`.
    public var options: [String: String] {
        Dictionary(orderedOptions.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    /// Options in board order. Repeated names keep their first occurrence.
    public init(id: String, name: String, orderedOptions: [ProjectFieldOption]) {
        self.id = id
        self.name = name
        var seen = Set<String>()
        self.orderedOptions = orderedOptions.filter { seen.insert($0.name).inserted }
    }

    /// Options without a known board order; they are ordered by name.
    public init(id: String, name: String, options: [String: String]) {
        self.init(id: id, name: name,
                  orderedOptions: options.sorted { $0.key < $1.key }.map { ProjectFieldOption(id: $0.value, name: $0.key) })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        if let ordered = try container.decodeIfPresent([ProjectFieldOption].self, forKey: .orderedOptions) {
            self.init(id: id, name: name, orderedOptions: ordered)
        } else {
            // Caches written before the board order was kept only hold the dictionary.
            self.init(id: id, name: name, options: try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:])
        }
    }

    /// Writes the dictionary as well, so the cache stays readable for older builds.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(options, forKey: .options)
        try container.encode(orderedOptions, forKey: .orderedOptions)
    }

    enum CodingKeys: String, CodingKey { case id, name, options, orderedOptions }
}

/// An open GitHub Project (v2) with its field definitions.
public struct ProjectInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let fields: [ProjectField]
    /// Repositories linked to the project ("owner/name"); empty when unknown.
    public let repositories: [String]
    /// Whether the login may change items (readable projects of other owners may be read-only).
    public let canWrite: Bool

    public init(id: String, number: Int, title: String, fields: [ProjectField], repositories: [String] = [],
                canWrite: Bool = true) {
        self.canWrite = canWrite
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
        canWrite = try container.decodeIfPresent(Bool.self, forKey: .canWrite) ?? true
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

/// Parent of a sub-issue with the values Tagwerk needs for epic deadlines.
public struct ParentIssue: Codable, Sendable, Equatable {
    public let id: String
    public let number: Int
    public let title: String
    public let labels: [String]
    public let due: DueDate?

    public init(id: String, number: Int, title: String, labels: [String], due: DueDate?) {
        self.id = id
        self.number = number
        self.title = title
        self.labels = labels
        self.due = due
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
    /// Parent issue (sub-issues); `nil` for caches written before parents were read.
    public var parent: ParentIssue?

    public init(issueID: String, number: Int, repository: String, title: String, body: String?, isOpen: Bool,
                url: URL, updatedAt: Date, labels: [String], assignees: [String], placements: [ProjectPlacement],
                parent: ParentIssue? = nil) {
        self.parent = parent
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
