import Foundation

/// Errors of GitHub API calls.
public enum GitHubAPIError: Error, Equatable, Sendable {
    /// No connection; callers fall back to the cache.
    case network(String)
    case http(Int)
    case graphQL(String)
    case decoding(String)
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

    /// All open projects of the viewer and every issue in them, merged per issue.
    public func openProjectIssues() async throws -> (login: String, projects: [ProjectInfo], issues: [GitHubIssueRecord]) {
        let (login, projects) = try await viewerProjects()
        var contents: [String: ProjectsQuery.IssueContent] = [:]
        var placements: [String: [ProjectPlacement]] = [:]
        var order: [String] = []

        for project in projects {
            var cursor: String?
            repeat {
                let data: ProjectsQuery.ItemsData = try await query(
                    ProjectsQuery.projectItems, variables: ItemsVariables(projectID: project.id, cursor: cursor)
                )
                guard let items = data.node?.items else { break }
                for item in items.nodes where !item.isArchived {
                    guard let content = item.content, content.__typename == "Issue", let issueID = content.id else { continue }
                    if contents[issueID] == nil {
                        contents[issueID] = content
                        order.append(issueID)
                    }
                    placements[issueID, default: []].append(item.placement(in: project))
                }
                cursor = items.pageInfo.hasNextPage ? items.pageInfo.endCursor : nil
            } while cursor != nil
        }

        let issues = order.compactMap { id in contents[id]?.record(placements: placements[id] ?? []) }
        return (login, projects, issues)
    }

    /// Fresh state of one issue with its items in open projects, or `nil` if it is gone.
    public func issue(nodeID: String) async throws -> GitHubIssueRecord? {
        let data: ProjectsQuery.IssueData = try await query(ProjectsQuery.issueNode, variables: ["id": nodeID])
        guard let node = data.node else { return nil }
        let placements = (node.projectItems?.nodes ?? []).compactMap { item -> ProjectPlacement? in
            guard !item.isArchived, let project = item.project, !project.closed else { return nil }
            return item.placement(in: project.info)
        }
        return node.content.record(placements: placements)
    }

    // MARK: Transport

    /// Runs a GraphQL document and decodes its `data` member.
    func query<Result: Decodable, Variables: Encodable & Sendable>(_ document: String, variables: Variables) async throws -> Result {
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
        if let message = envelope.errors?.first?.message { throw GitHubAPIError.graphQL(message) }
        guard let result = envelope.data else { throw GitHubAPIError.decoding("missing data") }
        return result
    }

    /// Runs a GraphQL document without variables.
    func query<Result: Decodable>(_ document: String) async throws -> Result {
        try await query(document, variables: [String: String]())
    }

    /// Sends a REST request with an optional JSON body and returns the response body.
    @discardableResult
    func rest(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil) async throws -> Data {
        let url = Self.restBaseURL.appending(path: path)
        let data = try body.map { try JSONEncoder().encode($0) }
        return try await send(method: method, url: url, body: data)
    }

    private func viewerProjects() async throws -> (login: String, projects: [ProjectInfo]) {
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

    private struct ItemsVariables: Encodable, Sendable {
        let projectID: String
        let cursor: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(projectID, forKey: .projectID)
            try container.encode(cursor, forKey: .cursor)
        }

        enum CodingKeys: String, CodingKey { case projectID, cursor }
    }
}
