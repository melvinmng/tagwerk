import Foundation
import GitHubKit
import Testing
@testable import Tagwerk

@MainActor
struct GitHubLoginModelTests {
    let store = MemoryCredentials()
    let credentials = GitHubCredentials(accessToken: "gho_test", refreshToken: "ghr_test", accessExpiresAt: nil, refreshExpiresAt: nil)

    @Test func login_success_movesToSignedInAndRegistersProvider() async {
        var signedInCalls = 0
        let model = GitHubLoginModel(login: FakeDeviceLogin(outcome: .success(credentials)), tokens: makeTokenManager(store),
                                     onSignedIn: { signedInCalls += 1; return "octo" }, onSignedOut: {})
        await model.start()
        #expect(model.phase == .signedIn("octo"))
        #expect(signedInCalls == 1)
        #expect(store.current == credentials)
    }

    @Test func login_expired_showsRestartableError() async {
        let model = GitHubLoginModel(login: FakeDeviceLogin(outcome: .failure(.expired)), tokens: makeTokenManager(store),
                                     onSignedIn: { "octo" }, onSignedOut: {})
        await model.start()
        #expect(model.phase == .failed("Der Code ist abgelaufen. Bitte neu starten."))
        #expect(store.current == nil)
    }

    @Test func login_denied_showsError() async {
        let model = GitHubLoginModel(login: FakeDeviceLogin(outcome: .failure(.denied)), tokens: makeTokenManager(store),
                                     onSignedIn: { "octo" }, onSignedOut: {})
        await model.start()
        #expect(model.phase == .failed("Die Anmeldung wurde auf GitHub abgelehnt."))
    }

    @Test func login_offline_showsError() async {
        let model = GitHubLoginModel(login: FakeDeviceLogin(outcome: .failure(.network("offline"))), tokens: makeTokenManager(store),
                                     onSignedIn: { "octo" }, onSignedOut: {})
        await model.start()
        #expect(model.phase == .failed("Keine Verbindung zu GitHub."))
    }

    @Test func signOut_deletesCredentialsAndRemovesProvider() async throws {
        try store.save(credentials)
        var signedOut = false
        let model = GitHubLoginModel(login: FakeDeviceLogin(outcome: .success(credentials)), tokens: makeTokenManager(store),
                                     onSignedIn: { "octo" }, onSignedOut: { signedOut = true })
        await model.signOut()
        #expect(store.current == nil)
        #expect(signedOut)
        #expect(model.phase == .idle)
    }
}
