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

    // MARK: Assignments

    /// What an `assign_task` call resolves to; shared by execution and confirmation card.
    struct AssignmentPlan: Equatable {
        /// GitHub's spelling, each person once; people who are assigned already are not part of `add`.
        let change: AssigneeChange
        let before: [String]
        let after: [String]
        /// The user was assigned before and is not afterwards.
        let handsOver: Bool
    }

    enum AssignmentError: Error, Equatable {
        case notAnIssue, nothingToChange, tooMany, notAssigned([String]), conflicting([String])

        var message: String {
            switch self {
            case .notAnIssue: String(localized: "Zuweisen geht nur bei GitHub-Issues.")
            case .nothingToChange: String(localized: "Es gibt nichts zu ändern.")
            case .tooMany: String(localized: "Höchstens 10 Personen je Issue.")
            case .notAssigned(let names): String(localized: "\(names.formatted(.list(type: .and))) ist dem Issue nicht zugewiesen.")
            case .conflicting(let names): String(localized: "\(names.formatted(.list(type: .and))) steht in add und in remove.")
            }
        }
    }

    /// Turns the requested people into a difference against the current state. `add` holds logins in GitHub's
    /// spelling already (the user's own login is spelled as `me`); `remove` is matched against `current`.
    /// People who are assigned already drop out of `add`.
    static func assignmentPlan(current: [String], add: [String], remove: [String], me: String?) -> Result<AssignmentPlan, AssignmentError> {
        func unique(_ logins: [String]) -> [String] {
            var seen: [String] = []
            for login in logins where !AssigneeRules.contains(seen, login) { seen.append(login) }
            return seen
        }
        let requestedAdd = unique(add.map { AssigneeSelection.isMe($0, me: me) ? (me ?? $0) : $0 })
        let requestedRemove = unique(remove)
        let overlap = requestedAdd.filter { AssigneeRules.contains(requestedRemove, $0) }
        guard overlap.isEmpty else { return .failure(.conflicting(overlap)) }
        let unassigned = requestedRemove.filter { !AssigneeRules.contains(current, $0) }
        guard unassigned.isEmpty else { return .failure(.notAssigned(unassigned)) }

        let newPeople = requestedAdd.filter { !AssigneeRules.contains(current, $0) }
        // Removed people are written the way GitHub spells them, which is the way `current` lists them.
        let removed = current.filter { AssigneeRules.contains(requestedRemove, $0) }
        let change = AssigneeChange(add: newPeople, remove: removed)
        guard !newPeople.isEmpty || !removed.isEmpty else { return .failure(.nothingToChange) }
        let after = AssigneeRules.applying(change, to: current)
        guard after.count <= AssigneeRules.maximum else { return .failure(.tooMany) }
        let handsOver = me.map { AssigneeRules.contains(current, $0) && !AssigneeRules.contains(after, $0) } ?? false
        return .success(AssignmentPlan(change: change, before: current, after: after, handsOver: handsOver))
    }

    /// Changes who is assigned to an issue of the user's tasks after the confirmation. A person who is added must
    /// be assignable in the repository (no blind assigning); an unknown login or a list that cannot be loaded
    /// writes nothing. Giving the issue away removes it from the lists; `onHandedOver` deletes its future blocks.
    func assignTask(_ args: Arguments) async throws -> String {
        let task = try task(args.require("id"))
        guard task.id.source == .github else { throw ToolError(AssignmentError.notAnIssue.message) }
        guard let directory = gitHub() else { throw ToolError(String(localized: "Diese Quelle ist nicht verfügbar.")) }
        let me = directory.login
        let current = task.assignees ?? []

        var add: [String] = []
        let requested = args.strings("add")
        let others = requested.filter { !AssigneeSelection.isMe($0, me: me) && !AssigneeRules.contains(current, $0) }
        var assignable: [String] = []
        if !others.isEmpty {
            guard let loaded = await directory.assignableUsers(in: task.container.id, maxAge: AppEnvironment.catalogMaxAge) else {
                throw ToolError(String(localized: "Personen konnten nicht geladen werden"))
            }
            assignable = loaded
            let unknown = others.filter { AssigneeRules.canonical($0, in: loaded) == nil }
            guard unknown.isEmpty else {
                throw ToolError(String(localized: "\(unknown.formatted(.list(type: .and))) ist in \(task.container.id) nicht zuweisbar."))
            }
        }
        for login in requested {
            add.append(AssigneeRules.canonical(login, in: assignable) ?? login)
        }

        let plan: AssignmentPlan
        switch Self.assignmentPlan(current: current, add: add, remove: args.strings("remove"), me: me) {
        case .success(let resolved): plan = resolved
        case .failure(let error): throw ToolError(error.message)
        }

        let futureBlocks = planning.futureBlockCount(for: task.id)
        var edit = TaskEdit()
        edit.assignees = .set(plan.change)
        let updated = try await taskList.applyReturning(edit, to: task.id)

        let listed = taskList.items.contains { $0.id == task.id }
        var response: [String: Any] = ["ok": true, "assignees": updated.assignees ?? [], "handed_over": !listed,
                                       "deleted_blocks": listed ? 0 : futureBlocks]
        if !listed {
            if let number = task.issueNumber { response["number"] = number }
            if let url = task.url { response["url"] = url.absoluteString }
        }
        // GitHub drops people silently; the model must be able to tell the user.
        let missing = AssigneeRules.missing(requested: plan.change.add, actual: updated.assignees)
        if !missing.isEmpty { response["not_assigned"] = missing }
        return Self.json(response)
    }
}
