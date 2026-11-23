import AVFoundation
import Foundation
import Observation
import TagwerkCore

/// Where "Spracheingabe und Vorlesen" gets what the system knows: the microphone permission, the state of the language packs
/// and the installed voices. The page never asks the system itself, so the UI tests can give it fixed values (`uiTest`) and
/// the unit tests can watch which thread the system is asked on.
struct VoiceSettingsSource: Sendable {
    var microphone: @Sendable () -> AVAudioApplication.recordPermission
    var packState: @Sendable (VoiceLanguage) async -> LanguagePackState
    /// Synchronous on purpose: `VoiceSettingsModel` calls it off the main actor.
    var voices: @Sendable (VoiceLanguage) -> [SpokenVoice]

    /// What the device reports.
    static let live = VoiceSettingsSource(
        microphone: { AVAudioApplication.shared.recordPermission },
        packState: { await VoiceAvailability.packState($0) },
        voices: { SystemSpeaker.installedVoices(for: $0) })

    /// The same on every run: both language packs available, no extra voices, microphone not asked yet. Without it the page would
    /// show the state of the machine that runs the audit, and asking for it blocked the page on slow CI runners.
    static let uiTest = VoiceSettingsSource(
        microphone: { .undetermined },
        packState: { _ in .available },
        voices: { _ in [] })

    /// `uiTest` in the UI test mode, `live` everywhere else (the mode is never active on a device).
    static var current: VoiceSettingsSource { UITestMode.isActive ? .uiTest : .live }
}

/// What "Spracheingabe und Vorlesen" shows from the system. `refresh()` asks the system off the main actor, so the page
/// stays responsive while the voice list and the permission load; the values appear when they arrive.
@MainActor
@Observable
final class VoiceSettingsModel {
    private(set) var microphone: AVAudioApplication.recordPermission = .undetermined
    private(set) var packs: [VoiceLanguage: LanguagePackState] = [:]
    private(set) var voices: [VoiceLanguage: [SpokenVoice]] = [:]

    private let source: VoiceSettingsSource

    init(source: VoiceSettingsSource = .current) {
        self.source = source
    }

    func refresh() async {
        let source = source
        microphone = await Task.detached { source.microphone() }.value
        for language in VoiceLanguage.allCases {
            packs[language] = await source.packState(language)
            voices[language] = await Task.detached { source.voices(language) }.value
        }
    }
}
