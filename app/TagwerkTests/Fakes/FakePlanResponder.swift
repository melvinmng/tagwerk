import AIKit
import Foundation

/// Answers planning calls with scripted JSON texts and records what was sent.
final class FakePlanResponder: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [[StreamEvent]] = []
    private var recorded: [(input: [InputItem], schema: String?)] = []
    private var instructionLog: [String] = []

    func enqueue(_ json: String) { lock.withLock { answers.append([.textDelta(json), .completed(usage: nil)]) } }
    func enqueueEvents(_ events: [StreamEvent]) { lock.withLock { answers.append(events) } }
    var instructions: [String] { lock.withLock { instructionLog } }
    var calls: [(input: [InputItem], schema: String?)] { lock.withLock { recorded } }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let answer = lock.withLock { () -> [StreamEvent]? in
            recorded.append((input, jsonSchema?.name))
            instructionLog.append(instructions)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            guard let answer else {
                continuation.finish(throwing: ChatGPTError.incomplete)
                return
            }
            answer.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
