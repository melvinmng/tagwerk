import AIKit
import Foundation

/// Answers planning calls with scripted JSON texts and records what was sent.
final class FakePlanResponder: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String] = []
    private var recorded: [(input: [InputItem], schema: String?)] = []

    func enqueue(_ json: String) { lock.withLock { answers.append(json) } }
    var calls: [(input: [InputItem], schema: String?)] { lock.withLock { recorded } }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let answer = lock.withLock { () -> String? in
            recorded.append((input, jsonSchema?.name))
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            guard let answer else {
                continuation.finish(throwing: ChatGPTError.incomplete)
                return
            }
            continuation.yield(.textDelta(answer))
            continuation.yield(.completed(usage: nil))
            continuation.finish()
        }
    }
}
