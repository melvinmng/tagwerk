import Foundation

/// A comment of an issue.
public struct IssueComment: Sendable, Equatable, Codable {
    public let author: String
    public let body: String
    /// ISO 8601 as delivered by GitHub.
    public let createdAt: String

    public init(author: String, body: String, createdAt: String) {
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

/// Number, title and state of an issue.
public struct IssueSummary: Sendable, Equatable, Codable {
    public let number: Int
    public let title: String
    public let isOpen: Bool

    public init(number: Int, title: String, isOpen: Bool) {
        self.number = number
        self.title = title
        self.isOpen = isOpen
    }
}

/// Labels of an issue plus its epic (parent) and the other sub-issues of that epic.
public struct IssueNeighbours: Sendable, Equatable, Codable {
    public let labels: [String]
    public let epic: IssueSummary?
    public let siblings: [IssueSummary]

    public init(labels: [String], epic: IssueSummary?, siblings: [IssueSummary]) {
        self.labels = labels
        self.epic = epic
        self.siblings = siblings
    }
}

/// A file or the entries of a directory.
public enum RepositoryContent: Sendable, Equatable {
    case file(String)
    /// Paths; directories end with "/".
    case directory([String])
}

public struct PullRequestSummary: Sendable, Equatable, Codable {
    public let number: Int
    public let title: String
    public let state: String
    public let merged: Bool
    public let author: String
    public let body: String
    public let changedFiles: Int
    public let additions: Int
    public let deletions: Int
    public let url: String

    public init(number: Int, title: String, state: String, merged: Bool, author: String, body: String,
                changedFiles: Int, additions: Int, deletions: Int, url: String) {
        self.number = number
        self.title = title
        self.state = state
        self.merged = merged
        self.author = author
        self.body = body
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
        self.url = url
    }
}

/// Read-only access to repository contents for the issue chat (design §8.3). Every call names the
/// repository explicitly; names and paths are validated so a request cannot leave that repository.
extension GitHubAPI {
    public func issueComments(repository: String, number: Int, limit: Int = 50) async throws -> [IssueComment] {
        struct Comment: Decodable {
            struct User: Decodable { let login: String }
            let user: User?
            let body: String?
            let created_at: String
        }
        let data = try await rest("GET", "repos/\(try Self.checked(repository))/issues/\(number)/comments",
                                  query: [URLQueryItem(name: "per_page", value: String(min(max(limit, 1), 100)))])
        return try Self.decode([Comment].self, data).map {
            IssueComment(author: $0.user?.login ?? "unbekannt", body: $0.body ?? "", createdAt: $0.created_at)
        }
    }

    public func readme(repository: String) async throws -> String {
        struct Readme: Decodable { let content: String; let encoding: String }
        let data = try await rest("GET", "repos/\(try Self.checked(repository))/readme")
        let readme = try Self.decode(Readme.self, data)
        return try Self.decodeContent(readme.content, encoding: readme.encoding)
    }

    public func file(repository: String, path: String) async throws -> RepositoryContent {
        struct File: Decodable { let content: String?; let encoding: String? }
        struct Entry: Decodable { let path: String; let type: String }
        let path = try Self.checkedPath(path)
        let data = try await rest("GET", "repos/\(try Self.checked(repository))/contents/\(path)")
        if let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            return .directory(entries.map { $0.type == "dir" ? $0.path + "/" : $0.path })
        }
        let file = try Self.decode(File.self, data)
        return .file(try Self.decodeContent(file.content ?? "", encoding: file.encoding ?? "base64"))
    }

    /// Paths of files matching `query` in the repository, at most `limit`.
    public func searchCode(repository: String, query: String, limit: Int = 10) async throws -> [String] {
        struct Result: Decodable {
            struct Item: Decodable { let path: String }
            let items: [Item]
        }
        let limit = min(max(limit, 1), 20)
        let data = try await rest("GET", "search/code", query: [
            URLQueryItem(name: "q", value: "\(Self.searchTerms(query)) repo:\(try Self.checked(repository))"),
            URLQueryItem(name: "per_page", value: String(limit)),
        ])
        return try Self.decode(Result.self, data).items.prefix(limit).map(\.path)
    }

    /// The query without qualifiers ("repo:", "org:", "user:" …), so a search never leaves the given repository.
    static func searchTerms(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).filter { !$0.contains(":") }.joined(separator: " ")
    }

    public func pullRequest(repository: String, number: Int) async throws -> PullRequestSummary {
        struct Pull: Decodable {
            struct User: Decodable { let login: String }
            let number: Int; let title: String; let state: String; let merged: Bool?
            let body: String?; let user: User?
            let changed_files: Int?; let additions: Int?; let deletions: Int?; let html_url: String
        }
        let data = try await rest("GET", "repos/\(try Self.checked(repository))/pulls/\(number)")
        let pull = try Self.decode(Pull.self, data)
        return PullRequestSummary(number: pull.number, title: pull.title, state: pull.state, merged: pull.merged ?? false,
                                  author: pull.user?.login ?? "unbekannt", body: pull.body ?? "",
                                  changedFiles: pull.changed_files ?? 0, additions: pull.additions ?? 0,
                                  deletions: pull.deletions ?? 0, url: pull.html_url)
    }

    /// Labels, epic and the epic's other sub-issues of the issue with `nodeID`.
    public func issueNeighbours(nodeID: String, selfNumber: Int) async throws -> IssueNeighbours {
        struct Data: Decodable {
            struct Node: Decodable {
                struct Labels: Decodable { struct Label: Decodable { let name: String }; let nodes: [Label] }
                struct Issue: Decodable { let number: Int; let title: String; let state: String }
                struct Parent: Decodable {
                    struct SubIssues: Decodable { let nodes: [Issue] }
                    let number: Int; let title: String; let state: String; let subIssues: SubIssues?
                }
                let labels: Labels?
                let parent: Parent?
            }
            let node: Node?
        }
        let document = """
        query($id: ID!) { node(id: $id) { ... on Issue {
          labels(first: 20) { nodes { name } }
          parent { number title state subIssues(first: 30) { nodes { number title state } } }
        } } }
        """
        let data: Data = try await query(document, variables: ["id": nodeID])
        let parent = data.node?.parent
        return IssueNeighbours(
            labels: data.node?.labels?.nodes.map(\.name) ?? [],
            epic: parent.map { IssueSummary(number: $0.number, title: $0.title, isOpen: $0.state == "OPEN") },
            siblings: (parent?.subIssues?.nodes ?? []).filter { $0.number != selfNumber }
                .map { IssueSummary(number: $0.number, title: $0.title, isOpen: $0.state == "OPEN") }
        )
    }

    // MARK: Helpers

    /// "owner/name" with GitHub's allowed characters only.
    static func checked(_ repository: String) throws -> String {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(allowed.contains)
        }) else { throw GitHubAPIError.invalidRepository }
        return repository
    }

    /// A relative path inside the repository, without "." or ".." segments.
    static func checkedPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !trimmed.isEmpty, segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw GitHubAPIError.invalidRepository
        }
        return trimmed
    }

    private static func decodeContent(_ content: String, encoding: String) throws -> String {
        guard encoding == "base64" else { return content }
        guard let data = Foundation.Data(base64Encoded: content, options: .ignoreUnknownCharacters) else {
            throw GitHubAPIError.decoding("base64 content")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ data: Foundation.Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GitHubAPIError.decoding(String(describing: error))
        }
    }
}
