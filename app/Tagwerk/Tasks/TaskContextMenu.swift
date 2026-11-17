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
    /// Day view only: create a time block / remove the planned day (replace the former swipe actions).
    var createBlock: (() -> Void)? = nil
    var unassign: (() -> Void)? = nil
}

struct TaskContextMenu: View {
    let item: TaskItem
    let actions: TaskMenuActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Mockup F1: the planned day lives in Tagwerk only; the due date changes the source.
        Section("Einplanen · nur in Tagwerk") {
            if typeSize >= .accessibility1 {
                planButton(.today); planButton(.tomorrow); planButton(.weekend); planButton(.nextMonday)
            } else {
                ControlGroup { planButton(.today); planButton(.tomorrow) }
                ControlGroup { planButton(.weekend); planButton(.nextMonday) }
            }
            Button("Anderer Tag …", systemImage: "calendar") { actions.planOnDate() }
        }
        if actions.isWritable {
            Section("Fälligkeit · ändert \(sourceName)") {
                Menu {
                    Button("Heute") { actions.moveDue(.today) }
                    Button("Morgen") { actions.moveDue(.tomorrow) }
                    Button("Wochenende (Sa)") { actions.moveDue(.weekend) }
                    Button("Nächste Woche (Mo)") { actions.moveDue(.nextMonday) }
                    Button("Datum wählen …") { actions.moveDueOnDate() }
                } label: {
                    Label("Fälligkeit verschieben", systemImage: "calendar.badge.clock")
                    Text(dueText)
                }
            }
        }
        if actions.createBlock != nil || actions.unassign != nil || actions.editEffort != nil {
            Section {
                if let createBlock = actions.createBlock {
                    Button("Zeitblock …", systemImage: "calendar.day.timeline.left") { createBlock() }
                }
                if let unassign = actions.unassign {
                    Button("Ausplanen", systemImage: "calendar.badge.minus") { unassign() }
                }
                if let editEffort = actions.editEffort {
                    Button("Aufwand ändern …", systemImage: "arrow.trianglehead.2.clockwise") { editEffort() }
                }
            }
        }
        if actions.isWritable {
            Section {
                Button("Erledigt", systemImage: "checkmark.circle") { actions.complete() }
                Button(TaskListView.deleteTitle(for: item), systemImage: "trash", role: .destructive) { actions.delete() }
            }
        }
    }

    private func planButton(_ option: RescheduleOption) -> some View {
        switch option {
        case .today: Button("Heute", systemImage: "sun.max") { actions.plan(.today) }
        case .tomorrow: Button("Morgen", systemImage: "sunrise") { actions.plan(.tomorrow) }
        case .weekend: Button("Wochenende", systemImage: "sofa") { actions.plan(.weekend) }
        default: Button("Nächste Woche", systemImage: "arrow.forward.to.line") { actions.plan(.nextMonday) }
        }
    }

    private var sourceName: String {
        switch item.id.source {
        case .github: "GitHub"
        case .reminders: "Erinnerung"
        case .local: "Tagwerk"
        }
    }

    private var dueText: String {
        guard let due = item.due else { return "keine Fälligkeit" }
        return "jetzt " + DueText.text(due, now: .now, calendar: .tagwerk)
    }
}
