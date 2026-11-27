import Foundation
import GitHubKit
import RemindersKit
import SwiftData
import TagwerkCore

extension ProjectProgressSources {
    /// How far back completed reminders are read. EventKit has no count, and a list with years of completed reminders would take long.
    static let reminderHistoryYears = 5

    /// The real sources: GitHub through the signed-in account, Reminders through EventKit, local tasks from the store.
    @MainActor
    static func live(taskList: TaskListModel, settings: AppSettings, reminderStore: any ReminderStore, gitHub: GitHubTaskProvider,
                     estimates: any EstimateStore, time: ProjectTimeReader, context: ModelContext,
                     now: @escaping () -> Date = Date.init) -> ProjectProgressSources {
        ProjectProgressSources(
            catalog: {
                var catalog = ProjectCatalog()
                if taskList.provider(for: .github) != nil {
                    catalog.gitHubConnected = true
                    let chosen = settings.selectedProjectIDs.map(Set.init)
                    let projects = (await gitHub.catalog(maxAge: AppEnvironment.catalogMaxAge))?.projects ?? gitHub.projects
                    catalog.references += projects.filter { chosen?.contains($0.id) ?? true }.map {
                        ProjectProgressReference(kind: .gitHubProject, id: $0.id, title: $0.title)
                    }
                    // Repositories of the issues the user has: the whole list of repositories would be hundreds of rows.
                    var seen = Set<String>()
                    for item in taskList.items where item.id.source == .github && seen.insert(item.container.id).inserted {
                        catalog.references.append(ProjectProgressReference(kind: .gitHubRepository, id: item.container.id,
                                                                           title: item.container.name))
                    }
                }
                if reminderStore.accessState == .fullAccess {
                    catalog.remindersAccess = true
                    let chosen = settings.selectedReminderListIDs.map(Set.init)
                    for list in reminderStore.lists() where list.id != settings.shoppingListID && (chosen?.contains(list.id) ?? true) {
                        catalog.references.append(ProjectProgressReference(kind: .remindersList, id: list.id, title: list.title))
                    }
                }
                if ((try? context.fetchCount(FetchDescriptor<LocalTask>())) ?? 0) > 0 {
                    catalog.references.append(.local(title: LocalTaskProvider.container.name))
                }
                return catalog
            },
            facts: { reference in
                switch reference.kind {
                case .gitHubProject, .gitHubRepository:
                    guard taskList.provider(for: .github) != nil else { throw ProjectLoadFailure.notConnected }
                    let keys = Set(taskList.items.filter { $0.id.source == .github }.map(\.id.key))
                    do {
                        let result = reference.kind == .gitHubProject
                            ? try await gitHub.api.projectItems(projectID: reference.id)
                            : try await gitHub.api.repositoryIssues(reference.id)
                        return ProjectFactsLoad(facts: result.items.map { ProjectFactsMapping.fact($0, loadedTaskKeys: keys) },
                                                isTruncated: result.isTruncated, fetchedAt: now())
                    } catch {
                        throw ProjectFactsMapping.failure(error)
                    }
                case .remindersList:
                    guard reminderStore.accessState == .fullAccess else { throw ProjectLoadFailure.noAccess }
                    let start = Calendar.tagwerk.date(byAdding: .year, value: -reminderHistoryYears, to: now()) ?? .distantPast
                    let interval = DateInterval(start: start, end: now().addingTimeInterval(60))
                    let open = await reminderStore.openReminders(in: [reference.id])
                    let completed = await reminderStore.completedReminders(in: interval, listIDs: [reference.id])
                    let facts = (open + completed).map { ProjectFactsMapping.fact($0, estimateMinutes: estimates.minutes(for: $0.id)) }
                    return ProjectFactsLoad(facts: facts, fetchedAt: now())
                case .local:
                    let tasks = (try? context.fetch(FetchDescriptor<LocalTask>())) ?? []
                    return ProjectFactsLoad(facts: tasks.map(ProjectFactsMapping.fact), fetchedAt: now())
                }
            },
            time: { taskKeys, range in time.inputs(taskKeys: taskKeys, range: range) })
    }
}
