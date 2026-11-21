import GitHubKit
import SwiftUI

/// Texts and preselection of the GitHub project row in "Neue Aufgabe" (multi-select menu like the repository row).
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

/// The project row: a menu with toggles that stays open while choosing (Mehrfachauswahl).
struct ProjectSelectionRow: View {
    let projects: [(id: String, title: String)]
    @Binding var selection: Set<String>
    @Binding var edited: Bool

    private var selectedTitles: [String] { projects.filter { selection.contains($0.id) }.map(\.title) }

    var body: some View {
        Menu {
            Toggle("Kein Projekt", isOn: Binding(
                get: { selection.isEmpty },
                set: { isOn in
                    guard isOn else { return }
                    edited = true
                    selection = []
                }))
            Section("Mehrere möglich") {
                ForEach(projects, id: \.id) { project in
                    Toggle(project.title, isOn: Binding(
                        get: { selection.contains(project.id) },
                        set: { isOn in
                            edited = true
                            if isOn { selection.insert(project.id) } else { selection.remove(project.id) }
                        }))
                }
            }
        } label: {
            LabeledContent {
                HStack(spacing: 4) {
                    if projects.isEmpty {
                        Text("Keine Projekte")
                    } else if selectedTitles.count == 2 {
                        ViewThatFits(in: .horizontal) {
                            Text(ProjectSelection.value(titles: selectedTitles))
                            Text("\(2) Projekte")
                        }
                    } else {
                        Text(ProjectSelection.value(titles: selectedTitles))
                    }
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .lineLimit(1)
                .foregroundStyle(.secondary)
            } label: {
                Text("Projekte").foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .menuActionDismissBehavior(.disabled)
        .disabled(projects.isEmpty)
        .accessibilityLabel("Projekte")
        .accessibilityValue(selectedTitles.formatted(.list(type: .and)))
        .accessibilityHint("Mehrfachauswahl")
    }
}
