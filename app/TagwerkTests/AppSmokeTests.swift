import Foundation
import Testing

struct AppSmokeTests {
    @Test func appBundleIdentifier_isTagwerk() {
        #expect(Bundle.main.bundleIdentifier == "com.melvinmng.tagwerk")
    }
}

struct GitHubConfigTests {
    @Test func gitHubClientID_comesFromXcconfig() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String == "Ov23liLkF2p4Nh2ztZg0")
    }
}

struct AppIconTests {
    @Test func appIcon_isBundled() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        #expect(primary?["CFBundleIconName"] as? String == "AppIcon")
    }
}
