import Foundation
import Observation
import TagwerkCore
import UIKit

/// Reads answers aloud, one at a time (mockup SP3a): which answer is playing, the current sentence, and a
/// short notice when reading is not possible.
@MainActor @Observable
final class VoiceOutputModel {
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

    init(speaker: SpeechSpeaking, audio: VoiceAudioSession, preferences: @escaping () -> Preferences,
         isVoiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning }) {
        self.speaker = speaker
        self.audio = audio
        self.preferences = preferences
        self.isVoiceOverRunning = isVoiceOverRunning
        speaker.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Reads `text`. `explicit` is a tap on "Vorlesen": it plays with the silent switch on and even while
    /// VoiceOver runs; automatic reading does neither.
    func speak(id: String, text: String, explicit: Bool, fallback: VoiceLanguage) {
        stop()
        notice = nil
        if !explicit && isVoiceOverRunning() { return }
        // A running recording keeps the microphone; reading waits for the user (plan voice-chat, review 3).
        if audio.isRecording {
            if explicit { notice = "Erst die Aufnahme beenden" }
            return
        }
        let language = VoiceLanguage.detect(text, fallback: fallback)
        let parts = SpokenText.sentences(SpokenText.prepare(text, language: language))
        guard !parts.isEmpty else { return }
        let mode: VoiceAudioMode = explicit ? .speakingExplicit : .speakingAutomatic
        do {
            try audio.activate(mode)
        } catch {
            notice = "Vorlesen nicht möglich"
            return
        }
        let preferences = preferences()
        let voiceID = speaker.resolvedVoiceID(language == .german ? preferences.germanVoiceID : preferences.englishVoiceID,
                                              language: language)
        activeMode = mode
        speakingID = id
        sentences = parts
        currentSentence = 0
        speaker.speak(parts, language: language, voiceID: voiceID, rate: Float(preferences.rate))
    }

    func stop() {
        guard speakingID != nil else { return }
        speaker.stop()
        finish()
    }

    func toggle(id: String, text: String, fallback: VoiceLanguage) {
        if speakingID == id { stop() } else { speak(id: id, text: text, explicit: true, fallback: fallback) }
    }

    func clearNotice() { notice = nil }

    private func handle(_ event: SpeakerEvent) {
        switch event {
        case .sentenceStarted(let index): currentSentence = index
        case .finished, .interrupted: finish()
        }
    }

    private func finish() {
        speakingID = nil
        sentences = []
        currentSentence = 0
        if let activeMode { audio.deactivate(activeMode) }
        activeMode = nil
    }
}
