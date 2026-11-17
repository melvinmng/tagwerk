import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

struct GitHubEpicTests {
    @Test func api_readsParentEpicWithDueDate() async throws {
        let transport = StubTransport()
        Fixtures.enqueueAssignedIssues(on: transport)
        let client = DeviceFlowClient(clientID: "c", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(GitHubCredentials(accessToken: "t", refreshToken: nil,
                                                                                 accessExpiresAt: nil, refreshExpiresAt: nil)),
                                  client: client, now: { fixedNow })
        let result = try await GitHubAPI(transport: transport, tokens: tokens).openProjectIssues()
        let issue = try #require(result.issues.first { $0.issueID == "I_1" })
        #expect(issue.parent == ParentIssue(id: "E_1", number: 10, title: "Phase 2", labels: ["epic"],
                                            due: DueDate(year: 2026, month: 11, day: 30)))
        #expect(transport.requests[1].bodyString.contains("parent"))
        let item = GitHubMapping.taskItem(issue)
        #expect(item.epic == EpicInfo(id: "E_1", number: 10, title: "Phase 2", due: DueDate(year: 2026, month: 11, day: 30), isEpic: true))
    }

    @Test func mapping_epicLabel_setsIsEpic() {
        var record = makeRecord(placements: [makePlacement(makeProject(1))])
        record.labels = ["epic"]
        #expect(GitHubMapping.taskItem(record).isEpic)
        record.labels = ["bug"]
        #expect(!GitHubMapping.taskItem(record).isEpic)
    }

    @Test func record_withoutParentKey_decodesFromOldCache() throws {
        let record = makeRecord(placements: [])
        let data = try JSONEncoder().encode(record)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "parent")
        let decoded = try JSONDecoder().decode(GitHubIssueRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.parent == nil)
    }
}
