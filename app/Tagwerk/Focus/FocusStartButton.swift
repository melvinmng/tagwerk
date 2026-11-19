import SwiftUI
import TagwerkCore

/// "Fokus starten" for a time block with a task or for a task. While a session runs it opens that session instead.
struct FocusStartButton: View {
    private enum Subject {
        case block(CalendarEvent)
        case task(TaskItem)
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isInSheet
    private let subject: Subject

    init(block: CalendarEvent) { subject = .block(block) }
    init(task: TaskItem) { subject = .task(task) }

    var body: some View {
        Button {
            let target = resolved()
            // A sheet that is closing cannot present another one at once; the focus sheet follows after it.
            let wasInSheet = isInSheet
            if wasInSheet { dismiss() }
            Task {
                if wasInSheet { try? await Task.sleep(for: .milliseconds(400)) }
                await environment.focus.start(task: target.task, block: target.block)
            }
        } label: {
            Label(environment.focus.isRunning ? "Fokus öffnen" : "Fokus starten", systemImage: "timer")
        }
    }

    private func resolved() -> (task: TaskItem?, block: CalendarEvent?) {
        switch subject {
        case .block(let block): (environment.planning.linkedTask(eventID: block.id), block)
        case .task(let task): (task, nil)
        }
    }
}
