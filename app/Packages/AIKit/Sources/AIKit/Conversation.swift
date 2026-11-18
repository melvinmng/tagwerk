import Foundation
import Observation

/// Anything that streams a model response; `ChatGPTClient` in the app, a fake in tests.
public protocol ResponseStreaming: Sendable {
    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error>
}

extension ChatGPTClient: ResponseStreaming {}

/// A function call the model asked for.
public struct ToolCall: Sendable, Identifiable, Equatable {
    /// The `call_id` of the call.
    public let id: String
    public let name: String
    public let arguments: Data

    public init(id: String, name: String, arguments: Data) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Read functions run at once; write functions wait for the user's confirmation.
public enum ToolKind: Sendable {
    case read
    case write
}

/// Executes the app functions offered to the model. Errors are returned as output text,
/// so the model learns about them and can react.
@MainActor
public protocol ToolHandler: AnyObject {
    var definitions: [ToolDefinition] { get }
    func kind(of name: String) -> ToolKind
    func run(_ call: ToolCall) async -> String
}

/// One entry of the visible chat.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum ActionStatus: Equatable, Sendable {
        case pending
        case running
        case done(String)
        case declined
    }

    public enum Content: Equatable, Sendable {
        case user(String)
        case assistant(String)
        /// A write function as an action card.
        case action(ToolCall, ActionStatus)
    }

    public let id: Int
    public let content: Content
}

/// A chat with the model that can call app functions.
///
/// - The whole (truncated) history is sent with every call; the view context goes into `instructions`.
/// - Read calls run immediately, write calls wait for `confirm` or `decline`.
/// - Once every call of a round has an output, the next call follows; at most 8 calls per user message.
@MainActor
@Observable
public final class Conversation {
    public enum State: Equatable, Sendable {
        case idle
        case streaming
        case waitingForConfirmation
        case runningAction
        case failed(ChatGPTError)
    }

    public static let maxRounds = 8
    public static let maxInputItems = 40
    public static let maxOutputBytes = 16_384
    public static let declinedOutput = #"{"status":"declined","message":"Vom Nutzer abgelehnt."}"#
    public static let roundLimitOutput = #"{"status":"not_run","message":"Nicht ausgeführt: Grenze an Funktionsaufrufen erreicht."}"#
    public static let interruptedOutput = #"{"status":"not_run","message":"Nicht ausgeführt: Das Gespräch wurde unterbrochen."}"#
    public static let clippedNotice = "\n[gekürzt: Die Ausgabe war länger als 16 KB.]"

    public private(set) var history: [InputItem]
    public private(set) var pendingActions: [ToolCall] = []
    public private(set) var state: State = .idle
    /// Text of the answer being streamed right now.
    public private(set) var streamingText = ""
    /// True once older messages are no longer sent to the model.
    public private(set) var truncatedNotice = false
    /// True when the last user message hit the limit of function call rounds.
    public private(set) var roundLimitReached = false

    @ObservationIgnored private let responder: ResponseStreaming
    @ObservationIgnored private let tools: ToolHandler
    @ObservationIgnored private let model: @MainActor () async throws -> String
    @ObservationIgnored private let instructions: @MainActor () -> String
    @ObservationIgnored private var rounds = 0
    @ObservationIgnored private var runningCallID: String?

    /// Restores a conversation. Calls without an output (the app ended while a card was open)
    /// are closed with a fixed output, so the history is always valid input.
    public init(responder: ResponseStreaming, tools: ToolHandler, model: @escaping @MainActor () async throws -> String,
                instructions: @escaping @MainActor () -> String, history: [InputItem] = []) {
        self.responder = responder
        self.tools = tools
        self.model = model
        self.instructions = instructions
        self.history = history
        self.truncatedNotice = history.count > Self.maxInputItems
        closeOpenCalls(output: Self.interruptedOutput)
    }

    // MARK: Actions

    public func send(_ text: String) async {
        closeOpenCalls(output: Self.declinedOutput)
        history.append(.user(text))
        rounds = 0
        roundLimitReached = false
        await runRound()
    }

    public func confirm(_ call: ToolCall) async {
        guard pendingActions.contains(call), runningCallID == nil else { return }
        runningCallID = call.id
        state = .runningAction
        let output = Self.clipped(await tools.run(call))
        runningCallID = nil
        resolve(call, output: output)
        await continueIfResolved()
    }

    public func decline(_ call: ToolCall) async {
        guard pendingActions.contains(call), runningCallID != call.id else { return }
        resolve(call, output: Self.declinedOutput)
        await continueIfResolved()
    }

    /// Repeats the failed call with the same history.
    public func retry() async {
        guard case .failed = state else { return }
        rounds = max(0, rounds - 1)
        await runRound()
    }

    public func clear() {
        history = []
        pendingActions = []
        streamingText = ""
        truncatedNotice = false
        roundLimitReached = false
        rounds = 0
        state = .idle
    }

    // MARK: Visible messages

    public var messages: [ChatMessage] {
        var outputs: [String: String] = [:]
        for case .functionOutput(let id, let output) in history { outputs[id] = output }
        var result: [ChatMessage] = []
        for (index, item) in history.enumerated() {
            switch item {
            case .user(let text):
                result.append(ChatMessage(id: index, content: .user(text)))
            case .assistant(let text):
                result.append(ChatMessage(id: index, content: .assistant(text)))
            case .functionCall(let id, let name, let arguments):
                guard tools.kind(of: name) == .write else { continue }
                let call = ToolCall(id: id, name: name, arguments: Data(arguments.utf8))
                result.append(ChatMessage(id: index, content: .action(call, status(of: id, output: outputs[id]))))
            case .functionOutput:
                continue
            }
        }
        return result
    }

    private func status(of id: String, output: String?) -> ChatMessage.ActionStatus {
        if runningCallID == id { return .running }
        guard let output else { return .pending }
        return output == Self.declinedOutput ? .declined : .done(output)
    }

    // MARK: Rounds

    private func runRound() async {
        rounds += 1
        state = .streaming
        streamingText = ""
        var calls: [ToolCall] = []
        do {
            let model = try await model()
            let input = Self.truncated(history)
            truncatedNotice = truncatedNotice || input.count < history.count
            let stream = responder.respond(model: model, instructions: instructions(), input: input,
                                           tools: tools.definitions, jsonSchema: nil)
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    streamingText += delta
                case .functionCall(let id, let name, let arguments):
                    calls.append(ToolCall(id: id, name: name, arguments: Data(arguments.utf8)))
                case .completed:
                    break
                }
            }
        } catch {
            // Half answers and half calls are discarded; the user can retry.
            streamingText = ""
            state = .failed(error as? ChatGPTError ?? .network)
            return
        }

        if !streamingText.isEmpty { history.append(.assistant(streamingText)) }
        streamingText = ""
        for call in calls {
            history.append(.functionCall(callID: call.id, name: call.name, arguments: String(decoding: call.arguments, as: UTF8.self)))
        }
        guard !calls.isEmpty else {
            state = .idle
            return
        }
        if rounds >= Self.maxRounds {
            for call in calls { history.append(.functionOutput(callID: call.id, output: Self.roundLimitOutput)) }
            roundLimitReached = true
            state = .idle
            return
        }
        for call in calls where tools.kind(of: call.name) == .read {
            history.append(.functionOutput(callID: call.id, output: Self.clipped(await tools.run(call))))
        }
        pendingActions = calls.filter { tools.kind(of: $0.name) == .write }
        await continueIfResolved()
    }

    private func resolve(_ call: ToolCall, output: String) {
        history.append(.functionOutput(callID: call.id, output: output))
        pendingActions.removeAll { $0 == call }
    }

    private func continueIfResolved() async {
        if pendingActions.isEmpty {
            await runRound()
        } else {
            state = .waitingForConfirmation
        }
    }

    private func closeOpenCalls(output: String) {
        for id in Self.openCallIDs(in: history) {
            history.append(.functionOutput(callID: id, output: output))
        }
        pendingActions = []
    }

    // MARK: Helpers

    /// Call IDs without an output, in history order.
    static func openCallIDs(in history: [InputItem]) -> [String] {
        var answered = Set<String>()
        for case .functionOutput(let id, _) in history { answered.insert(id) }
        var open: [String] = []
        for case .functionCall(let id, _, _) in history where !answered.contains(id) && !open.contains(id) {
            open.append(id)
        }
        return open
    }

    /// The last items, cut only at a user message so calls and their outputs stay together.
    /// A single turn longer than the limit is kept whole from its user message.
    static func truncated(_ history: [InputItem]) -> [InputItem] {
        guard history.count > maxInputItems else { return history }
        let earliest = history.count - maxInputItems
        let userIndices = history.indices.filter { if case .user = history[$0] { true } else { false } }
        if let start = userIndices.first(where: { $0 >= earliest }) {
            return Array(history[start...])
        }
        if let lastUser = userIndices.last {
            return Array(history[lastUser...])
        }
        return Array(history.suffix(maxInputItems))
    }

    /// Keeps a tool output within 16 KB (UTF-8), cut at a character boundary.
    static func clipped(_ output: String) -> String {
        guard output.utf8.count > maxOutputBytes else { return output }
        var clipped = ""
        var bytes = 0
        for character in output {
            let size = character.utf8.count
            guard bytes + size <= maxOutputBytes else { break }
            clipped.append(character)
            bytes += size
        }
        return clipped + clippedNotice
    }
}
