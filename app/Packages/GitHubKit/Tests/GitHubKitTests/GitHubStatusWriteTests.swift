import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

/// Status per project: reading, editing, completing and reopening (design rules 3, 4 and 10).
@MainActor
struct GitHubStatusWriteTests {
    let transport = StubTransport()
    let issueID = TaskID(source: .github, rawValue: "I_1")

    func makeProvider() -> GitHubTaskProvider {
        let credentials = GitHubCredentials(accessToken: "gho_valid", refreshToken: "ghr", accessExpiresAt: nil, refreshExpiresAt: nil)
        let client = DeviceFlowClient(clientID: "client", transport: transport, sleep: { _ in }, now: { fixedNow })
        let tokens = TokenManager(store: MemoryCredentialStore(credentials), client: client, now: { fixedNow })
        return GitHubTaskProvider(api: GitHubAPI(transport: transport, tokens: tokens), tokens: tokens, cache: MemoryGitHubCache(),
                                  selectedProjectIDs: { nil }, now: { fixedNow })
    }

    private func load(_ provider: GitHubTaskProvider, state: String = "OPEN", _ boards: [Board]) async throws -> TaskItem {
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(state: state, boards: boards))
        return try #require(try await provider.task(id: issueID))
    }

    /// Queues the replies of one `apply`: the version check, `mutations` field writes, an optional issue PATCH, the re-read.
    private func enqueueApply(state: String = "OPEN", before: [Board], after: [Board], mutations: Int, patch: Bool = false) {
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(state: state, boards: before))
        if patch { transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK) }
        for _ in 0..<mutations { transport.enqueueJSON("/graphql", Fixtures.mutationOK) }
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(state: state, updatedAt: "2026-11-17T14:00:00Z", boards: after))
    }

    /// "PATCH <state>" or "MUTATION <field> <option>" for every write after the initial load, in order.
    private func writes() -> [String] {
        transport.requests.dropFirst().compactMap { request in
            let body = request.bodyString
            if request.httpMethod == "PATCH" {
                return body.contains(#""state":"closed""#) ? "PATCH closed" : body.contains(#""state":"open""#) ? "PATCH open" : "PATCH other"
            }
            guard body.contains("updateProjectV2ItemFieldValue") else { return nil }
            let ids = ["F1_status", "F2_status", "F3_status"].first { body.contains($0) } ?? "field"
            let option = body.range(of: #"singleSelectOptionId":""#).map { String(body[$0.upperBound...].prefix { $0 != "\"" }) } ?? "-"
            return "\(ids) \(option)"
        }
    }

    private func edit(_ change: (inout TaskEdit) -> Void) -> TaskEdit {
        var edit = TaskEdit()
        change(&edit)
        return edit
    }

    // MARK: Reading

    @Test func taskItem_listsStatusPerProject_inBoardOrder() async throws {
        let provider = makeProvider()
        let item = try await load(provider, [Board(number: 1, status: "In progress"),
                                             Board(number: 2, stages: ["Todo", "Doing", "Done"], status: "Todo")])
        #expect(item.editableFields.contains(.status))
        #expect(item.statuses.map(\.subContainerID) == ["PVT_1", "PVT_2"])
        #expect(item.statuses[0].current == "In progress")
        #expect(item.statuses[0].options == ["Backlog", "Ready", "In progress", "Blocked", "In review", "Done"])
        #expect(item.statuses[1].options == ["Todo", "Doing", "Done"])
        #expect(item.statuses.allSatisfy { $0.isWritable })
    }

    @Test func taskItem_readOnlyProject_isMarkedNotWritable_andDoesNotMakeStatusEditable() async throws {
        let provider = makeProvider()
        let item = try await load(provider, [Board(number: 1, writable: false)])
        #expect(item.statuses.count == 1 && item.statuses[0].isWritable == false)
        #expect(!item.editableFields.contains(.status))
    }

    @Test func taskItem_projectWithoutStatusField_hasNoOptions() {
        let project = makeProject(1, fields: ["Due date"])
        let item = GitHubMapping.taskItem(makeRecord(placements: [makePlacement(project, status: nil)]))
        #expect(item.statuses.map(\.options) == [[]])
        #expect(!item.editableFields.contains(.status))
    }

    @Test func displayed_treatsDoneCaseInsensitively() {
        let project = makeBoardProject(stages: ["Todo", "DONE"])
        #expect(!GitHubMapping.isVisible(makeRecord(placements: [makePlacement(project, status: "DONE")]), login: "octo"))
        #expect(GitHubMapping.isVisible(makeRecord(placements: [makePlacement(project, status: "Todo")]), login: "octo"))
    }

    // MARK: Changing a status

    @Test func statusChange_setsOnlyThatProject_withItsOwnOptionID() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1), Board(number: 2, stages: ["Todo", "Doing", "Done"], status: "Todo")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_2": "Doing"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F2_status OPT2_Doing"])
    }

    @Test func statusChange_ignoresTargetSubContainerSelection() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1), Board(number: 2)]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1)

        _ = try await provider.apply(edit {
            $0.statusChanges = ["PVT_2": "In review"]
            $0.targetSubContainerIDs = ["PVT_1"]
        }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F2_status OPT2_In review"])
    }

    @Test func statusChange_matchesOptionCaseInsensitively_andWritesProjectSpelling() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1)]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "in progress"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F1_status OPT1_In progress"])
    }

    @Test func statusChange_unknownOption_failsBeforeAnyWrite() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1), Board(number: 2, stages: ["Todo", "Done"], status: "Todo")]
        let item = try await load(provider, boards)
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(boards: boards))

        await #expect(throws: TaskWriteError.failed("Den Status „In progress“ gibt es im Projekt „Projekt 2“ nicht.")) {
            try await provider.apply(edit {
                $0.title = .set("Neu")
                $0.statusChanges = ["PVT_1": "In progress", "PVT_2": "In progress"]
            }, to: issueID, expectedVersion: item.version)
        }
        #expect(writes().isEmpty)
    }

    @Test func statusChange_inReadOnlyOrForeignProject_fails() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1), Board(number: 2, writable: false)]
        let item = try await load(provider, boards)
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(boards: boards))

        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit { $0.statusChanges = ["PVT_2": "Blocked"] }, to: issueID, expectedVersion: item.version)
        }
        await #expect(throws: TaskWriteError.self) {
            try await provider.apply(edit { $0.statusChanges = ["PVT_99": "Blocked"] }, to: issueID, expectedVersion: nil)
        }
        #expect(writes().isEmpty)
    }

    // MARK: Done and completed (rule 3)

    @Test func done_inOneOfTwoProjects_setsFieldOnly_issueStaysOpen() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "In review"), Board(number: 2, status: "In progress")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: [Board(number: 1, status: "Done"), boards[1]], mutations: 1)

        let result = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "Done"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F1_status OPT1_Done"])
        #expect(!result.isCompleted)
        #expect(GitHubMapping.isVisible(makeRecord(placements: [makePlacement(makeBoardProject(1), status: "Done"), makePlacement(makeBoardProject(2), status: "In progress")]), login: "octo"))
    }

    @Test func done_inLastOpenProject_closesTheIssue_beforeWritingFields() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done"), Board(number: 2, status: "In review")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: [boards[0], Board(number: 2, status: "Done")], mutations: 1, patch: true)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_2": "Done"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH closed", "F2_status OPT2_Done"])
        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        #expect(patch.bodyString.contains(#""state_reason":"completed""#))
    }

    @Test func done_inEveryProjectAtOnce_closesTheIssue_andWritesEachFieldOnce() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Ready"), Board(number: 2, status: "Blocked")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 2, patch: true)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "Done", "PVT_2": "Done"] }, to: issueID, expectedVersion: item.version)

        let sequence = writes()
        #expect(sequence.first == "PATCH closed")
        #expect(Set(sequence.dropFirst()) == ["F1_status OPT1_Done", "F2_status OPT2_Done"])
        #expect(sequence.count == 3)
    }

    @Test func done_closesWhenOnlyReadOnlyProjectsAreNotDone() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Ready"), Board(number: 2, status: "Ready", writable: false)]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1, patch: true)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "Done"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH closed", "F1_status OPT1_Done"])
    }

    @Test func nonDoneChange_onOpenIssue_neverTouchesIssueState() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done"), Board(number: 2, status: "Done")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "In progress"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F1_status OPT1_In progress"])
    }

    @Test func complete_usesTheProjectsOwnSpellingOfDone() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, stages: ["Todo", "DONE"], status: "Todo"), Board(number: 2, status: "Ready")]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 2, patch: true)

        _ = try await provider.apply(edit { $0.isCompleted = .set(true) }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH closed", "F1_status OPT1_DONE", "F2_status OPT2_Done"])
    }

    @Test func complete_projectWithoutDoneOption_isSkippedQuietly() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, stages: ["Todo", "Doing"], status: "Todo"), Board(number: 2)]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 1, patch: true)

        _ = try await provider.apply(edit { $0.isCompleted = .set(true) }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH closed", "F2_status OPT2_Done"])
    }

    @Test func complete_withChosenStatus_chosenStageWinsForThatProject() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1), Board(number: 2)]
        let item = try await load(provider, boards)
        enqueueApply(before: boards, after: boards, mutations: 2, patch: true)

        _ = try await provider.apply(edit {
            $0.isCompleted = .set(true)
            $0.statusChanges = ["PVT_2": "In review"]
        }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH closed", "F1_status OPT1_Done", "F2_status OPT2_In review"])
    }

    @Test func delete_setsTheProjectsDoneOption() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, stages: ["Todo", "DONE"], status: "Todo")]
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(boards: boards))
        transport.enqueueJSON("/repos/beispiel/app/issues/1", Fixtures.issuePatchOK)
        transport.enqueueJSON("/graphql", Fixtures.mutationOK)

        try await provider.delete(issueID, expectedVersion: nil)

        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        #expect(patch.bodyString.contains("not_planned"))
        #expect(transport.requests.last?.bodyString.contains("OPT1_DONE") == true)
    }

    // MARK: Reopening (rule 4)

    @Test func reopen_prefersReady_perProject() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done"), Board(number: 2, stages: ["Todo", "Ready", "Done"], status: "Done")]
        let item = try await load(provider, state: "CLOSED", boards)
        enqueueApply(state: "CLOSED", before: boards, after: boards, mutations: 2, patch: true)

        _ = try await provider.apply(edit { $0.isCompleted = .set(false) }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH open", "F1_status OPT1_Ready", "F2_status OPT2_Ready"])
    }

    @Test func reopen_withoutReadyOption_usesFirstNonDoneStageInBoardOrder() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, stages: ["Done", "Backlog", "In progress"], status: "Done"),
                      Board(number: 2, stages: ["Todo", "Doing", "Done"], status: "Done")]
        let item = try await load(provider, state: "CLOSED", boards)
        enqueueApply(state: "CLOSED", before: boards, after: boards, mutations: 2, patch: true)

        _ = try await provider.apply(edit { $0.isCompleted = .set(false) }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["PATCH open", "F1_status OPT1_Backlog", "F2_status OPT2_Todo"])
    }

    @Test func statusAwayFromDone_onClosedIssue_reopensItAfterTheStatusWrite() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done"), Board(number: 2, status: "Done")]
        let item = try await load(provider, state: "CLOSED", boards)
        enqueueApply(state: "CLOSED", before: boards, after: boards, mutations: 1, patch: true)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "In progress"] }, to: issueID, expectedVersion: item.version)

        // The other project keeps Done; the field is written first so a failure cannot leave an open, hidden issue.
        #expect(writes() == ["F1_status OPT1_In progress", "PATCH open"])
    }

    @Test func statusDone_onClosedIssue_doesNotReopen() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done")]
        let item = try await load(provider, state: "CLOSED", boards)
        enqueueApply(state: "CLOSED", before: boards, after: boards, mutations: 1)

        _ = try await provider.apply(edit { $0.statusChanges = ["PVT_1": "Done"] }, to: issueID, expectedVersion: item.version)

        #expect(writes() == ["F1_status OPT1_Done"])
    }

    @Test func statusAwayFromDone_failedFieldWrite_leavesIssueClosed() async throws {
        let provider = makeProvider()
        let boards = [Board(number: 1, status: "Done")]
        let item = try await load(provider, state: "CLOSED", boards)
        transport.enqueueJSON("/graphql", Fixtures.boardIssue(state: "CLOSED", boards: boards))
        transport.enqueueJSON("/graphql", #"{"errors":[{"message":"Kein Zugriff"}]}"#)

        await #expect(throws: TaskWriteError.failed("Kein Zugriff")) {
            try await provider.apply(edit { $0.statusChanges = ["PVT_1": "Ready"] }, to: issueID, expectedVersion: item.version)
        }
        #expect(!writes().contains("PATCH open"))
    }

    // MARK: Listing after a write

    @Test func isListed_needsAssigneeAndAtLeastOnePlacement() async throws {
        let provider = makeProvider()
        Fixtures.enqueueAssignedIssues(on: transport)
        _ = try await provider.openTasks()
        let readOnlyProject = ProjectInfo(id: "PVT_foreign", number: 4, title: "Team", fields: [], canWrite: false)

        let onForeignBoardOnly = GitHubMapping.taskItem(makeRecord(placements: [makePlacement(readOnlyProject)]))
        #expect(onForeignBoardOnly.subContainers.isEmpty)
        #expect(provider.isListed(onForeignBoardOnly))
        #expect(provider.isListed(GitHubMapping.taskItem(makeRecord(placements: [makePlacement(makeProject(1))]))))

        #expect(!provider.isListed(GitHubMapping.taskItem(makeRecord(placements: []))))
        #expect(!provider.isListed(GitHubMapping.taskItem(makeRecord(assignees: ["lea-m"], placements: [makePlacement(makeProject(1))]))))
    }
}
