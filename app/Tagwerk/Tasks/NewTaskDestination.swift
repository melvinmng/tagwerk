import GitHubKit
import SwiftUI
import TagwerkCore

/// Where a new task is to be created when "Neue Aufgabe" opens from a project (#348): the "+" on the page of a project and the entry
/// "Issue anlegen" in the search. The sheet then starts with the source of the project and fills what the project determines;
/// every field stays editable.
struct NewTaskDestination: Identifiable, Hashable {
    let reference: ProjectProgressReference

    var id: String { reference.key }

    /// The source a task of this project is created in.
    var source: TaskSource {
        switch reference.kind {
        case .gitHubProject, .gitHubRepository: .github
        case .remindersList: .reminders
        case .local: .local
        }
    }

    /// What the "+" and the menu entry are called: GitHub projects and repositories hold issues, the other sources tasks.
    var actionName: String {
        source == .github ? String(localized: "Issue anlegen") : String(localized: "Aufgabe anlegen")
    }

    /// Whether a task can be created for the project right now: the source is registered and loaded, and a GitHub Project accepts
    /// items (a project of another owner can be read-only: a new issue could not be added to it, so no "+" is offered there). The UI
    /// test mode with `-TagwerkUITestGitHubCatalog` stands in for a connected GitHub account.
    @MainActor
    func isAvailable(in model: TaskListModel) -> Bool {
        let invented = UITestMode.githubCatalog
        if source == .github {
            guard invented != nil || NewTaskSheet.availableTargets(in: model).contains(.github) else { return false }
            let catalog = invented ?? (model.provider(for: .github) as? GitHubTaskProvider)?.storedCatalog
            return acceptsIssues(in: catalog)
        }
        return NewTaskSheet.availableTargets(in: model).contains(source)
    }

    /// A GitHub Project that the catalog knows as read-only takes no new issue; everything else does (a project the catalog does not
    /// know yet is not turned away).
    func acceptsIssues(in catalog: GitHubCatalog?) -> Bool {
        guard reference.kind == .gitHubProject, let project = catalog?.projects.first(where: { $0.id == reference.id }) else { return true }
        return project.canWrite
    }

    /// What the project fills in for a GitHub issue.
    struct IssueFields: Equatable {
        /// "owner/name"; `nil` when the choice is left to the user.
        var repository: String?
        var projectIDs: Set<String>
        /// The projects were chosen on purpose: choosing a repository later adds the projects linked to it instead of replacing them.
        var protectsProjects: Bool
    }

    /// The fields of a GitHub issue for `catalog`; `nil` for a source without issues.
    /// - A repository fills itself. The projects linked to it follow as with any chosen repository.
    /// - A GitHub Project fills itself. Its repository is filled in only when exactly one repository is linked to it: with none or
    ///   several the choice is the user's, and the project stays chosen.
    func issueFields(in catalog: GitHubCatalog) -> IssueFields? {
        switch reference.kind {
        case .gitHubRepository:
            guard catalog.repositories.contains(reference.id) else { return IssueFields(repository: nil, projectIDs: [], protectsProjects: false) }
            return IssueFields(repository: reference.id, projectIDs: Set(catalog.projectIDs(linkedTo: reference.id)), protectsProjects: false)
        case .gitHubProject:
            guard let project = catalog.projects.first(where: { $0.id == reference.id }) else {
                return IssueFields(repository: nil, projectIDs: [], protectsProjects: false)
            }
            let linked = project.repositories.filter(catalog.repositories.contains)
            return IssueFields(repository: linked.count == 1 ? linked[0] : nil, projectIDs: [project.id], protectsProjects: true)
        case .remindersList, .local:
            return nil
        }
    }

    /// The identifier of the reminder list to preselect, when the project is a list that the sheet offers.
    func reminderListID(among lists: [TaskContainer]) -> String? {
        guard reference.kind == .remindersList, lists.contains(where: { $0.id == reference.id }) else { return nil }
        return reference.id
    }
}
