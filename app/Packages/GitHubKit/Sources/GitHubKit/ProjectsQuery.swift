import Foundation
import TagwerkCore

/// GraphQL documents and response shapes for reading projects and issues.
enum ProjectsQuery {
    static let fieldsSelection = """
    fields(first: 30) { nodes {
      ... on ProjectV2FieldCommon { id name }
      ... on ProjectV2SingleSelectField { options { id name } }
    } }
    """

    static let fieldValuesSelection = """
    fieldValues(first: 20) { nodes {
      ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2FieldCommon { name } } }
      ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }
      ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2FieldCommon { name } } }
    } }
    """

    static let issueSelection = """
    id number title body state updatedAt url
    repository { nameWithOwner }
    assignees(first: 10) { nodes { login } }
    labels(first: 20) { nodes { name } }
    """

    static let viewerProjects = """
    query { viewer { login projectsV2(first: 20, query: "is:open") { nodes {
      id number title closed
      \(fieldsSelection)
    } } } }
    """

    /// Open issues assigned to the viewer with their project items. Reading from the issue side keeps
    /// the cost independent of the projects' history (closed and "Done" items are never fetched).
    static let assignedIssues = """
    query($cursor: String) {
      search(query: "is:issue is:open assignee:@me archived:false", type: ISSUE, first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { ... on Issue {
          \(issueSelection)
          projectItems(first: 20) { nodes {
            id updatedAt isArchived
            project { id }
            \(fieldValuesSelection)
          } }
        } }
      }
    }
    """

    static let issueNode = """
    query($id: ID!) { node(id: $id) { __typename ... on Issue {
      \(issueSelection)
      projectItems(first: 20) { nodes {
        id updatedAt isArchived
        project { id number title closed \(fieldsSelection) }
        \(fieldValuesSelection)
      } }
    } } }
    """

    // MARK: Response shapes

    struct Nodes<Element: Decodable>: Decodable {
        let nodes: [Element]
    }

    struct FieldNode: Decodable {
        struct Option: Decodable { let id: String; let name: String }
        let id: String?
        let name: String?
        let options: [Option]?
    }

    struct ProjectNode: Decodable {
        let id: String
        let number: Int
        let title: String
        let closed: Bool
        let fields: Nodes<FieldNode>

        var info: ProjectInfo {
            ProjectInfo(
                id: id, number: number, title: title,
                fields: fields.nodes.compactMap { node in
                    guard let id = node.id, let name = node.name else { return nil }
                    return ProjectField(id: id, name: name,
                                        options: Dictionary((node.options ?? []).map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a }))
                }
            )
        }
    }

    struct FieldValueNode: Decodable {
        struct FieldName: Decodable { let name: String? }
        let date: String?
        let name: String?
        let number: Double?
        let field: FieldName?
    }

    struct IssueContent: Decodable {
        struct Repository: Decodable { let nameWithOwner: String }
        struct Login: Decodable { let login: String }
        struct Label: Decodable { let name: String }
        let __typename: String

        enum CodingKeys: String, CodingKey {
            case __typename, id, number, title, body, state, updatedAt, url, repository, assignees, labels
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Search results of other types decode as empty objects; issue fields carry the type implicitly.
            __typename = try container.decodeIfPresent(String.self, forKey: .__typename)
                ?? (container.contains(.number) ? "Issue" : "Other")
            id = try container.decodeIfPresent(String.self, forKey: .id)
            number = try container.decodeIfPresent(Int.self, forKey: .number)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            state = try container.decodeIfPresent(String.self, forKey: .state)
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            url = try container.decodeIfPresent(URL.self, forKey: .url)
            repository = try container.decodeIfPresent(Repository.self, forKey: .repository)
            assignees = try container.decodeIfPresent(Nodes<Login>.self, forKey: .assignees)
            labels = try container.decodeIfPresent(Nodes<Label>.self, forKey: .labels)
        }
        let id: String?
        let number: Int?
        let title: String?
        let body: String?
        let state: String?
        let updatedAt: Date?
        let url: URL?
        let repository: Repository?
        let assignees: Nodes<Login>?
        let labels: Nodes<Label>?

        func record(placements: [ProjectPlacement]) -> GitHubIssueRecord? {
            guard __typename == "Issue", let id, let number, let title, let state, let updatedAt, let url,
                  let repository else { return nil }
            return GitHubIssueRecord(
                issueID: id, number: number, repository: repository.nameWithOwner, title: title,
                body: body.flatMap { $0.isEmpty ? nil : $0 }, isOpen: state == "OPEN", url: url, updatedAt: updatedAt,
                labels: labels?.nodes.map(\.name) ?? [], assignees: assignees?.nodes.map(\.login) ?? [],
                placements: placements
            )
        }
    }

    struct ItemNode: Decodable {
        let id: String
        let updatedAt: Date
        let isArchived: Bool
        let fieldValues: Nodes<FieldValueNode>
        let content: IssueContent?
        let project: ProjectReference?

        func placement(in project: ProjectInfo) -> ProjectPlacement {
            var placement = ProjectPlacement(project: project, itemID: id, itemUpdatedAt: updatedAt,
                                             status: nil, priority: nil, due: nil, estimateMinutes: nil)
            for value in fieldValues.nodes {
                switch value.field?.name {
                case GitHubMapping.statusField?: placement.status = value.name
                case GitHubMapping.priorityField?: placement.priority = value.name.flatMap(GitHubMapping.priority(fromOption:))
                case GitHubMapping.dueField?: placement.due = value.date.flatMap(ProjectsQuery.dueDate)
                case let name? where value.number != nil:
                    if let minutes = GitHubMapping.estimateMinutes(fieldName: name, value: value.number!) {
                        placement.estimateMinutes = minutes
                    }
                default: break
                }
            }
            return placement
        }
    }

    /// A project as referenced from an item: the ID always, the full node when queried.
    struct ProjectReference: Decodable {
        let id: String
        let node: ProjectNode?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            node = container.contains(.fields) ? try ProjectNode(from: decoder) : nil
        }

        enum CodingKeys: String, CodingKey { case id, fields }
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    struct ViewerData: Decodable {
        struct Viewer: Decodable {
            let login: String
            let projectsV2: Nodes<ProjectNode>
        }
        let viewer: Viewer
    }

    struct SearchData: Decodable {
        struct Search: Decodable { let pageInfo: PageInfo; let nodes: [IssueData.IssueNode?] }
        let search: Search
    }

    struct IssueData: Decodable {
        struct IssueNode: Decodable {
            let content: IssueContent
            let projectItems: Nodes<ItemNode>?

            init(from decoder: Decoder) throws {
                content = try IssueContent(from: decoder)
                guard content.__typename == "Issue" else {
                    projectItems = nil
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                projectItems = try container.decodeIfPresent(Nodes<ItemNode>.self, forKey: .projectItems)
            }

            enum CodingKeys: String, CodingKey { case projectItems }
        }
        let node: IssueNode?
    }

    /// Parses a project date value "YYYY-MM-DD" as a date without time.
    static func dueDate(_ text: String) -> DueDate? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DueDate(year: parts[0], month: parts[1], day: parts[2])
    }
}
