import Foundation
import Synchronization
import Testing
@testable import AIKit

/// Plays the browser: optionally answers the authorize URL by calling the loopback server.
@MainActor
final class FakeWebAuthenticator: WebAuthenticating {
    enum Behavior { case callBack(clientID: String?), cancel }
    let behavior: Behavior
    let port: UInt16
    private(set) var presentedURLs: [URL] = []
    private(set) var callbackSchemes: [String] = []

    init(_ behavior: Behavior, port: UInt16) {
        self.behavior = behavior
        self.port = port
    }

    func authenticate(url: URL, callbackScheme: String) async throws {
        presentedURLs.append(url)
        callbackSchemes.append(callbackScheme)
        switch behavior {
        case .cancel:
            throw ChatGPTAuthError.cancelled
        case .callBack(let clientID):
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            var query = "code=code1&state=\(state)"
            if let clientID { query += "&client_id=\(clientID)" }
            _ = try await RawHTTPClient.get("/auth/callback?\(query)", port: port)
        }
    }
}

@MainActor
struct ChatGPTLoginTests {
    let transport = StubAITransport()

    @Test func signIn_fullSequence_storesTokens() async throws {
        let port = TestPorts.make()
        let store = InMemoryChatGPTCredentialStore()
        let browser = FakeWebAuthenticator(.callBack(clientID: "oaiapp_new"), port: port)
        // The token reply carries the nonce of the authorize URL the browser was shown.
        let session = ChatGPTSessionStore(store: store, transport: NonceEchoTransport(browser: browser), now: { fixedNow })
        let login = ChatGPTLogin(session: session, authenticator: browser, port: port)

        try await login.signIn()

        #expect(browser.callbackSchemes == ["tagwerk"])
        #expect(store.tokens?.accessToken == "at_login")
        #expect(try store.loadClientID() == "oaiapp_new")
        #expect(await session.isSignedIn)
    }

    @Test func signIn_loopbackRedirectUsesTheTestPort() async throws {
        // The authorize URL always names port 1455; tests run the server on other ports.
        let port = TestPorts.make()
        let browser = FakeWebAuthenticator(.cancel, port: port)
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(), transport: transport, now: { fixedNow })
        await #expect(throws: ChatGPTAuthError.cancelled) {
            try await ChatGPTLogin(session: session, authenticator: browser, port: port).signIn()
        }
        let url = try #require(browser.presentedURLs.first)
        let redirect = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "redirect_uri" }?.value
        #expect(redirect == "http://127.0.0.1:1455/auth/callback")
    }

    @Test func cancel_stopsServerAndFreesPort() async throws {
        let port = TestPorts.make()
        let store = InMemoryChatGPTCredentialStore()
        let session = ChatGPTSessionStore(store: store, transport: transport, now: { fixedNow })
        let login = ChatGPTLogin(session: session, authenticator: FakeWebAuthenticator(.cancel, port: port), port: port)

        await #expect(throws: ChatGPTAuthError.cancelled) { try await login.signIn() }
        #expect(transport.requests.isEmpty)
        // The port is free again: a new server can bind it immediately.
        let server = LoopbackServer(port: port, expectedState: "x")
        try await server.start()
        await server.stop()
    }

    @Test func signIn_portInUse_reportsErrorWithoutOpeningSheet() async throws {
        let port = TestPorts.make()
        let blocker = LoopbackServer(port: port, expectedState: "x")
        try await blocker.start()
        let browser = FakeWebAuthenticator(.cancel, port: port)
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(), transport: transport, now: { fixedNow })
        let login = ChatGPTLogin(session: session, authenticator: browser, port: port)

        await #expect(throws: ChatGPTAuthError.portInUse) { try await login.signIn() }
        #expect(browser.presentedURLs.isEmpty)
        await blocker.stop()
    }
}

/// Answers the token endpoint with an ID token whose nonce matches the authorize URL the browser saw.
final class NonceEchoTransport: AIHTTPTransport {
    private let nonce: @Sendable () async -> String

    @MainActor
    init(browser: FakeWebAuthenticator) {
        nonce = { @MainActor in
            let url = browser.presentedURLs.last
            return url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "nonce" }?.value } ?? ""
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let idToken = makeJWT(["nonce": await nonce(), "email": "person@example.com"])
        let body = #"{"access_token":"at_login","refresh_token":"rt_login","id_token":"\#(idToken)","expires_in":3600}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        throw URLError(.unsupportedURL)
    }
}
