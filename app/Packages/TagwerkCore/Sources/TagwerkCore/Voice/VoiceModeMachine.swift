import Foundation

/// Pure state machine of the voice mode (mockup SP5a): listen, send after a pause with a visible countdown,
/// speak the answer, play a tone, listen again.
///
/// Like `DictationMachine` it owns no timers, recognizer or speaker. The caller reports events with the
/// current time and executes the returned `Effect`s. The microphone is off while the answer is spoken, and
/// nothing is sent from `paused` or `ended`. Open action cards keep listening (issue #120): a whole-sentence
/// "ja" confirms after a two-second countdown, "nein" declines, anything else is sent as a correction.
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
        /// "Ja" was heard: the cards are confirmed at `deadline` unless the user speaks or cancels.
        case confirming(deadline: Date)
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
        case answered(speech: String, cards: OpenCards)
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
        /// Speak a short answer to a spoken reply, then play the tone and listen again.
        case prompt(ActionAnnouncement.Prompt)
        /// Confirm or decline these cards (still the ones the user answered to).
        case confirm(ids: [String])
        case decline(ids: [String])
        /// Put the text into the message field of the normal chat.
        case moveToDraft(String)
        /// Leave the voice mode: release the audio session and show the normal chat.
        case endSession
    }

    /// Time without text change before the countdown becomes visible, in seconds.
    public static let countdownVisibleAfter: TimeInterval = 0.6
    /// The countdown stays visible at least this long, so "Nicht senden" can be reached.
    public static let minimumCountdown: TimeInterval = 1
    /// Limits for steps that report their end asynchronously, in seconds.
    public static let startTimeout: TimeInterval = 10
    public static let sendTimeout: TimeInterval = 90
    public static let toneTimeout: TimeInterval = 2
    /// Time between a spoken "ja" and running the action.
    public static let confirmationDelay: TimeInterval = 2

    public private(set) var phase: Phase = .idle
    public private(set) var language: VoiceLanguage
    public let sendDelay: TimeInterval
    public let silenceLimit: TimeInterval
    public private(set) var finalText = ""
    public private(set) var volatileText = ""

    private var lastChange: Date?
    private var phaseSince: Date?
    /// Action cards waiting for an answer.
    public private(set) var openCards = OpenCards.none
    /// The countdown of a "ja" was just stopped; a following "nein" or "stopp" only means that.
    private var confirmationCancelled = false

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
        let deadline: Date
        switch phase {
        case .countdown(let end): deadline = end
        case .confirming(let end): deadline = end == .distantFuture ? now.addingTimeInterval(Self.confirmationDelay) : end
        default: return 0
        }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    // MARK: Start and listening

    /// Starts listening; `cards` are action cards that are already open.
    public mutating func start(now: Date, cards: OpenCards = .none) -> [Effect] {
        guard phase == .idle else { return [] }
        openCards = cards
        return listen(now: now)
    }

    public mutating func recordingStarted(now: Date) {
        if case .confirming = phase {
            // The countdown starts only once the microphone listens again, so "stopp" can always be heard.
            lastChange = now
            phase = .confirming(deadline: now.addingTimeInterval(Self.confirmationDelay))
            return
        }
        guard phase == .starting else { return }
        phase = .listening
        phaseSince = now
        lastChange = now
    }

    public mutating func heard(final: String, volatile: String, now: Date) {
        if case .confirming = phase {
            // Any speech during the countdown stops it and counts as a new utterance.
            guard !(final + volatile).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            phase = .listening
            phaseSince = now
            confirmationCancelled = true
        }
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
            let earliest = Self.countdownVisibleAfter + Self.minimumCountdown
            phase = .countdown(deadline: lastChange.addingTimeInterval(max(sendDelay, earliest)))
            return tick(now: now)
        case .countdown(let deadline):
            guard now >= deadline else { return [] }
            phase = .finalizing
            phaseSince = now
            return [.stopListening]
        case .confirming(let deadline):
            if deadline == .distantFuture {
                // The microphone did not come back: run nothing.
                guard elapsed(now) >= Self.startTimeout else { return [] }
                return [.cancelListening] + pause(.failed, announce: .failed)
            }
            guard now >= deadline else { return [] }
            let ids = openCards.ids
            phase = .sending
            phaseSince = now
            return [.cancelListening, .confirm(ids: ids)]
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
            return answer(message, now: now)
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
        case .starting, .listening, .countdown, .finalizing, .confirming:
            return keepText() + pause(.failed, announce: .failed)
        default:
            return []
        }
    }

    /// Headphones plugged in or out: start a fresh recording on the new route.
    public mutating func routeChanged(now: Date) -> [Effect] {
        switch phase {
        case .starting, .listening, .countdown:
            let kept = keepText()
            phase = .starting
            phaseSince = now
            return [.cancelListening] + kept + [.startListening(language)]
        default:
            return []
        }
    }

    // MARK: Answer

    public mutating func turnFinished(_ outcome: Outcome, now: Date) -> [Effect] {
        switch phase {
        case .sending, .tone, .paused:
            return handle(outcome, now: now)
        case .speaking:
            // A card was tapped while the answer was read: its result replaces the rest of the answer.
            return [.stopSpeaking] + handle(outcome, now: now)
        case .starting, .listening, .countdown, .finalizing, .confirming:
            // A card was tapped while listening: the microphone goes off for the answer.
            clearText()
            return [.cancelListening] + handle(outcome, now: now)
        case .idle, .ended:
            return []
        }
    }

    private mutating func handle(_ outcome: Outcome, now: Date) -> [Effect] {
        confirmationCancelled = false
        switch outcome {
        case .answered(let speech, let cards):
            openCards = cards
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
        case .starting, .listening, .countdown, .confirming:
            let effects = keepText()
            confirmationCancelled = false
            phase = .paused(.user)
            return [.cancelListening] + effects
        default:
            return []
        }
    }

    /// Also stops a running announcement, so the microphone does not hear it.
    /// The open cards changed without an answer (a failed turn, a correction that closed them).
    public mutating func cardsChanged(_ cards: OpenCards) {
        openCards = cards
    }

    /// "Abbrechen" during the confirmation countdown: the cards stay open, listening goes on.
    public mutating func cancelConfirmation(now: Date) -> [Effect] {
        guard case .confirming = phase else { return [] }
        phase = .listening
        phaseSince = now
        lastChange = now
        confirmationCancelled = false
        return []
    }

    public mutating func resume(now: Date) -> [Effect] {
        guard case .paused = phase else { return [] }
        return [.stopSpeaking] + listen(now: now)
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
        confirmationCancelled = false
        phase = .starting
        phaseSince = now
        return [.startListening(language)]
    }

    /// The final text of an utterance: an answer to open cards, or a message to send.
    private mutating func answer(_ message: String, now: Date) -> [Effect] {
        let reply = VoiceReply(message)
        let cancelled = confirmationCancelled
        confirmationCancelled = false
        if cancelled && (reply == .stop || reply == .decline) {
            // After a stopped countdown "nein" or "stopp" only meant that.
            return say(.cancelled, now: now)
        }
        if reply == .stop && !openCards.isEmpty {
            return listen(now: now)
        }
        guard !openCards.isEmpty, reply != .other else {
            phase = .sending
            phaseSince = now
            clearText()
            return [.send(message)]
        }
        let cards = openCards
        switch reply {
        case .confirm where cards.count > 1, .confirmDelete where cards.count > 1, .decline where cards.count > 1:
            return say(.severalCards(cards.count), now: now)
        case .confirm where cards.deletes > 0:
            return say(.sayDelete, now: now)
        case .confirmAll where cards.deletes > 0:
            return say(.deletesNeedTap, now: now)
        case .confirmAll where cards.guarded > 0:
            return say(.guardedNeedTap, now: now)
        case .confirm, .confirmDelete, .confirmAll:
            clearText()
            phase = .confirming(deadline: .distantFuture)
            phaseSince = now
            // Keep listening during the countdown, so "stopp" or a correction can stop it.
            return [.startListening(language)]
        case .decline:
            clearText()
            phase = .sending
            phaseSince = now
            return [.decline(ids: cards.ids)]
        case .stop, .other:
            return listen(now: now)
        }
    }

    private mutating func say(_ prompt: ActionAnnouncement.Prompt, now: Date) -> [Effect] {
        clearText()
        phase = .speaking
        phaseSince = now
        return [.prompt(prompt)]
    }

    private mutating func afterSpeaking(now: Date) -> [Effect] {
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
        case .starting, .listening, .countdown, .finalizing, .confirming:
            effects = [.cancelListening] + keepText()
        case .speaking, .paused:
            // `.paused` may still be announcing why.
            effects = [.stopSpeaking]
        case .sending, .tone:
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
