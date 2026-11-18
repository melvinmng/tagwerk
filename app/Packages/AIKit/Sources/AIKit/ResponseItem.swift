import Foundation
import Synchronization

/// A model the user can pick, from `GET /v1/models` (`visibility == "list"` only).
public struct AIModel: Sendable, Hashable, Codable, Identifiable {
    public var slug: String
    public var displayName: String
    /// Reasoning efforts the model accepts ("low" … "ultra"), in server order.
    public var reasoningLevels: [String]
    /// The effort the server uses when none is sent.
    public var defaultReasoning: String?
    public var id: String { slug }

    public init(slug: String, displayName: String, reasoningLevels: [String] = [], defaultReasoning: String? = nil) {
        self.slug = slug
        self.displayName = displayName
        self.reasoningLevels = reasoningLevels
        self.defaultReasoning = defaultReasoning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        reasoningLevels = try container.decodeIfPresent([String].self, forKey: .reasoningLevels) ?? []
        defaultReasoning = try container.decodeIfPresent(String.self, forKey: .defaultReasoning)
    }
}

/// Settings sent with every call; changed by the app (model page), read when a request is built.
public final class AIRequestOptions: Sendable {
    private let effort = Mutex<String?>(nil)

    public init() {}

    /// `reasoning.effort`; `nil` leaves the model's default.
    public var reasoningEffort: String? {
        get { effort.withLock { $0 } }
        set { effort.withLock { $0 = newValue } }
    }
}

/// One entry of the conversation history sent as `input`. The whole history goes with every call,
/// because `store:false` allows no server-side continuation.
///
/// Only messages and function calls are sent back; reasoning items are never needed
/// (device capture of 2026-11-18).
public enum InputItem: Sendable, Equatable, Codable {
    case user(String)
    case assistant(String)
    case functionCall(callID: String, name: String, arguments: String)
    case functionOutput(callID: String, output: String)

    /// The Responses API representation.
    var requestJSON: [String: Any] {
        switch self {
        case .user(let text):
            ["role": "user", "content": [["type": "input_text", "text": text]]]
        case .assistant(let text):
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]
        case .functionCall(let callID, let name, let arguments):
            ["type": "function_call", "call_id": callID, "name": name, "arguments": arguments]
        case .functionOutput(let callID, let output):
            ["type": "function_call_output", "call_id": callID, "output": output]
        }
    }
}

/// A function the model may call. `parameters` is a JSON schema.
public struct ToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: Data
    public var strict: Bool

    public init(name: String, description: String, parameters: Data, strict: Bool = true) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }

    func requestJSON() throws -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": try JSONSerialization.jsonObject(with: parameters),
            "strict": strict,
        ]
    }
}

/// What a response stream delivers. Text arrives as it is generated; function calls only after
/// `response.completed`, so a cut stream never leads to half-executed calls.
public enum StreamEvent: Sendable, Equatable {
    case textDelta(String)
    case functionCall(callID: String, name: String, arguments: String)
    /// The response finished; `usage` is the total token count, if reported.
    case completed(usage: Int?)
}
