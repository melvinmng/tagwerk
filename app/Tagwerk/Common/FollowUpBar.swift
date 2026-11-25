import SwiftUI
import TagwerkCore

/// What a follow-up bar shows below its exchange (plan ki-vorschlaege-anpassen, task A3).
enum FollowUpState: Equatable {
    case ready
    /// A request is running: "ChatGPT antwortet …", sending is off.
    case sending
    /// The last request failed; `retry` on the bar offers "Erneut versuchen".
    case failed(String)
}

/// What a follow-up message is about, shown as a chip above the input: "Zu: Feta ✕" or "Zu allen 4 Vorschlägen ✕".
struct FollowUpScope {
    let label: String
    let onClear: () -> Void
}

/// The shared bar to talk to ChatGPT about a proposal: the exchange so far, quick replies, an input line with
/// microphone and the note of what "Senden" sends. "Tag planen" (`SuggestionConversation`), the preview sheets and the
/// card sheet use it, each with its own quick replies and its own footer text.
///
/// The body is a group of rows without a container, so it works inside a `Form` section (each part a row) and in a
/// plain stack. The bar only collects the message; the caller sends it and keeps the exchange (nothing is stored here).
/// It never sends by itself: "Senden", the keyboard's send key, a quick reply or the end of a dictation start a request.
struct FollowUpBar<Exchange: View>: View {
    @Environment(AppEnvironment.self) private var environment
    let availability: FollowUpAvailability
    var state: FollowUpState = .ready
    let place: DictationPlace
    let quickReplies: [String]
    let placeholder: LocalizedStringKey
    /// The note under the bar: what "Senden" sends, in the words of the function. `nil` when the caller shows its own.
    var footer: Text? = nil
    var scope: FollowUpScope? = nil
    var isFocused: FocusState<Bool>.Binding
    /// Recording hides the decision bar of the surrounding screen like typing does (mockup SP6b).
    var isRecording: Binding<Bool> = .constant(false)
    /// Changes whenever `onSend` should address something else (another suggestion): the voice input is bound again.
    var sendIdentity: AnyHashable = 0
    let onSend: (String) -> Void
    var onRetry: (() -> Void)? = nil
    @ViewBuilder var exchange: () -> Exchange

    @State private var text = ""
    @State private var voice: VoiceInputModel?

    private var isSending: Bool { state == .sending }

    var body: some View {
        if availability != .hidden {
            exchange()
            statusRow
            if let voice { VoiceNoticeRow(voice: voice) }
            if let voice, voice.isRecording {
                VoiceRecordingBar(voice: voice, compact: true, canSend: availability == .available && !isSending, tint: .purple)
                    .onAppear { isRecording.wrappedValue = true }
                    .onDisappear {
                        isRecording.wrappedValue = false
                        // The screen went away while recording; a normal end of the recording leaves nothing to cancel.
                        if voice.isRecording { voice.cancel() }
                    }
            } else {
                if let scope { scopeChip(scope) }
                quickReplyRow
                inputRow
            }
            if let footer {
                // The named tone: the hierarchical `.secondary` fails the contrast audit in dark mode at the largest text size.
                footer.font(.footnote).foregroundStyle(Color.secondaryText)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var statusRow: some View {
        if availability == .offline {
            Label("Keine Verbindung. Ändern von Hand geht weiter.", systemImage: "wifi.slash")
                .font(.caption).foregroundStyle(.secondaryText)
        } else if isSending {
            HStack(spacing: 8) {
                ProgressView()
                Text("ChatGPT antwortet …").foregroundStyle(.secondaryText)
            }
        } else if case .failed(let message) = state {
            HStack {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orangeText)
                if let onRetry {
                    Spacer()
                    Button("Erneut versuchen", action: onRetry).font(.caption)
                }
            }
        }
    }

    private func scopeChip(_ scope: FollowUpScope) -> some View {
        HStack(spacing: 4) {
            Text(scope.label).font(.caption.weight(.semibold))
            Button(action: scope.onClear) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bezug entfernen")
        }
        .foregroundStyle(.purpleText)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.purple.opacity(0.15), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickReplyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickReplies, id: \.self) { reply in
                    Button(reply) { send(reply) }
                        .buttonStyle(FollowUpChipButtonStyle())
                        .disabled(!FollowUpAvailability.canSend(availability, text: reply, isSending: isSending))
                }
            }
        }
        .keepsKeyboardOnTap()
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit { send(text) }
                .disabled(availability != .available)
            if environment.settings.voiceInputEnabled, let voice {
                VoiceMicrophoneButton(voice: voice, isEnabled: environment.ai.isSignedIn && availability == .available,
                                      language: environment.settings.dictationLanguage(at: place))
            }
            Button {
                send(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
            .disabled(!FollowUpAvailability.canSend(availability, text: text, isSending: isSending))
            .accessibilityLabel("Senden")
        }
        .keepsKeyboardOnTap()
        .onAppear { prepareVoice() }
        // `send` addresses what the caller's closure addresses; keep the dictation on the current one.
        .onChange(of: sendIdentity) { _, _ in voice?.onSend = { send($0) } }
        // The input row also leaves when a recording starts; only a screen that goes away while idle ends the voice input.
        .onDisappear { if voice?.isRecording != true { voice?.cancel() } }
    }

    private func prepareVoice() {
        if voice == nil {
            let model = VoiceInputFactory.make(environment, place: place)
            model.readDraft = { text }
            model.writeDraft = { text = $0 }
            voice = model
        }
        voice?.onSend = { send($0) }
    }

    private func send(_ message: String) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FollowUpAvailability.canSend(availability, text: message, isSending: isSending) else { return }
        text = ""
        isFocused.wrappedValue = false
        onSend(message)
    }
}

/// The quick-reply chip of the follow-up bar: text in `purpleText` on a 15 % tint of the system purple. The system style
/// `.bordered` with `.tint(.purple)` draws the text in the system purple, which is too light on its own tint in the light appearance.
private struct FollowUpChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.purpleText)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// One answer of the exchange in a follow-up bar: the sentence of ChatGPT, the mark and "Rückgängig" after a change.
struct FollowUpAnswerRow: View {
    let reply: String
    var mark: ProposalMark? = .byAssistant
    var onUndo: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let mark { ProposalMarkLabel(mark: mark) }
            if !reply.isEmpty {
                Text("„\(reply)“").font(.caption).foregroundStyle(.purpleText)
            }
            if let onUndo {
                Button("Rückgängig", action: onUndo).buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
