import Testing
@testable import Tagwerk

struct ProjectSelectionTests {
    @Test func value_perCount() {
        #expect(ProjectSelection.value(titles: []) == "Wählen …")
        #expect(ProjectSelection.value(titles: ["Tagwerk"]) == "Tagwerk")
        #expect(ProjectSelection.value(titles: ["Tagwerk", "Bachelorarbeit"]) == "Tagwerk, Bachelorarbeit")
        #expect(ProjectSelection.value(titles: ["A", "B", "C"]) == "3 Projekte")
    }

    /// Untouched: the projects linked to the repository replace the selection, also when there are none.
    @Test func preselect_untouched_replaces() {
        #expect(ProjectSelection.preselect(current: ["a"], linked: ["b"], edited: false) == ["b"])
        #expect(ProjectSelection.preselect(current: ["a"], linked: [], edited: false) == [])
    }

    /// After a manual choice the linked projects are added, nothing is removed.
    @Test func preselect_edited_merges() {
        #expect(ProjectSelection.preselect(current: ["a"], linked: ["b"], edited: true) == ["a", "b"])
    }
}
