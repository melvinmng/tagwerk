import Foundation
import GitHubKit
import TagwerkCore

/// Texts and preselection of the GitHub project row in "Neue Aufgabe" (multi-select list in a searchable sheet, `ProjectChoiceRow`).
enum ProjectSelection {
    /// Collapsed value: "Kein Projekt", one or two names, from three on the count.
    static func value(titles: [String]) -> String {
        switch titles.count {
        case 0: String(localized: "Kein Projekt")
        case 1, 2: titles.joined(separator: ", ")
        default: String(localized: "\(titles.count) Projekte")
        }
    }

    /// Untouched, the projects linked to the repository replace the selection (also when none are linked);
    /// after a manual choice they are added.
    static func preselect(current: Set<String>, linked: Set<String>, edited: Bool) -> Set<String> {
        edited ? current.union(linked) : linked
    }

    /// The sections of the project picker: projects linked to the chosen repository first, then the others; both filtered by
    /// `query` (the title). `total` is the number of all projects, `othersTotal` that of the unlinked ones, whatever the query.
    struct Sections: Equatable {
        var linked: [ProjectInfo]
        var others: [ProjectInfo]
        var total: Int
        var othersTotal: Int
    }

    static func sections(projects: [ProjectInfo], linkedIDs: Set<String>, query: String) -> Sections {
        let shown = ChoiceFilter.matching(projects, query: query) { [$0.title] }
        return Sections(linked: shown.filter { linkedIDs.contains($0.id) },
                        others: shown.filter { !linkedIDs.contains($0.id) },
                        total: projects.count,
                        othersTotal: projects.filter { !linkedIDs.contains($0.id) }.count)
    }

    /// `selection` with `id` added, or removed when it is in.
    static func toggled(_ id: String, in selection: Set<String>) -> Set<String> {
        var result = selection
        if !result.insert(id).inserted { result.remove(id) }
        return result
    }

    /// Start stages offered for new issues: the stages that every selected project has, in the order of
    /// the first project, without "Done" (a new issue must not start as finished). Empty without a project.
    static func commonStatusOptions(_ optionLists: [[String]]) -> [String] {
        guard let first = optionLists.first else { return [] }
        return first.filter { option in
            !GitHubMapping.isDone(option)
                && optionLists.dropFirst().allSatisfy { list in list.contains { $0.caseInsensitiveCompare(option) == .orderedSame } }
        }
    }

    /// True when several projects are selected, each has stages, and they share none: the row "Status" is not offered
    /// and each issue starts in the start stage of its project (`GitHubMapping.reopenOption`: "Ready", else the first
    /// stage that is not "Done").
    static func lacksCommonStatus(_ optionLists: [[String]]) -> Bool {
        optionLists.count > 1 && optionLists.allSatisfy { !$0.isEmpty } && commonStatusOptions(optionLists).isEmpty
    }

    /// Footer of the GitHub section in "Neue Aufgabe": what the project choice means, then who gets the issue.
    static func footer(repositoryChosen: Bool, hasProject: Bool, optionLists: [[String]], assignment: String) -> String {
        var sentences: [String] = []
        if lacksCommonStatus(optionLists) {
            sentences.append(String(localized: "Die Projekte haben keine gemeinsame Stufe; jedes Issue startet in „Ready“, sonst in der ersten Stufe seines Projekts, die nicht „Done“ ist."))
        }
        if repositoryChosen, !hasProject {
            sentences.append(String(localized: "Ohne Projekt erscheint das Issue nicht in deinen Aufgaben, nur auf GitHub."))
        }
        sentences.append(assignment)
        return sentences.joined(separator: " ")
    }

    /// Preselected start stage: "Ready" when offered, otherwise the first option in board order.
    static func defaultStartStatus(in options: [String]) -> String? {
        options.first { $0.caseInsensitiveCompare(GitHubMapping.reopenStatus) == .orderedSame } ?? options.first
    }

    /// The selection after a change of the options: kept while still offered, else the default.
    static func startStatus(current: String?, options: [String]) -> String? {
        if let current, options.contains(current) { return current }
        return defaultStartStatus(in: options)
    }
}
