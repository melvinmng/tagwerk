import SwiftUI
import TagwerkCore

/// Actions of the long-press menu (mockup d-A). AI entries follow in plan 2b-2.
struct TaskMenuActions {
    var plan: (RescheduleOption) -> Void
    var planOnDate: () -> Void
    var moveDue: (RescheduleOption) -> Void
    var moveDueOnDate: () -> Void
    var complete: () -> Void
    var delete: () -> Void
    var editEffort: (() -> Void)?
    var isWritable: Bool
}

struct TaskContextMenu: View {
    let item: TaskItem
    let actions: TaskMenuActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section("Einplanen") {
            if typeSize >= .accessibility1 {
                planButtons
            } else {
                ControlGroup { planButtons }
            }
            Button("Datum wählen …", systemImage: "calendar") { actions.planOnDate() }
        }
        if actions.isWritable {
            Menu("Fälligkeit verschieben …", systemImage: "calendar.badge.clock") {
                Button("Heute") { actions.moveDue(.today) }
                Button("Morgen") { actions.moveDue(.tomorrow) }
                Button("Wochenende (Sa)") { actions.moveDue(.weekend) }
                Button("Nächste Woche (Mo)") { actions.moveDue(.nextMonday) }
                Button("Datum wählen …") { actions.moveDueOnDate() }
            }
            if let editEffort = actions.editEffort {
                Button("Aufwand ändern …", systemImage: "arrow.trianglehead.2.clockwise") { editEffort() }
            }
            Button("Erledigt", systemImage: "checkmark.circle") { actions.complete() }
            Button(TaskListView.deleteTitle(for: item), systemImage: "trash", role: .destructive) { actions.delete() }
        }
    }

    @ViewBuilder private var planButtons: some View {
        Button("Heute", systemImage: "sun.max") { actions.plan(.today) }
        Button("Morgen", systemImage: "sunrise") { actions.plan(.tomorrow) }
        Button("Wochenende", systemImage: "sofa") { actions.plan(.weekend) }
        Button("Nächste Woche", systemImage: "calendar.badge.plus") { actions.plan(.nextMonday) }
    }
}
