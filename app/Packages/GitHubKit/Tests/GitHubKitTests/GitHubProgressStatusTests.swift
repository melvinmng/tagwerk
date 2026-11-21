import Testing
import TagwerkCore
@testable import GitHubKit

/// What a task row says about the progress of an issue (GH4c): only stages after the start stage count as "in work".
struct GitHubProgressStatusTests {
    private let board = ["Backlog", "Ready", "In Progress", "Done"]

    private func status(_ current: String?, options: [String]? = nil, project: String = "P") -> SubContainerStatus {
        SubContainerStatus(subContainerID: "PVT_\(project)", subContainerName: project, current: current,
                           options: options ?? board, isWritable: true)
    }

    @Test func progressStatus_startStage_isNil() {
        #expect(GitHubMapping.progressStatus(of: [status("Ready")]) == nil)
    }

    @Test func progressStatus_beforeStartStage_isNil() {
        #expect(GitHubMapping.progressStatus(of: [status("Backlog")]) == nil)
    }

    @Test func progressStatus_done_isNil() {
        #expect(GitHubMapping.progressStatus(of: [status("Done")]) == nil)
        #expect(GitHubMapping.progressStatus(of: [status("done")]) == nil)
    }

    @Test func progressStatus_inProgress_namesStage() {
        #expect(GitHubMapping.progressStatus(of: [status("In Progress")]) == .stage("In Progress"))
    }

    /// Without "Ready" the first stage that is not "Done" is the start stage.
    @Test func progressStatus_withoutReady_usesFirstNonDoneAsStart() {
        let options = ["Todo", "Doing", "Done"]
        #expect(GitHubMapping.progressStatus(of: [status("Doing", options: options)]) == .stage("Doing"))
        #expect(GitHubMapping.progressStatus(of: [status("Todo", options: options)]) == nil)
    }

    @Test func progressStatus_twoProjectsSameStage_namesItOnce() {
        let statuses = [status("In Progress", project: "A"), status("In Progress", project: "B")]
        #expect(GitHubMapping.progressStatus(of: statuses) == .stage("In Progress"))
    }

    @Test func progressStatus_twoProjectsDifferentStages_isSeveral() {
        let options = ["Ready", "In Progress", "In Review", "Done"]
        let statuses = [status("In Progress", options: options, project: "A"), status("In Review", options: options, project: "B")]
        #expect(GitHubMapping.progressStatus(of: statuses) == .several(2))
    }

    @Test func progressStatus_oneInWorkOneAtStart_namesTheOneInWork() {
        let statuses = [status("Ready", project: "A"), status("In Progress", project: "B")]
        #expect(GitHubMapping.progressStatus(of: statuses) == .stage("In Progress"))
    }

    @Test func progressStatus_noStatusValue_isNil() {
        #expect(GitHubMapping.progressStatus(of: [status(nil)]) == nil)
        #expect(GitHubMapping.progressStatus(of: []) == nil)
    }

    @Test func isInProgress_stageMissingFromTheBoard_isFalse() {
        #expect(!GitHubMapping.isInProgress(status("Gone")))
        #expect(!GitHubMapping.isInProgress(status("In Progress", options: [])))
    }
}
