import AIKit
import Foundation
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
        let call: ToolCall
        let text: AssistantModel.ActionCard
        var status: ChatMessage.ActionStatus
        var time: Date?
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
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeout: Duration
    /// Counts resets and requests; an answer that arrives for an older count is dropped (review focus 5).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var noteID: UUID?

    init(responder: any ResponseStreaming, model: @escaping @MainActor () async throws -> String, tools: any ToolHandler,
         describer: ActionCardDescriber, notes: NoteStore, hasConsent: @escaping @MainActor () -> Bool,
         context: @escaping @MainActor () -> NoteSuggestionContext, now: @escaping () -> Date = Date.init,
         timeout: Duration = .seconds(60)) {
        self.responder = responder
        self.model = model
        self.tools = tools
        self.describer = describer
        self.notes = notes
        self.hasConsent = hasConsent
        self.context = context
        self.now = now
        self.timeout = timeout
    }

    var openCount: Int { cards.filter { $0.status == .pending }.count }

    // MARK: Request

    /// One request. Without consent nothing happens, not even the model list is loaded.
    func fetch(noteID: UUID, text: String, kind: NoteKind) async {
        // Private notes (journal, later Bible Study) never go to ChatGPT, whatever the consent says. The stored kind counts
        // as well as the one the caller names.
        guard !kind.isPrivate, notes.note(id: noteID)?.kind.isPrivate != true else { return }
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
            let request = Self.request(text: text, kind: kind, context: sent, now: now())
            let tools = self.tools.definitions.filter { NoteSuggestionRules.allowedTools.contains($0.name) }
            let calls = try await withTimeout { [responder] in
                try await Self.collect(responder.respond(model: slug, instructions: Self.instructions, input: [.user(request)],
                                                         tools: tools, jsonSchema: nil))
            }
            guard mine == generation else { return }
            notes.markProcessed(noteID, at: now())
            let accepted = NoteSuggestionRules.accepted(calls, context: sent)
            cards = accepted.map { Card(call: $0, text: describer.describe($0), status: .pending, time: nil) }
            phase = cards.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            if mine == generation { phase = .idle }
        } catch {
            guard mine == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    /// Runs the function of a card once; no further request follows.
    func confirm(_ id: String) async {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].status == .pending else { return }
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

    func confirmAll() async {
        for card in cards where card.status == .pending { await confirm(card.id) }
    }

    /// The sheet closed or the text changed: drops the cards and any answer that is still on its way.
    func reset() {
        generation += 1
        cards = []
        phase = .idle
    }

    // MARK: Prompt

    static var instructions: String {
        """
        You turn one short personal note into suggested changes for a task and calendar app. You may only answer with \
        function calls; write no text.
        - Suggest at most 5 function calls, and only what the note clearly asks for or implies. Suggest nothing when the \
        note holds no such wish: then answer with no function call.
        - Use only ids that appear in the given tasks and events. Never invent an id. update_event works only on events \
        marked time_block. A new task needs no id; create it with source null or "local" or "reminders", never "github".
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
        \(text)

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
