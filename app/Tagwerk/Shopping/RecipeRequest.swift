import AIKit
import Foundation

/// The transport steps that every single request about a recipe shares (`RecipeImporter` reads one, `RecipeTranslator`
/// translates one): collecting a completed answer, the time limit, and what a ChatGPT error means for the caller.
enum RecipeRequest {
    /// What went wrong on the way, before anyone looks at the answer.
    enum TransportFailure: Equatable {
        case network, signedOut, usageLimit, failed
    }

    static func failure(for error: ChatGPTError) -> TransportFailure {
        switch error {
        case .network: .network
        case .notSignedIn, .invalidUser: .signedOut
        case .usageLimit: .usageLimit
        case .server, .incomplete: .failed
        }
    }

    /// Text of a completed answer; a stream that ends without `completed` is an error.
    nonisolated static func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> String {
        var text = ""
        var completed = false
        for try await event in stream {
            switch event {
            case .textDelta(let delta): text += delta
            case .completed: completed = true
            case .functionCall: break
            }
        }
        guard completed else { throw ChatGPTError.incomplete }
        return text
    }

    struct TimedOut: Error {}

    /// Runs `operation` and throws `TimedOut` when it takes longer than `limit`.
    static func withTimeout(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
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
}
