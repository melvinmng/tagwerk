import AVFoundation
import Foundation
import Observation
import TagwerkCore
import UIKit

/// What the voice mode needs from the assistant chat; `AssistantModel` provides it.
@MainActor
protocol VoiceModeAssistant: AnyObject {
    var onTurnFinished: ((AssistantModel.TurnOutcome) -> Void)? { get set }
    /// Action cards wait for a tap.
    var hasPendingActions: Bool { get }
    func send(_ text: String, spoken: Bool) async
}

extension AssistantModel: VoiceModeAssistant {
    var hasPendingActions: Bool { conversation?.pendingActions.isEmpty == false }
}

/// Runs the voice mode (mockup SP5a): wires `VoiceModeMachine` to the recognizer, the assistant, the reader
/// and the tone inside one `.conversation` audio session. It is started by the user; a message goes out only
/// after the visible countdown (§8.4).
@MainActor @Observable
final class VoiceModeController {
    struct Settings: Equatable {
        var language: VoiceLanguage
        var sendDelay: TimeInterval
        var silenceLimit: TimeInterval
    }

    private(set) var machine: VoiceModeMachine
    private(set) var level: Float = 0
    /// The answer being read, for the sentence highlight.
    private(set) var answerID: String?

    /// Text for the field of the normal chat ("Nicht senden", "Pause", a failure).
    @ObservationIgnored var onMoveToDraft: (String) -> Void = { _ in }
    /// The voice mode ended; the sheet shows the normal chat again.
    @ObservationIgnored var onEnded: () -> Void = {}

    @ObservationIgnored private let assistant: VoiceModeAssistant
    @ObservationIgnored private let session: RecognitionSession
    @ObservationIgnored private let output: VoiceOutputModel
    @ObservationIgnored private let tone: ToneSounding
    @ObservationIgnored private let audio: VoiceAudioSession
    @ObservationIgnored private let settings: () -> Settings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let keepScreenOn: (Bool) -> Void
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var sending: Task<Void, Never>?
    /// Completions of an older reading (replaced or stopped) are ignored.
    @ObservationIgnored private var speech = 0

    init(assistant: VoiceModeAssistant, makeRecognizer: @escaping () -> SpeechRecognizing, output: VoiceOutputModel,
         tone: ToneSounding, audio: VoiceAudioSession, settings: @escaping () -> Settings,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         keepScreenOn: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 },
         notifications: NotificationCenter = .default) {
        let initial = settings()
        machine = VoiceModeMachine(language: initial.language, sendDelay: initial.sendDelay, silenceLimit: initial.silenceLimit)
        self.assistant = assistant
        session = RecognitionSession(makeRecognizer: makeRecognizer, now: now)
        self.output = output
        self.tone = tone
        self.audio = audio
        self.settings = settings
        self.now = now
        self.sleep = sleep
        self.keepScreenOn = keepScreenOn
        self.notifications = notifications
        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    var phase: VoiceModeMachine.Phase { machine.phase }
    var isRunning: Bool {
        switch machine.phase {
        case .idle, .ended: false
        default: true
        }
    }

    // MARK: Actions

    func start() {
        guard !isRunning else { return }
        let current = settings()
        machine = VoiceModeMachine(language: current.language, sendDelay: current.sendDelay, silenceLimit: current.silenceLimit)
        output.stop()
        assistant.onTurnFinished = { [weak self] outcome in self?.turnFinished(outcome) }
        observe()
        keepScreenOn(true)
        do {
            try audio.activate(.conversation)
        } catch {
            _ = machine.start(now: now())
            apply(machine.recognizerFailed())
            return
        }
        apply(machine.start(now: now(), cardsPending: assistant.hasPendingActions))
    }

    func doNotSend() { apply(machine.doNotSend()) }
    func pause() { apply(machine.pause()) }
    func resume() { apply(machine.resume(now: now())) }
    func interrupt() { apply(machine.userInterrupt(now: now())) }
    func typeInstead() { apply(machine.typeInstead()) }
    func end() { apply(machine.end()) }

    func tick() {
        session.tick()
        apply(machine.tick(now: now()))
    }

    func remaining() -> Int { machine.remaining(now: now()) }

    // MARK: Events

    private func handle(_ event: RecognitionSession.Event) {
        switch event {
        case .started:
            machine.recordingStarted(now: now())
        case .text(let final, let volatile):
            machine.heard(final: final, volatile: volatile, now: now())
        case .level(let value):
            level = value
        case .finished:
            level = 0
            apply(machine.recognizerFinished(text: machine.text, now: now()))
        case .failed:
            level = 0
            apply(machine.recognizerFailed())
        }
    }

    private func turnFinished(_ outcome: AssistantModel.TurnOutcome) {
        let mapped: VoiceModeMachine.Outcome
        switch outcome {
        case .answered(let id, let speech, let hasPendingCards):
            answerID = id
            mapped = .answered(speech: speech, hasPendingCards: hasPendingCards)
        case .rejected:
            mapped = .rejected
        case .failed(let offline):
            mapped = .failed(offline: offline)
        }
        apply(machine.turnFinished(mapped, now: now()))
    }

    // MARK: Effects

    private func apply(_ effects: [VoiceModeMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .startListening(let language):
                session.start(language)
            case .stopListening:
                session.stop()
            case .cancelListening:
                session.cancel()
                level = 0
            case .send(let text):
                sending = Task { [assistant] in await assistant.send(text, spoken: true) }
            case .speak(let text):
                speech += 1
                let current = speech
                output.speak(id: answerID ?? "voice-mode", text: text, explicit: true, fallback: machine.language) { [weak self] _ in
                    guard let self, current == self.speech else { return }
                    self.apply(self.machine.speakingFinished(now: self.now()))
                }
            case .stopSpeaking:
                speech += 1
                output.stop()
            case .playTone:
                tone.play { [weak self] in
                    guard let self else { return }
                    self.apply(self.machine.toneFinished(now: self.now()))
                }
            case .announce(let announcement):
                speech += 1
                output.speak(id: "voice-mode-notice", text: Self.text(announcement, language: machine.language),
                             explicit: true, fallback: machine.language)
            case .moveToDraft(let text):
                onMoveToDraft(text)
            case .endSession:
                finishSession()
            }
        }
        updateTicking()
    }

    private func finishSession() {
        session.cancel()
        sending?.cancel()
        sending = nil
        speech += 1
        output.stop()
        tone.stop()
        level = 0
        answerID = nil
        assistant.onTurnFinished = nil
        observers.forEach(notifications.removeObserver)
        observers = []
        keepScreenOn(false)
        audio.deactivate(.conversation)
        onEnded()
    }

    private func updateTicking() {
        if isRunning, ticking == nil {
            ticking = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sleep(.milliseconds(250))
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        } else if !isRunning {
            ticking?.cancel()
            ticking = nil
        }
    }

    /// A call, the app leaving the foreground or the screen locking ends the voice mode; a new audio route
    /// starts a fresh recording.
    private func observe() {
        guard observers.isEmpty else { return }
        observers.append(notifications.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemInterruption() }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                   queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.systemInterruption() }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                                   queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reasons: [AVAudioSession.RouteChangeReason] = [.oldDeviceUnavailable, .newDeviceAvailable]
            guard let raw, reasons.map(\.rawValue).contains(raw) else { return }
            MainActor.assumeIsolated { self?.routeChanged() }
        })
    }

    private func systemInterruption() { apply(machine.systemInterruption()) }
    private func routeChanged() { apply(machine.routeChanged(now: now())) }

    static func text(_ announcement: VoiceModeMachine.Announcement, language: VoiceLanguage) -> String {
        switch (announcement, language) {
        case (.offline, .german): "Keine Verbindung. Der Sprechmodus pausiert."
        case (.offline, .english): "No connection. Voice mode is paused."
        case (.failed, .german): "Das hat nicht geklappt. Der Sprechmodus pausiert."
        case (.failed, .english): "That didn't work. Voice mode is paused."
        }
    }
}
