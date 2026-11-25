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

// MARK: - Choosing a voice (#309)

/// Downloaded voices could not be chosen any more: the list arrived after the page was shown and the picker only knew
/// "Automatisch" until then, so a stored choice matched nothing. These tests pin what the replacement page relies on.
struct VoiceChoiceTests {
    private static let premium = SpokenVoice(id: "de.premium", name: "Anna", language: .german, quality: 3)
    private static let enhanced = SpokenVoice(id: "de.enhanced", name: "Markus", language: .german, quality: 2)
    private static let standard = SpokenVoice(id: "de.default", name: "Helena", language: .german, quality: 1)

    private func source(listed: [SpokenVoice], lookup: [String: SpokenVoice] = [:], log: CallLog? = nil) -> VoiceSettingsSource {
        VoiceSettingsSource(
            microphone: { log?.record("microphone"); return .granted },
            packState: { _ in log?.record("packState"); return .installed },
            voices: { language in log?.record("voices"); return listed.filter { $0.language == language } },
            voice: { id, _ in log?.record("voice"); return lookup[id] })
    }

    @Test func sections_groupByQualityBestFirstAndSkipEmptyOnes() {
        let sections = VoiceSection.grouped([Self.premium, Self.standard, Self.enhanced])
        #expect(sections.map(\.quality) == [3, 2, 1])
        #expect(sections.map { $0.voices.map(\.id) } == [["de.premium"], ["de.enhanced"], ["de.default"]])
        #expect(VoiceSection.grouped([Self.standard]).map(\.quality) == [1])
        #expect(VoiceSection.grouped([]).isEmpty)
    }

    @Test func storedVoiceIDs_listOnlyTheChosenVoices() {
        let settings = AppSettings()
        #expect(settings.storedVoiceIDs.isEmpty)
        settings.voiceEnglishVoiceID = "en.premium"
        #expect(settings.storedVoiceIDs == [.english: "en.premium"])
        settings.voiceGermanVoiceID = "de.premium"
        #expect(settings.storedVoiceIDs == [.german: "de.premium", .english: "en.premium"])
    }

    @MainActor
    @Test func storedChoice_isShownBeforeTheListArrives() {
        let model = VoiceSettingsModel(source: source(listed: [Self.premium]))
        #expect(!model.hasLoadedVoices)
        #expect(model.selection(for: .german, selectedID: nil) == .automatic)
        #expect(model.selection(for: .german, selectedID: "de.premium") == .pending)
    }

    @MainActor
    @Test func storedChoice_survivesTheLoading() async {
        let model = VoiceSettingsModel(source: source(listed: [Self.premium, Self.standard]))
        await model.refresh(storedVoiceIDs: [.german: "de.premium"])
        #expect(model.hasLoadedVoices)
        #expect(model.selection(for: .german, selectedID: "de.premium") == .voice(Self.premium))
        #expect(model.selection(for: .german, selectedID: nil) == .automatic)
    }

    /// The system list can omit a downloaded voice the system still knows by its identifier: the stored voice is looked up and added.
    @MainActor
    @Test func storedVoice_missingFromTheList_isLookedUpAndKept() async {
        let model = VoiceSettingsModel(source: source(listed: [Self.standard], lookup: ["de.premium": Self.premium]))
        await model.refresh(storedVoiceIDs: [.german: "de.premium"])
        #expect(model.voices[.german]?.map(\.id) == ["de.premium", "de.default"])
        #expect(model.selection(for: .german, selectedID: "de.premium") == .voice(Self.premium))
    }

    @MainActor
    @Test func storedVoice_thatIsGone_isReportedAsMissingAfterLoading() async {
        let model = VoiceSettingsModel(source: source(listed: [Self.standard]))
        await model.refresh(storedVoiceIDs: [.german: "de.removed"])
        #expect(model.voices[.german]?.map(\.id) == ["de.default"])
        #expect(model.selection(for: .german, selectedID: "de.removed") == .missing)
    }

    @MainActor
    @Test func lookup_isOnlyUsedForAStoredVoiceThatTheListLacks() async {
        let log = CallLog()
        let model = VoiceSettingsModel(source: source(listed: [Self.premium], log: log))
        await model.refresh(storedVoiceIDs: [.german: "de.premium"])
        #expect(!log.names.contains("voice"))
        await model.refresh(storedVoiceIDs: [.german: "de.other"])
        #expect(log.names.contains("voice"))
    }

    /// The voices come first: the language pack state can take long, and the page must not wait for it to show the voices.
    @MainActor
    @Test func refresh_loadsTheVoicesBeforeThePackState() async {
        let log = CallLog()
        let model = VoiceSettingsModel(source: source(listed: [Self.premium], log: log))
        await model.refresh()
        let names = log.names
        let lastVoices = names.lastIndex(of: "voices")
        let firstPack = names.firstIndex(of: "packState")
        #expect(lastVoices != nil && firstPack != nil && lastVoices! < firstPack!)
    }

    @MainActor
    @Test func refresh_remembersWhenTheVoicesWereChecked() async {
        let moment = Date(timeIntervalSince1970: 1_000)
        let model = VoiceSettingsModel(source: source(listed: [Self.premium]), now: { moment })
        #expect(model.voicesCheckedAt == nil)
        await model.refresh()
        #expect(model.voicesCheckedAt == moment)
    }

    @MainActor
    @Test func refresh_picksUpVoicesDownloadedInTheMeantime() async {
        let listed = LockedVoices([Self.standard])
        let model = VoiceSettingsModel(source: VoiceSettingsSource(
            microphone: { .granted }, packState: { _ in .installed },
            voices: { _ in listed.value }, voice: { _, _ in nil }))
        await model.refresh()
        #expect(model.voices[.german]?.count == 1)
        listed.value = [Self.premium, Self.standard]
        await model.refresh()
        #expect(model.voices[.german]?.map(\.id) == ["de.premium", "de.default"])
    }

    // MARK: Speaking with the chosen voice

    @MainActor
    @Test func resolvedVoice_keepsAChosenVoiceThatTheListLacksButTheSystemKnows() {
        let speaker = FakeSpeaker()
        speaker.known = ["de.hidden"]
        #expect(speaker.resolvedVoiceID("de.hidden", language: .german) == "de.hidden")
        // An unknown identifier still falls back to the best installed voice.
        #expect(speaker.resolvedVoiceID("de.removed", language: .german) == "de.premium")
        #expect(speaker.resolvedVoiceID(nil, language: .german) == "de.premium")
        // A listed voice wins over the best one.
        #expect(speaker.resolvedVoiceID("de.default", language: .german) == "de.default")
    }

    @Test func spokenVoice_forAVoiceTheSystemKnowsByIdentifier() {
        let system = SystemVoice(id: "x", name: "Anna", language: "de-AT", quality: 3)
        #expect(SystemSpeaker.spokenVoice(system, for: .german) == SpokenVoice(id: "x", name: "Anna", language: .german, quality: 3))
        #expect(SystemSpeaker.spokenVoice(system, for: .english) == nil)
        // A novelty voice is not offered in the list, but a voice the user chose before stays usable.
        let novelty = SystemVoice(id: "n", name: "Zarvox", language: "de-DE", quality: 1, isNovelty: true)
        #expect(SystemSpeaker.spokenVoice(novelty, for: .german)?.id == "n")
    }
}

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var names: [String] { lock.withLock { recorded } }
    func record(_ name: String) { lock.withLock { recorded.append(name) } }
}

private final class LockedVoices: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SpokenVoice]
    init(_ voices: [SpokenVoice]) { stored = voices }
    var value: [SpokenVoice] {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
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
