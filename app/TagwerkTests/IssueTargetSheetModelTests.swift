import Foundation
import GitHubKit
import Testing
import TagwerkCore
@testable import Tagwerk

/// The sheet "Ziel wählen" for an issue suggested from a note (issue #173, decisions D7 and D8).
@MainActor
struct IssueTargetSheetModelTests {
    let catalog: GitHubCatalog

    init() {
        let tagwerk = ProjectInfo(id: "PVT_T", number: 1, title: "Tagwerk", fields: [], repositories: ["melvinmng/tagwerk"])
        let other = ProjectInfo(id: "PVT_O", number: 2, title: "Sonstiges", fields: [], repositories: [])
        catalog = GitHubCatalog(repositories: ["melvinmng/tagwerk", "melvinmng/app"], projects: [tagwerk, other],
                                fetchedAt: Date(timeIntervalSince1970: 0))
    }

    private func make(repository: String? = nil, projectIDs: [String] = [],
                      assignable: [String: [String]?] = ["melvinmng/tagwerk": ["octo", "lea-m", "jonas-k"], "melvinmng/app": ["octo", "kai"]])
        -> IssueTargetSheetModel {
        IssueTargetSheetModel(catalog: catalog, me: "octo", repository: repository, projectIDs: projectIDs,
                              loadAssignable: { repository in assignable[repository] ?? nil })
    }

    @Test func sheetModel_preselectsLinkedProjects() {
        let model = make()
        #expect(!model.canApply && model.projectIDs.isEmpty)
        model.repository = "melvinmng/tagwerk"
        #expect(model.projectIDs == ["PVT_T"])
        // A repository the card already carries is preselected the same way when it brings no projects.
        #expect(make(repository: "melvinmng/tagwerk").projectIDs == ["PVT_T"])
        // Projects the card carries are kept.
        #expect(make(repository: "melvinmng/tagwerk", projectIDs: ["PVT_O"]).projectIDs == ["PVT_O"])
    }

    @Test func sheetModel_changingRepository_resetsPeopleAndProjects() async {
        let model = make(repository: "melvinmng/tagwerk")
        await model.loadAssignees()
        model.choose(["lea-m"])
        model.projectIDs = ["PVT_O"]
        model.projectsEdited = true
        model.repository = "melvinmng/app"
        #expect(model.projectIDs.isEmpty && !model.projectsEdited)       // no project is linked to that repository
        #expect(model.assignees == ["octo"] && !model.assigneesChosen)
        #expect(model.result?.assignees == nil)
        #expect(model.assigneeLoad == .idle)
    }

    @Test func sheetModel_resultWithoutChoice_assignsMe() async {
        let model = make(repository: "melvinmng/tagwerk")
        #expect(model.result?.assignees == nil)
        await model.loadAssignees()
        #expect(model.result?.repository == "melvinmng/tagwerk" && model.result?.projectIDs == ["PVT_T"])
        #expect(model.result?.assignees == nil)
        model.choose(["octo", "lea-m"])
        #expect(model.result?.assignees == ["octo", "lea-m"])    // menu order: the user first
        model.choose([])
        #expect(model.result?.assignees == [])                    // "Niemand" is a choice
    }

    @Test func sheetModel_resultKeepsCatalogOrderOfProjects() {
        let model = make(repository: "melvinmng/tagwerk")
        model.projectIDs = ["PVT_O", "PVT_T"]
        #expect(model.result?.projectIDs == ["PVT_T", "PVT_O"])
        model.projectIDs = []
        #expect(model.result?.projectIDs == [])
    }

    @Test func sheetModel_withoutRepository_cannotApply() {
        let model = make()
        #expect(!model.canApply && model.result == nil)
    }

    @Test func sheetModel_tenPeopleLimit() async {
        let logins = (1...12).map { "person-\($0)" }
        let model = make(repository: "melvinmng/tagwerk", assignable: ["melvinmng/tagwerk": logins])
        await model.loadAssignees()
        model.choose(Set(logins.prefix(10)))
        #expect(model.assignees.count == 10 && model.result?.assignees?.count == 10)
        #expect(!model.canAddAssignee)
        model.choose(Set(logins.prefix(11)))              // the eleventh is refused
        #expect(model.assignees.count == 10)
    }

    @Test func sheetModel_assignableLoadFails_offersOnlyMe() async {
        let model = make(repository: "melvinmng/tagwerk", assignable: [:])
        await model.loadAssignees()
        #expect(model.assigneeLoad == .failed(repository: "melvinmng/tagwerk"))
        #expect(model.assigneeCandidates == ["octo"])
        #expect(model.result?.assignees == nil)
    }

    @Test func sheetModel_loadedPeople_areOrderedWithMeFirst() async {
        let model = make(repository: "melvinmng/tagwerk")
        await model.loadAssignees()
        #expect(model.assigneeCandidates == ["octo", "jonas-k", "lea-m"])
    }

    @Test func sheetModel_lateAnswerForAnotherRepository_isDiscarded() async {
        let model = IssueTargetSheetModel(catalog: catalog, me: "octo", repository: "melvinmng/tagwerk", projectIDs: [],
                                          loadAssignable: { _ in
                                              try? await Task.sleep(for: .milliseconds(50))
                                              return ["octo", "late"]
                                          })
        let loading = Task { await model.loadAssignees() }
        while model.assigneeLoad == .idle { await Task.yield() }
        model.repository = "melvinmng/app"
        await loading.value
        #expect(model.assigneeLoad == .idle && !model.assigneeCandidates.contains("late"))
    }

    // MARK: Row text

    @Test func summary_namesRepositoryAndProjects() {
        let tagwerk = AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T"])
        #expect(IssueTargetText.summary(of: tagwerk, in: catalog) == "Ziel: melvinmng/tagwerk · Projekt Tagwerk")
        #expect(IssueTargetText.summary(of: AppTools.GitHubTarget(repository: "melvinmng/app", projectIDs: []), in: catalog)
                == "Ziel: melvinmng/app · Kein Projekt")
        #expect(IssueTargetText.summary(of: AppTools.GitHubTarget(repository: "melvinmng/tagwerk", projectIDs: ["PVT_T", "PVT_O"]), in: catalog)
                == "Ziel: melvinmng/tagwerk · Projekt Tagwerk, Sonstiges")
        #expect(IssueTargetText.summary(of: nil, in: catalog) == "Ziel wählen")
    }
}
