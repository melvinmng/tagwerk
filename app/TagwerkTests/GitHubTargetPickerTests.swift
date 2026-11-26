import GitHubKit
import Testing
@testable import Tagwerk

struct GitHubTargetPickerTests {
    private let repositories = ["melvinmng/tagwerk", "melvinmng/tagwerk-docs", "acme/platform", "acme/tools"]

    // MARK: Repository sections

    @Test func repositorySections_withoutQuery_listEverythingAndTheRecentOnesFirst() {
        let sections = RepositoryChoice.sections(repositories: repositories, recent: ["acme/tools", "gone/repo", "acme/platform"], query: "")
        #expect(sections.recent == ["acme/tools", "acme/platform"])
        #expect(sections.all == repositories)
        #expect(sections.total == 4)
    }

    @Test func repositorySections_filterBothSectionsByTheQuery() {
        let sections = RepositoryChoice.sections(repositories: repositories, recent: ["acme/tools", "melvinmng/tagwerk"], query: "tag")
        #expect(sections.recent == ["melvinmng/tagwerk"])
        #expect(sections.all == ["melvinmng/tagwerk", "melvinmng/tagwerk-docs"])
        #expect(sections.total == 4)
    }

    @Test func repositorySections_noHit_isEmptyButKeepsTheTotal() {
        let sections = RepositoryChoice.sections(repositories: repositories, recent: [], query: "foobar")
        #expect(sections.recent.isEmpty && sections.all.isEmpty)
        #expect(sections.total == 4)
    }

    @Test func repositorySections_capTheRecentList() {
        let many = (1...8).map { "octo/repo\($0)" }
        let sections = RepositoryChoice.sections(repositories: many, recent: many, query: "")
        #expect(sections.recent == ["octo/repo1", "octo/repo2", "octo/repo3"])
    }

    @Test func repositorySections_completeListIsNotTruncated() {
        let many = (1...250).map { "octo/repo\($0)" }
        #expect(RepositoryChoice.sections(repositories: many, recent: [], query: "").all.count == 250)
    }

    @Test func repositoryParts_splitOwnerAndName() {
        #expect(RepositoryChoice.parts(of: "melvinmng/tagwerk") == .init(owner: "melvinmng", name: "tagwerk"))
        #expect(RepositoryChoice.parts(of: "norepo") == .init(owner: nil, name: "norepo"))
    }

    // MARK: Project sections

    private func project(_ number: Int, _ title: String, repositories: [String] = []) -> ProjectInfo {
        ProjectInfo(id: "PVT_\(number)", number: number, title: title, fields: [], repositories: repositories)
    }

    @Test func projectSections_linkedFirstThenTheOthers() {
        let projects = [project(1, "Studium"), project(2, "Tagwerk", repositories: ["melvinmng/tagwerk"]), project(3, "Homelab")]
        let sections = ProjectSelection.sections(projects: projects, linkedIDs: ["PVT_2"], query: "")
        #expect(sections.linked.map(\.title) == ["Tagwerk"])
        #expect(sections.others.map(\.title) == ["Studium", "Homelab"])
        #expect(sections.total == 3 && sections.othersTotal == 2)
    }

    @Test func projectSections_filterByTitle() {
        let projects = [project(1, "Studium & Klausuren"), project(2, "Tagwerk"), project(3, "Privat & Haushalt")]
        let sections = ProjectSelection.sections(projects: projects, linkedIDs: ["PVT_2"], query: "klausur")
        #expect(sections.linked.isEmpty)
        #expect(sections.others.map(\.title) == ["Studium & Klausuren"])
        #expect(sections.total == 3 && sections.othersTotal == 2)
    }

    @Test func projectSections_completeListIsNotTruncated() {
        let projects = (1...130).map { project($0, "Project \($0)") }
        #expect(ProjectSelection.sections(projects: projects, linkedIDs: [], query: "").others.count == 130)
    }

    // MARK: Project choice draft

    @Test func toggled_addsAndRemovesAProject() {
        #expect(ProjectSelection.toggled("a", in: ["b"]) == ["a", "b"])
        #expect(ProjectSelection.toggled("a", in: ["a", "b"]) == ["b"])
    }

    @Test func counts_headerShowsFilteredOfTotalOnlyWhileFiltering() {
        #expect(RepositoryChoice.countText(shown: 28, total: 28) == "28")
        #expect(RepositoryChoice.countText(shown: 2, total: 28) == "2 von 28")
    }
}
