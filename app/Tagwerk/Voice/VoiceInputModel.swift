import Foundation
import Observation
import TagwerkCore

/// One message field's dictation (mockups SP1a, SP2a, SP8): wires `DictationMachine` to a recognizer, the
/// field's text and the send action. Nothing is sent without a tap on ↑ (§8.4).
@MainActor @Observable
final class VoiceInputModel {
    private(set) var machine: DictationMachine
    private(set) var level: Float = 0
    /// The field's text came from a recording; a message sent from it counts as spoken.
    private(set) var draftIsSpoken = false

    /// Field access and send action, set by the composer.
    @ObservationIgnored var readDraft: () -> String = { "" }
    @ObservationIgnored var writeDraft: (String) -> Void = { _ in }
    @ObservationIgnored var onSend: (String) -> Void = { _ in }
    /// Called when a recording starts, e.g. to stop reading aloud.
    @ObservationIgnored var onRecordingStarts: () -> Void = {}

    @ObservationIgnored private let makeRecognizer: () -> SpeechRecognizing
    @ObservationIgnored private let isExplained: () -> Bool
    @ObservationIgnored private let markExplained: () -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var recognizer: SpeechRecognizing?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var ticking: Task<Void, Never>?

    init(language: VoiceLanguage, makeRecognizer: @escaping () -> SpeechRecognizing, isExplained: @escaping () -> Bool,
         markExplained: @escaping () -> Void, now: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        machine = DictationMachine(language: language)
        self.makeRecognizer = makeRecognizer
        self.isExplained = isExplained
        self.markExplained = markExplained
        self.now = now
        self.sleep = sleep
    }

    var phase: DictationMachine.Phase { machine.phase }
    var isRecording: Bool {
        switch machine.phase {
        case .preparing, .recording, .stopping: true
        default: false
        }
    }
    var displayText: String { machine.displayText }
    var language: VoiceLanguage { machine.language }
    func elapsed() -> TimeInterval { machine.elapsed(now: now()) }

    // MARK: Actions

    func tapMicrophone() { apply(machine.tapMicrophone(draft: readDraft(), explained: isExplained(), now: now())) }
    func continueAfterExplanation() { apply(machine.continueAfterExplanation(draft: readDraft(), now: now())) }
    func dismissExplanation() { apply(machine.dismissExplanation()) }
    func finish() { apply(machine.finish()) }
    func send() { apply(machine.send()) }
    func cancel() { apply(machine.cancel()) }
    func switchLanguage() { apply(machine.switchLanguage(now: now())) }
    func setLanguage(_ language: VoiceLanguage) { machine.setLanguage(language) }

    /// The field was sent or cleared by hand: the next text is typed until a new recording fills it.
    func draftConsumed() { draftIsSpoken = false }

    /// Checks the time limits; runs about four times a second while recording or showing a notice.
    func tick() { apply(machine.tick(now: now())) }

    // MARK: Effects

    private func apply(_ effects: [DictationMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .explain:
                break
            case .markExplained:
                markExplained()
            case .start(let language):
                start(language)
            case .restart(let language):
                stopListening(cancel: true)
                start(language)
            case .stop:
                let recognizer = recognizer
                Task { await recognizer?.stop() }
            case .cancel:
                stopListening(cancel: true)
            case .fill(let text):
                writeDraft(text)
                draftIsSpoken = !text.isEmpty
            case .send(let text):
                writeDraft("")
                draftIsSpoken = false
                onSend(text)
            case .restoreDraft(let text):
                writeDraft(text)
            }
        }
        updateTicking()
    }

    private func start(_ language: VoiceLanguage) {
        onRecordingStarts()
        let recognizer = makeRecognizer()
        self.recognizer = recognizer
        listening = Task { [weak self] in
            let events = await recognizer.start(language: language)
            guard let self, !Task.isCancelled else { return }
            if case .preparing = self.machine.phase { self.machine.recordingStarted(now: self.now()) }
            self.updateTicking()
            for await event in events {
                guard !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: RecognitionEvent) {
        switch event {
        case .text(let final, let volatile):
            machine.received(final: final, volatile: volatile, now: now())
        case .level(let value):
            level = value
        case .finished:
            level = 0
            recognizer = nil
            apply(machine.recognizerFinished(now: now()))
        case .failed(let failure):
            level = 0
            recognizer = nil
            apply(machine.recognizerFailed(Self.notice(for: failure), now: now()))
        }
    }

    private func stopListening(cancel: Bool) {
        listening?.cancel()
        listening = nil
        level = 0
        if cancel, let recognizer {
            Task { await recognizer.cancel() }
        }
        recognizer = nil
    }

    private func updateTicking() {
        let active: Bool = switch machine.phase {
        case .recording, .notice: true
        default: false
        }
        if active, ticking == nil {
            ticking = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sleep(.milliseconds(250))
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        } else if !active {
            ticking?.cancel()
            ticking = nil
        }
    }

    static func notice(for failure: RecognitionFailure) -> DictationMachine.Notice {
        switch failure {
        case .unsupported: .unsupported
        case .assetUnavailable: .assetUnavailable
        case .microphoneDenied: .permissionDenied
        case .interrupted: .interrupted
        case .engine: .failed
        }
    }
}
