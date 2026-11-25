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
    /// One voice by its identifier: the list can omit a downloaded voice the system still knows. Also synchronous and off the
    /// main actor.
    var voice: @Sendable (String, VoiceLanguage) -> SpokenVoice? = { _, _ in nil }

    /// What the device reports.
    static let live = VoiceSettingsSource(
        microphone: { AVAudioApplication.shared.recordPermission },
        packState: { await VoiceAvailability.packState($0) },
        voices: { SystemSpeaker.installedVoices(for: $0) },
        voice: { SystemSpeaker.installedVoice(withID: $0, for: $1) })

    /// The same on every run: both language packs available, no extra voices, microphone not asked yet. Without it the page would
    /// show the state of the machine that runs the audit, and asking for it blocked the page on slow CI runners.
    static let uiTest = VoiceSettingsSource(
        microphone: { .undetermined },
        packState: { _ in .available },
        voices: { _ in [] })

    /// `uiTest` in the UI test mode, `live` everywhere else (the mode is never active on a device).
    static var current: VoiceSettingsSource { UITestMode.isActive ? .uiTest : .live }
}

/// What the picker of a voice shows for the stored choice.
enum VoiceSelection: Equatable {
    /// "Automatisch": the best installed voice.
    case automatic
    /// A voice is stored and the list has not arrived yet: shown as chosen, without a name.
    case pending
    /// The stored voice is installed.
    case voice(SpokenVoice)
    /// The list is loaded and the stored voice is not on the iPhone any more; reading falls back to the best voice.
    case missing
}

/// What "Spracheingabe und Vorlesen" and the voice pages show from the system. `refresh()` asks the system off the main actor,
/// so the pages stay responsive while the voice list and the permission load; the values appear when they arrive.
@MainActor
@Observable
final class VoiceSettingsModel {
    private(set) var microphone: AVAudioApplication.recordPermission = .undetermined
    private(set) var packs: [VoiceLanguage: LanguagePackState] = [:]
    private(set) var voices: [VoiceLanguage: [SpokenVoice]] = [:]
    /// True once the voice list of every language has been asked for at least once.
    private(set) var hasLoadedVoices = false
    private(set) var voicesCheckedAt: Date?

    private let source: VoiceSettingsSource
    private let now: () -> Date

    init(source: VoiceSettingsSource = .current, now: @escaping () -> Date = { Date() }) {
        self.source = source
        self.now = now
    }

    /// Asks the system again. `storedVoiceIDs` are the voices the user chose: a stored voice the list lacks is looked up by its
    /// identifier and added, so a choice is never hidden by an incomplete list. The voices load first: the language pack state can
    /// take long and must not delay them.
    func refresh(storedVoiceIDs: [VoiceLanguage: String] = [:]) async {
        await refreshVoices(storedVoiceIDs: storedVoiceIDs)
        let source = source
        microphone = await Task.detached { source.microphone() }.value
        for language in VoiceLanguage.allCases {
            packs[language] = await source.packState(language)
        }
    }

    /// Only the voice lists (the voice pages need nothing else).
    func refreshVoices(storedVoiceIDs: [VoiceLanguage: String] = [:]) async {
        let source = source
        for language in VoiceLanguage.allCases {
            let stored = storedVoiceIDs[language]
            voices[language] = await Task.detached { Self.catalog(source: source, language: language, storedVoiceID: stored) }.value
        }
        hasLoadedVoices = true
        voicesCheckedAt = now()
    }

    /// The listed voices of `language`, plus the stored voice when the system knows it but the list does not.
    nonisolated static func catalog(source: VoiceSettingsSource, language: VoiceLanguage, storedVoiceID: String?) -> [SpokenVoice] {
        let listed = source.voices(language)
        guard let storedVoiceID, !listed.contains(where: { $0.id == storedVoiceID }),
              let stored = source.voice(storedVoiceID, language) else { return listed }
        return (listed + [stored]).sorted(by: SpokenVoice.isOrderedBefore)
    }

    /// What the picker of `language` shows for the voice stored in the settings (`nil` for "Automatisch").
    func selection(for language: VoiceLanguage, selectedID: String?) -> VoiceSelection {
        guard let selectedID else { return .automatic }
        if let voice = voices[language]?.first(where: { $0.id == selectedID }) { return .voice(voice) }
        return hasLoadedVoices ? .missing : .pending
    }

    /// The voice "Automatisch" speaks with.
    func automaticVoice(for language: VoiceLanguage) -> SpokenVoice? { voices[language]?.first }
}
