import Foundation
import Testing
@testable import AIKit

struct ChatGPTAuthTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func codeChallenge_matchesRFC7636AppendixB() {
        #expect(ChatGPTAuth.codeChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func authorizeURL_registration_containsRequiredParameters() {
        let url = ChatGPTAuth.authorizeURL(
            clientID: nil, hostID: "urn:uuid:11111111-2222-4333-8444-555555555555",
            state: "s1", nonce: "n1", challenge: "c1"
        )
        let query = query(url)
        #expect(url.host == "auth.openai.com")
        #expect(url.path == "/api/accounts/authorize")
        #expect(query["client_id"] == "dynamic_agent_client")
        #expect(query["agent_name_hint"] == "Tagwerk")
        #expect(query["ext_agent_host_id"] == "urn:uuid:11111111-2222-4333-8444-555555555555")
        #expect(query["response_type"] == "code")
        #expect(query["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(query["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(query["resource"] == "https://api.openai.com/v1")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == "c1")
        #expect(query["state"] == "s1")
        #expect(query["nonce"] == "n1")
    }

    @Test func authorizeURL_reauthorization_usesIssuedIDWithoutNameHint() {
        let url = ChatGPTAuth.authorizeURL(clientID: "oaiapp_abc", hostID: "urn:uuid:x", state: "s", nonce: "n", challenge: "c")
        let query = query(url)
        #expect(query["client_id"] == "oaiapp_abc")
        #expect(query["agent_name_hint"] == nil)
    }

    @Test func parseCallback_stateMismatch_throws() {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=wrong&client_id=oaiapp_1")!
        #expect(throws: ChatGPTAuthError.stateMismatch) {
            try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true)
        }
    }

    @Test func parseCallback_registrationWithoutClientID_throws() {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=s1")!
        #expect(throws: ChatGPTAuthError.missingIssuedClientID) {
            try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true)
        }
    }

    @Test func parseCallback_errorParameter_throwsDenied() {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?error=access_denied&state=s1")!
        #expect(throws: ChatGPTAuthError.authorizationFailed("access_denied")) {
            try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: false)
        }
    }

    @Test func parseCallback_valid_returnsCodeAndClientID() throws {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=s1&client_id=oaiapp_1")!
        let callback = try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true)
        #expect(callback == ChatGPTCallback(code: "abc", clientID: "oaiapp_1"))
    }

    @Test func tokenRequest_isFormEncodedAuthorizationCodeGrant() {
        let request = ChatGPTAuth.tokenRequest(clientID: "oaiapp_1", code: "abc", verifier: "v1")
        #expect(request.url?.absoluteString == "https://auth.openai.com/api/accounts/oauth/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let fields = request.bodyFields
        #expect(fields.contains("grant_type=authorization_code"))
        #expect(fields.contains("client_id=oaiapp_1"))
        #expect(fields.contains("code=abc"))
        #expect(fields.contains("code_verifier=v1"))
        #expect(fields.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"))
        #expect(fields.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"))
    }

    @Test func refreshRequest_usesRefreshTokenGrantWithoutScope() {
        let request = ChatGPTAuth.refreshRequest(clientID: "oaiapp_1", refreshToken: "r1")
        let fields = request.bodyFields
        #expect(fields.contains("grant_type=refresh_token"))
        #expect(fields.contains("refresh_token=r1"))
        #expect(fields.contains("client_id=oaiapp_1"))
        #expect(!fields.contains { $0.hasPrefix("scope=") })
    }

    @Test func idTokenClaims_decodesNonceEmailAndAccount() {
        let token = makeJWT([
            "nonce": "n1", "email": "person@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-1"],
        ])
        let claims = ChatGPTAuth.idTokenClaims(token)
        #expect(claims?.nonce == "n1")
        #expect(claims?.email == "person@example.com")
        #expect(claims?.accountID == "acct-1")
    }

    @Test func idTokenClaims_garbage_isNil() {
        #expect(ChatGPTAuth.idTokenClaims("not-a-jwt") == nil)
    }

    @Test func tokens_descriptionRedactsSecrets() {
        let tokens = ChatGPTTokens(accessToken: "secret-access", refreshToken: "secret-refresh", idToken: "secret-id",
                                   expiresAt: fixedNow, clientID: "oaiapp_1", accountID: nil)
        #expect(!String(describing: tokens).contains("secret"))
        #expect(!String(reflecting: tokens).contains("secret"))
    }
}
