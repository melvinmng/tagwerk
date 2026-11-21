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

    // MARK: Footer of "Neue Aufgabe" (GH5c, GH9)

    @Test func lacksCommonStatus_twoBoardsWithDifferentNames_isTrue() {
        #expect(ProjectSelection.lacksCommonStatus([["Todo", "Doing", "Done"], ["Backlog", "Ready", "Done"]]))
    }

    @Test func lacksCommonStatus_oneProject_isFalse() {
        #expect(!ProjectSelection.lacksCommonStatus([["Todo", "Doing", "Done"]]))
        #expect(!ProjectSelection.lacksCommonStatus([]))
    }

    @Test func lacksCommonStatus_projectWithoutStatusField_isFalse() {
        #expect(!ProjectSelection.lacksCommonStatus([["Todo", "Done"], []]))
    }

    @Test func lacksCommonStatus_sharedStageOnlyDone_isTrue() {
        #expect(ProjectSelection.lacksCommonStatus([["Todo", "Done"], ["Open", "done"]]))
    }

    @Test func lacksCommonStatus_sharedOpenStage_isFalse() {
        #expect(!ProjectSelection.lacksCommonStatus([["Todo", "Ready", "Done"], ["Backlog", "ready", "Done"]]))
    }

    @Test func footer_withoutProject_saysTheIssueIsOnlyOnGitHub() {
        let footer = ProjectSelection.footer(repositoryChosen: true, hasProject: false, optionLists: [], assignment: "Das Issue wird dir zugewiesen.")
        #expect(footer == "Ohne Projekt erscheint das Issue nicht in deinen Aufgaben, nur auf GitHub. Das Issue wird dir zugewiesen.")
    }

    @Test func footer_noCommonStage_saysSoFirst() {
        let footer = ProjectSelection.footer(repositoryChosen: true, hasProject: true, optionLists: [["Todo", "Done"], ["Open", "Done"]],
                                             assignment: "Das Issue wird dir zugewiesen.")
        #expect(footer == "Die Projekte haben keine gemeinsame Stufe; jedes Issue startet in der ersten Stufe seines Projekts. Das Issue wird dir zugewiesen.")
    }

    @Test func footer_withoutRepository_isTheAssignmentOnly() {
        #expect(ProjectSelection.footer(repositoryChosen: false, hasProject: false, optionLists: [], assignment: "Das Issue wird dir zugewiesen.")
            == "Das Issue wird dir zugewiesen.")
    }
}
