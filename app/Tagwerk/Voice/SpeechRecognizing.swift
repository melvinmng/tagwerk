import AVFoundation
import Foundation
import Speech
import Synchronization
import TagwerkCore
import UIKit

/// Which Apple transcriber turns speech into text.
enum TranscriberKind: String, CaseIterable, Sendable {
    /// `SpeechTranscriber`: general speech, no punctuation option.
    case speech
    /// `DictationTranscriber`: dictation with punctuation, tuned for short messages.
    case dictation
}

enum RecognitionFailure: Error, Equatable, Sendable {
    case unsupported
    case assetUnavailable
    case microphoneDenied
    case interrupted
    case engine(String)
}

enum RecognitionEvent: Equatable, Sendable {
    /// All final text so far and the still-changing tail.
    case text(final: String, volatile: String)
    /// Input level 0...1, about ten times a second.
    case level(Float)
    case finished
    case failed(RecognitionFailure)
}

/// Speech to text on the device. One recording at a time.
protocol SpeechRecognizing: AnyObject, Sendable {
    func start(language: VoiceLanguage) async -> AsyncStream<RecognitionEvent>
    /// Ends the recording; the remaining audio becomes final text, then `.finished` arrives.
    func stop() async
    /// Ends the recording and drops what was not final yet.
    func cancel() async
}

/// Joins final and volatile results the way they arrive from the analyzer.
struct TranscriptAccumulator: Equatable, Sendable {
    private(set) var final = ""
    private(set) var volatile = ""

    mutating func add(_ text: String, isFinal: Bool) {
        if isFinal {
            final = Self.join(final, text)
            volatile = ""
        } else {
            volatile = text
        }
    }

    var event: RecognitionEvent { .text(final: final, volatile: volatile) }
    var full: String { Self.join(final, volatile) }

    static func join(_ head: String, _ tail: String) -> String {
        let head = head.trimmingCharacters(in: .whitespaces)
        let tail = tail.trimmingCharacters(in: .whitespaces)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}

enum AudioLevel {
    /// RMS of float samples mapped to 0...1 over a -50 dB...0 dB range.
    static func unit(fromRMSOf samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return max(0, min(1, (decibels + 50) / 50))
    }
}

/// `SpeechAnalyzer` fed from the microphone through `AVAudioEngine`.
///
/// One recording at a time. `stop()` or `cancel()` may arrive while `start()` is still preparing (language
/// pack, permission, analyzer); `start()` checks after every suspension and cleans up instead of starting.
final class AppleSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    let kind: TranscriberKind
    private let audio: VoiceAudioSession

    private enum Phase {
        case idle
        /// Preparing; `abort` is set by a `stop()` (`.finished`) or `cancel()` (nil) that arrived meanwhile.
        case starting(continuation: AsyncStream<RecognitionEvent>.Continuation, abort: RecognitionEvent??)
        case running(Session)
    }

    private let phase = Mutex(Phase.idle)

    private final class Session: @unchecked Sendable {
        let engine = AVAudioEngine()
        let analyzer: SpeechAnalyzer
        let converter: AnalyzerInputConverter
        let input: AsyncStream<AnalyzerInput>.Continuation
        let events: AsyncStream<RecognitionEvent>.Continuation
        var resultsTask: Task<Void, Never>?
        var observers: [NSObjectProtocol] = []
        var tapInstalled = false
        let lock = NSLock()
        var lastLevel = Date.distantPast

        init(analyzer: SpeechAnalyzer, converter: AnalyzerInputConverter, input: AsyncStream<AnalyzerInput>.Continuation,
             events: AsyncStream<RecognitionEvent>.Continuation) {
            self.analyzer = analyzer
            self.converter = converter
            self.input = input
            self.events = events
        }
    }

    init(kind: TranscriberKind = .dictation, audio: VoiceAudioSession = SystemVoiceAudioSession.shared) {
        self.kind = kind
        self.audio = audio
    }

    /// The module for `language`, or nil when the device does not support it.
    static func module(_ kind: TranscriberKind, language: VoiceLanguage) async -> (any SpeechModule)? {
        switch kind {
        case .speech:
            guard SpeechTranscriber.isAvailable,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else { return nil }
            return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        case .dictation:
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: language.locale) else { return nil }
            return DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                                        reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
        }
    }

    func start(language: VoiceLanguage) async -> AsyncStream<RecognitionEvent> {
        await cancel()
        let (events, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        phase.withLock { $0 = .starting(continuation: continuation, abort: nil) }
        /// Ends the start with `event` (a failure) unless a stop or cancel arrived; those decide the last event.
        func give(up event: RecognitionEvent) -> AsyncStream<RecognitionEvent> {
            let abort = phase.withLock { phase -> RecognitionEvent?? in
                defer { phase = .idle }
                if case .starting(_, let abort) = phase { return abort }
                return nil
            }
            switch abort {
            case .some(.some(let final)): continuation.yield(final)
            case .some(.none): break
            case .none: continuation.yield(event)
            }
            continuation.finish()
            return events
        }
        var aborted: Bool {
            phase.withLock { phase in
                if case .starting(_, let abort) = phase { return abort != nil }
                return true
            }
        }

        guard let module = await Self.module(kind, language: language) else { return give(up: .failed(.unsupported)) }
        do {
            if await AssetInventory.status(forModules: [module]) != .installed {
                try await AssetInventory.reserve(locale: language.locale)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
            }
        } catch {
            return give(up: .failed(.assetUnavailable))
        }
        if aborted { return give(up: .finished) }
        guard await AVAudioApplication.requestRecordPermission() else { return give(up: .failed(.microphoneDenied)) }
        if aborted { return give(up: .finished) }

        let session: Session
        do {
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [module])
            let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: [module])
            session = Session(analyzer: analyzer, converter: converter, input: inputContinuation, events: continuation)
            try await analyzer.start(inputSequence: inputs)
        } catch {
            return give(up: .failed(.engine(String(describing: error).prefix(160).description)))
        }
        do {
            try audio.activate(.recording)
            Self.installTap(on: session)
            session.tapInstalled = true
            try session.engine.start()
        } catch {
            await teardown(session, cancelAnalysis: true)
            return give(up: .failed(.engine(String(describing: error).prefix(160).description)))
        }
        observeInterruptions(of: session)
        session.resultsTask = Task { [weak self] in
            if let failure = await Self.readResults(of: module, into: continuation) {
                await self?.end(reporting: failure)
            }
        }
        // Publish the session; a stop or cancel that arrived during the last steps is carried out now.
        let abort = phase.withLock { phase -> RecognitionEvent?? in
            defer { phase = .running(session) }
            if case .starting(_, let abort) = phase { return abort }
            return nil
        }
        if let abort {
            if let final = abort { await end(reporting: final) } else { await cancel() }
        }
        return events
    }

    func stop() async {
        if markAbort(.some(.finished)) { return }
        await end(reporting: .finished)
    }

    func cancel() async {
        if markAbort(.some(nil)) { return }
        guard let session = takeSession() else { return }
        await teardown(session, cancelAnalysis: true)
        session.events.finish()
    }

    /// While starting, records the stop or cancel for `start()` to carry out. Returns true when it did.
    private func markAbort(_ abort: RecognitionEvent??) -> Bool {
        phase.withLock { phase in
            guard case .starting(let continuation, let existing) = phase else { return false }
            if existing == nil { phase = .starting(continuation: continuation, abort: abort) }
            return true
        }
    }

    private func takeSession() -> Session? {
        phase.withLock { phase -> Session? in
            guard case .running(let session) = phase else { return nil }
            phase = .idle
            return session
        }
    }

    /// Finalizes what was heard and closes the stream with `final` (`.finished` or a failure).
    private func end(reporting final: RecognitionEvent) async {
        guard let session = takeSession() else { return }
        stopAudio(session)
        let rest = session.lock.withLock { (try? session.converter.flush()) ?? [] }
        for input in rest { session.input.yield(input) }
        session.input.finish()
        try? await session.analyzer.finalizeAndFinishThroughEndOfInput()
        if final == .finished { await session.resultsTask?.value } else { session.resultsTask?.cancel() }
        audio.deactivate(.recording)
        session.events.yield(final)
        session.events.finish()
    }

    private func teardown(_ session: Session, cancelAnalysis: Bool) async {
        stopAudio(session)
        session.input.finish()
        if cancelAnalysis { await session.analyzer.cancelAndFinishNow() }
        session.resultsTask?.cancel()
        audio.deactivate(.recording)
    }

    private func stopAudio(_ session: Session) {
        session.observers.forEach(NotificationCenter.default.removeObserver)
        session.observers = []
        if session.tapInstalled {
            session.engine.inputNode.removeTap(onBus: 0)
            session.tapInstalled = false
        }
        session.engine.stop()
    }

    /// A call, Siri, a route change or the app going to the background ends the recording; the text so far stays.
    private func observeInterruptions(of session: Session) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                                          .AVAudioEngineConfigurationChange, UIApplication.didEnterBackgroundNotification]
        session.observers = names.map { name in
            center.addObserver(forName: name, object: name == .AVAudioEngineConfigurationChange ? session.engine : nil,
                               queue: nil) { [weak self] notification in
                if name == AVAudioSession.interruptionNotification,
                   (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) != AVAudioSession.InterruptionType.began.rawValue {
                    return
                }
                // Only a lost input (headset unplugged) ends the recording, not a new device appearing.
                if name == AVAudioSession.routeChangeNotification,
                   (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) != AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    return
                }
                Task { await self?.end(reporting: .failed(.interrupted)) }
            }
        }
    }

    /// The tap runs on the audio thread; it must not touch the main actor.
    private nonisolated static func installTap(on session: Session) {
        let node = session.engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, time in
            session.lock.lock()
            let inputs = (try? session.converter.convert(buffer, at: time)) ?? []
            let now = Date()
            let reportLevel = now.timeIntervalSince(session.lastLevel) >= 0.1
            if reportLevel { session.lastLevel = now }
            session.lock.unlock()
            for input in inputs { session.input.yield(input) }
            if reportLevel, let channel = buffer.floatChannelData?[0] {
                let level = AudioLevel.unit(fromRMSOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                session.events.yield(.level(level))
            }
        }
    }

    /// Streams results until the analyzer ends; returns a failure when reading broke off.
    private static func readResults(of module: any SpeechModule,
                                    into continuation: AsyncStream<RecognitionEvent>.Continuation) async -> RecognitionEvent? {
        var accumulator = TranscriptAccumulator()
        do {
            if let transcriber = module as? SpeechTranscriber {
                for try await result in transcriber.results {
                    accumulator.add(String(result.text.characters), isFinal: result.isFinal)
                    continuation.yield(accumulator.event)
                }
            } else if let transcriber = module as? DictationTranscriber {
                for try await result in transcriber.results {
                    accumulator.add(String(result.text.characters), isFinal: result.isFinal)
                    continuation.yield(accumulator.event)
                }
            }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return .failed(.engine(String(describing: error).prefix(160).description))
        }
    }
}
