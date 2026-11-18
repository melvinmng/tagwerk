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

    private var conversation: Conversation? { assistant.conversation }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextChip
                messages
                composer
            }
            .navigationTitle("ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { setUpVoice() }
            .onDisappear {
                voice?.cancel()
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
        VoiceAvailability.recognitionLanguage(setting: environment.settings.voiceRecognitionLanguage)
    }

    private func setUpVoice() {
        guard voice == nil else { return }
        let model = VoiceInputFactory.make(environment)
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.vertical, 6)
            .accessibilityLabel("Kontext: \(contextText)")
    }

    private var contextText: String {
        switch assistant.context {
        case .planning(let scope, _):
            let days = environment.planning.days
            guard let first = days.first?.day, let last = days.last?.day else { return "Planen" }
            let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
            let range = first == last ? first.startDate(in: environment.planning.calendar).formatted(format)
                : "\(first.startDate(in: environment.planning.calendar).formatted(format))–\(last.startDate(in: environment.planning.calendar).formatted(format))"
            return "Kontext: \(AIPlanBar.actionName(scope)) \(range)"
        case .tasks: return "Kontext: Aufgaben"
        case .settings: return "Kontext: allgemein"
        case .capture: return "Kontext: Erfassen"
        case .task: return "Kontext: \(assistant.task?.title ?? "Aufgabe")"
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if conversation?.truncatedNotice == true {
                        Text("Ältere Nachrichten werden nicht mehr mitgeschickt.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if !environment.ai.isSignedIn {
                        Label("Melde dich in Einstellungen › KI mit ChatGPT an, um den Assistenten zu nutzen.",
                              systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if conversation?.history.isEmpty != false {
                        Text("Frag nach deinem Tag, deinen Aufgaben oder bitte um Änderungen. Änderungen führt Tagwerk erst aus, wenn du sie bestätigst.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(conversation?.messages ?? []) { message in
                        row(message).id(message.id)
                    }
                    if let text = conversation?.streamingText, !text.isEmpty {
                        Text(text).frame(maxWidth: .infinity, alignment: .leading).id("streaming")
                    } else if conversation?.state == .streaming {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading).id("streaming")
                    }
                    if case .failed(let error) = conversation?.state {
                        HStack {
                            Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Spacer()
                            Button("Erneut versuchen") { Task { await assistant.retry() } }
                        }
                        .font(.subheadline)
                    }
                    if conversation?.roundLimitReached == true {
                        Text("Der Assistent hat zu viele Schritte gebraucht und angehalten. Formuliere die Bitte genauer.")
                            .font(.caption).foregroundStyle(.secondary)
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
                    Label("gesprochen", systemImage: "mic.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let text):
            VStack(alignment: .leading, spacing: 6) {
                SpokenAnswerText(id: "message-\(message.id)", text: text).textSelection(.enabled)
                ReadAloudButton(id: "message-\(message.id)", text: text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .action(let call, let status):
            ActionCardView(card: assistant.describe(call), status: status, time: assistant.actionTimes[call.id],
                           onConfirm: { Task { await assistant.confirm(call) } },
                           onDecline: { Task { await assistant.decline(call) } })
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let pending = conversation?.pendingActions, pending.count > 1 {
                Button {
                    Task { await assistant.confirmAll() }
                } label: {
                    Text("Alle bestätigen (\(pending.count))").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(card.title).font(.subheadline.weight(.semibold))
            Text(card.change).font(.subheadline).foregroundStyle(.secondary)
            if case .done(let output) = status, let error = Self.error(in: output) {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if status == .pending {
                HStack {
                    Button("Verwerfen", action: onDecline).buttonStyle(.bordered)
                    Spacer()
                    Button("Bestätigen", action: onConfirm).buttonStyle(.borderedProminent)
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
            Text("Vorgeschlagene Änderung · noch nicht ausgeführt").font(.caption).foregroundStyle(.purple)
        case .running:
            HStack(spacing: 6) { ProgressView(); Text("Wird ausgeführt …").font(.caption).foregroundStyle(.secondary) }
        case .done(let output):
            if Self.error(in: output) != nil {
                Text("Nicht ausgeführt").font(.caption).foregroundStyle(.orange)
            } else {
                Text("✓ Ausgeführt" + (time.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    .font(.caption).foregroundStyle(.green)
            }
        case .declined:
            Text("Verworfen").font(.caption).foregroundStyle(.secondary)
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
