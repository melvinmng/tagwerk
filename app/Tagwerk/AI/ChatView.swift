import AIKit
import SwiftUI
import TagwerkCore

/// The assistant chat sheet (mockup e): context chip, messages, action cards that run only after
/// "Bestätigen", composer. Errors are rows with "Erneut versuchen", not dialogs.
struct ChatView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let assistant: AssistantModel
    @State private var draft = ""
    @State private var askingClear = false
    @State private var voice: VoiceInputModel?
    @FocusState private var composing: Bool
    /// Sheet height; the voice mode uses half height so the calendar stays visible (SP5a).
    @State private var detent: PresentationDetent = .large
    @State private var explainingVoiceMode = false

    private var conversation: Conversation? { assistant.conversation }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if voiceModeRunning {
                    if detent == .large { messages }
                    VoiceModePanel(assistant: assistant, contextText: contextText, showsExchange: detent != .large,
                                   onShowHistory: { detent = .large })
                        .background(.bar)
                } else {
                    contextChip
                    messages
                    composer
                }
            }
            .presentationDetents(voiceModeRunning ? [.medium, .large] : [.large], selection: $detent)
            .presentationBackgroundInteraction(voiceModeRunning ? .enabled(upThrough: .medium) : .disabled)
            .navigationTitle("ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { setUpVoice() }
            .onDisappear {
                voice?.cancel()
                environment.voiceMode.end()
                environment.voiceOutput.stop()
            }
            .onChange(of: draft) { _, text in if text.isEmpty { voice?.draftConsumed() } }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("ChatGPT", systemImage: "sparkles").labelStyle(.titleAndIcon).font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Verlauf löschen", role: .destructive) { askingClear = true }
                            .disabled(assistant.conversation?.isBusy == true)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Mehr")
                }
            }
            .confirmationDialog("Verlauf löschen?", isPresented: $askingClear, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) { assistant.clear() }
            }
        }
    }

    // MARK: Voice

    private var showsMicrophone: Bool { environment.settings.voiceInputEnabled }
    private var canSend: Bool { conversation?.isBusy != true && environment.ai.isSignedIn }
    private var recognitionLanguage: VoiceLanguage {
        environment.settings.dictationLanguage(at: .chat)
    }

    private var voiceModeRunning: Bool { environment.voiceMode.isRunning }
    /// The send button turns into the voice mode entry while the field is empty (SP5 Einstieg).
    private var offersVoiceMode: Bool {
        showsMicrophone && environment.ai.isSignedIn && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestVoiceMode() {
        if environment.settings.voiceModeExplained { startVoiceMode() } else { explainingVoiceMode = true }
    }

    private func startVoiceMode() {
        explainingVoiceMode = false
        environment.settings.voiceModeExplained = true
        voice?.cancel()
        composing = false
        let mode = environment.voiceMode
        mode.onMoveToDraft = { text in draft = draft.isEmpty ? text : draft + " " + text }
        mode.onEnded = { detent = .large }
        detent = .medium
        mode.start()
    }

    private func setUpVoice() {
        guard voice == nil else { return }
        let model = VoiceInputFactory.make(environment, place: .chat)
        model.readDraft = { draft }
        model.writeDraft = { draft = $0 }
        model.onSend = { text in
            environment.voiceOutput.stop()
            Task { await assistant.send(text, spoken: true) }
        }
        voice = model
    }

    // MARK: Parts

    private var contextChip: some View {
        Label(contextText, systemImage: "scope")
            .font(.caption)
            .foregroundStyle(.secondaryText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.vertical, 6)
            .accessibilityLabel("Kontext: \(contextText)")
    }

    private var contextText: String {
        switch assistant.context {
        case .planning(let scope, _):
            let days = environment.planning.days
            guard let first = days.first?.day, let last = days.last?.day else { return String(localized: "Planen") }
            let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
            let range = first == last ? first.startDate(in: environment.planning.calendar).formatted(format)
                : "\(first.startDate(in: environment.planning.calendar).formatted(format))–\(last.startDate(in: environment.planning.calendar).formatted(format))"
            return String(localized: "Kontext: \(AIPlanBar.actionName(scope)) \(range)")
        case .tasks: return String(localized: "Kontext: Aufgaben")
        case .settings: return String(localized: "Kontext: allgemein")
        case .capture: return String(localized: "Kontext: Erfassen")
        case .task: return assistant.task.map { String(localized: "Kontext: \($0.title)") } ?? String(localized: "Kontext: Aufgabe")
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if conversation?.truncatedNotice == true {
                        Text("Ältere Nachrichten werden nicht mehr mitgeschickt.")
                            .font(.caption).foregroundStyle(.secondaryText).frame(maxWidth: .infinity)
                    }
                    if !environment.ai.isSignedIn {
                        Label("Melde dich in Einstellungen › KI mit ChatGPT an, um den Assistenten zu nutzen.",
                              systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.subheadline).foregroundStyle(.secondaryText)
                    } else if conversation?.history.isEmpty != false {
                        Text("Frag nach deinem Tag, deinen Aufgaben oder bitte um Änderungen. Änderungen führt Tagwerk erst aus, wenn du sie bestätigst.")
                            .font(.subheadline).foregroundStyle(.secondaryText)
                    }
                    ForEach(conversation?.messages ?? []) { message in
                        row(message).id(message.id)
                    }
                    if let text = conversation?.streamingText, !text.isEmpty {
                        // The same blocks as the finished message, so the answer does not change its look when it ends.
                        ChatMarkdownView(text: text).id("streaming")
                    } else if conversation?.state == .streaming {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading).id("streaming")
                    }
                    if case .failed(let error) = conversation?.state {
                        HStack {
                            Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orangeText)
                            Spacer()
                            Button("Erneut versuchen") { Task { await assistant.retry() } }
                        }
                        .font(.subheadline)
                    }
                    if conversation?.roundLimitReached == true {
                        Text("Der Assistent hat zu viele Schritte gebraucht und angehalten. Formuliere die Bitte genauer.")
                            .font(.caption).foregroundStyle(.secondaryText)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal)
            }
            .onChange(of: conversation?.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: conversation?.streamingText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func row(_ message: ChatMessage) -> some View {
        switch message.content {
        case .user(let text):
            VStack(alignment: .trailing, spacing: 2) {
                Text(text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                if assistant.isSpoken(message) {
                    Label("gesprochen", systemImage: "mic.fill").font(.caption2).foregroundStyle(.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let text):
            VStack(alignment: .leading, spacing: 6) {
                SpokenAnswerText(id: "message-\(message.id)", text: text).textSelection(.enabled)
                HStack(spacing: 8) {
                    ReadAloudButton(id: "message-\(message.id)", text: text)
                    CopyAnswerButton(text: text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .action(let call, let status):
            ActionCardView(card: assistant.describe(call), status: status, time: assistant.actionTimes[call.id],
                           onConfirm: { Task { await assistant.confirm(call) } },
                           onDecline: { Task { await assistant.decline(call) } })
        case .activity(let call, let output):
            // A read call the user should see ("Gelesen: „Titel“"); small and grey, not an answer.
            if let text = assistant.activityText(call, output: output) {
                Label(text, systemImage: "doc.text").font(.caption).foregroundStyle(.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let pending = conversation?.pendingActions, pending.count > 1 {
                // Guarded cards (assignments) are confirmed one by one and are not part of the count.
                let batch = assistant.batchConfirmable.count
                if batch > 1 {
                    Button {
                        Task { await assistant.confirmAll() }
                    } label: {
                        Text("Alle bestätigen (\(batch))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let notice = AssistantModel.singleConfirmationNotice(for: pending, me: assistant.gitHubDirectory()?.login) {
                    Text(notice).font(.footnote).foregroundStyle(.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if explainingVoiceMode {
                VoiceModeExplanation(onStart: startVoiceMode, onCancel: { explainingVoiceMode = false })
            }
            if let voice { VoiceNoticeRow(voice: voice) }
            if let voice, voice.isRecording {
                VoiceRecordingBar(voice: voice, canSend: canSend)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Nachricht …", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composing)
                        .padding(.leading, 12).padding(.trailing, showsMicrophone ? 36 : 12).padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .bottomTrailing) {
                            if showsMicrophone, let voice {
                                VoiceMicrophoneButton(voice: voice, isEnabled: environment.ai.isSignedIn, language: recognitionLanguage)
                                    .offset(x: 2, y: 4)
                            }
                        }
                    if offersVoiceMode {
                        Button(action: requestVoiceMode) {
                            Image(systemName: "waveform.circle.fill").font(.title)
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Sprechmodus starten")
                    } else {
                        Button {
                            let text = draft
                            let spoken = voice?.draftIsSpoken ?? false
                            draft = ""
                            voice?.draftConsumed()
                            environment.voiceOutput.stop()
                            Task { await assistant.send(text, spoken: spoken) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canSend)
                        .accessibilityLabel("Senden")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .keepsKeyboardOnTap()
    }
}

/// An action card (mockup e): "Vorgeschlagene Änderung · noch nicht ausgeführt" with "Verwerfen" and
/// "Bestätigen"; afterwards a record "✓ Ausgeführt · 09:38" or the error.
struct ActionCardView: View {
    let card: AssistantModel.ActionCard
    let status: ChatMessage.ActionStatus
    let time: Date?
    let onConfirm: () -> Void
    let onDecline: () -> Void
    /// False while the card lacks something the user has to choose first: "Bestätigen" is then disabled.
    var canConfirm = true
    /// A row below the change text, e.g. the target of an issue suggested from a note.
    var accessory: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(card.title).font(.subheadline.weight(.semibold))
            Text(card.change).font(.subheadline).foregroundStyle(.secondaryText)
            if let accessory { accessory }
            if let warning = card.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.redText)
            }
            if case .done(let output) = status, let error = Self.error(in: output) {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orangeText)
            }
            if status == .pending {
                HStack {
                    Button("Verwerfen", action: onDecline).buttonStyle(.bordered)
                    Spacer()
                    Button(role: card.isDestructive ? .destructive : nil, action: onConfirm) {
                        Text(card.confirmTitle ?? String(localized: "Bestätigen"))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(card.isDestructive ? .red : nil)
                    .disabled(!canConfirm)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if status == .pending {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch status {
        case .pending:
            Text("Vorgeschlagene Änderung · noch nicht ausgeführt").font(.caption).foregroundStyle(.purpleText)
        case .running:
            HStack(spacing: 6) { ProgressView(); Text("Wird ausgeführt …").font(.caption).foregroundStyle(.secondaryText) }
        case .done(let output):
            if Self.error(in: output) != nil {
                Text("Nicht ausgeführt").font(.caption).foregroundStyle(.orangeText)
            } else {
                Text(time.map { String(localized: "✓ Ausgeführt · \($0.formatted(date: .omitted, time: .shortened))") } ?? String(localized: "✓ Ausgeführt"))
                    .font(.caption).foregroundStyle(.greenText)
            }
        case .declined:
            Text("Verworfen").font(.caption).foregroundStyle(.secondaryText)
        }
    }

    /// The `error` of a function output, if it reports one.
    static func error(in output: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return nil }
        if let error = json["error"] as? String { return error }
        if json["status"] as? String == "not_run" { return json["message"] as? String }
        return nil
    }
}
