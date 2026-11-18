import AVFoundation
import Foundation
import Speech
import Synchronization

/// German or English: the two languages Tagwerk recognizes and reads aloud.
enum VoiceLanguage: String, CaseIterable, Sendable {
    case german = "de-DE"
    case english = "en-US"

    var locale: Locale { Locale(identifier: rawValue) }
    var shortName: String { self == .german ? "DE" : "EN" }
}

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
final class AppleSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    let kind: TranscriberKind
    private let state = Mutex(Session?.none)

    private final class Session: @unchecked Sendable {
        let engine = AVAudioEngine()
        let analyzer: SpeechAnalyzer
        let converter: AnalyzerInputConverter
        let input: AsyncStream<AnalyzerInput>.Continuation
        let events: AsyncStream<RecognitionEvent>.Continuation
        var resultsTask: Task<Void, Never>?
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

    init(kind: TranscriberKind = .dictation) {
        self.kind = kind
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
        let (events, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        await cancel()
        guard let module = await Self.module(kind, language: language) else {
            continuation.yield(.failed(.unsupported)); continuation.finish(); return events
        }
        do {
            if await AssetInventory.status(forModules: [module]) != .installed {
                try await AssetInventory.reserve(locale: language.locale)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
            }
        } catch {
            continuation.yield(.failed(.assetUnavailable)); continuation.finish(); return events
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            continuation.yield(.failed(.microphoneDenied)); continuation.finish(); return events
        }
        do {
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [module])
            let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: [module])
            let session = Session(analyzer: analyzer, converter: converter, input: inputContinuation, events: continuation)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            try await analyzer.start(inputSequence: inputs)
            session.resultsTask = Task { await Self.readResults(of: module, into: continuation) }
            Self.installTap(on: session)
            try session.engine.start()
            state.withLock { $0 = session }
        } catch {
            continuation.yield(.failed(.engine(String(describing: error).prefix(160).description)))
            continuation.finish()
        }
        return events
    }

    func stop() async {
        guard let session = state.withLock({ current -> Session? in defer { current = nil }; return current }) else { return }
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        let rest = session.lock.withLock { (try? session.converter.flush()) ?? [] }
        for input in rest { session.input.yield(input) }
        session.input.finish()
        try? await session.analyzer.finalizeAndFinishThroughEndOfInput()
        await session.resultsTask?.value
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        session.events.yield(.finished)
        session.events.finish()
    }

    func cancel() async {
        guard let session = state.withLock({ current -> Session? in defer { current = nil }; return current }) else { return }
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.input.finish()
        await session.analyzer.cancelAndFinishNow()
        session.resultsTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        session.events.finish()
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

    private static func readResults(of module: any SpeechModule, into continuation: AsyncStream<RecognitionEvent>.Continuation) async {
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
        } catch {
            continuation.yield(.failed(.engine(String(describing: error).prefix(160).description)))
        }
    }
}
