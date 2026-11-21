import AIKit
import Foundation
import GitHubKit
import Observation
import TagwerkCore

/// The assistant chat (design §8.3, mockup e): one conversation with the app functions, the context of the
/// current view in the instructions, kept across app starts. Nothing is sent before the user writes.
@MainActor
@Observable
final class AssistantModel {
    enum Context: Equatable {
        case planning(scope: PlanScope, anchor: PlanDay)
        case tasks
        case settings
        case capture
        /// "Über diese Aufgabe sprechen": its own chat per task (design §8.3).
        case task(TaskID)
    }

    private(set) var conversation: Conversation?
    private(set) var context: Context = .settings
    /// When each action (call ID) was carried out, for "✓ Ausgeführt · 09:38".
    private(set) var actionTimes: [String: Date] = [:]
    /// User messages that came from a recording (mockup SP2: small microphone in the history).
    private(set) var spokenMarks: [SpokenMark] = []
    var isPresented = false

    /// Voice hooks (plan voice-chat): when to read new answers automatically, whether to announce action
    /// cards, and the reader itself. Only the view layer sets them.
    @ObservationIgnored var readPolicy: () -> ReadAloudPolicy = { .never }
    @ObservationIgnored var announcesActions: () -> Bool = { true }
    @ObservationIgnored var readAutomatically: (_ id: String, _ text: String, _ fallback: VoiceLanguage) -> Void = { _, _, _ in }
    /// The language chosen for the voice chat (Einstellungen › Sprache › "Sprache im Sprachchat"); `nil` follows the user.
    /// It decides the answer language of the voice mode and the language that is read when the text gives no clear hint.
    @ObservationIgnored var fixedVoiceLanguage: () -> VoiceLanguage? = { nil }

    /// The language spoken text falls back to when it is too short to tell: the chosen voice chat language, else the app's.
    private var speechFallback: VoiceLanguage { fixedVoiceLanguage() ?? .app }

    /// How a turn ended, for the voice mode (plan voice-chat, stage 2 point 9).
    enum TurnOutcome: Equatable {
        /// `id` is the answer to highlight; `speech` the answer and card announcement, possibly empty.
        case answered(id: String, speech: String, cards: OpenCards)
        /// Nothing was sent (empty text, conversation busy).
        case rejected
        case failed(offline: Bool)
    }

    /// Set while the voice mode runs: every turn reports here, and the voice mode reads the answer itself,
    /// so automatic reading stays silent.
    @ObservationIgnored var onTurnFinished: ((TurnOutcome) -> Void)?

    @ObservationIgnored private let responder: ResponseStreaming
    @ObservationIgnored let tools: AppTools
    @ObservationIgnored private let model: @MainActor () async throws -> String
    @ObservationIgnored private let store: ChatStore
    @ObservationIgnored private let planning: PlanningModel
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var key = ChatStore.assistantKey
    /// The consent was withdrawn while a turn was running; the history is reduced as soon as the turn ends.
    @ObservationIgnored private var pendingNoteSessionEnd = false
    /// The consent "Notizen mit ChatGPT" as the settings hold it; `nil` until `watchNoteConsent` is called.
    @ObservationIgnored private var noteConsent: (() -> Bool)?
    /// The consent as last seen, to notice the change to `false` (and nothing else).
    @ObservationIgnored private var noteConsentWasGiven = false
    /// GitHub access and issue lookup for chats about one task.
    @ObservationIgnored var reader: RepositoryReading?
    @ObservationIgnored var issueReference: (TaskID) -> IssueReference? = { _ in nil }
    /// GitHub catalog and login for the issue card and the instructions; `nil` while GitHub is not signed in.
    @ObservationIgnored var gitHubDirectory: () -> (any GitHubDirectory)? = { nil }
    /// Name of an open shopping item by its id, for the card of `update_shopping`.
    @ObservationIgnored var shoppingItemName: (String) -> String? = { _ in nil }
    /// The task a task chat is about and its loaded context (comments, neighbours …).
    private(set) var task: TaskItem?
    @ObservationIgnored private var taskContext: String?

    init(responder: ResponseStreaming, tools: AppTools, model: @escaping @MainActor () async throws -> String, store: ChatStore,
         planning: PlanningModel, now: @escaping () -> Date = Date.init) {
        self.responder = responder
        self.tools = tools
        self.model = model
        self.store = store
        self.planning = planning
        self.now = now
    }

    /// Opens the chat for the current view; restores the stored conversation without sending anything.
    func open(context: Context) {
        // The voice mode keeps its conversation until it ends (stage 2 review 4).
        guard onTurnFinished == nil else { isPresented = true; return }
        guard !isHoldingOtherChat(ChatStore.assistantKey) else { isPresented = true; return }
        self.context = context
        switchThread(to: ChatStore.assistantKey, tools: tools)
        task = nil
        isPresented = true
    }

    /// "Über diese Aufgabe sprechen": the task's own chat, with the repository functions for GitHub issues.
    func open(task: TaskItem) {
        guard onTurnFinished == nil else { isPresented = true; return }
        guard !isHoldingOtherChat("task:\(task.id.key)") else { isPresented = true; return }
        context = .task(task.id)
        let reference = task.id.source == .github ? issueReference(task.id) : nil
        let handler = TaskChatTools(base: tools, reader: reader ?? NoRepositoryReader(), reference: reader == nil ? nil : reference)
        if self.task?.id != task.id { taskContext = nil }
        self.task = task
        switchThread(to: "task:\(task.id.key)", tools: handler)
        isPresented = true
    }

    /// True while a turn runs in a chat other than `newKey`. Such a switch waits: the turn belongs to the running
    /// conversation, and replacing it would let the turn read notes into the session of the new chat and save its result
    /// under the wrong key. The chat that is shown stays until the turn ends (the same rule as the voice mode).
    private func isHoldingOtherChat(_ newKey: String) -> Bool {
        conversation?.isBusy == true && key != newKey
    }

    private func switchThread(to newKey: String, tools handler: ToolHandler) {
        guard conversation == nil || key != newKey else { return }
        if conversation != nil {
            persist()
            // Leaving a chat ends the note session: the next chat starts from its stored form.
            tools.noteSession.reset()
        }
        key = newKey
        actionTimes = store.actionTimes(for: newKey)
        spokenMarks = store.spokenMarks(for: newKey)
        conversation = Conversation(responder: responder, tools: handler, model: model,
                                    instructions: { [weak self] in self?.instructions() ?? "" },
                                    history: store.history(for: newKey))
    }

    func send(_ text: String, spoken: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversation, !conversation.isBusy else {
            onTurnFinished?(.rejected)
            return
        }
        syncNoteConsent()
        if let task, taskContext == nil {
            // GitHub is asked only now, when the user starts the conversation.
            let reference = task.id.source == .github ? issueReference(task.id) : nil
            taskContext = await IssueContext.load(task: task, reference: reference, reader: reference == nil ? nil : reader)
            // The voice mode ended while GitHub was asked: send nothing.
            if Task.isCancelled { return }
        }
        let start = conversation.history.count
        await conversation.send(trimmed)
        // `send` may first close open calls; the user message is the first `.user` item from `start` on.
        let index = conversation.history.indices.dropFirst(start).first { conversation.history[$0] == .user(trimmed) } ?? start
        if spoken {
            spokenMarks.append(SpokenMark(index: index, text: trimmed))
        }
        persist()
        if onTurnFinished != nil {
            reportTurn(after: index, executed: false, fallback: .detect(trimmed, fallback: speechFallback))
        } else {
            readNewOutput(after: index, spoken: spoken, userText: trimmed)
        }
    }

    /// Reports the end of a voice mode turn: failure, or "Ausgeführt." (when `executed`), the new answers and the
    /// card announcement after `index`.
    private func reportTurn(after index: Int, executed: Bool, fallback: VoiceLanguage) {
        guard let report = onTurnFinished, let conversation else { return }
        if case .failed(let error) = conversation.state {
            report(.failed(offline: error == .network))
            return
        }
        let fresh = conversation.messages.filter { $0.id > index }
        var texts: [String] = []
        var calls: [ToolCall] = []
        for message in fresh {
            switch message.content {
            case .assistant(let text): texts.append(text)
            case .action(let call, .pending): calls.append(call)
            default: break
            }
        }
        let language = VoiceLanguage.detect(texts.joined(separator: " "), fallback: fallback)
        let cards = calls.map { describe($0, language: language, spoken: true) }.map { (title: $0.title, change: $0.change) }
        let parts = (executed ? [ActionAnnouncement.executed(language)] : []) + texts
        var speech = parts
        let open = openCards
        if announcesActions(), let announcement = ActionAnnouncement.text(for: cards, language: language, byVoice: true,
                                                                          deletes: open.deletes) {
            speech.append(announcement)
        }
        let answer = fresh.last { if case .assistant = $0.content { true } else { false } }
        report(.answered(id: answer.map { "message-\($0.id)" } ?? "message-\(index)",
                         speech: speech.joined(separator: "\n"),
                         cards: open))
    }

    /// The cards waiting for an answer, for the voice mode (issue #120).
    var openCards: OpenCards {
        let pending = conversation?.pendingActions ?? []
        let me = gitHubDirectory()?.login
        return OpenCards(ids: pending.map(\.id), deletes: pending.filter { $0.name == "delete_event" }.count,
                         guarded: pending.filter { Self.needsSingleConfirmation($0, me: me) }.count)
    }

    /// Tools whose cards are always confirmed alone, never with "Alle bestätigen" and never together with other
    /// cards by voice. The note tools of the notes chat are added here.
    static let singleConfirmationTools: Set<String> = ["assign_task"]

    /// True for a card that must be confirmed alone: a tool of `singleConfirmationTools`, or creating a task that is
    /// assigned beyond the user (`assignsBeyondMe`).
    static func needsSingleConfirmation(_ call: ToolCall, me: String?) -> Bool {
        singleConfirmationTools.contains(call.name) || assignsBeyondMe(call, me: me)
    }

    /// The open cards that "Alle bestätigen" may confirm: every pending call except the guarded ones.
    var batchConfirmable: [ToolCall] {
        let me = gitHubDirectory()?.login
        return (conversation?.pendingActions ?? []).filter { !Self.needsSingleConfirmation($0, me: me) }
    }

    /// The line below "Alle bestätigen" that names what is confirmed alone; `nil` without guarded cards.
    static func singleConfirmationNotice(for calls: [ToolCall], me: String? = nil) -> String? {
        calls.contains { needsSingleConfirmation($0, me: me) } ? String(localized: "Zuweisungen bestätigst du einzeln.") : nil
    }

    /// True for a `create_task` call that assigns an issue to other people or to no one. Such a card is
    /// visible to others on GitHub, so by voice it is confirmed alone, never together with other cards.
    static func assignsBeyondMe(_ call: ToolCall, me: String?) -> Bool {
        guard call.name == "create_task",
              let args = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any],
              args["source"] as? String == "github", let assignees = args["assignees"] as? [String] else { return false }
        guard let me else { return true }
        return assignees.isEmpty || assignees.contains { !AssigneeSelection.isMe($0, me: me) }
    }

    /// Spoken "ja" after the countdown: confirms the cards the user answered to, if they are still open.
    func confirmCards(_ ids: [String]) async {
        guard let conversation else { onTurnFinished?(.rejected); return }
        let calls = conversation.pendingActions.filter { ids.contains($0.id) }
        // Exactly the cards the user answered to; deletions only one at a time ("Ja, löschen"), and so
        // are issues assigned to other people or to no one.
        let me = gitHubDirectory()?.login
        guard !calls.isEmpty, calls.count == ids.count,
              calls.count == 1 || !calls.contains(where: { $0.name == "delete_event" || Self.needsSingleConfirmation($0, me: me) }) else {
            onTurnFinished?(.rejected)
            return
        }
        if calls.count == 1 { return await confirm(calls[0]) }
        syncNoteConsent()
        let index = conversation.history.count
        for call in calls {
            actionTimes[call.id] = now()
            await conversation.confirm(call)
        }
        persist()
        reportTurn(after: index - 1, executed: allExecuted(calls) && announcesActions(), fallback: speechFallback)
    }

    /// Spoken "nein": declines the one card the user answered to.
    func declineCards(_ ids: [String]) async {
        guard ids.count == 1, let call = conversation?.pendingActions.first(where: { $0.id == ids[0] }) else {
            onTurnFinished?(.rejected)
            return
        }
        await decline(call)
    }

    func isSpoken(_ message: ChatMessage) -> Bool {
        guard case .user(let text) = message.content else { return false }
        return spokenMarks.contains { $0.matches(index: message.id, text: text) }
    }

    /// Reads what arrived after `index` when the policy says so: the answer text, then one sentence for new
    /// action cards (mockup SP4a). Cards are only announced, never confirmed by voice.
    private func readNewOutput(after index: Int, spoken: Bool, userText: String) {
        guard let conversation,
              readPolicy().readsAutomatically(lastUserMessageWasSpoken: spoken, conversationVisible: isPresented) else { return }
        let fresh = conversation.messages.filter { $0.id > index }
        var texts: [String] = []
        var calls: [ToolCall] = []
        for message in fresh {
            switch message.content {
            case .assistant(let text): texts.append(text)
            case .action(let call, .pending): calls.append(call)
            default: break
            }
        }
        let language = VoiceLanguage.detect(texts.joined(separator: " ").isEmpty ? userText : texts.joined(separator: " "),
                                            fallback: .detect(userText, fallback: speechFallback))
        // Cards are announced in the language of the answer, not mixed with the app language.
        let cards = calls.map { describe($0, language: language, spoken: true) }.map { (title: $0.title, change: $0.change) }
        if announcesActions(), let announcement = ActionAnnouncement.text(for: cards, language: language) {
            texts.append(announcement)
        }
        guard !texts.isEmpty else { return }
        // The id of the last answer, so its "Vorlesen" capsule shows "Liest vor · Stopp" (review 5).
        let answer = fresh.last { if case .assistant = $0.content { true } else { false } }
        readAutomatically(answer.map { "message-\($0.id)" } ?? "message-\(index)", texts.joined(separator: "\n"), language)
    }

    private func status(of call: ToolCall) -> ChatMessage.ActionStatus? {
        for message in conversation?.messages ?? [] {
            if case .action(let other, let status) = message.content, other.id == call.id { return status }
        }
        return nil
    }

    /// Whether the last user message was spoken; confirmations continue reading in that case.
    private var lastUserMessageWasSpoken: Bool {
        guard let last = conversation?.messages.last(where: { if case .user = $0.content { true } else { false } }) else { return false }
        return isSpoken(last)
    }

    func confirm(_ call: ToolCall) async {
        guard let conversation else { return }
        syncNoteConsent()
        actionTimes[call.id] = now()
        let index = conversation.history.count
        await conversation.confirm(call)
        persist()
        if onTurnFinished != nil {
            let executed: Bool
            if case .done(let output) = status(of: call), ActionCardView.error(in: output) == nil { executed = true } else { executed = false }
            reportTurn(after: index - 1, executed: executed && announcesActions(), fallback: speechFallback)
        } else {
            readAfterConfirmation(from: index, call: call)
        }
    }

    /// "Ausgeführt." and whatever the model says next, when answers are being read (SP4a).
    private func readAfterConfirmation(from index: Int, call: ToolCall) {
        let spoken = lastUserMessageWasSpoken
        guard let conversation, readPolicy().readsAutomatically(lastUserMessageWasSpoken: spoken, conversationVisible: isPresented)
        else { return }
        let answers = conversation.messages.filter { message in
            guard message.id >= index, case .assistant = message.content else { return false }
            return true
        }
        let texts = answers.compactMap { message -> String? in
            if case .assistant(let text) = message.content { return text }
            return nil
        }
        let language = VoiceLanguage.detect(texts.joined(separator: " "), fallback: speechFallback)
        var parts = [String]()
        if announcesActions(), case .done(let output) = status(of: call), ActionCardView.error(in: output) == nil {
            parts.append(ActionAnnouncement.executed(language))
        }
        parts += texts
        guard !parts.isEmpty else { return }
        readAutomatically(answers.last.map { "message-\($0.id)" } ?? "confirm-\(call.id)", parts.joined(separator: "\n"), language)
    }

    /// "Alle bestätigen (N)" (mockup e).
    func confirmAll() async {
        guard let conversation else { return }
        syncNoteConsent()
        let index = conversation.history.count
        // Guarded cards stay open: they are confirmed one by one.
        let calls = batchConfirmable
        for call in calls {
            actionTimes[call.id] = now()
            await conversation.confirm(call)
        }
        persist()
        reportTurn(after: index - 1, executed: allExecuted(calls) && announcesActions(), fallback: speechFallback)
    }

    /// Whether every call ran without an error, for "Ausgeführt.".
    private func allExecuted(_ calls: [ToolCall]) -> Bool {
        calls.allSatisfy { call in
            if case .done(let output) = status(of: call), ActionCardView.error(in: output) == nil { return true }
            return false
        }
    }

    func decline(_ call: ToolCall) async {
        syncNoteConsent()
        let index = conversation?.history.count ?? 0
        await conversation?.decline(call)
        persist()
        reportTurn(after: index - 1, executed: false, fallback: speechFallback)
    }

    func retry() async {
        syncNoteConsent()
        let index = conversation?.history.count ?? 0
        await conversation?.retry()
        persist()
        reportTurn(after: index - 1, executed: false, fallback: speechFallback)
    }

    /// "Verlauf löschen".
    func clear() {
        guard conversation?.isBusy != true else { return }
        conversation?.clear()
        tools.noteSession.reset()
        actionTimes = [:]
        spokenMarks = []
        taskContext = nil
        store.delete(key)
    }

    /// Ends the note session (`watchNoteConsent` calls it when the consent "Notizen mit ChatGPT" was withdrawn). The history
    /// in memory is reduced to its stored form (the model no longer sees note texts it read earlier), the saved chat is updated.
    /// While a turn is running the reduction follows when the turn ends (`persist()` runs after every turn).
    func endNoteSession() {
        pendingNoteSessionEnd = true
        tools.noteSession.reset()
        applyNoteSessionEnd()
        persist()
    }

    /// Starts following the consent "Notizen mit ChatGPT" (`AppEnvironment` passes the setting): every change to `false`
    /// ends the note session, wherever it comes from (settings screen, backup restore, any later code path). The
    /// observation hands over on the next main actor turn; `syncNoteConsent()` closes that gap at the start of a turn.
    func watchNoteConsent(_ consent: @escaping () -> Bool) {
        noteConsent = consent
        noteConsentWasGiven = consent()
        observeNoteConsent()
    }

    private func observeNoteConsent() {
        guard let noteConsent else { return }
        withObservationTracking {
            _ = noteConsent()
        } onChange: { [weak self] in
            // `onChange` runs before the new value is set; read it one turn later and register again.
            Task { @MainActor [weak self] in
                self?.syncNoteConsent()
                self?.observeNoteConsent()
            }
        }
    }

    /// Compares the consent with the last value seen and ends the session when it was withdrawn. Cheap and safe to call
    /// at any time; the turn entry points call it so no request is built from a history that still holds note text.
    private func syncNoteConsent() {
        guard let noteConsent else { return }
        let allowed = noteConsent()
        defer { noteConsentWasGiven = allowed }
        if noteConsentWasGiven && !allowed { endNoteSession() }
    }

    /// "Gelesen: „A“, „B“" for a `read_note` call; built from the output, so it works with the full and with the stored
    /// form. `nil` while there is no output, for an error and for other calls.
    func activityText(_ call: ToolCall, output: String?) -> String? {
        guard call.name == "read_note", let output else { return nil }
        let titles = AppTools.readNoteTitles(in: output)
        guard !titles.isEmpty else { return nil }
        let quoted = titles.map { String(localized: "„\($0)“") }.joined(separator: ", ")
        return String(localized: "Gelesen: \(quoted)")
    }

    private func applyNoteSessionEnd() {
        guard pendingNoteSessionEnd, let conversation, !conversation.isBusy else { return }
        conversation.reduceToStoredForm()
        pendingNoteSessionEnd = false
    }

    private func persist() {
        guard let conversation else { return }
        applyNoteSessionEnd()
        // Only the stored form: note text read in this session must not survive in the saved chat.
        store.save(conversation.storableHistory, actionTimes: actionTimes, for: key, now: now())
        store.saveSpokenMarks(spokenMarks, for: key)
    }

    // MARK: Instructions

    /// While the voice mode runs (issue #120): the user hears the answer and replies by voice.
    static let voiceModeInstructions = """
    Der Nutzer spricht gerade mit dir im Sprechmodus und hört deine Antworten. Vorschläge nimmt er mit „ja“ an, \
    lehnt sie mit „nein“ ab oder sagt, was anders sein soll; das erledigt die App. Fordere ihn deshalb nie auf, \
    auf dem Bildschirm zu bestätigen oder zu tippen, und frage nicht selbst nach einer Bestätigung. Antworte in \
    kurzen, gut sprechbaren Sätzen ohne Aufzählungen und Tabellen.
    """

    /// The voice mode instructions plus, when a voice chat language is chosen, the order to answer in it.
    private func voiceModeText() -> String {
        guard let sentence = VoiceChatLanguage.answerInstruction(for: fixedVoiceLanguage()) else { return Self.voiceModeInstructions }
        return Self.voiceModeInstructions + " " + sentence
    }

    /// The language to answer in without a user message or when the message language is unclear.
    @ObservationIgnored var language: () -> VoiceLanguage = { .app }

    func instructions() -> String {
        let current = now()
        let today = planning.today
        let time = AIPlanner.time(planning.calendar.component(.hour, from: current) * 60 + planning.calendar.component(.minute, from: current))
        return """
        Du bist der Assistent der App Tagwerk, die Aufgaben (Erinnerungen, GitHub-Issues, lokale Aufgaben) und \
        Kalender zusammenführt und Tage plant. Antworte knapp in der Sprache der letzten Nachricht des Nutzers (Deutsch oder Englisch); \
        gibt es noch keine Nachricht oder ist die Sprache unklar, antworte auf \(language().promptName).
        Heute ist \(AIPlanner.dayString(today)), es ist \(time) Uhr (Zeitzone \(planning.calendar.timeZone.identifier)).
        Nutze die Funktionen: lesende darfst du jederzeit aufrufen, um nachzusehen. Ändernde Funktionen rufst du \
        direkt auf, ohne vorher im Text um Erlaubnis zu fragen; die App zeigt sie als Karte und führt sie erst nach \
        Bestätigung aus. Danach erhältst du das Ergebnis oder den Fehler und kannst reagieren.
        Aufgaben-IDs haben die Form quelle:kennung (z. B. github:… oder local:…); verwende sie genau so.
        Termine kannst du anlegen, ändern und löschen (create_event, update_event, delete_event), in jedem \
        beschreibbaren Kalender; ohne Nennung eines Kalenders im Standardkalender. Nennt der Nutzer keine Dauer, \
        dauert ein neuer Termin eine Stunde.
        Fragt der Nutzer nach einem bestimmten Termin oder einer bestimmten Aufgabe, nutze search, statt mit list_events \
        Zeiträume zu raten.
        search findet auch Notizen und Einkaufsartikel. Von Notizen siehst du Titel und einen kurzen Ausschnitt. Gib \
        Notiztext nicht wörtlich wieder, sondern nenne Titel und Datum, außer der Nutzer bittet ausdrücklich um den \
        Wortlaut. Meldet search notesLocked, sag dem Nutzer, dass er „Notizen mit ChatGPT“ unter Einstellungen › KI \
        einschalten kann. github_online setzt du nur, wenn es um Issues geht, die nicht in den Aufgaben stehen, oder \
        wenn die lokale Suche nichts ergibt.
        \(noteInstructions())
        Einkaufsartikel stehen nicht in list_tasks: Die Einkaufsliste liest du mit list_shopping und änderst sie mit \
        update_shopping (hinzufügen, abhaken). Lege Einkaufsartikel nie über create_task an.
        \(gitHubInstructions())
        \(onTurnFinished == nil ? "" : voiceModeText())
        \(contextText())
        """
    }

    /// How to read notes; only while the consent is on and the context has notes.
    private func noteInstructions() -> String {
        guard tools.offersNotes else { return "" }
        return """
        Reicht der Ausschnitt eines Notiztreffers nicht, lies die Notiz mit read_note. Lies nur Notizen, die für die \
        Bitte nötig sind.
        """
    }

    /// How to create GitHub issues; only while GitHub is signed in. Logins of other people reach the model
    /// only through list_assignees, so it is told to call that only when the user wants to assign.
    private func gitHubInstructions() -> String {
        guard gitHubDirectory() != nil else { return "" }
        var text = """
        Für ein GitHub-Issue rufst du zuerst list_github_targets auf und übergibst repository und project_ids \
        ausdrücklich. Will der Nutzer das Issue ohne Project anlegen, übergibst du project_ids als leere Liste []; es \
        erscheint dann nicht in seinen Aufgaben, und du sagst ihm das mit Nummer und Link. list_assignees rufst du nur \
        auf, wenn der Nutzer das Issue jemandem zuweisen will. Passt ein genannter Name zu keinem oder zu mehreren \
        Logins, frag nach, statt zu raten. Um die Zuständigkeit eines bestehenden Issues zu ändern, nutze assign_task. \
        Lies vorher mit get_task, wer zugewiesen ist, und mit list_assignees, wer zuweisbar ist. Entfernst du den \
        Nutzer selbst, gibt er das Issue ab; sag ihm danach Nummer und Link. Auch ein offenes Issue, das search mit \
        github_online gefunden hat und das nicht in den Aufgaben steht, kannst du mit assign_task zuweisen, etwa wenn \
        der Nutzer es übernehmen will; die id aus dem Suchergebnis gilt dafür bis zur nächsten GitHub-Suche.
        """
        if case .task(let id) = context, id.source == .github, let reference = issueReference(id) {
            text += " Naheliegendes Ziel für neue Issues: \(reference.repository)."
        }
        return text
    }

    private func contextText() -> String {
        switch context {
        case .task:
            return taskContext ?? task.map { "Das Gespräch betrifft die Aufgabe „\($0.title)“ (id \($0.id.key))." } ?? ""
        case .settings:
            return "Ansicht: Einstellungen (kein besonderer Kontext)."
        case .capture:
            // Meals, water and workouts never go to the assistant (main design §7).
            return "Ansicht: Erfassen (Essen, Trinken, Training). Diese Daten stehen dir nicht zur Verfügung."
        case .tasks:
            let open = planning.taskList.items.filter { !$0.isCompleted }.count
            return "Ansicht: Aufgaben (\(open) offene Aufgaben; Einzelheiten über list_tasks)."
        case .planning(let scope, _):
            let days = planning.days.filter { !$0.isPast || $0.day == planning.today }
            let lines = days.prefix(31).map { plan -> String in
                let capacity = plan.capacity
                let load = capacity.isDayOff ? "frei (kein Arbeitstag)"
                    : "\(CapacityText.duration(max(0, capacity.freeMinutes))) frei von \(CapacityText.duration(capacity.availableMinutes))"
                        + (capacity.isOverbooked ? ", überbucht" : "")
                return "- \(AIPlanner.dayString(plan.day)): \(load), \(plan.assigned.count) Aufgaben zugeordnet, \(plan.blocks.count) Zeitblöcke"
            }
            return "Ansicht: Planen · \(AIPlanBar.actionName(scope))\n" + lines.joined(separator: "\n")
        }
    }

    // MARK: Action cards

    struct ActionCard: Equatable {
        let title: String
        /// "Vorher → Nachher" or what will happen.
        let change: String
        /// Shown in red below `change`: what the action costs (a hand-over deletes blocks).
        var warning: String? = nil
        /// Replaces "Bestätigen" on the button ("Abgeben").
        var confirmTitle: String? = nil
        /// A red confirm button, for an action that cannot be undone by the user.
        var isDestructive = false
    }

    /// Text of an action card (mockup e): what the change is about and how it changes it. `language` is the app
    /// language on screen and the language of the answer when the card is announced (plan english-app, Task 2).
    /// On screen (the app language) dates follow the iPhone's region, e.g. 24-hour clock in en_GB; a card announced in
    /// another language uses that language's own formats.
    static func formatLocale(_ language: VoiceLanguage) -> Locale {
        language == .app ? .current : language.locale
    }

    /// `spoken`: the card is read aloud; texts then avoid symbols that speech drops (the screen keeps them).
    /// The texts come from `ActionCardDescriber`, which the thoughts note's suggestions use as well.
    func describe(_ call: ToolCall, language: VoiceLanguage = .app, spoken: Bool = false) -> ActionCard {
        ActionCardDescriber(planning: planning, gitHubDirectory: gitHubDirectory, shoppingItemName: shoppingItemName,
                            foundIssue: { [tools] in tools.foundIssues[$0] })
            .describe(call, language: language, spoken: spoken)
    }
}

/// Placeholder when GitHub is not connected; the repository functions are not offered then.
@MainActor
final class NoRepositoryReader: RepositoryReading {
    private struct Unavailable: Error {}
    func issueComments(repository: String, number: Int) async throws -> [IssueComment] { throw Unavailable() }
    func issueNeighbours(nodeID: String, selfNumber: Int) async throws -> IssueNeighbours { throw Unavailable() }
    func readme(repository: String) async throws -> String { throw Unavailable() }
    func file(repository: String, path: String) async throws -> RepositoryContent { throw Unavailable() }
    func searchCode(repository: String, query: String) async throws -> [String] { throw Unavailable() }
    func pullRequest(repository: String, number: Int) async throws -> PullRequestSummary { throw Unavailable() }
}
