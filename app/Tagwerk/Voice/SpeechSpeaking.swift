import AVFoundation
import Foundation
import TagwerkCore

/// A system voice that can read in one of the two languages.
struct SpokenVoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let language: VoiceLanguage
    /// 3 premium, 2 enhanced, 1 default.
    let quality: Int

    var qualityLabel: String? {
        switch quality {
        case 3: String(localized: "Premium")
        case 2: String(localized: "Erweitert")
        default: nil
        }
    }
}

enum SpeakerEvent: Equatable, Sendable {
    case sentenceStarted(Int)
    case finished
    /// Ended by the system (a call, another app), not by `stop()`.
    case interrupted
}

/// Text to speech. Speaks a list of sentences, one utterance each, and reports which one is playing.
/// `stop()` ends silently; the caller already knows it stopped.
@MainActor
protocol SpeechSpeaking: AnyObject {
    var onEvent: ((SpeakerEvent) -> Void)? { get set }
    func speak(_ sentences: [String], language: VoiceLanguage, voiceID: String?, rate: Float)
    func stop()
    func voices(for language: VoiceLanguage) -> [SpokenVoice]
}

extension SpeechSpeaking {
    /// The chosen voice if it is installed, else the best installed one.
    func resolvedVoiceID(_ chosen: String?, language: VoiceLanguage) -> String? {
        let voices = voices(for: language)
        if let chosen, voices.contains(where: { $0.id == chosen }) { return chosen }
        return voices.max { ($0.quality, $1.name) < ($1.quality, $0.name) }?.id
    }
}

@MainActor
final class SystemSpeaker: NSObject, SpeechSpeaking, AVSpeechSynthesizerDelegate {
    var onEvent: ((SpeakerEvent) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterances: [ObjectIdentifier: Int] = [:]
    private var lastIndex = -1

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ sentences: [String], language: VoiceLanguage, voiceID: String?, rate: Float) {
        stop()
        lastIndex = sentences.count - 1
        let voice = resolvedVoiceID(voiceID, language: language).flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: language.rawValue)
        for (index, sentence) in sentences.enumerated() {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterances[ObjectIdentifier(utterance)] = index
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        // Forget the utterances first, so the cancel callback of our own stop reports nothing.
        utterances = [:]
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func voices(for language: VoiceLanguage) -> [SpokenVoice] {
        let prefix = String(language.rawValue.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .map { voice in
                let quality = switch voice.quality {
                case .premium: 3
                case .enhanced: 2
                default: 1
                }
                return SpokenVoice(id: voice.identifier, name: voice.name, language: language, quality: quality)
            }
            .sorted { ($0.quality, $1.name) > ($1.quality, $0.name) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        MainActor.assumeIsolated {
            if let index = utterances[id] { onEvent?(.sentenceStarted(index)) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        MainActor.assumeIsolated {
            if utterances[id] == lastIndex { onEvent?(.finished) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        MainActor.assumeIsolated {
            guard utterances[id] != nil else { return }
            utterances = [:]
            onEvent?(.interrupted)
        }
    }
}
