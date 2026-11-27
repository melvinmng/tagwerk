import Foundation
import Testing
import GitHubKit
import TagwerkCore
@testable import Tagwerk

struct NewTaskDestinationTests {
    private func project(_ id: String, _ title: String, repositories: [String]) -> ProjectInfo {
        ProjectInfo(id: id, number: 1, title: title, fields: [], repositories: repositories)
    }

    private let catalog = GitHubCatalog(
        repositories: ["octo/app", "octo/docs", "octo/solo"],
        projects: [
            ProjectInfo(id: "P_APP", number: 1, title: "App", fields: [], repositories: ["octo/app"]),
            ProjectInfo(id: "P_ALL", number: 2, title: "Alles", fields: [], repositories: ["octo/app", "octo/docs"]),
            ProjectInfo(id: "P_NONE", number: 3, title: "Leer", fields: [], repositories: []),
            ProjectInfo(id: "P_GONE", number: 4, title: "Fremd", fields: [], repositories: ["other/hidden"]),
        ],
        fetchedAt: Date(timeIntervalSince1970: 0))

    private func destination(_ kind: ProjectProgressReference.Kind, _ id: String, _ title: String = "Titel") -> NewTaskDestination {
        NewTaskDestination(reference: ProjectProgressReference(kind: kind, id: id, title: title))
    }

    @Test func eachKindCreatesInItsOwnSource() {
        #expect(destination(.gitHubProject, "P_APP").source == .github)
        #expect(destination(.gitHubRepository, "octo/app").source == .github)
        #expect(destination(.remindersList, "list-1").source == .reminders)
        #expect(destination(.local, ProjectProgressReference.localID).source == .local)
    }

    @Test func githubKindsOfferAnIssueAndTheOthersATask() {
        #expect(destination(.gitHubProject, "P_APP").actionName == "Issue anlegen")
        #expect(destination(.gitHubRepository, "octo/app").actionName == "Issue anlegen")
        #expect(destination(.remindersList, "list-1").actionName == "Aufgabe anlegen")
        #expect(destination(.local, ProjectProgressReference.localID).actionName == "Aufgabe anlegen")
    }

    @Test func aRepositoryFillsItselfAndThePreselectedProjectsOfThatRepository() {
        let fields = destination(.gitHubRepository, "octo/app").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: "octo/app", projectIDs: ["P_APP", "P_ALL"], protectsProjects: false))
    }

    @Test func aRepositoryWithoutLinkedProjectsFillsNoProject() {
        let fields = destination(.gitHubRepository, "octo/solo").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: "octo/solo", projectIDs: [], protectsProjects: false))
    }

    @Test func aRepositoryThatTheCatalogLacksLeavesTheChoiceToTheUser() {
        let fields = destination(.gitHubRepository, "octo/archiviert").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: nil, projectIDs: [], protectsProjects: false))
    }

    @Test func aProjectWithOneRepositoryFillsBothAndKeepsTheProjectOnARepositoryChange() {
        let fields = destination(.gitHubProject, "P_APP").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: "octo/app", projectIDs: ["P_APP"], protectsProjects: true))
    }

    @Test func aProjectWithSeveralRepositoriesFillsOnlyTheProject() {
        let fields = destination(.gitHubProject, "P_ALL").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: nil, projectIDs: ["P_ALL"], protectsProjects: true))
    }

    @Test func aProjectWithoutRepositoriesFillsOnlyTheProject() {
        let fields = destination(.gitHubProject, "P_NONE").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: nil, projectIDs: ["P_NONE"], protectsProjects: true))
    }

    @Test func aRepositoryOfAProjectThatTheCatalogLacksIsNotFilledIn() {
        let fields = destination(.gitHubProject, "P_GONE").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: nil, projectIDs: ["P_GONE"], protectsProjects: true))
    }

    @Test func aProjectThatTheCatalogLacksFillsNothing() {
        let fields = destination(.gitHubProject, "P_UNKNOWN").issueFields(in: catalog)
        #expect(fields == NewTaskDestination.IssueFields(repository: nil, projectIDs: [], protectsProjects: false))
    }

    @Test func remindersAndLocalTasksHaveNoIssueFields() {
        #expect(destination(.remindersList, "list-1").issueFields(in: catalog) == nil)
        #expect(destination(.local, ProjectProgressReference.localID).issueFields(in: catalog) == nil)
    }

    @Test func aReminderListIsPreselectedOnlyWhenTheSheetOffersIt() {
        let lists = [TaskContainer(id: "list-1", name: "Privat", colorHex: nil), TaskContainer(id: "list-2", name: "Studium", colorHex: nil)]
        #expect(destination(.remindersList, "list-2").reminderListID(among: lists) == "list-2")
        #expect(destination(.remindersList, "list-9").reminderListID(among: lists) == nil)
        #expect(destination(.remindersList, "list-2").reminderListID(among: []) == nil)
        #expect(destination(.local, "list-2").reminderListID(among: lists) == nil)
        #expect(destination(.gitHubRepository, "list-2").reminderListID(among: lists) == nil)
    }

    @Test func aReadOnlyProjectTakesNoIssue() {
        let readOnly = GitHubCatalog(
            repositories: ["octo/app"],
            projects: [ProjectInfo(id: "P_RO", number: 1, title: "Fremd", fields: [], repositories: ["octo/app"], canWrite: false),
                       ProjectInfo(id: "P_RW", number: 2, title: "Eigen", fields: [], repositories: ["octo/app"], canWrite: true)],
            fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(!destination(.gitHubProject, "P_RO").acceptsIssues(in: readOnly))
        #expect(destination(.gitHubProject, "P_RW").acceptsIssues(in: readOnly))
        // A project the catalog does not know, a missing catalog, and the other kinds are not turned away.
        #expect(destination(.gitHubProject, "P_UNKNOWN").acceptsIssues(in: readOnly))
        #expect(destination(.gitHubProject, "P_RO").acceptsIssues(in: nil))
        #expect(destination(.gitHubRepository, "octo/app").acceptsIssues(in: readOnly))
        #expect(destination(.remindersList, "P_RO").acceptsIssues(in: readOnly))
        #expect(destination(.local, ProjectProgressReference.localID).acceptsIssues(in: readOnly))
    }

    @Test func theIdentityIsTheKeyOfTheProject() {
        #expect(destination(.gitHubRepository, "octo/app").id == "gitHubRepository:octo/app")
        #expect(destination(.gitHubProject, "octo/app").id != destination(.gitHubRepository, "octo/app").id)
    }
}
