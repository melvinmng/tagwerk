import Foundation
import Testing

struct AppSmokeTests {
    @Test func appBundleIdentifier_isTagwerk() {
        #expect(Bundle.main.bundleIdentifier == "com.melvinmng.tagwerk")
    }
}
