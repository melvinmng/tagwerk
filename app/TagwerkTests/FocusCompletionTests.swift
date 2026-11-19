import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// "Erledigt" on the Live Activity can run when the app was started in the background and no task list is loaded.
@MainActor
struct FocusCompletionTests {
    @Test func completeTask_loadsTheListFirst_whenTheAppWasStartedInTheBackground() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appending(path: "focus-completion-\(UUID().uuidString)")
        let environment = try AppEnvironment(modelContainer: container, notificationCenter: FakeNotificationCenter(),
                                             health: FakeHealthStore(), snapshotWriter: WidgetSnapshotWriter(directory: directory, reload: {}))
        let created = try await LocalTaskProvider(context: container.mainContext).create(TaskDraft(title: "Bericht"))
        // Nothing was loaded: this is the state right after a background launch.
        #expect(environment.taskList.items.isEmpty)
        let complete = try #require(environment.focus.completeTask)
        await complete(created.id.key)
        let completed = (environment.taskList.provider(for: .local) as? LocalTaskProvider)?.completedTasks() ?? []
        #expect(completed.map(\.item.id) == [created.id])
    }
}
