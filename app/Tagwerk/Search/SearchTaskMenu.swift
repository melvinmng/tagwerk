import SwiftUI
import TagwerkCore

/// The entries of the context menu on a task hit, in order (mockup SU1b). Pure, so the order and the rules are tested.
/// There is deliberately no entry for deleting, closing, status, due date, weekend, next week, effort or the AI:
/// a hit is a way to reach a task, not a place to rework it (review focus 8).
enum SearchTaskMenu {
    enum Entry: Hashable, CaseIterable {
        case open, showInTasks, showInPlan, planToday, planTomorrow, planOnDate, startFocus, openOnGitHub, complete
    }

    /// - Parameters:
    ///   - isPlanned: The task has a planned day; "Im Plan zeigen" replaces "In Aufgaben zeigen".
    ///   - isOffline: The source of the task is offline (read-only cache). Planning lives in Tagwerk and still works.
    static func entries(for item: TaskItem, isPlanned: Bool, isOffline: Bool) -> [Entry] {
        var result: [Entry] = [.open, isPlanned ? .showInPlan : .showInTasks, .planToday, .planTomorrow, .planOnDate]
        if TaskContextMenu.showsFocusStart(for: item) { result.append(.startFocus) }
        if item.id.source == .github, item.url != nil { result.append(.openOnGitHub) }
        if !isOffline { result.append(.complete) }
        return result
    }

    /// What VoiceOver says after a planned day was set from a hit.
    static func plannedAnnouncement(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        if day == today { return String(localized: "Für heute eingeplant") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today.startDate(in: calendar)),
           day == PlanDay(date: tomorrow, calendar: calendar) {
            return String(localized: "Für morgen eingeplant")
        }
        // The style takes the time zone of the calendar that built the date; the default would use the system zone.
        let style = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month()
        let text = day.startDate(in: calendar).formatted(style)
        return String(localized: "Eingeplant für \(text)")
    }
}

/// What the menu and the VoiceOver actions of a task hit do; the sheet supplies the closures.
struct SearchTaskMenuActions {
    var open: () -> Void
    var show: () -> Void
    var plan: (RescheduleOption) -> Void
    var planOnDate: () -> Void
    var startFocus: () -> Void
    var openOnGitHub: () -> Void
    var complete: () -> Void
}

/// The context menu of a task hit (mockup SU1b): open and show, planning, focus, GitHub, done.
struct SearchTaskMenuContent: View {
    let item: TaskItem
    let entries: [SearchTaskMenu.Entry]
    let actions: SearchTaskMenuActions

    var body: some View {
        Button("Öffnen", systemImage: "chevron.right") { actions.open() }
        if entries.contains(.showInPlan) {
            Button("Im Plan zeigen", systemImage: "calendar") { actions.show() }
        } else if entries.contains(.showInTasks) {
            Button("In Aufgaben zeigen", systemImage: "checklist") { actions.show() }
        }
        // Planning lives in Tagwerk only, so it is offered for every source, also while the source is offline.
        Section("Einplanen · nur in Tagwerk") {
            ControlGroup {
                TaskPlanButton(option: .today) { actions.plan(.today) }
                TaskPlanButton(option: .tomorrow) { actions.plan(.tomorrow) }
            }
            Button("Anderer Tag …", systemImage: "calendar") { actions.planOnDate() }
        }
        if entries.contains(.startFocus) {
            // The search sheet closes first, then the start sheet follows (no sheet over a sheet).
            Section { FocusStartButton(task: item, action: actions.startFocus) }
        }
        if entries.contains(.openOnGitHub) {
            Button("Auf GitHub öffnen", systemImage: "arrow.up.right.square") { actions.openOnGitHub() }
        }
        if entries.contains(.complete) {
            Button("Erledigt", systemImage: "checkmark.circle") { actions.complete() }
        }
    }
}

/// The VoiceOver actions of a task hit: the same entries as the menu, with names that say what they do.
struct SearchTaskAccessibilityActions: ViewModifier {
    let entries: [SearchTaskMenu.Entry]
    let isPlanned: Bool
    let isFocusRunning: Bool
    let actions: SearchTaskMenuActions

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(entries, id: \.self) { entry in
                Button(title(of: entry)) { perform(entry) }
            }
        }
    }

    private func title(of entry: SearchTaskMenu.Entry) -> String {
        switch entry {
        case .open: String(localized: "Öffnen")
        case .showInPlan: String(localized: "Im Plan zeigen")
        case .showInTasks: String(localized: "In Aufgaben zeigen")
        case .planToday: String(localized: "Für heute einplanen")
        case .planTomorrow: String(localized: "Für morgen einplanen")
        case .planOnDate: String(localized: "Anderen Tag einplanen")
        case .startFocus: isFocusRunning ? String(localized: "Fokus öffnen") : String(localized: "Fokus starten")
        case .openOnGitHub: String(localized: "Auf GitHub öffnen")
        case .complete: String(localized: "Erledigt")
        }
    }

    private func perform(_ entry: SearchTaskMenu.Entry) {
        switch entry {
        case .open: actions.open()
        case .showInPlan, .showInTasks: actions.show()
        case .planToday: actions.plan(.today)
        case .planTomorrow: actions.plan(.tomorrow)
        case .planOnDate: actions.planOnDate()
        case .startFocus: actions.startFocus()
        case .openOnGitHub: actions.openOnGitHub()
        case .complete: actions.complete()
        }
    }
}
