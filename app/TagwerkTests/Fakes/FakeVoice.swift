import Foundation
import TagwerkCore
@testable import Tagwerk

@MainActor
final class FakeSpeaker: SpeechSpeaking {
    var onEvent: ((SpeakerEvent) -> Void)?
    private(set) var spoken: [(sentences: [String], language: VoiceLanguage, voiceID: String?, rate: Float)] = []
    private(set) var stopCount = 0
    var installed: [SpokenVoice] = [
        SpokenVoice(id: "de.default", name: "Anna", language: .german, quality: 1),
        SpokenVoice(id: "de.premium", name: "Petra", language: .german, quality: 3),
        SpokenVoice(id: "en.default", name: "Samantha", language: .english, quality: 1),
    ]

    func speak(_ sentences: [String], language: VoiceLanguage, voiceID: String?, rate: Float) {
        spoken.append((sentences, language, voiceID, rate))
    }

    func stop() { stopCount += 1 }

    func voices(for language: VoiceLanguage) -> [SpokenVoice] { installed.filter { $0.language == language } }

    func emit(_ event: SpeakerEvent) { onEvent?(event) }
}

final class FakeAudioSession: VoiceAudioSession, @unchecked Sendable {
    private let lock = NSLock()
    private var _modes: [VoiceAudioMode] = []
    private var _deactivations = 0
    private var _current: VoiceAudioMode?
    var failing = false

    var modes: [VoiceAudioMode] { lock.withLock { _modes } }
    var deactivations: Int { lock.withLock { _deactivations } }
    var currentMode: VoiceAudioMode? { lock.withLock { _current } }

    func activate(_ mode: VoiceAudioMode) throws {
        if failing { throw URLError(.cannotLoadFromNetwork) }
        lock.withLock {
            guard SystemVoiceAudioSession.reconfigures(requested: mode, current: _current) else { return }
            _modes.append(mode); _current = mode
        }
    }

    func deactivate(_ mode: VoiceAudioMode) {
        lock.withLock {
            guard _current == mode else { return }
            _current = nil
            _deactivations += 1
        }
    }
}

/// Recognizer whose events the test sends by hand.
final class FakeSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<RecognitionEvent>.Continuation?
    private var _started: [VoiceLanguage] = []
    private var _stops = 0
    private var _cancels = 0
    /// Text the recognizer finalises when stopped.
    var finalOnStop: String?
    /// Simulates a recognizer that never answers a stop.
    var ignoresStop = false

    var started: [VoiceLanguage] { lock.withLock { _started } }
    var stops: Int { lock.withLock { _stops } }
    var cancels: Int { lock.withLock { _cancels } }

    func start(language: VoiceLanguage) async -> AsyncStream<RecognitionEvent> {
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        lock.withLock {
            _started.append(language)
            self.continuation = continuation
        }
        return stream
    }

    func send(_ event: RecognitionEvent) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(event)
        if event == .finished { continuation?.finish() }
    }

    func stop() async {
        let continuation = lock.withLock { () -> AsyncStream<RecognitionEvent>.Continuation? in
            _stops += 1
            return self.continuation
        }
        if ignoresStop { return }
        if let finalOnStop { continuation?.yield(.text(final: finalOnStop, volatile: "")) }
        continuation?.yield(.finished)
        continuation?.finish()
    }

    func cancel() async {
        let continuation = lock.withLock { () -> AsyncStream<RecognitionEvent>.Continuation? in
            _cancels += 1
            return self.continuation
        }
        continuation?.finish()
    }
}
