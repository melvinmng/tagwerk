import SwiftUI
import TagwerkCore

/// Actions of the long-press menu (mockup d-A); the AI entries come from the environment (plan 2b-2, Task 8c).
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
    /// "Arbeitstag: Mi. 18. Nov." or "noch nicht eingeplant".
    var plannedText = String(localized: "noch nicht eingeplant")
    var unassign: (() -> Void)? = nil
    /// Sets the status in one sub-container (GitHub Project ID, option); `nil` where status is not offered.
    var setStatus: ((String, String) -> Void)? = nil
    /// Day view only: the shown day, which "Mit KI planen" plans when it is today or later.
    var shownDay: PlanDay? = nil
    /// Day view of today only: marks the task as today's focus or removes the mark (phase 7).
    var toggleFocus: (() -> Void)? = nil
    var isFocus = false
}

struct TaskContextMenu: View {
    let item: TaskItem
    let actions: TaskMenuActions
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppEnvironment.self) private var environment

    /// The AI entries appear only with a ChatGPT sign-in (mockup d: order dates, AI, done, destructive).
    static func showsAIEntries(isSignedIn: Bool) -> Bool { isSignedIn }

    /// "Fokus starten" is offered for every open task, from every list that shows this menu.
    static func showsFocusStart(for item: TaskItem) -> Bool { !item.isCompleted }

    /// The day "Mit KI planen" plans: the day the Planen day view shows, if it is today or later, else today
    /// (plan-tomorrow, F8). Menus outside the day view pass no day.
    static func aiPlanAnchor(shownDay: PlanDay?, today: PlanDay) -> PlanDay {
        guard let shownDay, shownDay >= today else { return today }
        return shownDay
    }

    var body: some View {
        // FO3b: "Fokus starten" is the first section.
        if Self.showsFocusStart(for: item) {
            Section { FocusStartButton(task: item) }
        }
        // Mockup F1: the planned day lives in Tagwerk only; the due date changes the source.
        Section("Einplanen · nur in Tagwerk") {
            if typeSize >= .accessibility1 {
                planButton(.today); planButton(.tomorrow); planButton(.weekend); planButton(.nextMonday)
            } else {
                // iOS hides the section title when control groups come first; this row keeps it and shows the current day.
                Text(actions.plannedText)
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
        if actions.isWritable, let setStatus = actions.setStatus, !Self.statusRows(of: item).isEmpty {
            Section("Status · ändert GitHub") {
                statusMenu(setStatus)
            }
        }
        if let toggleFocus = actions.toggleFocus {
            Section {
                Button(actions.isFocus ? "Fokus entfernen" : "Als Fokus markieren", systemImage: actions.isFocus ? "star.slash" : "star") {
                    toggleFocus()
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
        if Self.showsAIEntries(isSignedIn: environment.ai.isSignedIn) {
            Section {
                Button("Mit KI planen", systemImage: "sparkles") {
                    let planning = environment.planning
                    let day = Self.aiPlanAnchor(shownDay: actions.shownDay, today: planning.today)
                    environment.requestedTab = 0
                    planning.scope = .day
                    planning.anchor = day
                    environment.planner.start(scope: .day, anchor: day, taskID: item.id)
                }
                Button("Über diese Aufgabe sprechen", systemImage: "bubble.left.and.text.bubble.right") {
                    environment.assistant.open(task: item)
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

    /// Status rows the user may change: writable projects that have a Status field.
    static func statusRows(of item: TaskItem) -> [SubContainerStatus] {
        guard item.id.source == .github, item.editableFields.contains(.status) else { return [] }
        return item.statuses.filter { $0.isWritable && !$0.options.isEmpty }
    }

    /// One project: the stages with a checkmark at the current one. Several projects: one submenu each.
    @ViewBuilder private func statusMenu(_ setStatus: @escaping (String, String) -> Void) -> some View {
        let rows = Self.statusRows(of: item)
        if rows.count == 1, let row = rows.first {
            Menu {
                statusOptions(of: row, setStatus)
            } label: {
                Label("Status ändern", systemImage: "circle.dashed")
                Text(row.current ?? String(localized: "kein Status"))
            }
        } else {
            Menu {
                ForEach(rows, id: \.subContainerID) { row in
                    Menu(row.subContainerName) { statusOptions(of: row, setStatus) }
                }
            } label: {
                Label("Status ändern", systemImage: "circle.dashed")
            }
        }
    }

    private func statusOptions(of row: SubContainerStatus, _ setStatus: @escaping (String, String) -> Void) -> some View {
        ForEach(row.options, id: \.self) { option in
            Button {
                setStatus(row.subContainerID, option)
            } label: {
                if option == row.current { Label(option, systemImage: "checkmark") } else { Text(option) }
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
        case .reminders: String(localized: "Erinnerung")
        case .local: "Tagwerk"
        }
    }

    private var dueText: String {
        guard let due = item.due else { return String(localized: "keine Fälligkeit") }
        return String(localized: "jetzt \(DueText.text(due, now: .now, calendar: .tagwerk))")
    }
}
