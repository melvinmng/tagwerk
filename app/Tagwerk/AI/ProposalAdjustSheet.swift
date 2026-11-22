import AIKit
import SwiftUI
import TagwerkCore

/// The sheet "Vorschlag anpassen" (mockups AN2a, AN4a): the fields of the function, below them the follow-up line to write
/// to ChatGPT about this card, "Zurück zum Vorschlag der KI" once the card carries a mark, and "Fertig", which writes the
/// values back into the card. Nothing is carried out here; the card is confirmed with "Bestätigen" (AN2a). The sheet hangs
/// on the chat view, never on the card (a sheet on a row of a list or form does not open reliably).
///
/// A follow-up answer fills the fields and carries the mark "von ChatGPT angepasst"; "Rückgängig" brings back the fields
/// from before the answer, until the user changes something by hand. Only "Fertig" changes the card, and the other cards and
/// the chat stay as they are.
struct ProposalAdjustSheet: View {
    let assistant: any CardAdjusting
    let call: ToolCall
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var editor: (any ProposalEditor)?
    @State private var followUp = FollowUpModel()
    @FocusState private var focused: Bool

    /// What the follow-up line keeps while the sheet is open; nothing of it is stored.
    struct FollowUpModel {
        var state: FollowUpState = .ready
        var reply = ""
        /// The fields as they were before the last answer.
        var undoEditor: (any ProposalEditor)?
        /// The arguments the last answer produced; a later change by hand makes them differ from the fields.
        var answerArguments: Data?
        var lastMessage = ""
    }

    private var isMarked: Bool { assistant.isAdjusted(call) }

    private var availability: FollowUpAvailability {
        FollowUpAvailability.state(hasConsent: assistant.cardFollowUpHasConsent, isSignedIn: environment.ai.isSignedIn, isOffline: false)
    }

    /// True while the fields still hold what the last answer produced.
    private var showsAnswer: Bool {
        guard let editor, let answer = followUp.answerArguments else { return false }
        return Self.sameArguments(editor.arguments(), answer)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let editor {
                    editor.fields
                    Section {} footer: {
                        Text("Geändert wird nur der Vorschlag. Ausgeführt wird erst mit „Bestätigen“ auf der Karte.")
                    }
                    if isMarked {
                        Section {
                            Button("Zurück zum Vorschlag der KI", role: .destructive) {
                                assistant.resetAdjustment(call)
                                dismiss()
                            }
                        }
                    }
                    followUpSection(editor)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Vorschlag anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        if let editor { assistant.adjust(call, arguments: editor.arguments(), mark: showsAnswer ? .byAssistant : .byUser) }
                        dismiss()
                    }
                    .disabled(editor?.isValid != true)
                }
            }
            .task {
                if editor == nil { editor = assistant.proposalEditor(for: call) }
                await editor?.load()
            }
        }
        .presentationDetents([.large])
        .modifier(UITestAppearance())
    }

    // MARK: Follow-up

    @ViewBuilder
    private func followUpSection(_ editor: any ProposalEditor) -> some View {
        Section {
            FollowUpBar(availability: availability, state: followUp.state, place: .chat,
                        quickReplies: CardReviser.quickReplies(for: call.name),
                        placeholder: "ChatGPT sagen, was anders sein soll …",
                        footer: Text("Senden gibt diesen Vorschlag mit deinen Änderungen und deiner Nachricht an ChatGPT. Die anderen Karten bleiben, wie sie sind."),
                        isFocused: $focused, sendIdentity: call.id, onSend: { send($0) },
                        onRetry: { send(followUp.lastMessage) }) {
                if !followUp.reply.isEmpty || showsAnswer {
                    FollowUpAnswerRow(reply: followUp.reply, mark: showsAnswer ? .byAssistant : nil,
                                      onUndo: showsAnswer && followUp.undoEditor != nil ? { undo() } : nil)
                }
            }
        } header: {
            if availability != .hidden { Label("Mit ChatGPT besprechen", systemImage: "sparkles") }
        }
    }

    private func send(_ message: String) {
        guard let editor, !message.isEmpty else { return }
        followUp.lastMessage = message
        followUp.state = .sending
        let current = editor.arguments()
        Task {
            do {
                let answer = try await assistant.reviseCard(call, current: current, comment: message)
                followUp.reply = answer.message
                if answer.changed, let revised = assistant.proposalEditor(for: call, arguments: answer.arguments) {
                    followUp.undoEditor = editor
                    followUp.answerArguments = revised.arguments()
                    self.editor = revised
                    await revised.load()
                } else {
                    // Nothing changed: the sentence tells why, the fields and an earlier "Rückgängig" stay as they are.
                }
                followUp.state = .ready
            } catch let failure as CardReviser.Failure {
                followUp.state = .failed(failure.message)
            } catch {
                followUp.state = .failed(CardReviser.Failure.failed.message)
            }
        }
    }

    /// "Rückgängig": the fields from before the answer.
    private func undo() {
        guard let previous = followUp.undoEditor else { return }
        editor = previous
        followUp.undoEditor = nil
        followUp.answerArguments = nil
        followUp.reply = ""
    }

    static func sameArguments(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = ProposalArguments.decode(lhs), let right = ProposalArguments.decode(rhs) else { return false }
        return NSDictionary(dictionary: left).isEqual(to: right)
    }
}
