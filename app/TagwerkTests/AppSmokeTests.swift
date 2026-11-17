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
