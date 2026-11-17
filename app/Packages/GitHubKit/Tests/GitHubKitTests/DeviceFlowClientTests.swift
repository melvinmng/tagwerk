import Foundation
import Testing
@testable import GitHubKit

struct DeviceFlowClientTests {
    let transport = StubTransport()
    let recorder = SleepRecorder()
    let code = DeviceCode(deviceCode: "dev-123", userCode: "ABCD-1234",
                          verificationURL: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)

    var client: DeviceFlowClient {
        DeviceFlowClient(clientID: "Ov23liLkF2p4Nh2ztZg0", transport: transport, sleep: recorder.sleep, now: { fixedNow })
    }

    @Test func requestCode_sendsClientIDAndScope() async throws {
        transport.enqueueJSON("/login/device/code", """
        {"device_code":"dev-123","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}
        """)
        let result = try await client.requestCode()

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = request.bodyString
        #expect(body.contains("client_id=Ov23liLkF2p4Nh2ztZg0"))
        #expect(body.contains("scope=repo%20project%20offline_access") || body.contains("scope=repo+project+offline_access"))
        #expect(result.userCode == "ABCD-1234")
        #expect(result.expiresIn == 899)
    }

    @Test func poll_pendingThenToken_returnsCredentialsWithExpiry() async throws {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"authorization_pending"}"#)
        transport.enqueueJSON("/login/oauth/access_token", """
        {"access_token":"gho_test","token_type":"bearer","scope":"project,repo","expires_in":28800,"refresh_token":"ghr_test","refresh_token_expires_in":15638400}
        """)
        let credentials = try await client.pollForToken(code)

        #expect(credentials.accessToken == "gho_test")
        #expect(credentials.refreshToken == "ghr_test")
        #expect(credentials.accessExpiresAt == fixedNow.addingTimeInterval(28800))
        #expect(credentials.refreshExpiresAt == fixedNow.addingTimeInterval(15638400))
        #expect(recorder.sleeps == [.seconds(5), .seconds(5)])
        let body = try #require(transport.requests.last).bodyString
        #expect(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(body.contains("device_code=dev-123"))
    }

    @Test func poll_slowDown_increasesInterval() async throws {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"slow_down"}"#)
        transport.enqueueJSON("/login/oauth/access_token", #"{"access_token":"gho_test","token_type":"bearer"}"#)
        _ = try await client.pollForToken(code)
        #expect(recorder.sleeps == [.seconds(5), .seconds(10)])
    }

    @Test func poll_slowDown_usesIntervalFromResponse() async throws {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"slow_down","interval":12}"#)
        transport.enqueueJSON("/login/oauth/access_token", #"{"access_token":"gho_test","token_type":"bearer"}"#)
        _ = try await client.pollForToken(code)
        #expect(recorder.sleeps == [.seconds(5), .seconds(12)])
    }

    @Test func poll_expired_throwsExpired() async {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"expired_token"}"#)
        await #expect(throws: GitHubAuthError.expired) { try await client.pollForToken(code) }
    }

    @Test func poll_denied_throwsDenied() async {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"access_denied"}"#)
        await #expect(throws: GitHubAuthError.denied) { try await client.pollForToken(code) }
    }

    @Test func poll_afterCodeLifetime_throwsExpired() async {
        let shortCode = DeviceCode(deviceCode: "d", userCode: "u", verificationURL: code.verificationURL, expiresIn: 0, interval: 5)
        await #expect(throws: GitHubAuthError.expired) { try await client.pollForToken(shortCode) }
        #expect(transport.requests.isEmpty)
    }

    @Test func poll_tokenWithoutExpiry_hasNilExpiry() async throws {
        transport.enqueueJSON("/login/oauth/access_token", #"{"access_token":"gho_test","token_type":"bearer"}"#)
        let credentials = try await client.pollForToken(code)
        #expect(credentials.accessExpiresAt == nil)
        #expect(credentials.refreshToken == nil)
    }

    @Test func refresh_sendsGrantTypeWithoutSecret() async throws {
        transport.enqueueJSON("/login/oauth/access_token", """
        {"access_token":"gho_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15638400}
        """)
        let credentials = try await client.refresh("ghr_old")
        let body = try #require(transport.requests.first).bodyString
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=ghr_old"))
        #expect(body.contains("client_id=Ov23liLkF2p4Nh2ztZg0"))
        #expect(!body.contains("client_secret"))
        #expect(credentials.accessToken == "gho_new")
    }

    @Test func refresh_errorCode_throwsServerWithCode() async {
        transport.enqueueJSON("/login/oauth/access_token", #"{"error":"bad_refresh_token"}"#)
        await #expect(throws: GitHubAuthError.server("bad_refresh_token")) { try await client.refresh("x") }
    }

    @Test func refresh_offline_throwsNetwork() async {
        transport.enqueue("/login/oauth/access_token", .failure(.notConnectedToInternet))
        await #expect(throws: GitHubAuthError.self) { try await client.refresh("x") }
        do {
            _ = try await client.refresh("x")
        } catch GitHubAuthError.network {
            // expected
        } catch {
            Issue.record("expected .network, got \(error)")
        }
    }

    @Test func credentials_descriptionNeverContainsTokens() {
        let credentials = GitHubCredentials(accessToken: "gho_secret", refreshToken: "ghr_secret",
                                            accessExpiresAt: nil, refreshExpiresAt: nil)
        let text = String(describing: credentials) + String(reflecting: credentials)
        #expect(!text.contains("gho_secret"))
        #expect(!text.contains("ghr_secret"))
    }

    @Test func credentials_needsRefresh_withinFiveMinutes() {
        let soon = GitHubCredentials(accessToken: "a", refreshToken: "r", accessExpiresAt: fixedNow.addingTimeInterval(299), refreshExpiresAt: nil)
        let later = GitHubCredentials(accessToken: "a", refreshToken: "r", accessExpiresAt: fixedNow.addingTimeInterval(301), refreshExpiresAt: nil)
        let never = GitHubCredentials(accessToken: "a", refreshToken: nil, accessExpiresAt: nil, refreshExpiresAt: nil)
        #expect(soon.needsRefresh(now: fixedNow))
        #expect(!later.needsRefresh(now: fixedNow))
        #expect(!never.needsRefresh(now: fixedNow))
    }
}
