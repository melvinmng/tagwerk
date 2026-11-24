import SwiftUI
import TagwerkCore

/// "Fokus starten" for a time block with a task or for a task. Shows the start sheet (or starts at once when the sheet is
/// switched off). While a session runs it opens that session instead.
struct FocusStartButton: View {
    private enum Subject {
        case block(CalendarEvent)
        case task(TaskItem)
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isInSheet
    private let subject: Subject
    /// A host that closes its own sheet before the start (the search sheet) passes its action; the title stays the same.
    private let customAction: (() -> Void)?

    init(block: CalendarEvent) { subject = .block(block); customAction = nil }
    init(task: TaskItem, action: (() -> Void)? = nil) { subject = .task(task); customAction = action }

    var body: some View {
        Button {
            if let customAction { customAction(); return }
            let target = resolved()
            // A sheet that is closing cannot present another one at once; the start or focus sheet follows after it.
            let wasInSheet = isInSheet
            if wasInSheet { dismiss() }
            Task {
                if wasInSheet { try? await Task.sleep(for: .milliseconds(400)) }
                await environment.focus.requestStart(task: target.task, block: target.block)
            }
        } label: {
            Label(title, systemImage: "timer")
        }
    }

    /// "Fokus starten · 25 min" for a task, "Fokus starten" for a block (its sheet offers "Bis Blockende"), "Fokus öffnen" while one runs.
    private var title: String {
        var planned: Int?
        if case .task = subject {
            let settings = environment.settings
            planned = FocusStart.plannedMinutes(base: settings.focusTimerSettings,
                                                lastMinutes: settings.focusAsksDurationAtStart ? settings.focusLastStartMinutes : nil)
        }
        return FocusTimerText.startTitle(plannedMinutes: planned, isRunning: environment.focus.isRunning)
    }

    private func resolved() -> (task: TaskItem?, block: CalendarEvent?) {
        switch subject {
        case .block(let block): (environment.planning.linkedTask(eventID: block.id), block)
        case .task(let task): (task, nil)
        }
    }
}
