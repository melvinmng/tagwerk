import Foundation
import GitHubKit
import TagwerkCore

/// GitHub side of the assistant functions: where a new issue goes and who gets it (issue #136).
extension AppTools {
    /// Repository and projects a `create_task` call resolves to; shared by execution and confirmation card.
    struct GitHubTarget: Equatable {
        let repository: String
        let projectIDs: [String]
    }

    enum GitHubTargetError: Error, Equatable {
        case repositoryMissing, repositoryUnknown, projectMissing, projectUnknown

        var message: String {
            switch self {
            case .repositoryMissing: String(localized: "Bitte ein Repository nennen.")
            case .repositoryUnknown: String(localized: "Dieses Repository steht nicht in der Liste von list_github_targets.")
            case .projectMissing: String(localized: "Bitte ein Project nennen.")
            case .projectUnknown: String(localized: "Dieses Project steht nicht in der Liste von list_github_targets.")
            }
        }
    }

    /// Resolves the target of a new issue. Without a repository the only one of the catalog is taken;
    /// without projects (`nil`) those linked to the repository (the preselection of the sheet), else the
    /// only project. An empty list means explicitly "no Project" (issue #153). The defaults are a safety
    /// net: the model is told to pass both explicitly.
    static func gitHubTarget(repository: String?, projectIDs: [String]?, catalog: GitHubCatalog) -> Result<GitHubTarget, GitHubTargetError> {
        let resolved: String
        if let repository {
            guard let known = catalog.repositories.first(where: { $0.lowercased() == repository.lowercased() }) else {
                return .failure(.repositoryUnknown)
            }
            resolved = known
        } else {
            guard catalog.repositories.count == 1 else { return .failure(.repositoryMissing) }
            resolved = catalog.repositories[0]
        }

        if let projectIDs, projectIDs.isEmpty {
            return .success(GitHubTarget(repository: resolved, projectIDs: []))
        }
        if let projectIDs {
            let known = Set(catalog.projects.map(\.id))
            guard projectIDs.allSatisfy(known.contains) else { return .failure(.projectUnknown) }
            return .success(GitHubTarget(repository: resolved, projectIDs: projectIDs))
        }
        let linked = catalog.projectIDs(linkedTo: resolved)
        if !linked.isEmpty { return .success(GitHubTarget(repository: resolved, projectIDs: linked)) }
        guard catalog.projects.count == 1 else { return .failure(.projectMissing) }
        return .success(GitHubTarget(repository: resolved, projectIDs: [catalog.projects[0].id]))
    }

    private func loadedCatalog() async throws -> (any GitHubDirectory, GitHubCatalog) {
        guard let directory = gitHub() else { throw ToolError(String(localized: "Diese Quelle ist nicht verfügbar.")) }
        guard let catalog = await directory.catalog(maxAge: AppEnvironment.catalogMaxAge) else {
            throw ToolError(String(localized: "Repositories konnten nicht geladen werden."))
        }
        return (directory, catalog)
    }

    /// Repositories (most recently pushed first, capped) with their linked projects, and all projects.
    func listGitHubTargets() async throws -> String {
        let (_, catalog) = try await loadedCatalog()
        let repositories = catalog.repositories.prefix(Self.maxListedRepositories).map { repository -> [String: Any] in
            ["name": repository, "linked_project_ids": catalog.projectIDs(linkedTo: repository)]
        }
        let projects = catalog.projects.map { ["id": $0.id, "title": $0.title] }
        return Self.json(["repositories": Array(repositories), "projects": projects])
    }

    /// The assignable people of one repository of the catalog: the user as `me`, everyone else alphabetically.
    func listAssignees(repository: String) async throws -> String {
        let (directory, catalog) = try await loadedCatalog()
        guard let known = catalog.repositories.first(where: { $0.lowercased() == repository.lowercased() }) else {
            throw ToolError(GitHubTargetError.repositoryUnknown.message)
        }
        guard let logins = await directory.assignableUsers(in: known, maxAge: AppEnvironment.catalogMaxAge) else {
            throw ToolError(String(localized: "Personen konnten nicht geladen werden"))
        }
        let others = AssigneeSelection.sorted(logins.filter { !AssigneeSelection.isMe($0, me: directory.login) }, me: nil)
        var response: [String: Any] = ["repository": known, "assignees": others]
        if let me = directory.login { response["me"] = me }
        return Self.json(response)
    }

    /// Creates an issue after the confirmation. People other than the user must be assignable in the
    /// repository; an unknown login or a list that cannot be loaded creates nothing (no blind assigning).
    func createIssue(_ draft: TaskDraft, repository: String?, projectIDs: [String]?, assignees: [String]?) async throws -> String {
        let (directory, catalog) = try await loadedCatalog()
        let target: GitHubTarget
        switch Self.gitHubTarget(repository: repository, projectIDs: projectIDs, catalog: catalog) {
        case .success(let resolved): target = resolved
        case .failure(let error): throw ToolError(error.message)
        }

        var chosen: [String]?
        if let assignees {
            guard assignees.count <= AssigneeRules.maximum else {
                throw ToolError(String(localized: "Höchstens 10 Personen je Issue."))
            }
            let me = directory.login
            let others = assignees.filter { !AssigneeSelection.isMe($0, me: me) }
            var assignable: [String] = []
            if !others.isEmpty {
                guard let loaded = await directory.assignableUsers(in: target.repository, maxAge: AppEnvironment.catalogMaxAge) else {
                    throw ToolError(String(localized: "Personen konnten nicht geladen werden"))
                }
                assignable = loaded
                let unknown = others.filter { AssigneeRules.canonical($0, in: loaded) == nil }
                guard unknown.isEmpty else {
                    throw ToolError(String(localized: "\(unknown.formatted(.list(type: .and))) ist in \(target.repository) nicht zuweisbar."))
                }
            }
            // Written is GitHub's spelling of every login, each person once.
            var spelled: [String] = []
            for login in assignees {
                let canonical = AssigneeSelection.isMe(login, me: me) ? (me ?? login) : (AssigneeRules.canonical(login, in: assignable) ?? login)
                if !AssigneeRules.contains(spelled, canonical) { spelled.append(canonical) }
            }
            chosen = spelled
        }

        var issue = draft
        issue.containerID = target.repository
        issue.subContainerIDs = target.projectIDs
        issue.assignees = chosen
        let created = try await taskList.createReturning(issue, in: .github)

        let listed = taskList.provider(for: .github)?.isListed(created) ?? true
        var response: [String: Any] = ["ok": true, "assignees": created.assignees ?? [], "listed": listed]
        if let number = created.issueNumber { response["number"] = number }
        if let url = created.url { response["url"] = url.absoluteString }
        // GitHub drops people silently; the model must be able to tell the user.
        let missing = AssigneeRules.missing(requested: chosen, actual: created.assignees)
        if !missing.isEmpty { response["not_assigned"] = missing }
        if listed {
            response["id"] = created.id.key
            response["task"] = Self.summary(created)
        }
        return Self.json(response)
    }
}
