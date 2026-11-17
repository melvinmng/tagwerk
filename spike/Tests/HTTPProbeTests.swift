import XCTest
@testable import TagwerkSpike

final class HTTPProbeTests: XCTestCase {
    func test_claudeRequest_hasRequiredHeadersAndBody() throws {
        let request = ClaudeProbe.makeRequest(apiKey: "test-key")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(json["fallbacks"] as? String, "default")
        XCTAssertNil(json["thinking"])
        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "low")
    }

    func test_claudeInterpret_refusal_isNotOk() {
        let body = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        let result = ClaudeProbe.interpret(status: 200, body: body)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.detail.contains("abgelehnt"))
    }

    func test_claudeInterpret_success_showsText() {
        let body = Data(#"{"model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Hallo"}]}"#.utf8)
        let result = ClaudeProbe.interpret(status: 200, body: body)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.detail.contains("Hallo"))
    }

    func test_claudeInterpret_429_isReadable() {
        let result = ClaudeProbe.interpret(status: 429, body: Data())
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.detail.contains("429"))
    }

    func test_githubRequest_usesBearerAndApiVersion() {
        let request = GitHubProbe.makeIssuesRequest(token: "gh-token", login: "melvinmng")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.github.com/repos/melvinmng/tagwerk/issues?assignee=melvinmng&state=open&per_page=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gh-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
    }

    func test_githubUserRequest_targetsUserEndpoint() {
        let request = GitHubProbe.makeUserRequest(token: "gh-token")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gh-token")
    }

    func test_githubParseLogin_readsLoginField() {
        XCTAssertEqual(GitHubProbe.parseLogin(Data(#"{"login":"melvinmng","id":1}"#.utf8)), "melvinmng")
        XCTAssertNil(GitHubProbe.parseLogin(Data("{}".utf8)))
    }

    func test_githubInterpret_401_mentionsToken() {
        let result = GitHubProbe.interpret(status: 401, body: Data())
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.detail.contains("Token"))
    }

    func test_githubInterpret_success_countsIssues() {
        let result = GitHubProbe.interpret(status: 200, body: Data(#"[{"number":5,"title":"x"}]"#.utf8))
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.detail.contains("1"))
    }
}
