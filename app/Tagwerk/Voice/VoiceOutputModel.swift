import AVFoundation
import Foundation
import Observation
import TagwerkCore
import UIKit

/// Reads answers aloud, one at a time (mockup SP3a): which answer is playing, the current sentence, and a
/// short notice when reading is not possible.
@MainActor @Observable
final class VoiceOutputModel {
    /// How one `speak` call ended; reported exactly once to its completion.
    enum Ending: Equatable {
        case finished
        /// Stopped by the user, another reading, the system or the time limit.
        case stopped
        /// Nothing was read (VoiceOver, a recording, empty text, no audio).
        case notSpoken
    }

    struct Preferences: Equatable {
        var germanVoiceID: String?
        var englishVoiceID: String?
        var rate: Double
    }

    private(set) var speakingID: String?
    private(set) var currentSentence = 0
    private(set) var sentences: [String] = []
    private(set) var notice: String?
    @ObservationIgnored private var activeMode: VoiceAudioMode?

    @ObservationIgnored private let speaker: SpeechSpeaking
    @ObservationIgnored private let audio: VoiceAudioSession
    @ObservationIgnored private let preferences: () -> Preferences
    @ObservationIgnored private let isVoiceOverRunning: () -> Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var completion: ((Ending) -> Void)?
    @ObservationIgnored private var timeLimit: Task<Void, Never>?

    init(speaker: SpeechSpeaking, audio: VoiceAudioSession, preferences: @escaping () -> Preferences,
         isVoiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning },
         notifications: NotificationCenter = .default,
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.speaker = speaker
        self.audio = audio
        self.preferences = preferences
        self.isVoiceOverRunning = isVoiceOverRunning
        self.sleep = sleep
        speaker.onEvent = { [weak self] event in self?.handle(event) }
        observeInterruptions(notifications)
    }

    /// The synthesizer only pauses when the app leaves or a call starts; reading ends there instead of
    /// leaving the sentence highlight and "Liest vor · Stopp" behind.
    private func observeInterruptions(_ center: NotificationCenter) {
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.stop() }
        })
    }

    /// Reads `text`. `explicit` is a tap on "Vorlesen" or the voice mode: it plays with the silent switch on
    /// and even while VoiceOver runs; automatic reading does neither. `completion` is called exactly once.
    func speak(id: String, text: String, explicit: Bool, fallback: VoiceLanguage,
               completion: ((Ending) -> Void)? = nil) {
        stop()
        notice = nil
        if !explicit && isVoiceOverRunning() { completion?(.notSpoken); return }
        // A running recording keeps the microphone; reading waits for the user (plan voice-chat, review 3).
        if audio.isRecording {
            if explicit { notice = String(localized: "Erst die Aufnahme beenden") }
            completion?(.notSpoken)
            return
        }
        let language = VoiceLanguage.detect(text, fallback: fallback)
        let parts = SpokenText.sentences(SpokenText.prepare(text, language: language))
        guard !parts.isEmpty else { completion?(.notSpoken); return }
        let mode: VoiceAudioMode = explicit ? .speakingExplicit : .speakingAutomatic
        do {
            try audio.activate(mode)
        } catch {
            notice = String(localized: "Vorlesen nicht möglich")
            completion?(.notSpoken)
            return
        }
        let preferences = preferences()
        let voiceID = speaker.resolvedVoiceID(language == .german ? preferences.germanVoiceID : preferences.englishVoiceID,
                                              language: language)
        activeMode = mode
        speakingID = id
        sentences = parts
        currentSentence = 0
        self.completion = completion
        speaker.speak(parts, language: language, voiceID: voiceID, rate: Float(preferences.rate))
        startTimeLimit(characters: parts.joined().count, rate: preferences.rate)
    }

    func stop() {
        guard speakingID != nil else { return }
        speaker.stop()
        finish(.stopped)
    }

    func toggle(id: String, text: String, fallback: VoiceLanguage) {
        if speakingID == id { stop() } else { speak(id: id, text: text, explicit: true, fallback: fallback) }
    }

    func clearNotice() { notice = nil }

    private func handle(_ event: SpeakerEvent) {
        switch event {
        case .sentenceStarted(let index): currentSentence = index
        case .finished: finish(.finished)
        case .interrupted: finish(.stopped)
        }
    }

    /// The synthesizer may not report its end (seen with route changes); reading ends after a generous limit.
    private func startTimeLimit(characters: Int, rate: Double) {
        let seconds = 5 + Double(characters) * 0.12 * (0.5 / max(rate, 0.1))
        let id = speakingID
        timeLimit = Task { [weak self] in
            await self?.sleep(.seconds(seconds))
            guard let self, !Task.isCancelled, self.speakingID == id else { return }
            self.stop()
        }
    }

    private func finish(_ ending: Ending) {
        guard speakingID != nil else { return }
        timeLimit?.cancel()
        timeLimit = nil
        speakingID = nil
        sentences = []
        currentSentence = 0
        if let activeMode { audio.deactivate(activeMode) }
        activeMode = nil
        let completion = completion
        self.completion = nil
        completion?(ending)
    }
}
