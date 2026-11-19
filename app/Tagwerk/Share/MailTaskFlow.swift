import SwiftUI
import TagwerkCore

/// "Mail zu Aufgabe" as one sheet in two steps: first the proposal (with or without ChatGPT), then "Neue Aufgabe" with the
/// fields filled in, where the task is saved with source and list as always. Switching the content instead of pushing keeps
/// it one sheet and one navigation stack.
struct MailTaskFlow: View {
    @Environment(AppEnvironment.self) private var environment
    @State var model: MailTaskModel
    /// Called when the task was created.
    let onFinished: () -> Void
    /// Offered by shared items; the clipboard route has nothing to discard.
    var onDiscard: (() -> Void)?
    @State private var prefill: MailTaskModel.Prefill?

    init(model: MailTaskModel, onFinished: @escaping () -> Void, onDiscard: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
        self.onDiscard = onDiscard
    }

    var body: some View {
        if let prefill {
            NewTaskSheet(model: environment.taskList, prefilledTitle: prefill.title, onCreated: onFinished,
                         prefilledNotes: prefill.notes, prefilledDue: prefill.due)
        } else {
            MailTaskSheet(model: model, onContinue: { prefill = model.prefill }, onDiscard: onDiscard)
        }
    }
}
