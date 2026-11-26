import Foundation
import Testing
import GitHubKit
import TagwerkCore
@testable import Tagwerk

struct GitHubTargetSearchTests {
    private func project(_ id: String, _ number: Int, _ title: String, repositories: [String] = []) -> ProjectInfo {
        ProjectInfo(id: id, number: number, title: title, fields: [], repositories: repositories)
    }

    private func catalog(repositories: [String] = [], projects: [ProjectInfo] = []) -> GitHubCatalog {
        GitHubCatalog(repositories: repositories, projects: projects, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func repositoriesComeFirstInCatalogOrderThenProjects() {
        let items = GitHubTargetSearch.items(from: catalog(repositories: ["octo/b", "octo/a"], projects: [project("P1", 1, "Planung")]))
        #expect(items.map(\.targetID) == ["octo/b", "octo/a", "P1"])
        #expect(items.map(\.kind) == [.repository, .repository, .project])
    }

    @Test func aRepositorySplitsIntoOwnerAndName() throws {
        let item = try #require(GitHubTargetSearch.items(from: catalog(repositories: ["uni-muenchen/notizen"])).first)
        #expect(item.title == "notizen")
        #expect(item.ownerText == "uni-muenchen")
        #expect(item.targetID == "uni-muenchen/notizen")
        #expect(item.projectNumber == nil)
    }

    @Test func aProjectNamesTheDistinctOwnersOfItsRepositoriesInOrder() throws {
        let linked = project("P1", 7, "Studium", repositories: ["uni/skripte", "melvin/notizen", "uni/uebungen"])
        let item = try #require(GitHubTargetSearch.items(from: catalog(projects: [linked])).first)
        #expect(item.title == "Studium")
        #expect(item.ownerText == "uni, melvin")
        #expect(item.projectNumber == 7)
        #expect(item.targetID == "P1")
    }

    @Test func aProjectWithoutRepositoriesHasNoOwner() throws {
        let item = try #require(GitHubTargetSearch.items(from: catalog(projects: [project("P2", 2, "Haushalt")])).first)
        #expect(item.ownerText.isEmpty)
        #expect(SearchTexts.githubTargetSubtitle(item) == "GitHub-Projekt · #2")
    }

    @Test func theSubtitleNamesKindAndOwner() throws {
        let repository = try #require(GitHubTargetSearch.items(from: catalog(repositories: ["octo/app"])).first)
        #expect(SearchTexts.githubTargetSubtitle(repository) == "Repository · octo")
        #expect(SearchTexts.githubTargetAccessibility(repository) == "Repository, app, octo")
    }

    @Test func anEmptyCatalogGivesNoCandidates() {
        #expect(GitHubTargetSearch.items(from: catalog()).isEmpty)
    }

    @Test func aSearchFindsARepositoryByItsOwnerAndAProjectByItsTitle() throws {
        let items = GitHubTargetSearch.items(from: catalog(repositories: ["octo/app", "other/web"], projects: [project("P1", 1, "Tagwerk", repositories: ["octo/app"])]))
        var input = SearchInput()
        input.githubTargets = items
        let results = SearchResults.make(query: SearchQuery("octo")!, filter: .all, includeCompleted: false, input: input,
                                         now: Date(), calendar: .tagwerk)
        let ids = results.sections.first?.rows.compactMap { row -> String? in
            if case .githubTarget(let item) = row { item.targetID } else { nil }
        }
        #expect(ids == ["octo/app", "P1"])
    }
}
