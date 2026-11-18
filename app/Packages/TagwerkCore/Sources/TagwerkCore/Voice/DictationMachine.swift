import Foundation

/// Pure state machine for one dictation in a message field.
///
/// The machine owns no timers and no recognizer. The caller reports events (taps, recognizer results,
/// clock ticks with the current time) and executes the returned `Effect`s.
public struct DictationMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case explaining
        case preparing
        case recording
        case stopping(Intent)
        case notice(Notice)
    }

    /// What happens with the recognized text once the recognizer has finished.
    public enum Intent: Equatable, Sendable {
        case fill
        case send
    }

    public enum Notice: Equatable, Sendable {
        case nothingHeard
        case interrupted
        case unsupported
        case permissionDenied
        case assetUnavailable
        case failed
    }

    public enum Effect: Equatable, Sendable {
        /// Show the one-time explanation before the first dictation.
        case explain
        /// Start recognition in the given language.
        case start(VoiceLanguage)
        /// Stop recognition and deliver the final result.
        case stop
        /// Abort recognition and discard results.
        case cancel
        /// Remember that the explanation was shown.
        case markExplained
        /// Put the text into the message field.
        case fill(String)
        /// Put the text into the message field and send it.
        case send(String)
        /// Put the original field text back.
        case restoreDraft(String)
        /// Stop the current session and start a new one in another language.
        case restart(VoiceLanguage)
    }

    /// Hard limit of one dictation, in seconds.
    public static let maximumDuration: TimeInterval = 60
    /// Time without any text change after which the dictation ends, in seconds.
    public static let silenceLimit: TimeInterval = 8
    /// Time a notice stays visible, in seconds.
    public static let noticeDuration: TimeInterval = 4

    public private(set) var phase: Phase = .idle
    public private(set) var language: VoiceLanguage
    /// Field text at the moment recording started.
    public private(set) var draftBefore: String = ""
    public private(set) var finalText: String = ""
    public private(set) var volatileText: String = ""

    private var startedAt: Date?
    private var lastChange: Date?
    private var noticeAt: Date?

    public init(language: VoiceLanguage) {
        self.language = language
    }

    // MARK: Derived text

    /// Draft, final and volatile text joined with single spaces.
    public var displayText: String {
        Self.joined([draftBefore, finalText, volatileText])
    }

    /// Text recognized in the current dictation (final and volatile parts).
    public var recognizedText: String {
        Self.joined([finalText, volatileText])
    }

    public func elapsed(now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    // MARK: Start

    public mutating func tapMicrophone(draft: String, explained: Bool, now: Date) -> [Effect] {
        switch phase {
        case .idle, .notice:
            guard explained else {
                phase = .explaining
                noticeAt = nil
                return [.explain]
            }
            return begin(draft: draft)
        case .recording, .preparing:
            return finish()
        case .explaining, .stopping:
            return []
        }
    }

    public mutating func continueAfterExplanation(draft: String, now: Date) -> [Effect] {
        guard phase == .explaining else { return [] }
        return [.markExplained] + begin(draft: draft)
    }

    public mutating func dismissExplanation() -> [Effect] {
        if phase == .explaining { phase = .idle }
        return []
    }

    public mutating func recordingStarted(now: Date) {
        guard phase == .preparing else { return }
        phase = .recording
        startedAt = now
        lastChange = now
    }

    // MARK: Recognition

    public mutating func received(final: String, volatile: String, now: Date) {
        switch phase {
        case .recording:
            if final != finalText || volatile != volatileText { lastChange = now }
        case .stopping:
            break
        default:
            return
        }
        finalText = final
        volatileText = volatile
    }

    public mutating func tick(now: Date) -> [Effect] {
        switch phase {
        case .recording:
            let reachedMaximum = elapsed(now: now) >= Self.maximumDuration
            let silent = lastChange.map { now.timeIntervalSince($0) >= Self.silenceLimit } ?? false
            guard reachedMaximum || silent else { return [] }
            phase = .stopping(.fill)
            return [.stop]
        case .notice:
            if let noticeAt, now.timeIntervalSince(noticeAt) >= Self.noticeDuration {
                phase = .idle
                self.noticeAt = nil
            }
            return []
        default:
            return []
        }
    }

    // MARK: Ending

    public mutating func finish() -> [Effect] {
        switch phase {
        case .recording, .preparing:
            phase = .stopping(.fill)
            return [.stop]
        default:
            return []
        }
    }

    public mutating func send() -> [Effect] {
        guard phase == .recording else { return [] }
        phase = .stopping(.send)
        return [.stop]
    }

    public mutating func cancel() -> [Effect] {
        switch phase {
        case .preparing, .recording, .stopping:
            phase = .idle
            return [.cancel, .restoreDraft(draftBefore)]
        case .explaining, .notice:
            phase = .idle
            noticeAt = nil
            return []
        case .idle:
            return []
        }
    }

    public mutating func recognizerFinished(now: Date) -> [Effect] {
        let intent: Intent
        switch phase {
        case .stopping(let stoppingIntent): intent = stoppingIntent
        case .recording: intent = .fill
        default: return []
        }

        guard !recognizedText.isEmpty else {
            enterNotice(.nothingHeard, now: now)
            return [.restoreDraft(draftBefore)]
        }
        phase = .idle
        switch intent {
        case .fill: return [.fill(displayText)]
        case .send: return [.send(displayText)]
        }
    }

    /// Keeps already recognized text (it is filled into the field) and shows `notice`.
    public mutating func recognizerFailed(_ notice: Notice, now: Date) -> [Effect] {
        let effects: [Effect] = recognizedText.isEmpty ? [] : [.fill(displayText)]
        enterNotice(notice, now: now)
        return effects
    }

    // MARK: Language

    /// Switches the language during recording and keeps everything said so far in the draft.
    public mutating func switchLanguage(now: Date) -> [Effect] {
        guard phase == .recording else { return [] }
        draftBefore = displayText
        finalText = ""
        volatileText = ""
        language = language == .german ? .english : .german
        phase = .preparing
        return [.restart(language)]
    }

    /// Changes the language for the next dictation; ignored unless idle.
    public mutating func setLanguage(_ language: VoiceLanguage) {
        guard phase == .idle else { return }
        self.language = language
    }

    // MARK: Helpers

    private mutating func begin(draft: String) -> [Effect] {
        draftBefore = draft
        finalText = ""
        volatileText = ""
        startedAt = nil
        lastChange = nil
        noticeAt = nil
        phase = .preparing
        return [.start(language)]
    }

    private mutating func enterNotice(_ notice: Notice, now: Date) {
        phase = .notice(notice)
        noticeAt = now
    }

    private static func joined(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
