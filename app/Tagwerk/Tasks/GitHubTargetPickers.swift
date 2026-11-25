import GitHubKit
import SwiftUI
import TagwerkCore

/// Pure rules of the repository picker: which repositories appear in which section.
enum RepositoryChoice {
    struct Sections: Equatable {
        /// "Zuletzt verwendet": the recently chosen repositories that still exist, filtered by the query.
        var recent: [String]
        /// "Alle Repositories": every repository, filtered by the query.
        var all: [String]
        /// Number of all repositories, whatever the query.
        var total: Int
    }

    struct Parts: Equatable {
        var owner: String?
        var name: String
    }

    static func sections(repositories: [String], recent: [String], query: String) -> Sections {
        let known = RecentChoices.visible(recent, available: repositories, limit: RecentChoices.storedLimit)
        let filteredRecent = ChoiceFilter.matching(known, query: query) { [$0] }
        return Sections(recent: Array(filteredRecent.prefix(RecentChoices.visibleLimit)),
                        all: ChoiceFilter.matching(repositories, query: query) { [$0] },
                        total: repositories.count)
    }

    /// "melvinmng/tagwerk" as owner and name; a name without "/" has no owner.
    static func parts(of repository: String) -> Parts {
        guard let slash = repository.firstIndex(of: "/") else { return Parts(owner: nil, name: repository) }
        return Parts(owner: String(repository[..<slash]), name: String(repository[repository.index(after: slash)...]))
    }

    /// "28" for the whole list, "2 von 28" while a query hides entries.
    static func countText(shown: Int, total: Int) -> String {
        shown == total ? String(shown) : String(localized: "\(shown) von \(total)")
    }
}

/// The repository row of a GitHub issue: opens a sheet with a search field instead of a menu that cannot be searched.
struct RepositoryChoiceRow: View {
    let repositories: [String]
    @Binding var selection: String?
    /// The catalog is still being loaded: the row says so instead of "Wählen …".
    var isLoading = false
    @Environment(AppEnvironment.self) private var environment
    @State private var isPickerShown = false

    var body: some View {
        Button {
            isPickerShown = true
        } label: {
            LabeledContent {
                HStack(spacing: 4) {
                    if isLoading, repositories.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                    Text(valueText).multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small).accessibilityHidden(true)
                }
                .foregroundStyle(.secondaryText)
            } label: {
                Text("Repository").foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(repositories.isEmpty)
        .accessibilityLabel("Repository")
        .accessibilityValue(selection ?? valueText)
        .accessibilityHint("Öffnet die Auswahl mit Suche")
        .sheet(isPresented: $isPickerShown) {
            RepositoryPickerSheet(repositories: repositories, selected: selection,
                                  recent: environment.settings.recentRepositories ?? []) { repository in
                selection = repository
                environment.settings.recentRepositories = RecentChoices.recorded(
                    repository, in: environment.settings.recentRepositories ?? [], limit: RecentChoices.storedLimit)
            }
        }
    }

    private var valueText: String {
        if let selection { return selection }
        if isLoading, repositories.isEmpty { return String(localized: "Repositories werden geladen …") }
        return String(localized: "Wählen …")
    }
}

/// The sheet "Repository wählen": the recently used repositories on top, then all of them, with a search field.
/// One tap chooses and closes the sheet.
struct RepositoryPickerSheet: View {
    let repositories: [String]
    let selected: String?
    let recent: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let sections = RepositoryChoice.sections(repositories: repositories, recent: recent, query: query)
        NavigationStack {
            List {
                if !sections.recent.isEmpty {
                    Section("Zuletzt verwendet") {
                        ForEach(sections.recent, id: \.self) { row($0) }
                    }
                }
                if !sections.all.isEmpty {
                    Section("Alle Repositories (\(RepositoryChoice.countText(shown: sections.all.count, total: sections.total)))") {
                        ForEach(sections.all, id: \.self) { row($0) }
                    }
                }
            }
            .overlay {
                if sections.all.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Repository suchen")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Repository wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ repository: String) -> some View {
        let parts = RepositoryChoice.parts(of: repository)
        return Button {
            onSelect(repository)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.name)
                    if let owner = parts.owner {
                        Text(owner).font(.caption).foregroundStyle(.secondaryText)
                    }
                }
                Spacer()
                if repository == selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel(repository)
        .accessibilityAddTraits(repository == selected ? .isSelected : [])
    }
}

/// The project row of a GitHub issue: opens a sheet for several projects with a search field.
struct ProjectChoiceRow: View {
    let projects: [ProjectInfo]
    /// Projects linked to the chosen repository, offered first.
    let linkedProjectIDs: Set<String>
    let linkedRepository: String?
    @Binding var selection: Set<String>
    /// Set when the user changes the choice, so a later change of the repository adds to it instead of replacing it.
    @Binding var edited: Bool
    @State private var isPickerShown = false

    private var selectedTitles: [String] { projects.filter { selection.contains($0.id) }.map(\.title) }

    var body: some View {
        Button {
            isPickerShown = true
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
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small).accessibilityHidden(true)
                }
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondaryText)
            } label: {
                Text("Projekte").foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(projects.isEmpty)
        .accessibilityLabel("Projekte")
        .accessibilityValue(selectedTitles.isEmpty ? ProjectSelection.value(titles: []) : selectedTitles.formatted(.list(type: .and)))
        .accessibilityHint("Öffnet die Mehrfachauswahl mit Suche")
        .sheet(isPresented: $isPickerShown) {
            ProjectPickerSheet(projects: projects, linkedProjectIDs: linkedProjectIDs, linkedRepository: linkedRepository,
                               initialSelection: selection) { chosen in
                guard chosen != selection else { return }
                edited = true
                selection = chosen
            }
        }
    }
}

/// The sheet "Projekte": several projects can be chosen, "Kein Projekt" clears the choice. The choice is applied with "Fertig";
/// "Abbrechen" leaves it as it was.
struct ProjectPickerSheet: View {
    let projects: [ProjectInfo]
    let linkedProjectIDs: Set<String>
    let linkedRepository: String?
    let onDone: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<String>
    @State private var query = ""

    init(projects: [ProjectInfo], linkedProjectIDs: Set<String>, linkedRepository: String?, initialSelection: Set<String>,
         onDone: @escaping (Set<String>) -> Void) {
        self.projects = projects
        self.linkedProjectIDs = linkedProjectIDs
        self.linkedRepository = linkedRepository
        self.onDone = onDone
        _draft = State(initialValue: initialSelection)
    }

    var body: some View {
        let sections = ProjectSelection.sections(projects: projects, linkedIDs: linkedProjectIDs, query: query)
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Button {
                            draft = []
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kein Projekt")
                                    Text("Das Issue erscheint nur auf GitHub.").font(.caption).foregroundStyle(.secondaryText)
                                }
                                Spacer()
                                if draft.isEmpty { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityAddTraits(draft.isEmpty ? .isSelected : [])
                    }
                }
                if !sections.linked.isEmpty {
                    Section(linkedRepository.map { String(localized: "Verknüpft mit \($0)") } ?? String(localized: "Mit dem Repository verknüpft")) {
                        ForEach(sections.linked) { row($0) }
                    }
                }
                if !sections.others.isEmpty {
                    let count = RepositoryChoice.countText(shown: sections.others.count, total: sections.othersTotal)
                    Section(sections.linked.isEmpty && sections.othersTotal == sections.total
                            ? String(localized: "Alle Projekte (\(count))") : String(localized: "Weitere Projekte (\(count))")) {
                        ForEach(sections.others) { row($0) }
                    }
                }
            }
            .overlay {
                if sections.linked.isEmpty, sections.others.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Projekt suchen")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(draft.isEmpty ? String(localized: "Projekte") : String(localized: "Projekte (\(draft.count))"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onDone(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ project: ProjectInfo) -> some View {
        let isSelected = draft.contains(project.id)
        let stages = GitHubMapping.statusOptions(in: project)
        return Button {
            draft = ProjectSelection.toggled(project.id, in: draft)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                    if !stages.isEmpty {
                        Text("Status: \(stages.joined(separator: ", "))").font(.caption).foregroundStyle(.secondaryText)
                    }
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
