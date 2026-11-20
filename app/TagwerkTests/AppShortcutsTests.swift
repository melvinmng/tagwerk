import AppIntents
import Testing
@testable import Tagwerk

/// The App Shortcuts provider as the system sees it. The phrase texts are checked against the String Catalog by
/// `scripts/check-strings.py`; Siri's recognition itself can only be tested on a device.
struct AppShortcutsTests {
    @Test func providerStaysWithinTheSystemLimitOfTenShortcuts() {
        #expect(TagwerkShortcuts.appShortcuts.count == 10)
        #expect(TagwerkShortcuts.appShortcuts.count <= 10)
    }
}
