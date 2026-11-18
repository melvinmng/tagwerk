import AVFoundation
import Foundation

/// What the shared audio session is used for at the moment.
enum VoiceAudioMode: Equatable, Sendable {
    /// Dictation: microphone only.
    case recording
    /// "Vorlesen" tapped: plays even with the ring/silent switch on, ducks other audio.
    case speakingExplicit
    /// Automatic reading: silent with the switch on, mixes with other audio.
    case speakingAutomatic
}

/// The single owner of `AVAudioSession` for recording and reading aloud.
protocol VoiceAudioSession: AnyObject, Sendable {
    func activate(_ mode: VoiceAudioMode) throws
    func deactivate()
}

final class SystemVoiceAudioSession: VoiceAudioSession, @unchecked Sendable {
    static let shared = SystemVoiceAudioSession()

    func activate(_ mode: VoiceAudioMode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .recording:
            try session.setCategory(.record, mode: .measurement)
        case .speakingExplicit:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .speakingAutomatic:
            try session.setCategory(.ambient, mode: .spokenAudio, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
