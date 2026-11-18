import Foundation
import TagwerkCore

/// One recognizer at a time, shared by dictation and the voice mode (plan voice-chat, stage 2, point 12).
///
/// - `start` cancels a running recognizer first and only then opens the microphone again.
/// - After `stop` exactly one `.finished` or `.failed` follows; a recognizer that does not finish within
///   `stopTimeout` (checked by `tick`) is cancelled and reported as `.finished`.
/// - After `cancel` no event follows; the caller already knows.
/// - A recognizer that ends on its own without an event counts as `.finished`.
@MainActor
final class RecognitionSession {
    enum Event: Equatable {
        /// The recognizer runs; the microphone is open.
        case started
        case text(final: String, volatile: String)
        case level(Float)
        case finished
        case failed(RecognitionFailure)
    }

    static let stopTimeout: TimeInterval = 3

    var onEvent: (Event) -> Void = { _ in }
    private(set) var isActive = false
    var isStopping: Bool { stoppingSince != nil }

    private let makeRecognizer: () -> SpeechRecognizing
    private let now: () -> Date
    private var recognizer: SpeechRecognizing?
    private var listening: Task<Void, Never>?
    private var stoppingSince: Date?
    /// Events of older recognizers carry an old generation and are dropped.
    private var generation = 0

    init(makeRecognizer: @escaping () -> SpeechRecognizing, now: @escaping () -> Date = Date.init) {
        self.makeRecognizer = makeRecognizer
        self.now = now
    }

    func start(_ language: VoiceLanguage) {
        let previous = recognizer
        listening?.cancel()
        generation += 1
        let current = generation
        let recognizer = makeRecognizer()
        self.recognizer = recognizer
        stoppingSince = nil
        isActive = true
        listening = Task { [weak self] in
            // The old recording must be gone before the new one takes the microphone.
            await previous?.cancel()
            let events = await recognizer.start(language: language)
            guard let self, current == self.generation, !Task.isCancelled else {
                // Cancelled while starting: release the microphone.
                await recognizer.cancel()
                return
            }
            self.onEvent(.started)
            for await event in events {
                guard current == self.generation, !Task.isCancelled else { return }
                switch event {
                case .text(let final, let volatile): self.onEvent(.text(final: final, volatile: volatile))
                case .level(let value): self.onEvent(.level(value))
                case .finished: return self.end(.finished)
                case .failed(let failure): return self.end(.failed(failure))
                }
            }
            if current == self.generation, !Task.isCancelled { self.end(.finished) }
        }
    }

    func stop() {
        guard isActive, stoppingSince == nil else { return }
        stoppingSince = now()
        let recognizer = recognizer
        Task { await recognizer?.stop() }
    }

    func cancel() {
        guard isActive else { return }
        let recognizer = recognizer
        reset()
        listening?.cancel()
        listening = nil
        Task { await recognizer?.cancel() }
    }

    /// Gives up a stop that takes longer than `stopTimeout`; the text so far counts as final.
    func tick() {
        guard let stoppingSince, now().timeIntervalSince(stoppingSince) >= Self.stopTimeout else { return }
        let recognizer = recognizer
        listening?.cancel()
        listening = nil
        Task { await recognizer?.cancel() }
        end(.finished)
    }

    private func end(_ event: Event) {
        reset()
        onEvent(event)
    }

    private func reset() {
        generation += 1
        isActive = false
        recognizer = nil
        stoppingSince = nil
    }
}
