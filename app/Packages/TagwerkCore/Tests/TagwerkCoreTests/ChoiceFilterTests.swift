import Foundation
import Testing
@testable import TagwerkCore

struct ChoiceFilterTests {
    private func repositories(_ names: [String], query: String) -> [String] {
        ChoiceFilter.matching(names, query: query) { [$0] }
    }

    @Test func matching_emptyQueryKeepsOrder() {
        let names = ["b/two", "a/one", "c/three"]
        #expect(repositories(names, query: "") == names)
        #expect(repositories(names, query: "   ") == names)
    }

    @Test func matching_allWordsMustOccur() {
        let names = ["melvinmng/tagwerk", "melvinmng/tagwerk-docs", "acme/platform"]
        #expect(repositories(names, query: "melvin docs") == ["melvinmng/tagwerk-docs"])
        #expect(repositories(names, query: "melvin platform").isEmpty)
    }

    @Test func matching_ignoresCaseAndDiacritics() {
        let names = ["acme/Übungen", "acme/strasse", "acme/other"]
        #expect(repositories(names, query: "ÜBUNG") == ["acme/Übungen"])
        #expect(repositories(names, query: "uebung").isEmpty)
        #expect(repositories(names, query: "straße") == ["acme/strasse"])
    }

    @Test func matching_findsOwnerOrName() {
        let names = ["acme/platform", "octo/acme-tools", "octo/app"]
        #expect(repositories(names, query: "acme") == ["acme/platform", "octo/acme-tools"])
        #expect(repositories(names, query: "octo app") == ["octo/app"])
    }

    @Test func matching_wordStartHitsComeFirstAndOrderIsStableOtherwise() {
        let names = ["octo/mytag", "octo/tagwerk", "octo/stagger", "acme/tag-tools"]
        #expect(repositories(names, query: "tag") == ["octo/tagwerk", "acme/tag-tools", "octo/mytag", "octo/stagger"])
    }

    @Test func matching_usesEveryTextFieldOfAnItem() {
        struct Project { let title: String; let statuses: String }
        let projects = [Project(title: "Tagwerk", statuses: "Backlog Ready"), Project(title: "Studium", statuses: "Todo Doing")]
        let result = ChoiceFilter.matching(projects, query: "studium doing") { [$0.title, $0.statuses] }
        #expect(result.map(\.title) == ["Studium"])
    }
}

struct RecentChoicesTests {
    @Test func recorded_putsTheChoiceFirstWithoutDuplicates() {
        #expect(RecentChoices.recorded("c", in: ["a", "b", "c"], limit: 5) == ["c", "a", "b"])
    }

    @Test func recorded_keepsOnlyTheNewestUpToTheLimit() {
        #expect(RecentChoices.recorded("f", in: ["e", "d", "c", "b", "a"], limit: 5) == ["f", "e", "d", "c", "b"])
    }

    @Test func recorded_ignoresBlankNames() {
        #expect(RecentChoices.recorded("  ", in: ["a"], limit: 5) == ["a"])
    }

    @Test func visible_dropsUnknownRepositoriesAndCapsTheCount() {
        let recent = ["gone/repo", "a/one", "b/two", "c/three", "d/four"]
        #expect(RecentChoices.visible(recent, available: ["a/one", "b/two", "c/three", "d/four"], limit: 3)
                == ["a/one", "b/two", "c/three"])
    }

    @Test func visible_withoutRecentIsEmpty() {
        #expect(RecentChoices.visible([], available: ["a/one"], limit: 3).isEmpty)
    }
}
