import Foundation
import TagwerkCore

/// One issue of a GitHub Project or repository as the project progress reads it (#332): every issue of the project, whoever it is
/// assigned to. Pull requests and draft issues are not read.
public struct ProjectItemRecord: Sendable, Equatable {
    public let issueID: String
    public let number: Int
    public let repository: String
    public let title: String
    public let url: URL
    public let state: ProjectItemState
    public let createdAt: Date?
    public let closedAt: Date?
    public let updatedAt: Date?
    public let assignees: [String]
    /// The Status of the item in the project; `nil` for the issues of a repository.
    public let status: String?
    public let due: DueDate?
    /// Open issues that block this one (native dependency "Blocked by").
    public let openBlockedByCount: Int
    /// Open issues that wait for this one (native dependency "Blocking").
    public let openBlockingCount: Int
    /// The item sits on the board but is archived there. It still counts: completing an issue in Tagwerk can leave an archived item.
    public let isArchived: Bool

    public init(issueID: String, number: Int, repository: String, title: String, url: URL, state: ProjectItemState,
                createdAt: Date?, closedAt: Date?, updatedAt: Date? = nil, assignees: [String] = [], status: String? = nil,
                due: DueDate? = nil, openBlockedByCount: Int = 0, openBlockingCount: Int = 0, isArchived: Bool = false) {
        self.issueID = issueID
        self.number = number
        self.repository = repository
        self.title = title
        self.url = url
        self.state = state
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.updatedAt = updatedAt
        self.assignees = assignees
        self.status = status
        self.due = due
        self.openBlockedByCount = openBlockedByCount
        self.openBlockingCount = openBlockingCount
        self.isArchived = isArchived
    }
}

/// The issues of one project and whether the read stopped at the page limit.
public struct ProjectItems: Sendable, Equatable {
    public let items: [ProjectItemRecord]
    /// More pages were announced than `maxPages` allows: the oldest or last items are missing.
    public let isTruncated: Bool

    public init(items: [ProjectItemRecord], isTruncated: Bool) {
        self.items = items
        self.isTruncated = isTruncated
    }
}

extension ProjectsQuery {
    /// The fields of an issue that the progress needs. `issueDependenciesSummary.blockedBy` and `.blocking` count the *open*
    /// issues (the totals count all), which is what blocked means: a closed blocker no longer blocks.
    static let progressIssueSelection = """
    id number title url state stateReason createdAt closedAt updatedAt
    repository { nameWithOwner }
    assignees(first: 10) { nodes { login } }
    issueDependenciesSummary { blockedBy blocking }
    """

    /// One page of the items of a project; `$id` is the node ID of the project.
    static let projectItems = """
    query($id: ID!, $cursor: String) { node(id: $id) { ... on ProjectV2 {
      items(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isArchived
          \(fieldValuesSelection)
          content { __typename ... on Issue { \(progressIssueSelection) } }
        }
      }
    } } }
    """

    /// One page of the issues of a repository, newest first.
    static let repositoryIssues = """
    query($owner: String!, $name: String!, $cursor: String) { repository(owner: $owner, name: $name) {
      issues(first: 100, after: $cursor, orderBy: { field: CREATED_AT, direction: DESC }) {
        pageInfo { hasNextPage endCursor }
        nodes { \(progressIssueSelection) }
      }
    } }
    """

    struct ProgressIssue: Decodable {
        struct Summary: Decodable { let blockedBy: Int?; let blocking: Int? }
        let __typename: String?
        let id: String?
        let number: Int?
        let title: String?
        let url: URL?
        let state: String?
        let stateReason: String?
        let createdAt: Date?
        let closedAt: Date?
        let updatedAt: Date?
        let repository: IssueContent.Repository?
        let assignees: Nodes<IssueContent.Login>?
        let issueDependenciesSummary: Summary?

        /// Issues only; a pull request or draft issue has no `number` in this selection and a node without a type is read as an issue.
        func record(item: ProgressItem?) -> ProjectItemRecord? {
            if let __typename, __typename != "Issue" { return nil }
            guard let id, let number, let title, let url, let state, let repository else { return nil }
            let itemState: ProjectItemState
            if state == "OPEN" {
                itemState = .open
            } else {
                // The rule of `ClosedIssue.isCompleted`: no reason (older issues) and "completed" count as done.
                itemState = (stateReason == nil || stateReason == "COMPLETED") ? .completed : .closedNotPlanned
            }
            var status: String?
            var due: DueDate?
            for value in item?.fieldValues.nodes ?? [] {
                switch value.field?.name {
                case GitHubMapping.statusField?: status = value.name
                case GitHubMapping.dueField?: due = value.date.flatMap(ProjectsQuery.dueDate)
                default: break
                }
            }
            return ProjectItemRecord(
                issueID: id, number: number, repository: repository.nameWithOwner, title: title, url: url, state: itemState,
                createdAt: createdAt, closedAt: itemState == .open ? nil : closedAt, updatedAt: updatedAt,
                assignees: assignees?.nodes.map(\.login) ?? [], status: status, due: due,
                openBlockedByCount: issueDependenciesSummary?.blockedBy ?? 0,
                openBlockingCount: issueDependenciesSummary?.blocking ?? 0, isArchived: item?.isArchived ?? false)
        }
    }

    struct ProgressItem: Decodable {
        let isArchived: Bool
        let fieldValues: Nodes<FieldValueNode>
        let content: ProgressIssue?

        enum CodingKeys: String, CodingKey { case isArchived, fieldValues, content }
    }

    struct ProjectItemsData: Decodable {
        struct Project: Decodable {
            struct Page: Decodable { let pageInfo: PageInfo; let nodes: [ProgressItem?] }
            let items: Page
        }
        let node: Project?
    }

    struct RepositoryIssuesData: Decodable {
        struct Repository: Decodable {
            struct Page: Decodable { let pageInfo: PageInfo; let nodes: [ProgressIssue?] }
            let issues: Page
        }
        let repository: Repository?
    }
}

private struct ProjectItemsVariables: Encodable, Sendable {
    let id: String
    let cursor: String?
}

private struct RepositoryIssuesVariables: Encodable, Sendable {
    let owner: String
    let name: String
    let cursor: String?
}

extension GitHubAPI {
    /// Pages of 100: a project of 10,000 issues is far beyond a personal project, and the limit only guards against a response that
    /// never ends. A project that exceeds it is reported as truncated.
    public static let projectItemsMaxPages = 100

    /// Every issue of the project `projectID` (node ID), assigned to anyone, archived items included. Follows the cursor until the
    /// last page; a failing page fails the whole call, so a partial history is never shown as complete. Throws `GitHubAPIError`.
    public func projectItems(projectID: String, maxPages: Int = GitHubAPI.projectItemsMaxPages) async throws -> ProjectItems {
        var records: [ProjectItemRecord] = []
        var cursor: String?
        var truncated = false
        for page in 0..<max(maxPages, 1) {
            let data: ProjectsQuery.ProjectItemsData = try await query(
                ProjectsQuery.projectItems, variables: ProjectItemsVariables(id: projectID, cursor: cursor), allowPartial: true)
            guard let items = data.node?.items else { throw GitHubAPIError.graphQL("Project not found") }
            for item in items.nodes.compactMap({ $0 }) {
                if let record = item.content?.record(item: item) { records.append(record) }
            }
            guard items.pageInfo.hasNextPage, let next = items.pageInfo.endCursor, next != cursor else { break }
            cursor = next
            if page == max(maxPages, 1) - 1 { truncated = true }
        }
        return ProjectItems(items: Self.uniqueByIssue(records), isTruncated: truncated)
    }

    /// Every issue of the repository ("owner/name"), newest first, with the same rules as `projectItems`.
    public func repositoryIssues(_ repository: String, maxPages: Int = GitHubAPI.projectItemsMaxPages) async throws -> ProjectItems {
        let parts = try Self.checked(repository).split(separator: "/").map(String.init)
        var records: [ProjectItemRecord] = []
        var cursor: String?
        var truncated = false
        for page in 0..<max(maxPages, 1) {
            let data: ProjectsQuery.RepositoryIssuesData = try await query(
                ProjectsQuery.repositoryIssues,
                variables: RepositoryIssuesVariables(owner: parts[0], name: parts[1], cursor: cursor), allowPartial: true)
            guard let issues = data.repository?.issues else { throw GitHubAPIError.graphQL("Repository not found") }
            records += issues.nodes.compactMap { $0?.record(item: nil) }
            guard issues.pageInfo.hasNextPage, let next = issues.pageInfo.endCursor, next != cursor else { break }
            cursor = next
            if page == max(maxPages, 1) - 1 { truncated = true }
        }
        return ProjectItems(items: Self.uniqueByIssue(records), isTruncated: truncated)
    }

    /// An issue can sit in a project twice (a moved item); it counts once.
    private static func uniqueByIssue(_ records: [ProjectItemRecord]) -> [ProjectItemRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.issueID).inserted }
    }
}
