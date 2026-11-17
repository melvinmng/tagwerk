import Foundation
import Testing

struct AppSmokeTests {
    @Test func appBundle_isTagwerk() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Tagwerk")
    }
}

struct GitHubConfigTests {
    @Test func gitHubClientID_isResolved() throws {
        let clientID = try #require(Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String)
        #expect(clientID != "$(GITHUB_CLIENT_ID)")
    }
}

struct AppIconTests {
    @Test func appIcon_isBundled() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        #expect(primary?["CFBundleIconName"] as? String == "AppIcon")
    }
}
