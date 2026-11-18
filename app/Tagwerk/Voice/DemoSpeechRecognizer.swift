import Foundation
import Synchronization
import TagwerkCore

/// Scripted recognizer for simulator screenshots (`-TagwerkDemoVoice`): types a fixed sentence word by word.
final class DemoSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    static func sentence(for language: VoiceLanguage) -> String {
        language == .german ? "Leg die Mail ans Prüfungsamt auf 16 Uhr." : "Move the email to the exam office to 4 PM."
    }

    private let task = Mutex<Task<Void, Never>?>(nil)
    private let continuation = Mutex<AsyncStream<RecognitionEvent>.Continuation?>(nil)
    private let words = Mutex<(shown: [String], all: [String])>(([], []))

    func start(language: VoiceLanguage) async -> AsyncStream<RecognitionEvent> {
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        self.continuation.withLock { $0 = continuation }
        let all = Self.sentence(for: language).split(separator: " ").map(String.init)
        words.withLock { $0 = ([], all) }
        task.withLock {
            $0 = Task {
                for index in all.indices {
                    try? await Task.sleep(for: .milliseconds(450))
                    if Task.isCancelled { return }
                    let shown = Array(all[...index])
                    self.words.withLock { $0.shown = shown }
                    let final = shown.dropLast().joined(separator: " ")
                    continuation.yield(.text(final: final, volatile: shown.last ?? ""))
                    continuation.yield(.level(Float.random(in: 0.3...0.9)))
                }
            }
        }
        return stream
    }

    func stop() async {
        task.withLock { $0?.cancel() }
        let shown = words.withLock { $0.shown }
        let continuation = self.continuation.withLock { value -> AsyncStream<RecognitionEvent>.Continuation? in defer { value = nil }; return value }
        continuation?.yield(.text(final: shown.joined(separator: " "), volatile: ""))
        continuation?.yield(.finished)
        continuation?.finish()
    }

    func cancel() async {
        task.withLock { $0?.cancel() }
        continuation.withLock { $0?.finish(); $0 = nil }
    }
}
