import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

@MainActor
struct GitHubTaskProviderWriteTests {
    let transport = StubTransport()
    let cache = MemoryGitHubCache()
    let issueID = TaskID(source: .github, rawValue: "I_1")

    func makeProvider(selection: Set<String>? = nil) -> GitHubTaskProvider {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: cache,
                                  selectedProjectIDs: { selection }, now: { fixedNow })
    }

    /// Loads the item once (consuming one GraphQL reply) and returns it with its version.
    private func loadItem(_ provider: GitHubTaskProvider) async throws -> TaskItem {
        transport.enqueueJSON("/graphql", Fixtures.issue())
        return try #require(try await provider.task(id: issueID))
    }

    /// GraphQL request bodies after the initial load, in order.
    private func writeBodies() -> [String] {
        Array(transport.requests.dropFirst().map { "\($0.httpMethod ?? "") \($0.url?.path ?? "") \($0.bodyString)" })
    }

    private func edit(_ change: (inout TaskEdit) -> Void) -> TaskEdit {
        var edit = TaskEdit()
        change(&edit)
        return edit
    }

    @Test func complete_closesIssueBeforeSettingDoneInAllProjects() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.issue(state: "CLOSED", status1: "Done", status2: "Done", updatedAt: "2026-11-17T14:00:00Z"))

        let result = try await provider.apply(edit { $0.isCompleted = .set(true) }, to: issueID, expectedVersion: item.version)

        let bodies = writeBodies()
        #expect(bodies.count == 5)
        #expect(bodies[0].contains("POST /graphql") && bodies[0].contains("I_1"))
        #expect(bodies[1].hasPrefix("PATCH /repos/beispiel/app/issues/1"))
        #expect(bodies[1].contains(#""state":"closed""#) && bodies[1].contains(#""state_reason":"completed""#))
        #expect(bodies[2].contains("updateProjectV2ItemFieldValue") && bodies[2].contains("OPT_done") && bodies[2].contains("PVTI_a"))
        #expect(bodies[3].contains("updateProjectV2ItemFieldValue") && bodies[3].contains("OPT2_done") && bodies[3].contains("PVTI_c"))
        #expect(bodies[4].contains("projectItems"))
        #expect(result.isCompleted)
    }

    @Test func complete_returnsStateReadAfterWrite() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        // A project workflow moved project 2 to "In review" after the write.
        transport.enqueueJSON("/graphql", Fixtures.issue(state: "CLOSED", status1: "Done", status2: "In review", updatedAt: "2026-11-17T14:00:00Z"))

        let result = try await provider.apply(edit { $0.isCompleted = .set(true) }, to: issueID, expectedVersion: item.version)
        #expect(result.isCompleted)
        #expect(result.version.hasPrefix("2026-11-17T14:00:00Z"))
    }

    @Test func reopen_setsStatusReady() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit { $0.isCompleted = .set(false) }, to: issueID, expectedVersion: item.version)

        let bodies = writeBodies()
        #expect(bodies[1].contains(#""state":"open""#))
        #expect(bodies[2].contains("OPT_ready"))
        #expect(bodies[3].contains("OPT2_ready"))
    }

    @Test func reschedule_changesOnlyDueDate() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit { $0.due = .set(DueDate(year: 2026, month: 11, day: 24, hour: 9, minute: 0)) },
                                     to: issueID, expectedVersion: item.version)

        let bodies = writeBodies()
        #expect(!bodies.contains { $0.hasPrefix("PATCH") })
        let mutations = bodies.filter { $0.contains("updateProjectV2ItemFieldValue") }
        #expect(mutations.count == 2)
        #expect(mutations.allSatisfy { $0.contains(#""date":"2026-11-24""#) })
        #expect(mutations[0].contains("F_due") && mutations[1].contains("F2_due"))
    }

    @Test func editPriority_targetSingleProject_onlyThatProject() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit {
            $0.priority = .set(.p1)
            $0.targetSubContainerIDs = ["PVT_1"]
        }, to: issueID, expectedVersion: item.version)

        let mutations = writeBodies().filter { $0.contains("updateProjectV2ItemFieldValue") }
        #expect(mutations.count == 1)
        #expect(mutations[0].contains("F_prio") && mutations[0].contains("OPT_p1"))
    }

    @Test func editEstimate_mandaysProject_writesMandays() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit { $0.estimateMinutes = .set(720) }, to: issueID, expectedVersion: item.version)

        let mutations = writeBodies().filter { $0.contains("updateProjectV2ItemFieldValue") }
        #expect(mutations.contains { $0.contains("F_est") && $0.contains(#""number":12"#) })
        #expect(mutations.contains { $0.contains("F2_est") && $0.contains(#""number":1.5"#) })
    }

    @Test func clearDue_usesClearMutation() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/graphql", Fixtures.clearOK)
        transport.enqueueJSON("/graphql", Fixtures.clearOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit { $0.due = .set(nil) }, to: issueID, expectedVersion: item.version)

        let mutations = writeBodies().filter { $0.contains("clearProjectV2ItemFieldValue") }
        #expect(mutations.count == 2)
    }

    @Test func apply_staleVersion_throwsConflictWithoutWrites() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue(updatedAt: "2026-11-17T15:00:00Z", title: "Extern geändert"))

        do {
            _ = try await provider.apply(edit { $0.title = .set("Neu") }, to: issueID, expectedVersion: item.version)
            Issue.record("expected a conflict")
        } catch TaskWriteError.conflict(let current) {
            #expect(current.title == "Extern geändert")
        }
        #expect(writeBodies().count == 1)
    }

    @Test func apply_offline_throwsOffline() async throws {
        let provider = makeProvider()
        transport.enqueue("/graphql", .failure(.notConnectedToInternet))
        await #expect(throws: TaskWriteError.offline) {
            try await provider.apply(edit { $0.title = .set("Neu") }, to: issueID, expectedVersion: "x")
        }
    }

    @Test func editTitleOnly_sendsOnlyTitle() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.issue(title: "Neu"))

        let result = try await provider.apply(edit { $0.title = .set("Neu") }, to: issueID, expectedVersion: item.version)

        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        let json = try #require(try JSONSerialization.jsonObject(with: patch.httpBody ?? Data()) as? [String: Any])
        #expect(json.keys.sorted() == ["title"])
        #expect(json["title"] as? String == "Neu")
        #expect(result.title == "Neu")
    }

    @Test func editLabelsAndClearBody() async throws {
        let provider = makeProvider()
        let item = try await loadItem(provider)
        transport.enqueueJSON("/graphql", Fixtures.issue())
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.issue())

        _ = try await provider.apply(edit {
            $0.labels = .set(["bug", "ui"])
            $0.notes = .set(nil)
        }, to: issueID, expectedVersion: item.version)

        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        let json = try #require(try JSONSerialization.jsonObject(with: patch.httpBody ?? Data()) as? [String: Any])
        #expect(json["labels"] as? [String] == ["bug", "ui"])
        #expect(json["body"] is NSNull)
    }

    @Test func listVersion_withRestrictedSelection_matchesFullIssueVersion() async throws {
        transport.enqueueJSON("/graphql", Fixtures.viewerProjects)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject1Page1)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject1Page2)
        transport.enqueueJSON("/graphql", Fixtures.itemsProject2)
        let provider = makeProvider(selection: ["PVT_1"])
        let shown = try #require(try await provider.openTasks().first)

        let full = try #require(provider.records["I_1"])
        #expect(shown.version == GitHubMapping.taskItem(full).version)
    }

    @Test func addComment_postsBody() async throws {
        let provider = makeProvider()
        _ = try await loadItem(provider)
        transport.enqueueJSON("/repos/beispiel/app/issues/1/comments", #"{"id":5}"#)
        try await provider.addComment(to: issueID, body: "Erledigt bis Freitag")
        let request = try #require(transport.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/repos/beispiel/app/issues/1/comments")
        #expect(request.bodyString.contains("Erledigt bis Freitag"))
    }
}
