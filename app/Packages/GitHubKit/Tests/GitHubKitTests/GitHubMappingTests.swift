import Foundation
import Testing
import TagwerkCore
@testable import GitHubKit

func makeProject(_ number: Int, fields: [String] = ["Status", "Priority", "Due date", "Estimate (h)"]) -> ProjectInfo {
    ProjectInfo(
        id: "PVT_\(number)", number: number, title: "Projekt \(number)",
        fields: fields.map { name in
            ProjectField(id: "F_\(number)_\(name)", name: name,
                         options: name == "Status" ? ["Ready": "OPT_ready", "Done": "OPT_done", "In progress": "OPT_prog"]
                             : name == "Priority" ? ["P1 (Very High)": "OPT_p1", "P2 (High)": "OPT_p2", "P3 (Medium)": "OPT_p3"]
                             : [:])
        }
    )
}

func makePlacement(_ project: ProjectInfo, status: String? = "Ready", priority: Priority? = nil, due: DueDate? = nil,
                   estimate: Int? = nil, updatedAt: TimeInterval = 100) -> ProjectPlacement {
    ProjectPlacement(project: project, itemID: "PVTI_\(project.number)", itemUpdatedAt: Date(timeIntervalSince1970: updatedAt),
                     status: status, priority: priority, due: due, estimateMinutes: estimate)
}

func makeRecord(isOpen: Bool = true, assignees: [String] = ["octo"], placements: [ProjectPlacement]) -> GitHubIssueRecord {
    GitHubIssueRecord(
        issueID: "I_42", number: 42, repository: "beispiel/app", title: "Login-Fehler beheben", body: "Text",
        isOpen: isOpen, url: URL(string: "https://github.com/beispiel/app/issues/42")!,
        updatedAt: Date(timeIntervalSince1970: 50), labels: ["bug"], assignees: assignees, placements: placements
    )
}

struct GitHubMappingTests {
    @Test func estimate_hours_and_mandays() {
        #expect(GitHubMapping.estimateMinutes(fieldName: "Estimate (h)", value: 1.5) == 90)
        #expect(GitHubMapping.estimateMinutes(fieldName: "Estimate (MDs)", value: 1.5) == 720)
        #expect(GitHubMapping.estimateMinutes(fieldName: "Story points", value: 3) == nil)
        #expect(GitHubMapping.fieldValue(fromMinutes: 720, fieldName: "Estimate (MDs)") == 1.5)
        #expect(GitHubMapping.fieldValue(fromMinutes: 90, fieldName: "Estimate (h)") == 1.5)
    }

    @Test func priority_parsesOptionNames() {
        #expect(GitHubMapping.priority(fromOption: "P2 (High)") == .p2)
        #expect(GitHubMapping.priority(fromOption: "P5") == .p5)
        #expect(GitHubMapping.priority(fromOption: "Urgent") == nil)
    }

    @Test func visible_excludesClosedUnassignedAndDone() {
        let project = makeProject(1)
        #expect(GitHubMapping.isVisible(makeRecord(placements: [makePlacement(project)]), login: "octo"))
        #expect(!GitHubMapping.isVisible(makeRecord(isOpen: false, placements: [makePlacement(project)]), login: "octo"))
        #expect(!GitHubMapping.isVisible(makeRecord(assignees: ["someone"], placements: [makePlacement(project)]), login: "octo"))
        #expect(!GitHubMapping.isVisible(makeRecord(placements: [makePlacement(project, status: "Done")]), login: "octo"))
        #expect(!GitHubMapping.isVisible(makeRecord(placements: []), login: "octo"))
    }

    @Test func visible_doneInOneProjectOnly_staysVisible() {
        let record = makeRecord(placements: [makePlacement(makeProject(1), status: "Done"), makePlacement(makeProject(2))])
        #expect(GitHubMapping.isVisible(record, login: "octo"))
    }

    @Test func taskItem_twoProjects_earliestDueHighestPriority() {
        let record = makeRecord(placements: [
            makePlacement(makeProject(1), priority: .p3, due: DueDate(year: 2026, month: 11, day: 20)),
            makePlacement(makeProject(2), priority: .p2, due: DueDate(year: 2026, month: 11, day: 25)),
        ])
        let item = GitHubMapping.taskItem(record)
        #expect(item.priority == .p2)
        #expect(item.due == DueDate(year: 2026, month: 11, day: 20))
        #expect(item.subContainers.map(\.name) == ["Projekt 1", "Projekt 2"])
        #expect(item.container == TaskContainer(id: "beispiel/app", name: "beispiel/app", colorHex: nil))
        #expect(item.id == TaskID(source: .github, rawValue: "I_42"))
        #expect(item.labels == ["bug"])
        #expect(item.notes == "Text")
        #expect(item.title == "Login-Fehler beheben")
        #expect(item.url?.absoluteString == "https://github.com/beispiel/app/issues/42")
    }

    @Test func taskItem_estimate_firstByProjectNumber() {
        let record = makeRecord(placements: [
            makePlacement(makeProject(5), estimate: 120),
            makePlacement(makeProject(3), estimate: nil),
            makePlacement(makeProject(4), estimate: 60),
        ])
        #expect(GitHubMapping.taskItem(record).estimateMinutes == 60)
    }

    @Test func taskItem_projectWithoutPriority_hidesPriorityField() {
        let record = makeRecord(placements: [makePlacement(makeProject(1, fields: ["Status", "Due date"]))])
        let item = GitHubMapping.taskItem(record)
        #expect(item.editableFields == [.title, .notes, .labels, .assignees, .due, .status])
        #expect(item.priority == nil)
    }

    @Test func taskItem_mandaysProject_showsEstimateField() {
        let record = makeRecord(placements: [makePlacement(makeProject(8, fields: ["Status", "Estimate (MDs)"]))])
        #expect(GitHubMapping.taskItem(record).editableFields.contains(.estimate))
    }

    @Test func taskItem_carriesAssigneesAndMakesThemEditable() {
        let item = GitHubMapping.taskItem(makeRecord(assignees: ["octo", "lea-m"], placements: [makePlacement(makeProject(1))]))
        #expect(item.assignees == ["octo", "lea-m"])
        #expect(item.editableFields.contains(.assignees))
    }

    @Test func version_changesWhenAnyItemChanges() {
        let first = makeRecord(placements: [makePlacement(makeProject(1)), makePlacement(makeProject(2))])
        let second = makeRecord(placements: [makePlacement(makeProject(1)), makePlacement(makeProject(2), updatedAt: 200)])
        let reordered = makeRecord(placements: [makePlacement(makeProject(2)), makePlacement(makeProject(1))])
        #expect(GitHubMapping.taskItem(first).version != GitHubMapping.taskItem(second).version)
        #expect(GitHubMapping.taskItem(first).version == GitHubMapping.taskItem(reordered).version)
    }

    @Test func defaultSelection_excludesProjectsWithoutAssignedOpenIssues() {
        let used = makeProject(1), template = makeProject(9)
        let visible = [makeRecord(placements: [makePlacement(used)])]
        #expect(GitHubMapping.defaultSelectedProjectIDs(projects: [used, template], visibleIssues: visible) == ["PVT_1"])
    }
}
