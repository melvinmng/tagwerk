import Foundation

/// Pure state machine of the voice mode (mockup SP5a): listen, send after a pause with a visible countdown,
/// speak the answer, play a tone, listen again.
///
/// Like `DictationMachine` it owns no timers, recognizer or speaker. The caller reports events with the
/// current time and executes the returned `Effect`s. The microphone is off while the answer is spoken, and
/// nothing is sent from `paused` or `ended`.
public struct VoiceModeMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The recognizer is starting; "Hört zu" shows only once it runs.
        case starting
        case listening
        /// Text was heard and the user paused; it is sent at `deadline` unless more speech arrives.
        case countdown(deadline: Date)
        /// The recognizer is finishing; the final text is sent once it arrives.
        case finalizing
        case sending
        case speaking
        /// The short tone after an answer; listening starts when it has played.
        case tone
        /// An action card waits for a tap; listening is paused until the cards are resolved.
        case awaitingConfirmation
        case paused(PauseReason)
        case ended
    }

    public enum PauseReason: Equatable, Sendable {
        case user
        case silence
        case offline
        case failed
    }

    /// How a turn with ChatGPT ended (a sent message, a confirmed or declined card, a retry).
    public enum Outcome: Equatable, Sendable {
        /// `speech` is the text to read (answer and card announcement), possibly empty.
        case answered(speech: String, hasPendingCards: Bool)
        /// Nothing was sent, e.g. the conversation was busy.
        case rejected
        case failed(offline: Bool)
    }

    /// Short spoken notices.
    public enum Announcement: Equatable, Sendable {
        case offline
        case failed
    }

    public enum Effect: Equatable, Sendable {
        case startListening(VoiceLanguage)
        /// Finish recognition and deliver the final text.
        case stopListening
        /// Abort recognition and discard its results.
        case cancelListening
        case send(String)
        case speak(String)
        case stopSpeaking
        case playTone
        case announce(Announcement)
        /// Put the text into the message field of the normal chat.
        case moveToDraft(String)
        /// Leave the voice mode: release the audio session and show the normal chat.
        case endSession
    }

    /// Time without text change before the countdown becomes visible, in seconds.
    public static let countdownVisibleAfter: TimeInterval = 0.6
    /// Limits for steps that report their end asynchronously, in seconds.
    public static let startTimeout: TimeInterval = 10
    public static let sendTimeout: TimeInterval = 90
    public static let toneTimeout: TimeInterval = 2

    public private(set) var phase: Phase = .idle
    public private(set) var language: VoiceLanguage
    public let sendDelay: TimeInterval
    public let silenceLimit: TimeInterval
    public private(set) var finalText = ""
    public private(set) var volatileText = ""

    private var lastChange: Date?
    private var phaseSince: Date?
    /// Action cards are open after the current answer has been spoken.
    private var cardsPending = false

    public init(language: VoiceLanguage, sendDelay: TimeInterval, silenceLimit: TimeInterval) {
        self.language = language
        self.sendDelay = sendDelay
        self.silenceLimit = silenceLimit
    }

    /// Heard text, final and volatile parts joined.
    public var text: String {
        [finalText, volatileText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whole seconds left in the countdown, rounded up.
    public func remaining(now: Date) -> Int {
        guard case .countdown(let deadline) = phase else { return 0 }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    // MARK: Start and listening

    public mutating func start(now: Date) -> [Effect] {
        guard phase == .idle else { return [] }
        return listen(now: now)
    }

    public mutating func recordingStarted(now: Date) {
        guard phase == .starting else { return }
        phase = .listening
        phaseSince = now
        lastChange = now
    }

    public mutating func heard(final: String, volatile: String, now: Date) {
        switch phase {
        case .listening, .countdown:
            if final != finalText || volatile != volatileText {
                lastChange = now
                if case .countdown = phase { phase = .listening }
            }
        case .finalizing:
            break
        default:
            return
        }
        finalText = final
        volatileText = volatile
    }

    public mutating func tick(now: Date) -> [Effect] {
        switch phase {
        case .starting:
            guard elapsed(now) >= Self.startTimeout else { return [] }
            return [.cancelListening] + pause(.failed, announce: .failed)
        case .listening:
            guard let lastChange else { return [] }
            if text.isEmpty {
                guard now.timeIntervalSince(lastChange) >= silenceLimit else { return [] }
                return [.cancelListening] + pause(.silence, announce: nil)
            }
            guard now.timeIntervalSince(lastChange) >= Self.countdownVisibleAfter else { return [] }
            phase = .countdown(deadline: lastChange.addingTimeInterval(sendDelay))
            return tick(now: now)
        case .countdown(let deadline):
            guard now >= deadline else { return [] }
            phase = .finalizing
            phaseSince = now
            return [.stopListening]
        case .sending:
            guard elapsed(now) >= Self.sendTimeout else { return [] }
            return pause(.failed, announce: .failed)
        case .tone:
            guard elapsed(now) >= Self.toneTimeout else { return [] }
            return listen(now: now)
        default:
            return []
        }
    }

    // MARK: Recognizer results

    /// The recognizer delivered its final text. Only a stop asked for by the countdown sends it.
    public mutating func recognizerFinished(text final: String, now: Date) -> [Effect] {
        switch phase {
        case .finalizing:
            let message = final.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return listen(now: now) }
            phase = .sending
            phaseSince = now
            clearText()
            return [.send(message)]
        case .listening, .countdown, .starting:
            // The recognizer ended without being asked; keep the text for the field, send nothing.
            finalText = final
            volatileText = ""
            return recognizerFailed()
        default:
            return []
        }
    }

    public mutating func recognizerFailed() -> [Effect] {
        switch phase {
        case .starting, .listening, .countdown, .finalizing:
            return keepText() + pause(.failed, announce: .failed)
        default:
            return []
        }
    }

    /// Headphones plugged in or out: start a fresh recording on the new route.
    public mutating func routeChanged() -> [Effect] {
        switch phase {
        case .starting, .listening, .countdown:
            clearText()
            phase = .starting
            phaseSince = nil
            return [.cancelListening, .startListening(language)]
        default:
            return []
        }
    }

    // MARK: Answer

    public mutating func turnFinished(_ outcome: Outcome, now: Date) -> [Effect] {
        guard phase == .sending || phase == .awaitingConfirmation else { return [] }
        switch outcome {
        case .answered(let speech, let hasPendingCards):
            cardsPending = hasPendingCards
            if !speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                phase = .speaking
                phaseSince = now
                return [.speak(speech)]
            }
            return afterSpeaking(now: now)
        case .rejected:
            return pause(.failed, announce: nil)
        case .failed(let offline):
            return pause(offline ? .offline : .failed, announce: offline ? .offline : .failed)
        }
    }

    public mutating func speakingFinished(now: Date) -> [Effect] {
        guard phase == .speaking else { return [] }
        return afterSpeaking(now: now)
    }

    public mutating func toneFinished(now: Date) -> [Effect] {
        guard phase == .tone else { return [] }
        return listen(now: now)
    }

    // MARK: User controls

    /// "Unterbrechen": stops the voice and listens right away, without the tone.
    public mutating func userInterrupt(now: Date) -> [Effect] {
        guard phase == .speaking else { return [] }
        if cardsPending {
            phase = .awaitingConfirmation
            return [.stopSpeaking]
        }
        return [.stopSpeaking] + listen(now: now)
    }

    /// "Nicht senden": the heard text goes into the field and the normal chat takes over.
    public mutating func doNotSend() -> [Effect] {
        switch phase {
        case .listening, .countdown, .finalizing:
            let effects = keepText()
            phase = .ended
            return [.cancelListening] + effects + [.endSession]
        default:
            return []
        }
    }

    /// "Pause": stops listening; text heard so far goes into the field.
    public mutating func pause() -> [Effect] {
        switch phase {
        case .starting, .listening, .countdown:
            let effects = keepText()
            phase = .paused(.user)
            return [.cancelListening] + effects
        default:
            return []
        }
    }

    public mutating func resume(now: Date) -> [Effect] {
        guard case .paused = phase else { return [] }
        return listen(now: now)
    }

    /// "Tippen": leave the voice mode for the keyboard.
    public mutating func typeInstead() -> [Effect] { leave() }

    /// "Beenden" or closing the sheet.
    public mutating func end() -> [Effect] { leave() }

    /// A call, the app leaving the foreground or the screen locking.
    public mutating func systemInterruption() -> [Effect] { leave() }

    // MARK: Helpers

    private mutating func listen(now: Date) -> [Effect] {
        clearText()
        cardsPending = false
        phase = .starting
        phaseSince = now
        return [.startListening(language)]
    }

    private mutating func afterSpeaking(now: Date) -> [Effect] {
        if cardsPending {
            phase = .awaitingConfirmation
            phaseSince = now
            return []
        }
        phase = .tone
        phaseSince = now
        return [.playTone]
    }

    private mutating func pause(_ reason: PauseReason, announce: Announcement?) -> [Effect] {
        phase = .paused(reason)
        phaseSince = nil
        return announce.map { [.announce($0)] } ?? []
    }

    private mutating func leave() -> [Effect] {
        var effects: [Effect]
        switch phase {
        case .idle, .ended:
            return []
        case .starting, .listening, .countdown, .finalizing:
            effects = [.cancelListening] + keepText()
        case .speaking:
            effects = [.stopSpeaking]
        case .sending, .tone, .awaitingConfirmation, .paused:
            effects = []
        }
        phase = .ended
        return effects + [.endSession]
    }

    /// Moves heard text into the field, if there is any.
    private mutating func keepText() -> [Effect] {
        let heard = text
        clearText()
        return heard.isEmpty ? [] : [.moveToDraft(heard)]
    }

    private mutating func clearText() {
        finalText = ""
        volatileText = ""
        lastChange = nil
    }

    private func elapsed(_ now: Date) -> TimeInterval {
        phaseSince.map { now.timeIntervalSince($0) } ?? 0
    }
}
