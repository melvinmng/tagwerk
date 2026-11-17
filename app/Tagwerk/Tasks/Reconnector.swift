import Foundation
import TagwerkCore

/// When and how often a source that could only be read from its cache is retried.
enum ReconnectPolicy {
    /// 30 s, then doubling, at most 5 min.
    static func delay(afterAttempts attempts: Int) -> Duration {
        let seconds = 30 * (1 << min(attempts, 4))
        return .seconds(min(seconds, 300))
    }

    /// Offline or failed sources are retried; signed-out or denied ones need the user.
    static func needsRetry(_ state: SourceState?) -> Bool {
        switch state {
        case .offline?, .failed?: true
        default: false
        }
    }
}

/// Retries one source with growing pauses until it answers again, so the app never stays stuck offline.
@MainActor
final class Reconnector {
    private let model: TaskListModel
    private let source: TaskSource
    private let sleep: @MainActor (Duration) async throws -> Void

    init(model: TaskListModel, source: TaskSource,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.model = model
        self.source = source
        self.sleep = sleep
    }

    func runUntilOnline() async {
        var attempts = 0
        while ReconnectPolicy.needsRetry(model.sourceStates[source]), !Task.isCancelled {
            do {
                try await sleep(ReconnectPolicy.delay(afterAttempts: attempts))
            } catch {
                return  // cancelled
            }
            await model.reload(only: [source])
            attempts += 1
        }
    }
}
