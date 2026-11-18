import Foundation

/// Errors of GitHub API calls.
public enum GitHubAPIError: Error, Equatable, Sendable {
    /// No connection; callers fall back to the cache.
    case network(String)
    case http(Int)
    case graphQL(String)
    case decoding(String)
    /// A repository name that is not "owner/name", or a path that leaves the repository.
    case invalidRepository
}

/// Authenticated access to the GitHub GraphQL and REST APIs.
public struct GitHubAPI: Sendable {
    static let graphQLURL = URL(string: "https://api.github.com/graphql")!
    static let restBaseURL = URL(string: "https://api.github.com")!

    private let transport: HTTPTransport
    private let tokens: TokenManager

    public init(transport: HTTPTransport, tokens: TokenManager) {
        self.transport = transport
        self.tokens = tokens
    }

    // MARK: Reading

    public func viewerLogin() async throws -> String {
        try await viewerProjects().login
    }

    /// Open issues assigned to the viewer in open projects, and those projects: the viewer's own plus
    /// every readable project of another owner (person or organization) that holds such an issue.
    /// Archived items and closed projects are ignored.
    public func openProjectIssues() async throws -> (login: String, projects: [ProjectInfo], issues: [GitHubIssueRecord]) {
        let (login, ownProjects) = try await viewerProjects()
        var projectsByID = Dictionary(ownProjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var issues: [GitHubIssueRecord] = []
        var cursor: String?
        repeat {
            let data: ProjectsQuery.SearchData = try await query(
                ProjectsQuery.assignedIssues, variables: CursorVariables(cursor: cursor), allowPartial: true
            )
            for node in data.search.nodes.compactMap({ $0 }) {
                let placements = (node.projectItems?.nodes ?? []).compactMap { item -> ProjectPlacement? in
                    guard !item.isArchived, let reference = item.project else { return nil }
                    if projectsByID[reference.id] == nil, let node = reference.node, !node.closed {
                        projectsByID[reference.id] = node.info
                    }
                    guard let project = projectsByID[reference.id] else { return nil }
                    return item.placement(in: project)
                }
                guard !placements.isEmpty, let record = node.content.record(placements: placements) else { continue }
                issues.append(record)
            }
            cursor = data.search.pageInfo.hasNextPage ? data.search.pageInfo.endCursor : nil
        } while cursor != nil
        let projects = projectsByID.values.sorted { ($0.number, $0.id) < ($1.number, $1.id) }
        return (login, projects, issues)
    }

    /// Fresh state of one issue with its items in open projects, or `nil` if it is gone.
    public func issue(nodeID: String) async throws -> GitHubIssueRecord? {
        let data: ProjectsQuery.IssueData = try await query(ProjectsQuery.issueNode, variables: ["id": nodeID])
        guard let node = data.node else { return nil }
        let placements = (node.projectItems?.nodes ?? []).compactMap { item -> ProjectPlacement? in
            guard !item.isArchived, let project = item.project?.node, !project.closed else { return nil }
            return item.placement(in: project.info)
        }
        return node.content.record(placements: placements)
    }

    // MARK: Transport

    /// Runs a GraphQL document and decodes its `data` member.
    /// With `allowPartial`, errors next to usable data (e.g. one node of an organization that has not
    /// approved the app) are ignored; the affected nodes arrive as `null` and are skipped.
    func query<Result: Decodable, Variables: Encodable & Sendable>(_ document: String, variables: Variables,
                                                                   allowPartial: Bool = false) async throws -> Result {
        let body = try JSONEncoder().encode(GraphQLRequest(query: document, variables: variables))
        let data = try await send(method: "POST", url: Self.graphQLURL, body: body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: GraphQLResponse<Result>
        do {
            envelope = try decoder.decode(GraphQLResponse<Result>.self, from: data)
        } catch {
            throw GitHubAPIError.decoding(String(describing: error))
        }
        if allowPartial, let result = envelope.data { return result }
        if let message = envelope.errors?.first?.message { throw GitHubAPIError.graphQL(message) }
        guard let result = envelope.data else { throw GitHubAPIError.decoding("missing data") }
        return result
    }

    /// Runs a GraphQL document without variables.
    func query<Result: Decodable>(_ document: String) async throws -> Result {
        try await query(document, variables: [String: String]())
    }

    /// Repositories owned by the viewer, most recently pushed first.
    public func ownedRepositories() async throws -> [String] {
        struct Repository: Decodable { let full_name: String }
        let data = try await rest("GET", "user/repos", query: [
            URLQueryItem(name: "affiliation", value: "owner"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
        do {
            return try JSONDecoder().decode([Repository].self, from: data).map(\.full_name)
        } catch {
            throw GitHubAPIError.decoding(String(describing: error))
        }
    }

    /// Sends a REST request with an optional JSON body and returns the response body.
    @discardableResult
    func rest(_ method: String, _ path: String, query: [URLQueryItem] = [],
              body: (any Encodable & Sendable)? = nil) async throws -> Data {
        var url = Self.restBaseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        let data = try body.map { try JSONEncoder().encode($0) }
        return try await send(method: method, url: url, body: data)
    }

    func viewerProjects() async throws -> (login: String, projects: [ProjectInfo]) {
        let data: ProjectsQuery.ViewerData = try await query(ProjectsQuery.viewerProjects)
        let projects = data.viewer.projectsV2.nodes.filter { !$0.closed }.map(\.info).sorted { $0.number < $1.number }
        return (data.viewer.login, projects)
    }

    /// Adds authentication; after HTTP 401 refreshes the token once and retries.
    private func send(method: String, url: URL, body: Data?) async throws -> Data {
        let token = try await authToken { try await tokens.validAccessToken() }
        let (data, response) = try await perform(method: method, url: url, body: body, token: token)
        guard response.statusCode == 401 else { return try check(data, response) }
        let fresh = try await authToken { try await tokens.handleUnauthorized(failedToken: token) }
        let (retryData, retryResponse) = try await perform(method: method, url: url, body: body, token: fresh)
        return try check(retryData, retryResponse)
    }

    private func authToken(_ fetch: () async throws -> String) async throws -> String {
        do {
            return try await fetch()
        } catch GitHubAuthError.network(let message) {
            throw GitHubAPIError.network(message)
        }
    }

    private func perform(method: String, url: URL, body: Data?, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            return try await transport.send(request)
        } catch {
            throw GitHubAPIError.network(error.localizedDescription)
        }
    }

    private func check(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        guard (200..<300).contains(response.statusCode) else { throw GitHubAPIError.http(response.statusCode) }
        return data
    }

    private struct GraphQLRequest<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }

    private struct GraphQLResponse<Result: Decodable>: Decodable {
        struct Message: Decodable { let message: String }
        let data: Result?
        let errors: [Message]?
    }

    private struct CursorVariables: Encodable, Sendable {
        let cursor: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(cursor, forKey: .cursor)
        }

        enum CodingKeys: String, CodingKey { case cursor }
    }
}
