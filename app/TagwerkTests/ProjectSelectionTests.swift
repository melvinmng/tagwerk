import Testing
@testable import Tagwerk

struct ProjectSelectionTests {
    @Test func value_perCount() {
        #expect(ProjectSelection.value(titles: []) == "Kein Projekt")
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

    // MARK: Start status

    @Test func commonStatusOptions_areTheIntersection_inOrderOfTheFirstProject_withoutDone() {
        let first = ["Backlog", "Ready", "In progress", "Blocked", "Done"]
        let second = ["Todo", "In progress", "Backlog", "DONE"]
        #expect(ProjectSelection.commonStatusOptions([first]) == ["Backlog", "Ready", "In progress", "Blocked"])
        #expect(ProjectSelection.commonStatusOptions([first, second]) == ["Backlog", "In progress"])
        #expect(ProjectSelection.commonStatusOptions([second, first]) == ["In progress", "Backlog"])
        #expect(ProjectSelection.commonStatusOptions([first, ["Todo", "Done"]]).isEmpty)
        #expect(ProjectSelection.commonStatusOptions([]).isEmpty)
    }

    @Test func defaultStartStatus_prefersReady_elseFirstOption() {
        #expect(ProjectSelection.defaultStartStatus(in: ["Backlog", "Ready", "In progress"]) == "Ready")
        #expect(ProjectSelection.defaultStartStatus(in: ["Todo", "Doing"]) == "Todo")
        #expect(ProjectSelection.defaultStartStatus(in: []) == nil)
    }

    @Test func startStatus_isKeptWhileOffered_elseReset() {
        #expect(ProjectSelection.startStatus(current: "In progress", options: ["Backlog", "In progress"]) == "In progress")
        #expect(ProjectSelection.startStatus(current: "Blocked", options: ["Backlog", "Ready"]) == "Ready")
        #expect(ProjectSelection.startStatus(current: "Ready", options: []) == nil)
    }
}
