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
    /// The note card whose proposal is shown in `NoteChangeSheet`.
    @State private var noteDetail: NoteDetailRequest?
    /// The card whose sheet "Vorschlag anpassen" is open; set by "Anpassen" on a card with an editor.
    @State private var adjusting: ToolCall?

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
            // Nothing left to revise: the reference of the next message goes away with the cards.
            .onChange(of: conversation?.pendingActions.isEmpty) { _, isEmpty in if isEmpty == true { assistant.composesRevision = false } }
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
            .sheet(item: $adjusting) { call in
                ProposalAdjustSheet(assistant: assistant, call: call)
            }
            .sheet(item: $noteDetail) { request in
                if let detail = request.card.detail {
                    NoteChangeSheet(card: request.card, detail: detail,
                                    onDecline: { Task { await assistant.decline(request.call) } },
                                    onConfirm: { Task { await assistant.confirm(request.call) } })
                }
            }
        }
        // A sheet does not take the forced text size of the UI test mode from the window; no effect outside that mode.
        .modifier(UITestAppearance())
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
        Label(contextText, systemImage: isNotesContext ? "lock" : "scope")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.vertical, 6)
            .accessibilityLabel(Self.contextAccessibilityLabel(for: contextText))
    }

    /// The chip text already starts with "Kontext:" in most contexts; only the bare planning text lacks it.
    /// Prefixing blindly made VoiceOver read "Kontext: Kontext: …".
    static func contextAccessibilityLabel(for text: String) -> String {
        // Reuses the "Kontext: %@" key, so the prefix follows the language and no extra catalog entry is needed.
        let prefix = String(localized: "Kontext: \("")")
        return text.hasPrefix(prefix) ? text : String(localized: "Kontext: \(text)")
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
        case .notes(let folderID):
            // The line says what stays out, so the user sees why the assistant does not find the private folders.
            let excluded = NoteToolAccess.listText(assistant.privateFolderNames)
            if let folderID, let name = assistant.noteFolderName(folderID) {
                return String(localized: "Kontext: Notizen in „\(name)“ · ohne \(excluded)")
            }
            return String(localized: "Kontext: Notizen · ohne \(excluded)")
        case .note(let id):
            let excluded = NoteToolAccess.listText(assistant.privateFolderNames)
            guard let title = assistant.noteTitle(id) else { return String(localized: "Kontext: Notizen · ohne \(excluded)") }
            return String(localized: "Kontext: Notiz „\(title)“ · ohne \(excluded)")
        }
    }

    private var isNotesContext: Bool {
        switch assistant.context {
        case .notes, .note: true
        default: false
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
                        if isNotesContext {
                            Text("Frag nach deinen Notizen oder bitte um Änderungen. Jede Änderung bestätigst du einzeln.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Frag nach deinem Tag, deinen Aufgaben oder bitte um Änderungen. Änderungen führt Tagwerk erst aus, wenn du sie bestätigst.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

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
                HStack(spacing: 8) {
                    ReadAloudButton(id: "message-\(message.id)", text: text)
                    CopyAnswerButton(text: text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .action(let call, let status):
            let card = assistant.describe(call, isOpen: status == .pending)
            ActionCardView(card: card, status: status, time: assistant.actionTimes[call.id],
                           onConfirm: { Task { await assistant.confirm(call) } },
                           onDecline: { Task { await assistant.decline(call) } },
                           proposal: proposalPosition(of: call),
                           onShowDetail: card.detail == nil ? nil : { noteDetail = NoteDetailRequest(call: call, card: card) },
                           onAdjust: status == .pending && card.canAdjust ? { adjusting = call } : nil)
        case .activity(let call, let output):
            // A read call the user should see ("Gelesen: „Titel“"); small and grey, not an answer.
            if let text = assistant.activityText(call, output: output) {
                Label(text, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "Vorschlag i von n" while several note cards are open; `nil` for one card and for other cards.
    private func proposalPosition(of call: ToolCall) -> (index: Int, count: Int)? {
        let open = (conversation?.pendingActions ?? []).filter { NoteChatTools.noteWriteTools.contains($0.name) }
        guard open.count > 1, let index = open.firstIndex(where: { $0.id == call.id }) else { return nil }
        return (index + 1, open.count)
    }

    /// "Alle anpassen …": the next message goes out together with the state of all open cards (AN5a).
    private func reviseAllButton(count: Int) -> some View {
        Button {
            assistant.composesRevision = true
            composing = true
        } label: {
            Text("Alle anpassen …").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!canSend)
    }

    private func confirmAllButton(_ batch: Int) -> some View {
        Button {
            Task { await assistant.confirmAll() }
        } label: {
            Text("Alle bestätigen (\(batch))").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    /// The reference of the next message, above the input: "Zu allen 3 Vorschlägen ✕", with what "Senden" sends below.
    private func revisionChip(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(count == 1 ? String(localized: "Zum offenen Vorschlag") : String(localized: "Zu allen \(count) Vorschlägen"))
                    .font(.caption.weight(.semibold))
                Button { assistant.composesRevision = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bezug entfernen")
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.purple.opacity(0.15), in: Capsule())
            Text("Senden gibt die offenen Vorschläge mit deinen Änderungen an ChatGPT; es legt sie überarbeitet neu vor.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let pending = conversation?.pendingActions, !pending.isEmpty {
                // Guarded cards (assignments) are confirmed one by one and are not part of the count.
                let batch = assistant.batchConfirmable.count
                let confirmsAll = pending.count > 1 && batch > 1
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        reviseAllButton(count: pending.count)
                        if confirmsAll { confirmAllButton(batch) }
                    }
                    VStack(spacing: 8) {
                        reviseAllButton(count: pending.count)
                        if confirmsAll { confirmAllButton(batch) }
                    }
                }
                // As before: the note under the buttons names the cards that are confirmed alone, from two open cards on.
                if pending.count > 1,
                   let notice = AssistantModel.singleConfirmationNotice(for: pending, me: assistant.gitHubDirectory()?.login) {
                    Text(notice).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if assistant.composesRevision, let pending = conversation?.pendingActions, !pending.isEmpty {
                revisionChip(count: pending.count)
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
    /// The place of a note card among several open ones: "Vorschlag 2 von 3 · noch nicht ausgeführt".
    var proposal: (index: Int, count: Int)? = nil
    /// Opens the sheet "Änderung ansehen"; `nil` for cards without a proposal to look at.
    var onShowDetail: (() -> Void)? = nil
    /// Opens the sheet "Vorschlag anpassen"; `nil` for cards without an editor (no third button, AN11a).
    var onAdjust: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(card.title).font(.subheadline.weight(.semibold))
            if let mark = card.mark, status == .pending { ProposalMarkLabel(mark: mark) }
            changeText
            if let accessory { accessory }
            if let onShowDetail {
                Button(action: onShowDetail) {
                    Label(detailTitle, systemImage: "doc.text.magnifyingglass").font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
            if let warning = card.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            if case .done(let output) = status, let error = Self.error(in: output) {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if status == .pending { buttons }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if status == .pending {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.purple, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .accessibilityActions {
            if status == .pending, let onAdjust { Button("Anpassen", action: onAdjust) }
        }
    }

    /// What the card changes. An adjusted card shows the old value of each changed part struck through before the new one
    /// (AN2a); when the two texts do not have the same parts, the whole proposal of the model follows below.
    @ViewBuilder
    private var changeText: some View {
        if let proposed = card.proposedChange, status == .pending {
            if let parts = ProposalChangeText.parts(current: card.change, proposed: proposed) {
                Text(ProposalChangeText.attributed(parts)).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(Text(ProposalChangeText.spoken(parts)))
            } else {
                Text(card.change).font(.subheadline).foregroundStyle(.secondary)
                Text("Vorschlag der KI: \(proposed)").font(.caption).foregroundStyle(.secondary).strikethrough()
                    .accessibilityLabel(Text("Vorschlag der KI: \(proposed)"))
            }
        } else {
            Text(card.change).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// "Verwerfen", "Bestätigen" and, for a card with an editor, "Anpassen" in between. With large text the three
    /// buttons do not fit in a row: "Bestätigen" then gets its own full-width row below the other two.
    @ViewBuilder
    private var buttons: some View {
        if let onAdjust {
            ViewThatFits(in: .horizontal) {
                HStack {
                    declineButton
                    Spacer()
                    adjustButton(onAdjust)
                    confirmButton
                }
                VStack(spacing: 8) {
                    HStack {
                        declineButton
                        Spacer()
                        adjustButton(onAdjust)
                    }
                    confirmButton.frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack {
                declineButton
                Spacer()
                confirmButton
            }
        }
    }

    private var declineButton: some View {
        Button("Verwerfen", action: onDecline).buttonStyle(.bordered)
    }

    private func adjustButton(_ action: @escaping () -> Void) -> some View {
        Button("Anpassen", action: action).buttonStyle(.bordered)
    }

    private var confirmButton: some View {
        Button(role: card.isDestructive ? .destructive : nil, action: onConfirm) {
            Text(card.confirmTitle ?? String(localized: "Bestätigen"))
        }
        .buttonStyle(.borderedProminent)
        .tint(card.isDestructive ? .red : nil)
        .disabled(!canConfirm)
    }

    @ViewBuilder
    private var header: some View {
        switch status {
        case .pending:
            if let proposal {
                Text("Vorschlag \(proposal.index) von \(proposal.count) · noch nicht ausgeführt").font(.caption).foregroundStyle(.purple)
            } else {
                Text("Vorgeschlagene Änderung · noch nicht ausgeführt").font(.caption).foregroundStyle(.purple)
            }
        case .running:
            HStack(spacing: 6) { ProgressView(); Text("Wird ausgeführt …").font(.caption).foregroundStyle(.secondary) }
        case .done(let output):
            if Self.error(in: output) != nil {
                Text("Nicht ausgeführt").font(.caption).foregroundStyle(.orange)
            } else {
                let done = time.map { String(localized: "✓ Ausgeführt · \($0.formatted(date: .omitted, time: .shortened))") } ?? String(localized: "✓ Ausgeführt")
                Text(card.doneNote.map { done + " · " + $0 } ?? done).font(.caption).foregroundStyle(.green)
            }
        case .declined:
            Text("Verworfen").font(.caption).foregroundStyle(.secondary)
        case .revised:
            Text("Überarbeitet").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "Notiz ansehen" for a new note and a deletion, "Änderung ansehen" for a revision.
    private var detailTitle: LocalizedStringKey {
        if case .update = card.detail { return "Änderung ansehen" }
        return "Notiz ansehen"
    }

    /// The `error` of a function output, if it reports one.
    static func error(in output: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return nil }
        if let error = json["error"] as? String { return error }
        if json["status"] as? String == "not_run" { return json["message"] as? String }
        return nil
    }
}
