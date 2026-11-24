import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct VoiceSettingsTests {
    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.voiceInputEnabled)
        #expect(!settings.voiceExplained)
        #expect(settings.voiceRecognitionLanguage == "auto")
        #expect(settings.voiceReadAloud == ReadAloudPolicy.never.rawValue)
        #expect(settings.voiceGermanVoiceID == nil)
        #expect(settings.voiceAnnounceActions)
        #expect(settings.recipeLanguage == "auto")
    }

    @Test func recognitionLanguage_autoFollowsLocale() {
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "en_GB")) == .english)
        #expect(VoiceAvailability.recognitionLanguage(setting: "auto", locale: Locale(identifier: "fr_FR")) == .german)
        #expect(VoiceAvailability.recognitionLanguage(setting: "en-US", locale: Locale(identifier: "de_DE")) == .english)
    }

    /// "Sprache im Sprachchat" replaced "Erkennung in" and kept its stored values (#226).
    @Test func voiceChatLanguage_readsTheStoredRecognitionValues() {
        let english = Locale(identifier: "en_GB")
        let german = Locale(identifier: "de_DE")
        for (stored, locale, expected) in [("auto", german, VoiceLanguage.german), ("auto", english, .english),
                                           ("de-DE", english, .german), ("en-US", german, .english)] {
            #expect(VoiceAvailability.recognitionLanguage(setting: stored, locale: locale) == expected)
            #expect(VoiceChatLanguage.resolve(setting: stored, locale: locale) == expected)
        }
        #expect(VoiceChatLanguage.fixed(setting: AppSettings().voiceRecognitionLanguage) == nil)
    }

    @Test func voiceChatLanguage_survivesTheBackup() throws {
        let source = AppSettings()
        source.voiceRecognitionLanguage = "en-US"
        let data = try JSONEncoder().encode(AppSettingsBackup(source))
        let target = AppSettings()
        try JSONDecoder().decode(AppSettingsBackup.self, from: data).apply(to: target)
        #expect(target.voiceRecognitionLanguage == "en-US")
    }

    // MARK: Takeover of the shared language value (L1)

    @Test func contentLanguageDefaults() {
        let settings = AppSettings()
        #expect(settings.voiceAnswerLanguage == nil)
        #expect(settings.shoppingLanguage == ContentLanguages.likeRecipes)
        #expect(settings.dictationPlaceLanguagesData == nil)
    }

    @Test func migration_auto_becomesSpoken() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "auto"
        settings.migrateVoiceAnswerLanguageIfNeeded()
        #expect(settings.voiceAnswerLanguage == ContentLanguages.spoken)
        #expect(settings.contentLanguages.fixedAnswerLanguage == nil)
    }

    @Test func migration_fixedLanguage_keepsAnswerLanguage() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "en-US"
        settings.migrateVoiceAnswerLanguageIfNeeded()
        #expect(settings.voiceAnswerLanguage == "en-US")
        // The assistant reads the same fixed language as before the update.
        #expect(settings.contentLanguages.fixedAnswerLanguage == .english)
        #expect(VoiceChatLanguage.fixed(setting: settings.voiceRecognitionLanguage) == settings.contentLanguages.fixedAnswerLanguage)
    }

    @Test func migration_unknownValue_becomesSpoken() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "fr-FR"
        settings.migrateVoiceAnswerLanguageIfNeeded()
        #expect(settings.voiceAnswerLanguage == ContentLanguages.spoken)
        // Dictation keeps resolving as before: to the app language.
        #expect(settings.voiceRecognitionLanguage == "fr-FR")
    }

    @Test func migration_runsOnce() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "en-US"
        settings.migrateVoiceAnswerLanguageIfNeeded()
        settings.voiceRecognitionLanguage = "de-DE"
        settings.migrateVoiceAnswerLanguageIfNeeded()
        #expect(settings.voiceAnswerLanguage == "en-US", "a later change of the dictation language must not move the answer language")
    }

    @Test func contentLanguages_readTheStoredFields() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "de-DE"
        settings.recipeLanguage = "en-US"
        settings.shoppingLanguage = "de-DE"
        settings.dictationPlaceLanguagesData = ContentLanguages.encodePlaces(["notes": "en-US"])
        let content = settings.contentLanguages
        #expect(content.dictationLanguage(at: .notes) == .english)
        #expect(content.dictationLanguage(at: .chat) == .german)
        #expect(content.dictationLanguage(at: .shopping) == .german)
        #expect(content.recipeLanguage() == .english)
    }

    @Test func summaryLine() {
        #expect(VoiceAvailability.summary(inputEnabled: true, readAloud: "never") == "Mikrofon an, Vorlesen nie")
        #expect(VoiceAvailability.summary(inputEnabled: false, readAloud: "always") == "Mikrofon aus, Vorlesen immer")
    }
}

// MARK: - Loading of "Spracheingabe und Vorlesen"

/// The page used to ask the system for the voices and the permission on the main actor and froze on slow runners
/// (over 190 s without an answer to the accessibility queries). These tests pin the replacement.
struct VoiceSettingsSourceTests {
    private static let systemVoices = [
        SystemVoice(id: "de.default", name: "Anna", language: "de-DE", quality: 1),
        SystemVoice(id: "de.premium", name: "Petra", language: "de-AT", quality: 3),
        SystemVoice(id: "de.enhanced", name: "Markus", language: "de-DE", quality: 2),
        SystemVoice(id: "de.novelty", name: "Zarvox", language: "de-DE", quality: 1, isNovelty: true),
        SystemVoice(id: "en.default", name: "Samantha", language: "en-US", quality: 1),
        SystemVoice(id: "fr.default", name: "Amélie", language: "fr-FR", quality: 3),
    ]

    @Test func installedVoices_keepsOneLanguageWithoutNoveltyVoicesBestFirst() {
        let german = SystemSpeaker.installedVoices(for: .german, among: Self.systemVoices)
        #expect(german.map(\.id) == ["de.premium", "de.enhanced", "de.default"])
        #expect(german.allSatisfy { $0.language == .german })
        #expect(SystemSpeaker.installedVoices(for: .english, among: Self.systemVoices).map(\.id) == ["en.default"])
    }

    @Test func installedVoices_sortsVoicesOfTheSameQualityByName() {
        let voices = [SystemVoice(id: "b", name: "Bea", language: "en-GB", quality: 2),
                      SystemVoice(id: "a", name: "Ann", language: "en-US", quality: 2)]
        #expect(SystemSpeaker.installedVoices(for: .english, among: voices).map(\.name) == ["Ann", "Bea"])
    }

    @Test func installedVoices_isEmptyWithoutVoices() {
        #expect(SystemSpeaker.installedVoices(for: .german, among: []).isEmpty)
    }

    @Test func uiTestSource_givesFixedValuesWithoutAskingTheSystem() async {
        let source = VoiceSettingsSource.uiTest
        #expect(source.microphone() == .undetermined)
        for language in VoiceLanguage.allCases {
            #expect(await source.packState(language) == .available)
            #expect(source.voices(language).isEmpty)
        }
    }

    @MainActor
    @Test func refresh_asksTheSystemOffTheMainThread() async {
        let threads = ThreadLog()
        let source = VoiceSettingsSource(
            microphone: { threads.record("microphone"); return .granted },
            packState: { _ in .installed },
            voices: { language in
                threads.record("voices")
                return [SpokenVoice(id: language.rawValue, name: "Test", language: language, quality: 1)]
            })
        let model = VoiceSettingsModel(source: source)
        await model.refresh()
        #expect(threads.calls.contains { $0.name == "microphone" })
        #expect(threads.calls.filter { $0.name == "voices" }.count == VoiceLanguage.allCases.count)
        #expect(threads.calls.allSatisfy { !$0.onMainThread })
        #expect(model.microphone == .granted)
        #expect(model.packs[.german] == .installed)
        #expect(model.voices[.english]?.map(\.name) == ["Test"])
    }

    @MainActor
    @Test func model_startsEmptyBeforeTheFirstRefresh() {
        let model = VoiceSettingsModel(source: .uiTest)
        #expect(model.microphone == .undetermined)
        #expect(model.packs.isEmpty)
        #expect(model.voices.isEmpty)
    }
}

private final class ThreadLog: @unchecked Sendable {
    struct Call { let name: String; let onMainThread: Bool }
    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] { lock.withLock { recorded } }

    func record(_ name: String) {
        let call = Call(name: name, onMainThread: Thread.isMainThread)
        lock.withLock { recorded.append(call) }
    }
}
