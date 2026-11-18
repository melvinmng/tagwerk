import AVFoundation
import Foundation
import Synchronization

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
/// Recording wins: reading aloud never takes the session from a running recording, and a mode only ends
/// the session it activated itself.
protocol VoiceAudioSession: AnyObject, Sendable {
    var currentMode: VoiceAudioMode? { get }
    func activate(_ mode: VoiceAudioMode) throws
    /// Deactivates only when `mode` is still the active one.
    func deactivate(_ mode: VoiceAudioMode)
}

extension VoiceAudioSession {
    var isRecording: Bool { currentMode == .recording }
}

final class SystemVoiceAudioSession: VoiceAudioSession, @unchecked Sendable {
    static let shared = SystemVoiceAudioSession()
    private let mode = Mutex<VoiceAudioMode?>(nil)

    var currentMode: VoiceAudioMode? { mode.withLock { $0 } }

    func activate(_ mode: VoiceAudioMode) throws {
        try configure(mode)
        self.mode.withLock { $0 = mode }
    }

    func deactivate(_ mode: VoiceAudioMode) {
        let isCurrent = self.mode.withLock { current -> Bool in
            guard current == mode else { return false }
            current = nil
            return true
        }
        if isCurrent { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func configure(_ mode: VoiceAudioMode) throws {
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
}
