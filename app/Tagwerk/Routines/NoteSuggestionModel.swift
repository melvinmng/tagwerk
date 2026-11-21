import AIKit
import Foundation
import GitHubKit
import Observation
import TagwerkCore

/// Suggestions from one thoughts note (phase 7 design §9.3): exactly one request per tap on "Vorschläge holen", answered
/// with function calls that become action cards. It uses neither `Conversation` nor `ChatStore`: confirming a card runs the
/// function through `AppTools` and sends nothing more. The note text is in no history and in no log; a failure message
/// never contains it.
@MainActor
@Observable
final class NoteSuggestionModel {
    enum Phase: Equatable {
        case idle, loading, loaded, empty
        case failed(String)
    }

    struct Card: Identifiable, Equatable {
        var id: String { call.id }
        /// For an issue the call carries the resolved target (`setTarget` rewrites it).
        var call: ToolCall
        var text: AssistantModel.ActionCard
        var status: ChatMessage.ActionStatus
        var time: Date?
        /// The call creates a GitHub issue.
        var isIssue = false
        /// Repository and projects of an issue; `nil` while the user has to choose them.
        var target: AppTools.GitHubTarget?

        /// Who last changed the open card; `nil` for a card as the model proposed it.
        var mark: ProposalMark?
        /// What the model proposed, for a card the user adjusted (or ChatGPT revised); `nil` for an unchanged card.
        var proposed: ToolCall?

        /// A GitHub issue without a resolved target: it cannot be confirmed before the user chooses one.
        var needsTarget: Bool { isIssue && target == nil }
    }

    private(set) var phase: Phase = .idle
    private(set) var cards: [Card] = []

    @ObservationIgnored private let responder: any ResponseStreaming
    @ObservationIgnored private let model: @MainActor () async throws -> String
    @ObservationIgnored private let tools: any ToolHandler
    @ObservationIgnored private let describer: ActionCardDescriber
    @ObservationIgnored private let notes: NoteStore
    @ObservationIgnored private let hasConsent: @MainActor () -> Bool
    @ObservationIgnored private let context: @MainActor () -> NoteSuggestionContext
    @ObservationIgnored private let gitHubDirectory: @MainActor () -> (any GitHubDirectory)?
    /// What the editors of the sheet "Vorschlag anpassen" need; without it no card offers "Anpassen".
    @ObservationIgnored private let editorContext: (@MainActor () -> ProposalEditorContext)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeout: Duration
    /// Counts resets and requests; an answer that arrives for an older count is dropped (review focus 5).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var noteID: UUID?

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String, tools: any ToolHandler,
         describer: ActionCardDescriber, notes: NoteStore, hasConsent: @escaping @MainActor () -> Bool,
         context: @escaping @MainActor () -> NoteSuggestionContext, now: @escaping () -> Date = Date.init,
         timeout: Duration = .seconds(60), gitHubDirectory: @escaping @MainActor () -> (any GitHubDirectory)? = { nil },
         editorContext: (@MainActor () -> ProposalEditorContext)? = nil) {
        self.responder = responder
        self.model = model
        self.tools = tools
        self.describer = describer
        self.notes = notes
        self.hasConsent = hasConsent
        self.context = context
        self.now = now
        self.timeout = timeout
        self.gitHubDirectory = gitHubDirectory
        self.editorContext = editorContext
    }

    var openCount: Int { cards.filter { $0.status == .pending }.count }

    /// The open cards "Alle bestätigen" may confirm: those that do not wait for a target and that are not confirmed alone
    /// (an issue for other people or for no one, like in the chat).
    var confirmableCount: Int { cards.filter(isBatchConfirmable).count }

    /// An open card the user has to confirm alone: a guarded issue (`AssistantModel.needsSingleConfirmation`).
    var hasSingleConfirmationCards: Bool {
        let me = gitHubDirectory()?.login
        return cards.contains { $0.status == .pending && AssistantModel.needsSingleConfirmation($0.call, me: me) }
    }

    /// The line below "Alle bestätigen" when open cards are confirmed alone; `nil` otherwise.
    var singleConfirmationNotice: String? {
        hasSingleConfirmationCards ? String(localized: "Zuweisungen bestätigst du einzeln.") : nil
    }

    private func isBatchConfirmable(_ card: Card) -> Bool {
        card.status == .pending && !card.needsTarget && !AssistantModel.needsSingleConfirmation(card.call, me: gitHubDirectory()?.login)
    }

    // MARK: Request

    /// One request. Without consent nothing happens, not even the model list is loaded.
    func fetch(noteID: UUID, text: String, kind: NoteKind) async {
        // Only the thought notes go to ChatGPT. Private notes (journal, Bible Study) and the dream log never do, whatever the
        // consent says. The stored kind counts as well as the one the caller names.
        guard kind.allowsSuggestions, notes.note(id: noteID)?.kind.allowsSuggestions != false else { return }
        guard hasConsent() else { return }
        generation += 1
        let mine = generation
        self.noteID = noteID
        cards = []
        phase = .loading
        do {
            let slug = try await model()
            guard mine == generation else { return }
            let sent = context()
            // A GitHub issue may be suggested when the target list is on the device. It is never sent: the target of an
            // issue is resolved here (decision D7).
            let catalog = gitHubDirectory()?.storedCatalog
            let request = Self.request(text: text, kind: kind, context: sent, now: now())
            let tools = NoteSuggestionRules.definitions(from: self.tools.definitions, gitHub: catalog != nil)
            let instructions = Self.instructions(gitHub: catalog != nil)
            let calls = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: instructions, input: [.user(request)],
                                                         tools: tools, jsonSchema: nil))
            }
            guard mine == generation else { return }
            notes.markProcessed(noteID, at: now())
            let accepted = NoteSuggestionRules.accepted(calls, context: sent, gitHub: catalog != nil)
            cards = accepted.map { makeCard($0, catalog: catalog) }
            phase = cards.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            if mine == generation { phase = .idle }
        } catch {
            guard mine == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    /// The card of an accepted call; for an issue the target is resolved against the catalog first.
    private func makeCard(_ call: ToolCall, catalog: GitHubCatalog?) -> Card {
        var card: Card
        if NoteSuggestionRules.isIssue(call), let catalog {
            let draft = NoteSuggestionRules.issueDraft(for: call, catalog: catalog)
            card = Card(call: draft.call, text: issueDescriber.describe(draft.call), status: .pending, time: nil, isIssue: true,
                        target: draft.target)
        } else {
            card = Card(call: call, text: describer.describe(call), status: .pending, time: nil)
        }
        card.text = describe(card)
        return card
    }

    /// Describes an issue without its target: the card shows that in a row of its own.
    private var issueDescriber: ActionCardDescriber {
        var copy = describer
        copy.showsIssueTarget = false
        return copy
    }

    /// The texts of a card from its current call: the mark and the proposal of the model for an adjusted card, and
    /// whether it offers "Anpassen".
    private func describe(_ card: Card) -> AssistantModel.ActionCard {
        let describer = card.isIssue ? issueDescriber : self.describer
        var text = describer.describe(card.call)
        guard card.status == .pending else { return text }
        text.mark = card.mark
        if let proposed = card.proposed {
            text.mark = card.mark ?? .byUser
            text.proposedChange = describer.describe(proposed).change
        }
        text.canAdjust = canAdjust(card)
        return text
    }

    /// Rewrites repository, projects and people of a pending issue card after the user chose them, and describes it again.
    /// `assignees == nil` stands for the user. The people are checked when the issue is created, like in the chat.
    func setTarget(_ id: String, repository: String, projectIDs: [String], assignees: [String]?) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].status == .pending, cards[index].isIssue,
              var arguments = try? JSONSerialization.jsonObject(with: cards[index].call.arguments) as? [String: Any] else { return }
        arguments["repository"] = repository
        arguments["project_ids"] = projectIDs
        arguments["assignees"] = assignees as Any? ?? NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        let call = ToolCall(id: cards[index].call.id, name: cards[index].call.name, arguments: data)
        cards[index].call = call
        cards[index].target = AppTools.GitHubTarget(repository: repository, projectIDs: projectIDs)
        cards[index].text = describe(cards[index])
    }

    /// The model of the sheet "Ziel wählen" for a pending issue card; `nil` for any other card or without a stored catalog.
    func targetSheetModel(for id: String) -> IssueTargetSheetModel? {
        guard let card = cards.first(where: { $0.id == id }), card.status == .pending, card.isIssue,
              let directory = gitHubDirectory(), let catalog = directory.storedCatalog,
              let arguments = try? JSONSerialization.jsonObject(with: card.call.arguments) as? [String: Any] else { return nil }
        let repository = card.target?.repository ?? arguments["repository"] as? String
        let projectIDs = card.target?.projectIDs ?? arguments["project_ids"] as? [String] ?? []
        return IssueTargetSheetModel(catalog: catalog, me: directory.login, repository: repository, projectIDs: projectIDs,
                                     loadAssignable: { await directory.assignableUsers(in: $0, maxAge: AppEnvironment.catalogMaxAge) })
    }

    /// The text of the target row of an issue card ("Ziel: owner/repo · Projekt X", "Ziel wählen"); `nil` for other cards.
    func targetSummary(of card: Card) -> String? {
        guard card.isIssue, let catalog = gitHubDirectory()?.storedCatalog else { return nil }
        return IssueTargetText.summary(of: card.target, in: catalog)
    }

    /// "owner/repo · Projekt X" for the VoiceOver value of the target row; `nil` while there is no target.
    func targetValue(of card: Card) -> String? {
        guard let target = card.target, let catalog = gitHubDirectory()?.storedCatalog else { return nil }
        return IssueTargetText.value(of: target, in: catalog)
    }

    // MARK: Adjusting (plan ki-vorschlaege-anpassen, task C1)

    /// True for an open card of a function with an editor; the voice-free sheet needs the context of the app.
    private func canAdjust(_ card: Card) -> Bool {
        guard let editorContext, card.status == .pending, NoteSuggestionRules.allowedTools.contains(card.call.name) else { return false }
        return ProposalEditors.make(for: card.call, context: editorContext()) != nil
    }

    /// Writes the values into an open card, by the user (`.byUser`) or taken from an answer of ChatGPT (`.byAssistant`), like
    /// `setTarget` does for the target: the call is rewritten and the card is described again. Nothing is sent or run; the card
    /// is carried out by "Bestätigen" only, with the values it shows now. The target of an issue stays as it is unless the new
    /// values name another one. Returns the new call, or `nil` for a card that is not open.
    @discardableResult
    func adjust(_ call: ToolCall, arguments: Data, mark: ProposalMark = .byUser) -> ToolCall? {
        guard let index = cards.firstIndex(where: { $0.id == call.id }), cards[index].status == .pending,
              let new = ProposalArguments.decode(arguments) else { return nil }
        let before = cards[index]
        let original = before.proposed ?? before.call
        let adjusted = ToolCall(id: before.call.id, name: before.call.name, arguments: arguments)
        let isProposal = (ProposalArguments.decode(original.arguments) as NSDictionary?)?.isEqual(to: new) == true
        cards[index].call = adjusted
        // Adjusting back to the proposal is no adjustment.
        cards[index].proposed = isProposal ? nil : original
        cards[index].mark = isProposal ? nil : mark
        if before.isIssue { cards[index].target = target(of: new, replacing: before) }
        cards[index].text = describe(cards[index])
        return adjusted
    }

    /// Puts the proposal of the model back; `nil` when the card was not adjusted.
    @discardableResult
    func resetAdjustment(_ call: ToolCall) -> ToolCall? {
        guard let index = cards.firstIndex(where: { $0.id == call.id }), cards[index].status == .pending,
              let original = cards[index].proposed else { return nil }
        return adjust(call, arguments: original.arguments)
    }

    func isAdjusted(_ call: ToolCall) -> Bool {
        cards.first { $0.id == call.id }?.proposed != nil
    }

    /// The target of an issue after its arguments changed: unchanged repository and projects keep what was resolved; other
    /// values are resolved against the stored catalog, and a target that cannot be resolved is chosen again.
    private func target(of arguments: [String: Any], replacing card: Card) -> AppTools.GitHubTarget? {
        let repository = (arguments["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let projectIDs = arguments["project_ids"] as? [String]
        if let target = card.target, target.repository == repository, projectIDs == nil || projectIDs == target.projectIDs { return target }
        guard let repository, let catalog = gitHubDirectory()?.storedCatalog,
              case .success(let resolved) = AppTools.gitHubTarget(repository: repository, projectIDs: projectIDs, catalog: catalog) else { return nil }
        return resolved
    }

    /// The editor for an open card; `nil` for a function without one and for a card that is not open.
    func proposalEditor(for call: ToolCall) -> (any ProposalEditor)? {
        guard let editorContext, let card = cards.first(where: { $0.id == call.id }), card.status == .pending,
              NoteSuggestionRules.allowedTools.contains(card.call.name) else { return nil }
        return ProposalEditors.make(for: card.call, context: editorContext())
    }

    /// An editor that starts from other arguments than the card holds, e.g. the answer of ChatGPT to a follow-up.
    func proposalEditor(for call: ToolCall, arguments: Data) -> (any ProposalEditor)? {
        guard let editorContext, let card = cards.first(where: { $0.id == call.id }), card.status == .pending,
              NoteSuggestionRules.allowedTools.contains(card.call.name) else { return nil }
        return ProposalEditors.make(for: ToolCall(id: card.call.id, name: card.call.name, arguments: arguments), context: editorContext())
    }

    /// Runs the function of a card once; no further request follows. An issue without a target is not run.
    func confirm(_ id: String) async {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].status == .pending,
              !cards[index].needsTarget else { return }
        let call = cards[index].call
        let mine = generation
        cards[index].status = .running
        let output = await tools.run(call)
        // The sheet closed while the function ran: the result has nowhere to go, the function itself was done.
        guard mine == generation, let current = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[current].status = .done(output)
        cards[current].time = now()
        if ActionCardView.error(in: output) == nil, let noteID { notes.addDerivedAction(noteID) }
    }

    func decline(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].status == .pending else { return }
        cards[index].status = .declined
    }

    /// Confirms every open card that has what it needs; issues that wait for a target or that are confirmed alone stay open.
    func confirmAll() async {
        for card in cards where isBatchConfirmable(card) { await confirm(card.id) }
    }

    /// The sheet closed or the text changed: drops the cards and any answer that is still on its way.
    func reset() {
        generation += 1
        cards = []
        phase = .idle
    }

    // MARK: Prompt

    static var instructions: String { instructions(gitHub: false) }

    /// With `gitHub` the model may name a GitHub issue; the target is resolved on the device and nothing about the user's
    /// repositories is sent.
    static func instructions(gitHub: Bool) -> String {
        let newTask = gitHub
            ? #"A new task needs no id. Use source "github" only when the note asks for a GitHub issue or names a repository; then pass the repository name from the note if there is one (else null), project_ids null and assignees null. Otherwise use source null, "local" or "reminders"."#
            : #"A new task needs no id; create it with source null or "local" or "reminders", never "github"."#
        return """
        You turn one short personal note into suggested changes for a task and calendar app. You may only answer with \
        function calls; write no text.
        - Suggest at most 5 function calls, and only what the note clearly asks for or implies. Suggest nothing when the \
        note holds no such wish: then answer with no function call.
        - Use only ids that appear in the given tasks and events. Never invent an id. update_event works only on events \
        marked time_block. \(newTask)
        - Dates are in the user's time zone. Today's date and time are given. Resolve words such as "tomorrow" from it.
        - Write titles in the language of the note and keep them short.
        - Every change is shown to the user and applied only after they confirm it.
        """
    }

    static func request(text: String, kind: NoteKind, context: NoteSuggestionContext, now: Date, calendar: Calendar = .tagwerk) -> String {
        let day = AIPlanner.dayString(PlanDay(date: now, calendar: calendar))
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let clock = AIPlanner.time((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        let origin = kind == .morning ? "morning start" : "evening wrap-up"
        return """
        Today: \(day), \(clock). The note is the \(origin) note.
        Note:
        \(MarkdownText.plainText(text))

        Open tasks and events of the next 7 days as JSON:
        \(context.json)
        """
    }

    // MARK: Helpers

    nonisolated private static func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> [ToolCall] {
        var calls: [ToolCall] = []
        var completed = false
        for try await event in stream {
            switch event {
            case .functionCall(let id, let name, let arguments): calls.append(ToolCall(id: id, name: name, arguments: Data(arguments.utf8)))
            case .completed: completed = true
            case .textDelta: break
            }
        }
        // A stream that ends without `completed` was cut off: no cards from a partial answer.
        guard completed else { throw ChatGPTError.incomplete }
        return calls
    }

    private struct TimedOut: Error {}

    private func withTimeout(_ operation: @escaping @Sendable () async throws -> [ToolCall]) async throws -> [ToolCall] {
        let limit = timeout
        return try await withThrowingTaskGroup(of: [ToolCall].self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    /// Messages never contain the note or anything of the answer.
    static func message(for error: Error) -> String {
        switch error as? ChatGPTError {
        case .network: String(localized: "Keine Verbindung. Vorschläge brauchen Internet.")
        case .notSignedIn, .invalidUser: String(localized: "Die Anmeldung bei ChatGPT ist abgelaufen. Melde dich unter Einstellungen › KI neu an.")
        case .usageLimit: String(localized: "ChatGPT nimmt gerade keine Anfragen an. Versuch es später noch einmal.")
        default: String(localized: "Die Vorschläge konnten nicht geholt werden. Versuch es noch einmal.")
        }
    }
}

// MARK: Sheet "Vorschlag anpassen"

extension NoteSuggestionModel: CardAdjusting {
    /// The follow-up about one card arrives with task C2; until then the sheet shows only the fields.
    var cardFollowUpHasConsent: Bool { false }

    func reviseCard(_ call: ToolCall, current: Data, comment: String) async throws -> CardReviser.Answer {
        throw CardReviser.Failure.consentMissing
    }
}
