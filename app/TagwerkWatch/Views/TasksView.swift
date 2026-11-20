import SwiftUI
import TagwerkCore

/// Open tasks of today: the circle checks one off.
struct TasksView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snapshot = store.display()
        let completing = store.completingKeys()
        List {
            UndoRow()
            if let snapshot, !snapshot.tasks.isEmpty {
                ForEach(snapshot.tasksForDisplay) { task in
                    TaskRow(task: task, isCompleting: completing.contains(task.key))
                }
            } else if snapshot != nil {
                Text("Keine offenen Aufgaben heute").foregroundStyle(.secondary)
            }
            SyncHint().listRowBackground(Color.clear)
        }
        .navigationTitle("Aufgaben")
    }
}

private struct TaskRow: View {
    @Environment(WatchStore.self) private var store
    let task: WatchTask
    let isCompleting: Bool

    var body: some View {
        Button {
            store.complete(task)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCompleting ? "checkmark.circle.fill" : (task.isDeadline ? "flag" : "circle"))
                    .foregroundStyle(isCompleting ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).lineLimit(2)
                    if task.hasTime, let due = task.due {
                        Text(DateText.time(due, calendar: .watch)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(isCompleting)
        .accessibilityHint(Text("Hakt die Aufgabe ab"))
    }
}
