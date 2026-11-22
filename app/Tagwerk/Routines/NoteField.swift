import Foundation
import Observation
import SwiftUI
import TagwerkCore

/// The brain dump of the morning start and the evening wrap-up (phase 7 design §7.6) and the dream log of the morning
/// start: one note per day and kind in the shared `NoteRecord` store. Text is saved while typing (debounced) and when the sheet closes, before anything could be sent.
@MainActor
@Observable
final class NoteFieldModel {
    var text: String
    var selection: TextSelection?
    private(set) var noteID: UUID?
    private(set) var wasDictated: Bool

    let kind: NoteKind
    let day: PlanDay
    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let isSignedIn: () -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// What the store holds (trimmed), so an unchanged text is not written again.
    @ObservationIgnored private var savedText: String
    /// Text behind the cursor while a recording runs, and the text before the recording.
    @ObservationIgnored private var dictationTail = ""
    @ObservationIgnored private var dictationBase = ""
    @ObservationIgnored private var wasDictatedBeforeRecording = false

    init(store: NoteStore, kind: NoteKind, day: PlanDay, debounce: Duration = .milliseconds(500),
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         isSignedIn: @escaping () -> Bool = { false }, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        precondition(kind == .morning || kind == .evening || kind == .dream)
        self.isSignedIn = isSignedIn
        self.now = now
        self.calendar = calendar
        self.store = store
        self.kind = kind
        self.day = day
        self.debounce = debounce
        self.sleep = sleep
        let note = store.note(kind: kind, dayKey: day.dayKey)
        text = note?.text ?? ""
        noteID = note?.id
        wasDictated = note?.wasDictated ?? false
        savedText = note?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Saving

    /// Call after each change of `text`; saves after the debounce.
    func textChanged() {
        pendingSave?.cancel()
        let sleep = self.sleep, debounce = self.debounce
        pendingSave = Task { [weak self] in
            await sleep(debounce)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    /// Saves at once; called when the sheet closes.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        persist()
    }

    /// Waits for the scheduled save; tests use it instead of timing.
    func waitForSave() async { await pendingSave?.value }

    private func persist() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedText else { return }
        let record = store.saveThought(text, kind: kind, dayKey: day.dayKey, wasDictated: wasDictated)
        noteID = record?.id
        savedText = record == nil ? "" : trimmed
    }

    // MARK: Dictation

    /// The text before the cursor (the whole text without a selection); dictation continues after it.
    func draftBeforeCursor() -> String {
        let cursor = cursorIndex()
        dictationTail = String(text[cursor...])
        dictationBase = String(text[..<cursor])
        wasDictatedBeforeRecording = wasDictated
        return dictationBase
    }

    /// The recognizer's current draft (text before the cursor plus what was said); the text behind the cursor is put
    /// back after it, so speaking in the middle of a note does not swallow the rest.
    func writeDictation(_ draft: String) {
        let tail = dictationTail
        if tail.isEmpty {
            text = draft
        } else if draft.isEmpty {
            text = tail
        } else {
            let separator = tail.first?.isNewline == true ? "" : " "
            text = draft.trimmingCharacters(in: .whitespaces) + separator + tail
        }
        // A cancelled recording writes the original draft back: the note was not dictated then.
        wasDictated = draft == dictationBase ? wasDictatedBeforeRecording : true
        textChanged()
    }

    private func cursorIndex() -> String.Index {
        guard let selection, case .selection(let range) = selection.indices,
              range.lowerBound <= text.endIndex else { return text.endIndex }
        return range.lowerBound
    }

    // MARK: Guiding questions

    /// "Leitfragen einfügen" is offered until the first question is in the text, in either language (the questions stay
    /// as they were inserted when the app language changes later).
    var offersGuidingQuestions: Bool {
        kind != .dream && !VoiceLanguage.allCases.contains { NoteTemplate.containsGuidingQuestions(text, locale: $0.locale) }
    }

    /// Appends the eight questions in the app language; the text stays an ordinary note.
    func insertGuidingQuestions(locale: Locale = .current) {
        text = NoteTemplate.appendingGuidingQuestions(to: text, locale: locale)
        selection = nil
        textChanged()
    }

    // MARK: Suggestions

    /// "Vorschläge holen" is offered with a ChatGPT sign-in, text, and only for the day the sheet belongs to now: the
    /// context of the request starts today and does not fit an older note (evening notes count until 03:59 for the day
    /// before, rule 10).
    var canSuggest: Bool {
        kind.allowsSuggestions && isSignedIn() && taskTitle != nil && day == RoutineSchedule.routineDay(at: now(), calendar: calendar)
    }

    // MARK: Tasks from the note

    /// The first non-empty line, for "Als Aufgabe anlegen"; `nil` for an empty note.
    var taskTitle: String? {
        let title = NoteText.title(text)
        return title.isEmpty ? nil : title
    }

    /// A task was created by hand from this note ("2 Aufgaben daraus").
    func taskCreated() {
        flush()
        if let noteID { store.addDerivedAction(noteID) }
    }
}

/// The section "Brain Dump" of both sheets (a multi-line field with a microphone and "Als Aufgabe anlegen") or, for the
/// dream log of the morning start, a plain field with a microphone that is never sent anywhere.
struct NoteField: View {
    let model: NoteFieldModel
    @Environment(AppEnvironment.self) private var environment
    @State private var voice: VoiceInputModel?
    @State private var creatingTask = false
    @State private var suggestions: NoteSuggestionModel?
    @State private var asksConsent = false
    /// The issue card whose target is being chosen.
    @State private var targetCardID: String?
    /// The card whose sheet "Vorschlag anpassen" is open.
    @State private var adjustingCardID: String?
    @FocusState private var followUpFocused: Bool

    private var isDreamLog: Bool { model.kind == .dream }

    var body: some View {
        Section {
            // One row, so the lifecycle and the sheet below attach once and not to every row of the section.
            VStack(alignment: .leading, spacing: 8) {
                if let voice { VoiceNoticeRow(voice: voice) }
                if let voice, voice.isRecording {
                    // The arrow stays off: dictation only fills the field, nothing is sent from here.
                    VoiceRecordingBar(voice: voice, canSend: false)
                } else {
                    HStack(alignment: .top, spacing: 4) {
                        TextEditor(text: Bindable(model).text, selection: Bindable(model).selection)
                            .keyboardDoneButton()
                            .frame(minHeight: 110)
                            .accessibilityLabel(isDreamLog ? "Was hast du geträumt?" : "Brain Dump")
                            .overlay(alignment: .topLeading) {
                                if model.text.isEmpty {
                                    Text(isDreamLog ? "Was hast du geträumt?" : "Schreib auf, was in deinen Kopf kommt. Sortier deine Gedanken.")
                                        .foregroundStyle(.secondaryText).padding(.top, 8).padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                        if environment.settings.voiceInputEnabled, let voice {
                            VoiceMicrophoneButton(voice: voice, isEnabled: true,
                                                  language: environment.settings.dictationLanguage(at: .notes))
                        }
                    }
                }
                if !isDreamLog, model.taskTitle != nil {
                    Button { creatingTask = true } label: { Label("Als Aufgabe anlegen", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                    suggestionButton
                }
            }
            .onChange(of: model.text) { _, _ in
                model.textChanged()
                // Cards belong to the text they came from.
                if let suggestions, suggestions.phase != .idle { suggestions.reset() }
            }
            .onAppear(perform: prepareVoice)
            // A row of a form can scroll out of sight without the sheet closing, so only the text is saved here.
            .onDisappear { model.flush() }
            .onChange(of: environment.routines.sheet) { _, sheet in
                guard sheet == nil else { return }
                // The sheet closed: a recording ends, open cards expire and no answer may arrive for it later.
                voice?.cancel()
                model.flush()
                suggestions?.reset()
            }
            .sheet(isPresented: $creatingTask) {
                NewTaskSheet(model: environment.taskList, prefilledTitle: model.taskTitle, onCreated: { model.taskCreated() })
            }
            .sheet(item: Binding(get: { targetCardID.map(TargetRequest.init) }, set: { targetCardID = $0?.id })) { request in
                if let suggestions, let sheet = suggestions.targetSheetModel(for: request.id) {
                    IssueTargetSheet(model: sheet) { repository, projectIDs, assignees in
                        suggestions.setTarget(request.id, repository: repository, projectIDs: projectIDs, assignees: assignees)
                    }
                }
            }
            .sheet(item: Binding(get: { adjustingCardID.map(TargetRequest.init) }, set: { adjustingCardID = $0?.id })) { request in
                if let suggestions, let card = suggestions.cards.first(where: { $0.id == request.id }) {
                    ProposalAdjustSheet(assistant: suggestions, call: card.call)
                }
            }
            .sheet(isPresented: $asksConsent) {
                NoteConsentSheet(
                    onAgree: {
                        environment.settings.noteSuggestionConsent = true
                        asksConsent = false
                        fetchSuggestions()
                    },
                    onDecline: { asksConsent = false })
            }
        } header: {
            HStack {
                Text(isDreamLog ? "Dream Log" : "Brain Dump")
                Spacer()
                if model.offersGuidingQuestions {
                    Button("Leitfragen einfügen") { model.insertGuidingQuestions() }.textCase(nil)
                }
            }
        } footer: {
            if isDreamLog {
                Text("Der Dream Log bleibt auf diesem iPhone und wird nie an ChatGPT gesendet.")
            }
        }
        if !isDreamLog, let suggestions { suggestionSection(suggestions) }
    }

    // MARK: Suggestions

    /// "✦ Vorschläge holen" with the sign-in; for an older day or without a sign-in it is not offered.
    @ViewBuilder
    private var suggestionButton: some View {
        if environment.ai.isSignedIn {
            if model.canSuggest {
                Button {
                    if environment.settings.noteSuggestionConsent { fetchSuggestions() } else { asksConsent = true }
                } label: {
                    Label("Vorschläge holen", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(suggestions?.phase == .loading)
                Text(suggestionFooter).font(.footnote).foregroundStyle(.secondaryText)
            }
        } else {
            Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Vorschläge zu holen.")
                .font(.footnote).foregroundStyle(.secondaryText)
        }
    }

    /// The evening wrap-up adds the invitation to check the brain dump against the next seven days; the sentence about
    /// sending the note to ChatGPT stays in both sheets.
    private var suggestionFooter: String {
        let sending = String(localized: "„Vorschläge holen“ sendet diese Notiz an ChatGPT. Nichts wird ohne deine Bestätigung geändert.")
        guard model.kind == .evening else { return sending }
        let invitation = String(localized: "Willst du etwas ändern? Vielleicht hat dir der Brain Dump Klarheit gegeben. „Vorschläge holen“ prüft ihn gegen deine Aufgaben und Termine der nächsten 7 Tage.")
        return invitation + " " + sending
    }

    @ViewBuilder
    private func suggestionSection(_ suggestions: NoteSuggestionModel) -> some View {
        switch suggestions.phase {
        case .idle:
            EmptyView()
        case .loading:
            Section { HStack(spacing: 8) { ProgressView(); Text("Vorschläge werden geholt …").foregroundStyle(.secondaryText) } }
        case .empty:
            Section { Text("Keine Vorschläge aus dieser Notiz.").foregroundStyle(.secondaryText) }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orangeText)
                Button("Erneut versuchen", action: fetchSuggestions)
            }
        case .loaded:
            Section {
                ForEach(suggestions.cards) { card in
                    ActionCardView(card: card.text, status: card.status, time: card.time,
                                   onConfirm: { Task { await suggestions.confirm(card.id) } },
                                   onDecline: { suggestions.decline(card.id) },
                                   canConfirm: !card.needsTarget,
                                   accessory: targetRow(card, in: suggestions),
                                   onAdjust: card.status == .pending && card.text.canAdjust ? { adjustingCardID = card.id } : nil)
                }
                // Cards that wait for a target are not part of it (review focus 10).
                if suggestions.confirmableCount > 1 {
                    Button { Task { await suggestions.confirmAll() } } label: {
                        Text("Alle bestätigen (\(suggestions.confirmableCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let notice = suggestions.singleConfirmationNotice {
                    Text(notice).font(.footnote).foregroundStyle(.secondaryText)
                }
            } header: {
                Text("\(suggestions.cards.count) Vorschläge aus der Notiz")
            }
            if suggestions.openCount > 0 { followUpSection(suggestions) }
        }
    }

    /// The line to write to ChatGPT about the open cards (task C2): a second request with the note, the open cards as they are
    /// now and the message. Only with the consent of the suggestions and a ChatGPT sign-in; without them the cards can still be
    /// adjusted by hand.
    private func followUpSection(_ suggestions: NoteSuggestionModel) -> some View {
        let availability = FollowUpAvailability.state(hasConsent: environment.settings.noteSuggestionConsent,
                                                      isSignedIn: environment.ai.isSignedIn, isOffline: false)
        return Section {
            FollowUpBar(availability: availability, state: suggestions.followUpState, place: .notes,
                        quickReplies: NoteSuggestionModel.quickReplies, placeholder: "Zu den Vorschlägen etwas sagen …",
                        footer: Text("Senden gibt diese Notiz, die offenen Vorschläge mit deinen Änderungen und deine Nachricht an ChatGPT."),
                        isFocused: $followUpFocused, onSend: { reviseSuggestions($0) },
                        onRetry: { reviseSuggestions(suggestions.followUpLastMessage) }) {
                if !suggestions.followUpReply.isEmpty {
                    FollowUpAnswerRow(reply: suggestions.followUpReply, mark: nil,
                                      onUndo: suggestions.canUndoRevision ? { suggestions.undoRevision() } : nil)
                }
            }
        } header: {
            if availability != .hidden { Label("Mit ChatGPT besprechen", systemImage: "sparkles") }
        }
    }

    /// Saves the note first, so the text that is sent is the text that is stored.
    private func reviseSuggestions(_ message: String) {
        guard let suggestions else { return }
        model.flush()
        guard let noteID = model.noteID else { return }
        let text = model.text
        let kind = model.kind
        Task { await suggestions.revise(noteID: noteID, text: text, kind: kind, comment: message) }
    }

    /// The row below an issue card: the target as a button while the card is open, as plain text afterwards.
    private func targetRow(_ card: NoteSuggestionModel.Card, in suggestions: NoteSuggestionModel) -> AnyView? {
        guard let summary = suggestions.targetSummary(of: card) else { return nil }
        guard card.status == .pending else {
            return card.target == nil ? nil : AnyView(Text(summary).font(.caption).foregroundStyle(.secondaryText))
        }
        let value = suggestions.targetValue(of: card)
        return AnyView(
            Button { targetCardID = card.id } label: {
                HStack(spacing: 4) {
                    Text(summary).font(.subheadline)
                    Image(systemName: "chevron.right").imageScale(.small)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(card.needsTarget ? Color.orangeText : Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ziel")
            .accessibilityValue(value ?? String(localized: "Nicht gewählt"))
            .accessibilityHint("Öffnet die Auswahl"))
    }

    /// Saves the note first, so the text that is sent is the text that is stored.
    private func fetchSuggestions() {
        guard let suggestions else { return }
        model.flush()
        guard let noteID = model.noteID else { return }
        let text = model.text
        let kind = model.kind
        Task { await suggestions.fetch(noteID: noteID, text: text, kind: kind) }
    }

    private func prepareVoice() {
        // The dream log has no suggestions, so it needs no model that could send anything.
        if suggestions == nil, !isDreamLog { suggestions = environment.makeNoteSuggestionModel() }
        guard voice == nil else { return }
        let input = VoiceInputFactory.make(environment, place: .notes)
        input.readDraft = { model.draftBeforeCursor() }
        input.writeDraft = { model.writeDictation($0) }
        input.onSend = { _ in }
        voice = input
    }
}
