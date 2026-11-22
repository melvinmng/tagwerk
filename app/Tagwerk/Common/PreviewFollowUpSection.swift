import SwiftUI
import TagwerkCore

/// The block "Mit ChatGPT besprechen" of a preview sheet (plan ki-vorschlaege-anpassen, strand D): the follow-up bar with the
/// sentence of the last answer, "Rückgängig", a note about items of the user that an answer overwrote, and the chip that says
/// what the message is about. The sheet gives it the model and what "Senden" does; it never sends by itself.
struct PreviewFollowUpSection<Item: Identifiable & Equatable & Sendable>: View where Item.ID: Sendable {
    let model: PreviewFollowUpModel<Item>
    let availability: FollowUpAvailability
    let place: DictationPlace
    let quickReplies: [String]
    let placeholder: LocalizedStringKey
    /// What "Senden" sends, in the words of the function.
    let footer: Text
    /// The chip text for the focused item, e.g. "Zu: Feta".
    let focusLabel: (Item) -> String
    let onSend: (String) -> Void
    @FocusState private var focused: Bool

    private var scope: FollowUpScope? {
        guard let id = model.focus, let item = model.items.first(where: { $0.id == id }) else { return nil }
        return FollowUpScope(label: focusLabel(item), onClear: { model.focus = nil })
    }

    var body: some View {
        Section {
            FollowUpBar(availability: availability, state: model.state, place: place, quickReplies: quickReplies,
                        placeholder: placeholder, scope: scope, isFocused: $focused,
                        sendIdentity: model.focus.map { AnyHashable("\($0)") } ?? AnyHashable("all"), onSend: onSend,
                        onRetry: { onSend(model.lastMessage) }) {
                if !model.reply.isEmpty || model.canUndo {
                    FollowUpAnswerRow(reply: model.reply, mark: model.canUndo ? .byAssistant : nil,
                                      onUndo: model.canUndo ? { model.undo() } : nil)
                }
                if !model.overwritten.isEmpty {
                    Label("Von dir geänderte Zeilen wurden überschrieben. „Rückgängig“ bringt sie zurück.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orangeText)
                }
            }
        } header: {
            if availability != .hidden { Label("Mit ChatGPT besprechen", systemImage: "sparkles").foregroundStyle(Color.secondaryText) }
        } footer: {
            // The footer of the section, not a row: the system footer style passes the contrast audit at the largest text size.
            if availability != .hidden { footer }
        }
    }
}

/// The mark of a row of a preview ("von dir angepasst" / "von ChatGPT angepasst"); nothing for an untouched row.
struct PreviewRowMark: View {
    let mark: ProposalMark?

    var body: some View {
        if let mark { ProposalMarkLabel(mark: mark) }
    }
}
