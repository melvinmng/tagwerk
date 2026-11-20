import Foundation
import Testing
@testable import TagwerkCore

struct VoiceChatLanguageTests {
    private let germanApp = Locale(identifier: "de_DE")
    private let englishApp = Locale(identifier: "en_GB")
    private let otherApp = Locale(identifier: "fr_FR")

    @Test func automatic_followsTheAppLanguage() {
        #expect(VoiceChatLanguage.resolve(setting: "auto", locale: germanApp) == .german)
        #expect(VoiceChatLanguage.resolve(setting: "auto", locale: englishApp) == .english)
        // The app shows German for every language it does not support.
        #expect(VoiceChatLanguage.resolve(setting: "auto", locale: otherApp) == .german)
        #expect(VoiceChatLanguage.fixed(setting: "auto") == nil)
    }

    @Test func fixedLanguage_winsOverTheAppLanguage() {
        #expect(VoiceChatLanguage.resolve(setting: "de-DE", locale: englishApp) == .german)
        #expect(VoiceChatLanguage.resolve(setting: "en-US", locale: germanApp) == .english)
        #expect(VoiceChatLanguage.fixed(setting: "de-DE") == .german)
        #expect(VoiceChatLanguage.fixed(setting: "en-US") == .english)
    }

    /// The setting replaces "Erkennung in" and keeps its stored values: every value an earlier version wrote means the same.
    @Test(arguments: [
        ("auto", "de_DE", VoiceLanguage.german), ("auto", "en_US", .english),
        ("de-DE", "en_US", .german), ("en-US", "de_DE", .english)
    ])
    func legacyRecognitionValues_resolveAsBefore(stored: String, locale: String, expected: VoiceLanguage) {
        let legacy = VoiceLanguage(rawValue: stored) ?? .from(locale: Locale(identifier: locale))
        #expect(VoiceChatLanguage.resolve(setting: stored, locale: Locale(identifier: locale)) == legacy)
        #expect(VoiceChatLanguage.resolve(setting: stored, locale: Locale(identifier: locale)) == expected)
    }

    @Test func unknownOrMissingSetting_followsTheAppLanguage() {
        #expect(VoiceChatLanguage.resolve(setting: "fr-FR", locale: englishApp) == .english)
        #expect(VoiceChatLanguage.resolve(setting: "", locale: germanApp) == .german)
        #expect(VoiceChatLanguage.resolve(setting: nil, locale: englishApp) == .english)
        #expect(VoiceChatLanguage.fixed(setting: "fr-FR") == nil)
        #expect(VoiceChatLanguage.fixed(setting: nil) == nil)
    }

    @Test func automaticMatchesTheAppLanguageConstant() {
        #expect(VoiceChatLanguage.resolve(setting: VoiceChatLanguage.automatic) == VoiceLanguage.app)
    }

    @Test func choices_areTheSupportedLanguages() {
        #expect(VoiceChatLanguage.choices == VoiceLanguage.allCases)
    }

    @Test func answerInstruction_namesTheLanguageOnlyWhenFixed() {
        #expect(VoiceChatLanguage.answerInstruction(for: nil) == nil)
        #expect(VoiceChatLanguage.answerInstruction(for: .german)?.contains("auf Deutsch") == true)
        #expect(VoiceChatLanguage.answerInstruction(for: .english)?.contains("auf Englisch (English)") == true)
        #expect(VoiceChatLanguage.answerInstruction(for: .english)?.contains("auch wenn") == true)
    }
}
