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

    /// The day "Mit KI planen" plans: the day the Planen day view shows, if it is today or later, else today
    /// (plan-tomorrow, F8). Menus outside the day view pass no day.
    static func aiPlanAnchor(shownDay: PlanDay?, today: PlanDay) -> PlanDay {
        guard let shownDay, shownDay >= today else { return today }
        return shownDay
    }

    var body: some View {
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
