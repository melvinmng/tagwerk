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

    /// How a turn ended, for the voice mode (plan voice-chat, stage 2 point 9).
    enum TurnOutcome: Equatable {
        /// `id` is the answer to highlight; `speech` the answer and card announcement, possibly empty.
        case answered(id: String, speech: String, hasPendingCards: Bool)
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
    /// GitHub access and issue lookup for chats about one task.
    @ObservationIgnored var reader: RepositoryReading?
    @ObservationIgnored var issueReference: (TaskID) -> IssueReference? = { _ in nil }
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
        self.context = context
        switchThread(to: ChatStore.assistantKey, tools: tools)
        task = nil
        isPresented = true
    }

    /// "Über diese Aufgabe sprechen": the task's own chat, with the repository functions for GitHub issues.
    func open(task: TaskItem) {
        guard onTurnFinished == nil else { isPresented = true; return }
        context = .task(task.id)
        let reference = task.id.source == .github ? issueReference(task.id) : nil
        let handler = TaskChatTools(base: tools, reader: reader ?? NoRepositoryReader(), reference: reader == nil ? nil : reference)
        if self.task?.id != task.id { taskContext = nil }
        self.task = task
        switchThread(to: "task:\(task.id.key)", tools: handler)
        isPresented = true
    }

    private func switchThread(to newKey: String, tools handler: ToolHandler) {
        guard conversation == nil || key != newKey else { return }
        if conversation != nil { persist() }
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
            reportTurn(after: index, executed: false, fallback: .detect(trimmed, fallback: .german))
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
        var cards: [(title: String, change: String)] = []
        for message in fresh {
            switch message.content {
            case .assistant(let text): texts.append(text)
            case .action(let call, .pending): let card = describe(call); cards.append((card.title, card.change))
            default: break
            }
        }
        let language = VoiceLanguage.detect(texts.joined(separator: " "), fallback: fallback)
        let parts = (executed ? [ActionAnnouncement.executed(language)] : []) + texts
        var speech = parts
        if announcesActions(), let announcement = ActionAnnouncement.text(for: cards, language: language) {
            speech.append(announcement)
        }
        let answer = fresh.last { if case .assistant = $0.content { true } else { false } }
        report(.answered(id: answer.map { "message-\($0.id)" } ?? "message-\(index)",
                         speech: speech.joined(separator: "\n"),
                         hasPendingCards: !conversation.pendingActions.isEmpty))
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
        var cards: [(title: String, change: String)] = []
        for message in fresh {
            switch message.content {
            case .assistant(let text): texts.append(text)
            case .action(let call, .pending): let card = describe(call); cards.append((card.title, card.change))
            default: break
            }
        }
        let language = VoiceLanguage.detect(texts.joined(separator: " ").isEmpty ? userText : texts.joined(separator: " "),
                                            fallback: .detect(userText, fallback: .german))
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
        actionTimes[call.id] = now()
        let index = conversation.history.count
        await conversation.confirm(call)
        persist()
        if onTurnFinished != nil {
            let executed: Bool
            if case .done(let output) = status(of: call), ActionCardView.error(in: output) == nil { executed = true } else { executed = false }
            reportTurn(after: index - 1, executed: executed && announcesActions(), fallback: .german)
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
        let language = VoiceLanguage.detect(texts.joined(separator: " "), fallback: .german)
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
        let index = conversation.history.count
        for call in conversation.pendingActions {
            actionTimes[call.id] = now()
            await conversation.confirm(call)
        }
        persist()
        reportTurn(after: index - 1, executed: announcesActions(), fallback: .german)
    }

    func decline(_ call: ToolCall) async {
        let index = conversation?.history.count ?? 0
        await conversation?.decline(call)
        persist()
        reportTurn(after: index - 1, executed: false, fallback: .german)
    }

    func retry() async {
        let index = conversation?.history.count ?? 0
        await conversation?.retry()
        persist()
        reportTurn(after: index - 1, executed: false, fallback: .german)
    }

    /// "Verlauf löschen".
    func clear() {
        guard conversation?.isBusy != true else { return }
        conversation?.clear()
        actionTimes = [:]
        spokenMarks = []
        taskContext = nil
        store.delete(key)
    }

    private func persist() {
        guard let conversation else { return }
        store.save(conversation.history, actionTimes: actionTimes, for: key, now: now())
        store.saveSpokenMarks(spokenMarks, for: key)
    }

    // MARK: Instructions

    func instructions() -> String {
        let current = now()
        let today = planning.today
        let time = current.formatted(.dateTime.hour().minute())
        return """
        Du bist der Assistent der App Tagwerk, die Aufgaben (Erinnerungen, GitHub-Issues, lokale Aufgaben) und \
        Kalender zusammenführt und Tage plant. Antworte knapp in der Sprache der letzten Nachricht des Nutzers (Deutsch oder Englisch).
        Heute ist \(AIPlanner.dayString(today)), es ist \(time) Uhr (Zeitzone \(planning.calendar.timeZone.identifier)).
        Nutze die Funktionen: lesende darfst du jederzeit aufrufen, um nachzusehen. Ändernde Funktionen rufst du \
        direkt auf, ohne vorher im Text um Erlaubnis zu fragen; die App zeigt sie als Karte und führt sie erst nach \
        Bestätigung aus. Danach erhältst du das Ergebnis oder den Fehler und kannst reagieren.
        Aufgaben-IDs haben die Form quelle:kennung (z. B. github:… oder local:…); verwende sie genau so.
        \(contextText())
        """
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
    }

    /// Text of an action card (mockup e): what the change is about and how it changes it.
    func describe(_ call: ToolCall) -> ActionCard {
        let args = (try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]) ?? [:]
        func string(_ key: String) -> String? { (args[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let task = string("id").flatMap { id in planning.taskList.items.first { $0.id.key == id } }
        let title = task?.title ?? string("title") ?? "Änderung"
        func dayText(_ text: String?) -> String {
            guard let text, let day = AIPlanner.planDay(String(text.prefix(10))) else { return "keine" }
            return day.startDate(in: planning.calendar).formatted(.dateTime.weekday(.abbreviated).day().month())
        }
        switch call.name {
        case "create_task":
            var parts = ["Neue Aufgabe"]
            if let source = string("source") { parts.append(source == "github" ? "als GitHub-Issue" : source) }
            if let due = string("due") { parts.append("fällig \(dayText(due))") }
            if let priority = string("priority") { parts.append(priority) }
            // Everything that is written is shown in full before the user confirms.
            let notes = string("notes").map { "\nNotizen: „\($0)“" } ?? ""
            return ActionCard(title: title, change: parts.joined(separator: " · ") + notes)
        case "update_task":
            var changes: [String] = []
            if let newTitle = string("title") { changes.append("Titel → \(newTitle)") }
            if let due = string("due") { changes.append("Fälligkeit: \(dayText(task?.due.map { AppTools.dueString($0) })) → \(dayText(due))") }
            if let priority = string("priority") { changes.append("Priorität: \(task?.priority?.label ?? "–") → \(priority)") }
            if let minutes = args["minutes"] as? Int { changes.append("Aufwand → \(CapacityText.duration(minutes))") }
            if let notes = string("notes") { changes.append("Notizen → „\(notes)“") }
            return ActionCard(title: title, change: changes.isEmpty ? "Ändern" : changes.joined(separator: " · "))
        case "reschedule_task":
            return ActionCard(title: title, change: "Fälligkeit: \(dayText(task?.due.map { AppTools.dueString($0) })) → \(dayText(string("due")))")
        case "complete_task":
            return ActionCard(title: title, change: "Als erledigt markieren")
        case "assign_to_day":
            let current = task.flatMap { planning.planStore.assignment(for: $0.id) }.map(AIPlanner.dayString)
            return ActionCard(title: title, change: "Verschieben: \(dayText(current)) → \(dayText(string("day")))")
        case "create_time_block":
            let minutes = (args["minutes"] as? Int).map { " · " + CapacityText.duration($0) } ?? ""
            return ActionCard(title: title, change: "Zeitblock \(dayText(string("day"))) · \(string("start") ?? "")\(minutes)")
        case "link_event_to_task":
            let linked = string("task_id").flatMap { id in planning.taskList.items.first { $0.id.key == id }?.title } ?? "Aufgabe"
            return ActionCard(title: linked, change: "Termin mit dieser Aufgabe verknüpfen")
        case "set_day_hours":
            let day = string("day")
            if args["off"] as? Bool == true { return ActionCard(title: "Arbeitszeit", change: "\(dayText(day)): frei") }
            let current = day.flatMap { AIPlanner.planDay($0) }.flatMap { planning.workHours(on: $0) }
                .map { "\(AIPlanner.time($0.startMinutes))–\(AIPlanner.time($0.endMinutes))" } ?? "frei"
            return ActionCard(title: "Arbeitszeit \(dayText(day))", change: "\(current) → \(string("start") ?? "")–\(string("end") ?? "")")
        case "set_lunch":
            let minutes = args["minutes"] as? Int ?? 0
            return ActionCard(title: "Mittagspause \(dayText(string("day")))",
                              change: minutes > 0 ? "\(string("start") ?? "") · \(CapacityText.duration(minutes))" : "Keine Pause")
        case "mark_events_free":
            let count = (args["event_ids"] as? [String])?.count ?? 0
            let free = args["free"] as? Bool ?? true
            let series = args["series"] as? Bool == true ? " · auch alle künftigen" : ""
            return ActionCard(title: count == 1 ? "1 Termin" : "\(count) Termine", change: (free ? "Auf Frei setzen" : "Auf Belegt setzen") + series)
        case "plan_period":
            let scope = string("scope").flatMap(PlanScope.init(rawValue:)) ?? .day
            return ActionCard(title: "\(AIPlanBar.actionName(scope)) planen", change: "Vorschläge in der Planen-Ansicht anlegen")
        case "add_comment":
            return ActionCard(title: title, change: "Kommentar: „\(string("body") ?? "")“")
        default:
            return ActionCard(title: title, change: call.name)
        }
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
