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
    /// Called after `switchLanguage()` changed the language, with the new language; the factory remembers it for the place.
    @ObservationIgnored var onLanguageSwitched: ((VoiceLanguage) -> Void)?
    /// Called when a recording starts, e.g. to stop reading aloud.
    @ObservationIgnored var onRecordingStarts: () -> Void = {}

    @ObservationIgnored private let session: RecognitionSession
    @ObservationIgnored private let isExplained: () -> Bool
    @ObservationIgnored private let markExplained: () -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var ticking: Task<Void, Never>?

    /// The field this dictation belongs to; the language the user switches to is remembered per place.
    let place: DictationPlace

    init(language: VoiceLanguage, place: DictationPlace = .notes, makeRecognizer: @escaping () -> SpeechRecognizing, isExplained: @escaping () -> Bool,
         markExplained: @escaping () -> Void, now: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.place = place
        machine = DictationMachine(language: language)
        session = RecognitionSession(makeRecognizer: makeRecognizer, now: now)
        self.isExplained = isExplained
        self.markExplained = markExplained
        self.now = now
        self.sleep = sleep
        session.onEvent = { [weak self] event in self?.handle(event) }
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
    func switchLanguage() {
        let before = machine.language
        apply(machine.switchLanguage(now: now()))
        if machine.language != before { onLanguageSwitched?(machine.language) }
    }
    func setLanguage(_ language: VoiceLanguage) { machine.setLanguage(language) }

    /// The field was sent or cleared by hand: the next text is typed until a new recording fills it.
    func draftConsumed() { draftIsSpoken = false }

    /// Checks the time limits; runs about four times a second while recording, stopping or showing a notice.
    /// A recognizer that does not finish within three seconds after a stop is given up on.
    func tick() {
        session.tick()
        apply(machine.tick(now: now()))
    }

    // MARK: Effects

    private func apply(_ effects: [DictationMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .explain:
                break
            case .markExplained:
                markExplained()
            case .start(let language), .restart(let language):
                onRecordingStarts()
                session.start(language)
            case .stop:
                session.stop()
            case .cancel:
                session.cancel()
                level = 0
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

    private func handle(_ event: RecognitionSession.Event) {
        switch event {
        case .started:
            if case .preparing = machine.phase { machine.recordingStarted(now: now()) }
            updateTicking()
        case .text(let final, let volatile):
            machine.received(final: final, volatile: volatile, now: now())
        case .level(let value):
            level = value
        case .finished:
            level = 0
            apply(machine.recognizerFinished(now: now()))
        case .failed(let failure):
            level = 0
            apply(machine.recognizerFailed(Self.notice(for: failure), now: now()))
        }
    }

    private func updateTicking() {
        let active: Bool = switch machine.phase {
        case .recording, .stopping, .notice: true
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
