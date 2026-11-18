import SwiftUI

/// Texts and preselection of the GitHub project row in "Neue Aufgabe" (multi-select menu like the repository row).
enum ProjectSelection {
    /// Collapsed value: "Wählen …", one or two names, from three on the count.
    static func value(titles: [String]) -> String {
        switch titles.count {
        case 0: String(localized: "Wählen …")
        case 1, 2: titles.joined(separator: ", ")
        default: String(localized: "\(titles.count) Projekte")
        }
    }

    /// Untouched, the projects linked to the repository replace the selection (also when none are linked);
    /// after a manual choice they are added.
    static func preselect(current: Set<String>, linked: Set<String>, edited: Bool) -> Set<String> {
        edited ? current.union(linked) : linked
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
