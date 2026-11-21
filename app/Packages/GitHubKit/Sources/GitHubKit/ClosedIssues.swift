import Foundation
import TagwerkCore

/// One closed issue as the day and week reviews need it.
public struct ClosedIssue: Sendable, Equatable {
    public let id: String
    public let closedAt: Date
    /// `true` for issues closed as "completed" and for issues without a reason (older issues); "not planned" and
    /// "duplicate" do not count as done.
    public let isCompleted: Bool
    /// Projects the issue sits in, archived items included: completing a task in Tagwerk can leave an archived item behind.
    public let projectIDs: Set<String>

    public init(id: String, closedAt: Date, isCompleted: Bool, projectIDs: Set<String>) {
        self.id = id
        self.closedAt = closedAt
        self.isCompleted = isCompleted
        self.projectIDs = projectIDs
    }
}

extension ProjectsQuery {
    /// Closed issues by search text. The search string and the cursor are variables, so no text can break out of the document.
    static let closedIssues = """
    query($query: String!, $cursor: String) {
      search(query: $query, type: ISSUE, first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { ... on Issue {
          id closedAt stateReason
          projectItems(first: 20) { nodes { isArchived project { id } } }
        } }
      }
    }
    """

    struct ClosedIssuesData: Decodable {
        struct Item: Decodable {
            struct Project: Decodable { let id: String }
            let project: Project?
        }

        struct Node: Decodable {
            let id: String
            let closedAt: Date?
            let stateReason: String?
            let projectItems: Nodes<Item>?
        }

        struct Search: Decodable { let pageInfo: PageInfo; let nodes: [Node?] }
        let search: Search
    }
}

private struct ClosedIssuesVariables: Encodable, Sendable {
    let query: String
    let cursor: String?
}

extension GitHubAPI {
    /// Pages of 100, at most 3 pages: 300 closed issues of one person in a week are unlikely, and the limit
    /// keeps a review at three search requests (GitHub allows 30 search requests per minute).
    static let closedIssuesMaxPages = 3

    /// Issues assigned to `login` that were closed on or after `day` (UTC date, "yyyy-MM-dd"), and, when `closedUntil` is
    /// given, on or before that UTC date. GitHub rounds `closed:` to whole UTC days, so callers pass the day before their
    /// interval and filter on `closedAt` themselves. Without an upper bound an older week would read everything closed
    /// since, which can exceed the page limit. Throws `IssueSearchError`.
    public func closedIssues(assignedTo login: String, closedSince day: String, closedUntil lastDay: String? = nil) async throws -> [ClosedIssue] {
        let closed = lastDay.map { "closed:\(day)..\($0)" } ?? "closed:>=\(day)"
        let search = "is:issue is:closed assignee:\(login) \(closed)"
        var issues: [ClosedIssue] = []
        var cursor: String?
        for _ in 0..<Self.closedIssuesMaxPages {
            let data: ProjectsQuery.ClosedIssuesData
            do {
                data = try await query(ProjectsQuery.closedIssues,
                                       variables: ClosedIssuesVariables(query: search, cursor: cursor), allowPartial: true)
            } catch {
                throw IssueSearchError.from(error)
            }
            for node in data.search.nodes.compactMap({ $0 }) {
                guard let closedAt = node.closedAt else { continue }
                issues.append(ClosedIssue(
                    id: node.id, closedAt: closedAt, isCompleted: node.stateReason == nil || node.stateReason == "COMPLETED",
                    projectIDs: Set((node.projectItems?.nodes ?? []).compactMap { $0.project?.id })))
            }
            guard data.search.pageInfo.hasNextPage, let next = data.search.pageInfo.endCursor else { break }
            cursor = next
        }
        return issues
    }
}

extension GitHubTaskProvider {
    /// UTC date ("yyyy-MM-dd") of `date`, moved by `days`.
    static func utcDate(_ date: Date, addingDays days: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let moved = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}
