import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

struct GitHubRepoReadTests {
    let transport = StubTransport()

    func makeAPI() -> GitHubAPI {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr_valid",
                                            accessExpiresAt: fixedNow.addingTimeInterval(3600), refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubAPI(transport: transport, tokens: tokens)
    }

    static func base64(_ text: String) -> String {
        // GitHub wraps base64 content in lines of 60 characters.
        let encoded = Data(text.utf8).base64EncodedString()
        return stride(from: 0, to: encoded.count, by: 60).map { offset -> String in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: min(60, encoded.count - offset))
            return String(encoded[start..<end])
        }.joined(separator: "\\n")
    }

    @Test func readme_decodesBase64() async throws {
        let text = String(repeating: "# Projekt\nÄnderungen und Hinweise.\n", count: 5)
        transport.enqueueJSON("/repos/beispiel/app/readme", #"{"encoding":"base64","content":"\#(Self.base64(text))"}"#)
        #expect(try await makeAPI().readme(repository: "beispiel/app") == text)
    }

    @Test func file_decodesBase64_andEncodesPath() async throws {
        transport.enqueueJSON("/repos/beispiel/app/contents/Sources/App Main.swift",
                              #"{"type":"file","encoding":"base64","content":"\#(Self.base64("let x = 1"))"}"#)
        let content = try await makeAPI().file(repository: "beispiel/app", path: "Sources/App Main.swift")
        #expect(content == .file("let x = 1"))
        #expect(transport.requests.first?.url?.absoluteString.contains("App%20Main.swift") == true)
    }

    @Test func file_directory_listsEntries() async throws {
        transport.enqueueJSON("/repos/beispiel/app/contents/docs",
                              #"[{"name":"a.md","path":"docs/a.md","type":"file"},{"name":"img","path":"docs/img","type":"dir"}]"#)
        let content = try await makeAPI().file(repository: "beispiel/app", path: "docs")
        #expect(content == .directory(["docs/a.md", "docs/img/"]))
    }

    @Test func searchRepository_limitsResults() async throws {
        let items = (1...30).map { #"{"name":"f\#($0).swift","path":"Sources/f\#($0).swift","html_url":"https://github.com/x"}"# }
        transport.enqueueJSON("/search/code", #"{"total_count":30,"items":[\#(items.joined(separator: ","))]}"#)
        let hits = try await makeAPI().searchCode(repository: "beispiel/app", query: "Login", limit: 10)
        #expect(hits.count == 10)
        #expect(hits.first == "Sources/f1.swift")
        let url = try #require(transport.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "q" }?.value == "Login repo:beispiel/app")
        #expect(query.first { $0.name == "per_page" }?.value == "10")
    }

    @Test func issueComments_decodes() async throws {
        transport.enqueueJSON("/repos/beispiel/app/issues/42/comments",
                              #"[{"user":{"login":"anna"},"body":"Sieht gut aus.","created_at":"2026-11-17T09:00:00Z"}]"#)
        let comments = try await makeAPI().issueComments(repository: "beispiel/app", number: 42)
        #expect(comments == [IssueComment(author: "anna", body: "Sieht gut aus.", createdAt: "2026-11-17T09:00:00Z")])
    }

    @Test func pullRequest_decodes() async throws {
        transport.enqueueJSON("/repos/beispiel/app/pulls/7", """
        {"number":7,"title":"Login reparieren","state":"closed","merged":true,"body":"Behebt #42","user":{"login":"anna"},
         "changed_files":3,"additions":40,"deletions":5,"html_url":"https://github.com/beispiel/app/pull/7"}
        """)
        let pull = try await makeAPI().pullRequest(repository: "beispiel/app", number: 7)
        #expect(pull.title == "Login reparieren")
        #expect(pull.merged)
        #expect(pull.changedFiles == 3)
        #expect(pull.author == "anna")
    }

    @Test func epicSiblings_readsParentAndSubIssues() async throws {
        transport.enqueueJSON("/graphql", """
        {"data":{"node":{"labels":{"nodes":[{"name":"bug"}]},"parent":{"number":2,"title":"Epic","state":"OPEN",
          "subIssues":{"nodes":[{"number":41,"title":"A","state":"OPEN"},{"number":42,"title":"Selbst","state":"OPEN"},
                                {"number":43,"title":"B","state":"CLOSED"}]}}}}}
        """)
        let context = try await makeAPI().issueNeighbours(nodeID: "I_42", selfNumber: 42)
        #expect(context.labels == ["bug"])
        #expect(context.epic == IssueSummary(number: 2, title: "Epic", isOpen: true))
        #expect(context.siblings == [IssueSummary(number: 41, title: "A", isOpen: true), IssueSummary(number: 43, title: "B", isOpen: false)])
    }

    @Test(arguments: ["beispiel", "../etc/passwd", "a/b/c", "beispiel/../x", "a b/c", ""])
    func invalidRepository_rejected(_ repository: String) async {
        await #expect(throws: GitHubAPIError.invalidRepository) { try await makeAPI().readme(repository: repository) }
        #expect(transport.requests.isEmpty)
    }

    @Test func invalidPath_rejected() async {
        await #expect(throws: GitHubAPIError.invalidRepository) {
            try await makeAPI().file(repository: "beispiel/app", path: "../../secrets")
        }
    }
}
