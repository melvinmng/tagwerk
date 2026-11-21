import GitHubKit
import Observation
import SwiftUI
import TagwerkCore

/// State of the sheet "Ziel wählen": repository, projects and people of one issue suggested from a note (decisions D7, D8).
/// The people default to the user (`result.assignees == nil`); the model never sees a login of its own.
@MainActor
@Observable
final class IssueTargetSheetModel {
    let catalog: GitHubCatalog
    let me: String?

    /// Changing the repository resets projects (to those linked to it) and people (to the user): an issue never goes to
    /// the people of another repository.
    var repository: String? {
        didSet {
            guard repository != oldValue else { return }
            projectsEdited = false
            projectIDs = repository.map { Set(catalog.projectIDs(linkedTo: $0)) } ?? []
            assignees = Set([me].compactMap { $0 })
            assigneesChosen = false
            assigneeLoad = .idle
        }
    }
    var projectIDs: Set<String>
    /// The user changed the projects by hand.
    var projectsEdited = false
    private(set) var assignees: Set<String>
    /// Until the user chose, the default "Ich" travels as `nil`.
    private(set) var assigneesChosen = false
    private(set) var assigneeLoad: AssigneeLoad = .idle

    @ObservationIgnored private let loadAssignable: (String) async -> [String]?

    /// `projectIDs` of a card that brings none are replaced by the projects linked to its repository, like in "Neue Aufgabe".
    init(catalog: GitHubCatalog, me: String?, repository: String?, projectIDs: [String],
         loadAssignable: @escaping (String) async -> [String]?) {
        self.catalog = catalog
        self.me = me
        self.repository = repository
        self.loadAssignable = loadAssignable
        self.assignees = Set([me].compactMap { $0 })
        if projectIDs.isEmpty, let repository {
            self.projectIDs = Set(catalog.projectIDs(linkedTo: repository))
        } else {
            self.projectIDs = Set(projectIDs)
        }
    }

    /// A repository is chosen; projects and people are optional.
    var canApply: Bool { repository != nil }

    /// People offered for the chosen repository: the user first, also while loading or after a failed load.
    var assigneeCandidates: [String] { AssigneeSelection.ordered(candidates: assigneeLoad.logins(for: repository), me: me) }

    var canAddAssignee: Bool { AssigneeSelection.canAdd(selectedCount: assignees.count) }

    /// The chosen people in menu order.
    var selectedAssignees: [String] { assigneeCandidates.filter(assignees.contains) }

    /// Takes the choice of the people row; more than `AssigneeRules.maximum` people are refused.
    func choose(_ people: Set<String>) {
        guard people.count <= AssigneeRules.maximum else { return }
        assignees = people
        assigneesChosen = true
    }

    /// Loads the assignable people of the chosen repository. An answer for a repository the user left meanwhile is dropped.
    func loadAssignees() async {
        guard let repository else {
            assigneeLoad = .idle
            return
        }
        assigneeLoad = .loading(repository: repository)
        let logins = await loadAssignable(repository)
        assigneeLoad = assigneeLoad.adopting(logins, for: repository, selected: self.repository)
    }

    /// What the sheet hands back: projects in catalog order; `assignees == nil` stands for the user. `nil` without a repository.
    var result: (repository: String, projectIDs: [String], assignees: [String]?)? {
        guard let repository else { return nil }
        let projects = catalog.projects.map(\.id).filter(projectIDs.contains)
        return (repository, projects, assigneesChosen ? selectedAssignees : nil)
    }
}

/// The row on the card of a suggested issue: where the issue goes.
enum IssueTargetText {
    /// "melvinmng/tagwerk · Projekt Tagwerk", "melvinmng/tagwerk · Kein Projekt".
    static func value(of target: AppTools.GitHubTarget, in catalog: GitHubCatalog) -> String {
        let titles = target.projectIDs.compactMap { id in catalog.projects.first { $0.id == id }?.title }
        let projects: String
        switch titles.count {
        case 0: projects = String(localized: "Kein Projekt")
        case 1, 2: projects = String(localized: "Projekt \(titles.joined(separator: ", "))")
        default: projects = String(localized: "\(titles.count) Projekte")
        }
        return target.repository + " · " + projects
    }

    /// "Ziel: melvinmng/tagwerk · Projekt Tagwerk", or "Ziel wählen" while there is no target.
    static func summary(of target: AppTools.GitHubTarget?, in catalog: GitHubCatalog) -> String {
        guard let target else { return String(localized: "Ziel wählen") }
        return String(localized: "Ziel: \(value(of: target, in: catalog))")
    }
}

/// Repository, projects and people of one suggested issue (mockup GI2). The three rows are those of "Neue Aufgabe".
struct IssueTargetSheet: View {
    @State private var model: IssueTargetSheetModel
    let onApply: (_ repository: String, _ projectIDs: [String], _ assignees: [String]?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var assigneesLoaded = false

    init(model: IssueTargetSheetModel, onApply: @escaping (_ repository: String, _ projectIDs: [String], _ assignees: [String]?) -> Void) {
        _model = State(initialValue: model)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Repository", selection: $model.repository) {
                        Text("Wählen …").tag(String?.none)
                        ForEach(model.catalog.repositories, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    ProjectSelectionRow(projects: model.catalog.projects.map { (id: $0.id, title: $0.title) },
                                        selection: $model.projectIDs, edited: $model.projectsEdited)
                    AssigneeSelectionRow(candidates: model.assigneeCandidates, me: model.me, load: model.assigneeLoad,
                                         selection: Binding(get: { model.assignees }, set: { model.choose($0) }),
                                         isEnabled: model.repository != nil, showsDefaultMe: !model.assigneesChosen)
                } footer: {
                    Text("Ohne Projekt erscheint das Issue nicht in deinen Aufgaben.")
                }
            }
            .navigationTitle("Ziel wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        if let result = model.result { onApply(result.repository, result.projectIDs, result.assignees) }
                        dismiss()
                    }
                    .disabled(!model.canApply)
                }
            }
            .task(id: model.repository) { await model.loadAssignees() }
        }
    }
}

/// Identifies the card whose target the sheet edits.
struct TargetRequest: Identifiable, Equatable {
    let id: String
}
