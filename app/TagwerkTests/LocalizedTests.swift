import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct LocalizedTests {
    @Test func picksTheRequestedLanguage() {
        #expect(Localized.string("Planen", in: .english, bundle: .main) == "Plan")
        #expect(Localized.string("Planen", in: .german, bundle: .main) == "Planen")
    }

    @Test func appLanguage_followsTheTestLanguage() {
        #expect(VoiceLanguage.app == .german)
    }
}
