import AIKit
import Foundation

/// Answers planning calls with scripted JSON texts and records what was sent.
final class FakePlanResponder: ResponseStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [[StreamEvent]] = []
    /// Failure of the answer at the same position; nil answers normally.
    private var failures: [ChatGPTError?] = []
    private var recorded: [(input: [InputItem], schema: String?)] = []
    private var instructionLog: [String] = []
    private var schemaLog: [Data] = []

    func enqueue(_ json: String) { lock.withLock { answers.append([.textDelta(json), .completed(usage: nil)]); failures.append(nil) } }
    func enqueueEvents(_ events: [StreamEvent]) { lock.withLock { answers.append(events); failures.append(nil) } }
    func enqueueFailure(_ error: ChatGPTError) { lock.withLock { answers.append([]); failures.append(error) } }
    var instructions: [String] { lock.withLock { instructionLog } }
    /// The JSON schema of each request, `Data()` for a request without one.
    var schemas: [Data] { lock.withLock { schemaLog } }
    var calls: [(input: [InputItem], schema: String?)] { lock.withLock { recorded } }

    func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                 jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let (answer, failure) = lock.withLock { () -> ([StreamEvent]?, ChatGPTError?) in
            recorded.append((input, jsonSchema?.name))
            instructionLog.append(instructions)
            schemaLog.append(jsonSchema?.schema ?? Data())
            return answers.isEmpty ? (nil, nil) : (answers.removeFirst(), failures.removeFirst())
        }
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            guard let answer else {
                continuation.finish(throwing: ChatGPTError.incomplete)
                return
            }
            answer.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
