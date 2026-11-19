import GitHubKit
import SwiftUI
import TagwerkCore

/// The task editor as a sheet, wired to the app (the suggestion sheets have their own `TaskEditorSheet`). "Planen" and the search open it; the list of "Aufgaben" builds
/// its own with a few more parameters.
struct AppTaskEditorSheet: View {
    let item: TaskItem
    /// Containers the editor offers for a move; the search reads them like the task list does.
    var containers: [TaskContainer] = []
    /// GitHub issues can be commented from the search, as from the task list.
    var allowsComments = false
    /// Offline GitHub tasks are read-only in the editor.
    var respectsOffline = false
    var onShowDay: ((PlanDay) -> Void)?
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let provider = environment.taskList.provider(for: item.id.source) {
            TaskEditorView(item: item, provider: provider, calendar: environment.taskList.calendar, containers: containers,
                           addComment: allowsComments ? Self.commentAction(for: provider) : nil,
                           isReadOnly: respectsOffline && environment.taskList.sourceStates[item.id.source]?.isOffline == true,
                           onDelete: { version in Task { await environment.taskList.delete(item.id, version: version) } },
                           planning: environment.planning,
                           onShowDay: onShowDay) { saved, requested in
                // A completed task is not in the list; reopening it must still reach the plan.
                environment.taskList.didSave(saved, requestedAssignees: requested, wasCompleted: item.isCompleted)
            }
        }
    }

    static func commentAction(for provider: any TaskProvider) -> TaskEditorModel.CommentAction? {
        guard let gitHub = provider as? GitHubTaskProvider else { return nil }
        return { id, text, version in try await gitHub.addComment(to: id, body: text, expectedVersion: version) }
    }
}

/// The sheet of a calendar event, with the task linked to it.
struct EventEntrySheet: View {
    let event: CalendarEvent
    let onShowTask: (TaskID) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        EntrySheet(entry: .event(event, environment.planning.linkedTask(eventID: event.id)?.id),
                   model: environment.planning, onShowTask: onShowTask)
    }
}

/// A note in its own navigation stack, so it opens from any tab; the notes page pushes it onto the stack of
/// "Aufgaben" instead, where a sheet over another tab could not show it.
struct NoteEditorSheet: View {
    let noteID: UUID
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NoteEditorView(noteID: noteID, store: environment.notes)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } } }
        }
    }
}

/// The shopping list in its own navigation stack, for the same reason.
struct ShoppingListSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShoppingListView(model: environment.shopping)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } } }
        }
    }
}
